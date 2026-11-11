import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/jellyfin_session.dart';
import '../models/media_item.dart';
import '../models/playback.dart';

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
  static const localBaseUrl = 'http://192.168.1.66:8096';
  static const localTelevisionUser = 'netpobre-tv';

  static const defaultCandidates = [
    localBaseUrl,
    'http://jellyfin-casa:8096',
    'http://jellyfin-casa.local:8096',
    publicBaseUrl,
  ];

  final JellyfinSession? _session;
  final http.Client _client;
  static const _itemFields =
      'Overview,OriginalTitle,BackdropImageTags,ProductionYear,ParentIndexNumber,IndexNumber,SeriesId,UserData,Trickplay';

  JellyfinSession get session {
    final value = _session;
    if (value == null) throw const JellyfinException('Sessão não iniciada.');
    return value;
  }

  Map<String, String> get authHeaders => {
    'Authorization': 'MediaBrowser Token="${session.token}"',
    'X-Emby-Token': session.token,
    'Accept-Language': 'pt-BR,pt;q=0.9,en;q=0.5',
  };

  static const deviceAuthorization =
      'MediaBrowser Client="NetPobre", Device="Mobile e TV", '
      'DeviceId="netpobre-client", Version="1.5.0"';

  static const deviceHeaders = {
    'Authorization': deviceAuthorization,
    'X-Emby-Authorization': deviceAuthorization,
  };

  static String normalizeUrl(String value) {
    var result = value.trim();
    if (!result.startsWith('http://') && !result.startsWith('https://')) {
      result = 'https://$result';
    }
    return result.replaceAll(RegExp(r'/+$'), '');
  }

  Future<Map<String, dynamic>> publicInfo(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final url = normalizeUrl(baseUrl);
    try {
      final response = await _client
          .get(Uri.parse('$url/System/Info/Public'))
          .timeout(timeout);
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

  Future<String> preferredBaseUrl() async {
    try {
      await publicInfo(
        localBaseUrl,
        timeout: const Duration(milliseconds: 900),
      );
      return localBaseUrl;
    } catch (_) {
      await publicInfo(publicBaseUrl);
      return publicBaseUrl;
    }
  }

  Future<String> discover() async {
    try {
      return await preferredBaseUrl();
    } catch (_) {
      throw const JellyfinException(
        'NetPobre não encontrou o servidor. Verifique sua internet e tente novamente.',
      );
    }
  }

  Future<JellyfinSession> authenticate({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final url = normalizeUrl(baseUrl);
    final response = await _client.post(
      Uri.parse('$url/Users/AuthenticateByName'),
      headers: {'Content-Type': 'application/json', ...deviceHeaders},
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

    return _sessionFromAuthentication(url, response.body);
  }

  Future<JellyfinSession> authenticateLocalTelevision() async {
    await publicInfo(localBaseUrl, timeout: const Duration(seconds: 2));
    return authenticate(
      baseUrl: localBaseUrl,
      username: localTelevisionUser,
      password: '',
    );
  }

  Future<QuickConnectCode> initiateQuickConnect(String baseUrl) async {
    final url = normalizeUrl(baseUrl);
    final response = await _client.post(
      Uri.parse('$url/QuickConnect/Initiate'),
      headers: deviceHeaders,
    );
    _ensurePublicSuccess(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return QuickConnectCode(
      baseUrl: url,
      code: json['Code'] as String,
      secret: json['Secret'] as String,
    );
  }

  Future<bool> quickConnectAuthorized(QuickConnectCode code) async {
    final uri = Uri.parse(
      '${code.baseUrl}/QuickConnect/Connect',
    ).replace(queryParameters: {'Secret': code.secret});
    final response = await _client.get(uri, headers: deviceHeaders);
    _ensurePublicSuccess(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['Authenticated'] as bool? ?? false;
  }

  Future<JellyfinSession> authenticateQuickConnect(
    QuickConnectCode code,
  ) async {
    final response = await _client.post(
      Uri.parse('${code.baseUrl}/Users/AuthenticateWithQuickConnect'),
      headers: {...deviceHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'Secret': code.secret}),
    );
    _ensurePublicSuccess(response);
    return _sessionFromAuthentication(code.baseUrl, response.body);
  }

  Future<JellyfinSession> _sessionFromAuthentication(
    String baseUrl,
    String body,
  ) async {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final user = json['User'] as Map<String, dynamic>;
    final info = await publicInfo(baseUrl);
    return JellyfinSession(
      baseUrl: baseUrl,
      token: json['AccessToken'] as String,
      userId: user['Id'] as String,
      userName: user['Name'] as String,
      serverName: (info['ServerName'] as String?) ?? 'Jellyfin Casa',
    );
  }

  void _ensurePublicSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JellyfinException('O servidor respondeu ${response.statusCode}.');
    }
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
            'Fields': _itemFields,
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
      query: {'Fields': _itemFields},
    );
    return MediaItem.fromJson(response);
  }

  Future<List<MediaItem>> episodes(String seriesId) async {
    final response = await _get(
      '/Shows/$seriesId/Episodes',
      query: {
        'UserId': session.userId,
        'Fields': _itemFields,
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

  Future<List<MediaItem>> resume() => _items(
    '/Users/${session.userId}/Items/Resume',
    query: {
      'Limit': '12',
      'MediaTypes': 'Video',
      'Fields': _itemFields,
      'ImageTypeLimit': '1',
      'EnableImageTypes': 'Primary,Backdrop',
    },
  );

  Future<List<MediaItem>> nextUp({String? seriesId, int limit = 12}) => _items(
    '/Shows/NextUp',
    query: {
      'UserId': session.userId,
      'Limit': '$limit',
      'SeriesId': ?seriesId,
      'Fields': _itemFields,
      'EnableImages': 'true',
      'ImageTypeLimit': '1',
      'EnableImageTypes': 'Primary,Backdrop',
      'EnableUserData': 'true',
    },
  );

  Future<List<RecommendationShelf>> recommendations() async {
    final uri = Uri.parse('${session.baseUrl}/Movies/Recommendations').replace(
      queryParameters: {
        'UserId': session.userId,
        'CategoryLimit': '4',
        'ItemLimit': '12',
        'Fields': _itemFields,
      },
    );
    final response = await _client.get(uri, headers: authHeaders);
    _ensureSuccess(response);
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(RecommendationShelf.fromJson)
        .where((shelf) => shelf.items.isNotEmpty)
        .toList();
  }

  Future<PlaybackInfo> playbackInfo(MediaItem item) async {
    final response = await _get(
      '/Items/${item.id}/PlaybackInfo',
      query: {'UserId': session.userId},
    );
    return PlaybackInfo.fromJson(response);
  }

  Future<List<MediaSegment>> mediaSegments(MediaItem item) async {
    try {
      final response = await _get(
        '/MediaSegments/${item.id}',
        query: {'IncludeSegmentTypes': 'Intro,Outro,Recap,Commercial,Preview'},
      );
      return ((response['Items'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(MediaSegment.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<MediaItem>> search(String term) {
    final query = term.trim();
    if (query.isEmpty) return Future.value(const []);
    return _items(
      '/Users/${session.userId}/Items',
      query: {
        'Recursive': 'true',
        'SearchTerm': query,
        'IncludeItemTypes': 'Movie,Series,Episode',
        'Limit': '60',
        'Fields': _itemFields,
        'ImageTypeLimit': '1',
        'EnableImageTypes': 'Primary,Backdrop',
      },
    );
  }

  Future<List<MediaItem>> favorites() => _items(
    '/Users/${session.userId}/Items',
    query: {
      'Recursive': 'true',
      'Filters': 'IsFavorite',
      'IncludeItemTypes': 'Movie,Series,Episode',
      'Limit': '100',
      'Fields': _itemFields,
      'ImageTypeLimit': '1',
      'EnableImageTypes': 'Primary,Backdrop',
    },
  );

  Future<void> setFavorite(String itemId, bool favorite) async {
    final uri = Uri.parse(
      '${session.baseUrl}/Users/${session.userId}/FavoriteItems/$itemId',
    );
    final response = favorite
        ? await _client.post(uri, headers: authHeaders)
        : await _client.delete(uri, headers: authHeaders);
    _ensureSuccess(response);
  }

  Future<void> refreshPortugueseMetadata() async {
    final libraries = await views();
    final targets = libraries.where(
      (view) =>
          view.collectionType == 'movies' || view.collectionType == 'tvshows',
    );
    for (final library in targets) {
      final uri = Uri.parse('${session.baseUrl}/Items/${library.id}/Refresh')
          .replace(
            queryParameters: {
              'metadataRefreshMode': 'FullRefresh',
              'imageRefreshMode': 'None',
              'replaceAllMetadata': 'true',
              'replaceAllImages': 'false',
            },
          );
      final response = await _client.post(uri, headers: authHeaders);
      _ensureSuccess(response);
    }
  }

  Future<List<String>> runMediaPreparationTasks() async {
    final response = await _client.get(
      Uri.parse('${session.baseUrl}/ScheduledTasks'),
      headers: authHeaders,
    );
    _ensureSuccess(response);
    final tasks = (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>();
    final selected = tasks.where((task) {
      final text = '${task['Name']} ${task['Key']}'.toLowerCase();
      return text.contains('segment') ||
          text.contains('trickplay') ||
          text.contains('subtitle');
    });
    final started = <String>[];
    for (final task in selected) {
      final id = task['Id'] as String?;
      if (id == null || task['State'] == 'Running') continue;
      final start = await _client.post(
        Uri.parse('${session.baseUrl}/ScheduledTasks/Running/$id'),
        headers: authHeaders,
      );
      if (start.statusCode >= 200 && start.statusCode < 300) {
        started.add((task['Name'] as String?) ?? 'Tarefa de mídia');
      }
    }
    return started;
  }

  Future<void> reportPlaybackStarted(
    MediaItem item,
    String playSessionId,
    Duration position,
  ) => _reportPlayback('/Sessions/Playing', item, playSessionId, position);

  Future<void> reportPlaybackProgress(
    MediaItem item,
    String playSessionId,
    Duration position, {
    required bool isPaused,
  }) => _reportPlayback(
    '/Sessions/Playing/Progress',
    item,
    playSessionId,
    position,
    isPaused: isPaused,
  );

  Future<void> reportPlaybackStopped(
    MediaItem item,
    String playSessionId,
    Duration position,
  ) => _reportPlayback(
    '/Sessions/Playing/Stopped',
    item,
    playSessionId,
    position,
  );

  Future<void> _reportPlayback(
    String path,
    MediaItem item,
    String playSessionId,
    Duration position, {
    bool isPaused = false,
  }) async {
    final response = await _client.post(
      Uri.parse('${session.baseUrl}$path'),
      headers: {...authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'ItemId': item.id,
        'MediaSourceId': item.id,
        'PlaySessionId': playSessionId,
        'PositionTicks': position.inMicroseconds * 10,
        'IsPaused': isPaused,
        'CanSeek': true,
        'PlayMethod': 'Transcode',
      }),
    );
    _ensureSuccess(response);
  }

  Future<List<MediaItem>> _items(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await _get(path, query: query);
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

  Uri downloadUrl(MediaItem item) =>
      Uri.parse('${session.baseUrl}/Items/${item.id}/Download');

  Uri trickplayUrl(
    MediaItem item,
    TrickplayInfo info,
    int spriteIndex,
  ) => Uri.parse(
    '${session.baseUrl}/Videos/${item.id}/Trickplay/${info.width}/$spriteIndex.jpg',
  ).replace(queryParameters: {'MediaSourceId': info.mediaSourceId});

  Uri playbackUrl(
    MediaItem item, {
    PlaybackQuality quality = PlaybackQuality.automatic,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final isLocal = session.baseUrl.startsWith('http://');
    final selected = quality == PlaybackQuality.automatic
        ? (isLocal ? PlaybackQuality.home : PlaybackQuality.balanced)
        : quality;
    final (maxBitrate, videoBitrate, maxWidth, maxHeight) = switch (selected) {
      PlaybackQuality.economy => ('1400000', '1150000', '854', '480'),
      PlaybackQuality.balanced => ('3000000', '2600000', '1280', '720'),
      PlaybackQuality.home => ('8000000', '7400000', '1920', '1080'),
      PlaybackQuality.automatic => ('3000000', '2600000', '1280', '720'),
    };
    return Uri.parse(
      '${session.baseUrl}/Videos/${item.id}/master.m3u8',
    ).replace(
      queryParameters: {
        'UserId': session.userId,
        'MediaSourceId': item.id,
        'VideoCodec': 'h264',
        'AudioCodec': 'aac',
        'MaxStreamingBitrate': maxBitrate,
        'VideoBitRate': videoBitrate,
        'AudioBitRate': '128000',
        'MaxWidth': maxWidth,
        'MaxHeight': maxHeight,
        if (audioStreamIndex != null) 'AudioStreamIndex': '$audioStreamIndex',
        if (subtitleStreamIndex != null)
          'SubtitleStreamIndex': '$subtitleStreamIndex',
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

class RecommendationShelf {
  const RecommendationShelf({required this.title, required this.items});

  final String title;
  final List<MediaItem> items;

  factory RecommendationShelf.fromJson(Map<String, dynamic> json) {
    final baseline = (json['BaselineItemName'] as String?)?.trim();
    return RecommendationShelf(
      title: baseline == null || baseline.isEmpty
          ? 'Escolhas para você'
          : 'Porque você assistiu $baseline',
      items: ((json['Items'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(MediaItem.fromJson)
          .toList(),
    );
  }
}

class QuickConnectCode {
  const QuickConnectCode({
    required this.baseUrl,
    required this.code,
    required this.secret,
  });

  final String baseUrl;
  final String code;
  final String secret;
}
