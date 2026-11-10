import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/jellyfin_session.dart';
import '../models/media_item.dart';

class JellyfinException implements Exception {
  const JellyfinException(this.message);
  final String message;

  @override
  String toString() => message;
}

class JellyfinApi {
  JellyfinApi({JellyfinSession? session, http.Client? client})
    : _session = session,
      _client = client ?? http.Client();

  static const publicBaseUrl = 'https://jellyfin-casa.tailfb7f41.ts.net';

  static const defaultCandidates = [
    publicBaseUrl,
    'http://jellyfin-casa:8096',
    'http://jellyfin-casa.local:8096',
    'http://192.168.1.66:8096',
  ];

  final JellyfinSession? _session;
  final http.Client _client;

  JellyfinSession get session {
    final value = _session;
    if (value == null) throw const JellyfinException('Sessão não iniciada.');
    return value;
  }

  Map<String, String> get authHeaders => {
    'Authorization': 'MediaBrowser Token="${session.token}"',
    'X-Emby-Token': session.token,
  };

  static String normalizeUrl(String value) {
    var result = value.trim();
    if (!result.startsWith('http://') && !result.startsWith('https://')) {
      result = 'https://$result';
    }
    return result.replaceAll(RegExp(r'/+$'), '');
  }

  Future<Map<String, dynamic>> publicInfo(String baseUrl) async {
    final url = normalizeUrl(baseUrl);
    try {
      final response = await _client
          .get(Uri.parse('$url/System/Info/Public'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        throw JellyfinException('Servidor respondeu ${response.statusCode}.');
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on JellyfinException {
      rethrow;
    } catch (_) {
      throw const JellyfinException(
        'Servidor não encontrado. Verifique sua internet ou o endereço.',
      );
    }
  }

  Future<String> discover() async {
    for (final candidate in defaultCandidates) {
      try {
        await publicInfo(candidate);
        return normalizeUrl(candidate);
      } catch (_) {
        // HTTPS, MagicDNS, mDNS and Tailscale IP are tried in this order.
      }
    }
    throw const JellyfinException(
      'CasaFlix não encontrou o servidor. Verifique sua internet e tente novamente.',
    );
  }

  Future<JellyfinSession> authenticate({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final url = normalizeUrl(baseUrl);
    final authorization =
        'MediaBrowser Client="CasaFlix", Device="Mobile", '
        'DeviceId="casaflix-mobile", Version="1.0.0"';
    final response = await _client.post(
      Uri.parse('$url/Users/AuthenticateByName'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': authorization,
        'X-Emby-Authorization': authorization,
      },
      body: jsonEncode({'Username': username.trim(), 'Pw': password}),
    );

    if (response.statusCode == 401) {
      throw const JellyfinException('Usuário ou senha incorretos.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JellyfinException(
        'Não foi possível entrar (${response.statusCode}).',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final user = json['User'] as Map<String, dynamic>;
    final info = await publicInfo(url);
    return JellyfinSession(
      baseUrl: url,
      token: json['AccessToken'] as String,
      userId: user['Id'] as String,
      userName: user['Name'] as String,
      serverName: (info['ServerName'] as String?) ?? 'Jellyfin Casa',
    );
  }

  Future<List<MediaView>> views() async {
    final response = await _get('/Users/${session.userId}/Views');
    return ((response['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(MediaView.fromJson)
        .toList();
  }

  Future<List<MediaItem>> latest(String parentId) async {
    final uri =
        Uri.parse(
          '${session.baseUrl}/Users/${session.userId}/Items/Latest',
        ).replace(
          queryParameters: {
            'ParentId': parentId,
            'Limit': '20',
            'Fields':
                'Overview,BackdropImageTags,ProductionYear,ParentIndexNumber,IndexNumber',
            'ImageTypeLimit': '1',
            'EnableImageTypes': 'Primary,Backdrop',
          },
        );
    final response = await _client.get(uri, headers: authHeaders);
    _ensureSuccess(response);
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(MediaItem.fromJson)
        .toList();
  }

  Future<MediaItem> item(String id) async {
    final response = await _get(
      '/Users/${session.userId}/Items/$id',
      query: {
        'Fields':
            'Overview,BackdropImageTags,ProductionYear,ParentIndexNumber,IndexNumber',
      },
    );
    return MediaItem.fromJson(response);
  }

  Future<List<MediaItem>> episodes(String seriesId) async {
    final response = await _get(
      '/Shows/$seriesId/Episodes',
      query: {
        'UserId': session.userId,
        'Fields':
            'Overview,BackdropImageTags,ProductionYear,ParentIndexNumber,IndexNumber',
        'EnableImages': 'true',
        'ImageTypeLimit': '1',
        'EnableImageTypes': 'Primary,Backdrop',
      },
    );
    return ((response['Items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(MediaItem.fromJson)
        .toList();
  }

  String imageUrl(MediaItem item, {bool backdrop = false, int width = 900}) {
    final type = backdrop && item.backdropTag != null
        ? 'Backdrop/0'
        : 'Primary';
    return '${session.baseUrl}/Items/${item.id}/Images/$type?maxWidth=$width&quality=88';
  }

  Uri playbackUrl(MediaItem item) {
    return Uri.parse(
      '${session.baseUrl}/Videos/${item.id}/master.m3u8',
    ).replace(
      queryParameters: {
        'UserId': session.userId,
        'MediaSourceId': item.id,
        'VideoCodec': 'h264',
        'AudioCodec': 'aac',
        'MaxStreamingBitrate': '20000000',
        'AudioBitRate': '192000',
        'SegmentContainer': 'ts',
        'MinSegments': '1',
        'BreakOnNonKeyFrames': 'true',
      },
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(
      '${session.baseUrl}$path',
    ).replace(queryParameters: query);
    final response = await _client.get(uri, headers: authHeaders);
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode == 401) {
      throw const JellyfinException('Sua sessão expirou. Entre novamente.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JellyfinException('O servidor respondeu ${response.statusCode}.');
    }
  }
}
