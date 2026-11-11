import 'package:casaflix/src/models/jellyfin_session.dart';
import 'package:casaflix/src/models/media_item.dart';
import 'package:casaflix/src/models/playback.dart';
import 'package:casaflix/src/services/jellyfin_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:casaflix/src/services/app_updater.dart';

void main() {
  group('AppUpdater', () {
    test('detects a newer semantic version', () {
      expect(
        AppUpdater.isVersionNewer(
          latestVersion: '1.7.0',
          currentVersion: '1.6.1',
        ),
        isTrue,
      );
    });

    test('does not downgrade or reinstall the same version', () {
      expect(
        AppUpdater.isVersionNewer(
          latestVersion: 'v1.6.1',
          currentVersion: '1.6.1',
        ),
        isFalse,
      );
      expect(
        AppUpdater.isVersionNewer(
          latestVersion: '1.5.9',
          currentVersion: '1.6.1',
        ),
        isFalse,
      );
    });
  });

  group('JellyfinApi.normalizeUrl', () {
    test('adds HTTPS and removes trailing slashes', () {
      expect(
        JellyfinApi.normalizeUrl(' jellyfin-casa/// '),
        'https://jellyfin-casa',
      );
    });

    test('preserves an explicit HTTP URL', () {
      expect(
        JellyfinApi.normalizeUrl('http://100.121.61.85:8096/'),
        'http://100.121.61.85:8096',
      );
    });
  });

  test('MediaItem reads Jellyfin image and episode metadata', () {
    final item = MediaItem.fromJson({
      'Id': 'episode-1',
      'Name': 'Casa',
      'OriginalTitle': 'Home',
      'Type': 'Episode',
      'SeriesName': 'Ted Lasso',
      'ParentIndexNumber': 4,
      'IndexNumber': 1,
      'ImageTags': {'Primary': 'poster-tag'},
      'BackdropImageTags': ['backdrop-tag'],
    });

    expect(item.playable, isTrue);
    expect(item.seriesName, 'Ted Lasso');
    expect(item.originalTitle, 'Home');
    expect(item.parentIndexNumber, 4);
    expect(item.indexNumber, 1);
    expect(item.imageTag, 'poster-tag');
    expect(item.backdropTag, 'backdrop-tag');
  });

  test('MediaItem reads resume progress and favorites from UserData', () {
    final item = MediaItem.fromJson({
      'Id': 'movie-1',
      'Name': 'Filme',
      'Type': 'Movie',
      'UserData': {
        'PlaybackPositionTicks': 900000000,
        'PlayedPercentage': 42.5,
        'IsFavorite': true,
        'Played': false,
      },
    });

    expect(item.resumePosition, const Duration(seconds: 90));
    expect(item.progress, 0.425);
    expect(item.isFavorite, isTrue);
    expect(item.played, isFalse);
  });

  test('JellyfinSession serializes without losing fields', () {
    const session = JellyfinSession(
      baseUrl: 'https://jellyfin-casa.example.ts.net',
      token: 'secret',
      userId: 'user-1',
      userName: 'netpobre',
      serverName: 'NetPobre',
    );

    expect(JellyfinSession.fromJson(session.toJson()).serverName, 'NetPobre');
  });

  test('mobile playback is capped at a stable 720p bitrate', () {
    const session = JellyfinSession(
      baseUrl: 'https://netpobre.example.ts.net',
      token: 'token',
      userId: 'user-1',
      userName: 'netpobre',
      serverName: 'NetPobre',
    );
    const item = MediaItem(id: 'video-1', name: 'Filme', type: 'Movie');

    final url = JellyfinApi(session: session).playbackUrl(item);

    expect(url.queryParameters['MaxStreamingBitrate'], '3000000');
    expect(url.queryParameters['VideoBitRate'], '2600000');
    expect(url.queryParameters['MaxHeight'], '720');
  });

  test('authenticated requests prefer Brazilian Portuguese metadata', () {
    const session = JellyfinSession(
      baseUrl: 'https://netpobre.example.ts.net',
      token: 'token',
      userId: 'user-1',
      userName: 'netpobre',
      serverName: 'NetPobre',
    );

    final headers = JellyfinApi(session: session).authHeaders;

    expect(headers['Accept-Language'], startsWith('pt-BR'));
  });

  test('playback quality changes bitrate and resolution', () {
    const session = JellyfinSession(
      baseUrl: 'https://netpobre.example.ts.net',
      token: 'token',
      userId: 'user-1',
      userName: 'netpobre',
      serverName: 'NetPobre',
    );
    const item = MediaItem(id: 'video-1', name: 'Filme', type: 'Movie');
    final api = JellyfinApi(session: session);

    final economy = api.playbackUrl(item, quality: PlaybackQuality.economy);
    final home = api.playbackUrl(item, quality: PlaybackQuality.home);

    expect(economy.queryParameters['MaxHeight'], '480');
    expect(home.queryParameters['MaxHeight'], '1080');
    expect(home.queryParameters['MaxStreamingBitrate'], '8000000');
  });

  test('playback info separates audio and subtitle tracks', () {
    final info = PlaybackInfo.fromJson({
      'PlaySessionId': 'play-1',
      'MediaSources': [
        {
          'DefaultAudioStreamIndex': 1,
          'MediaStreams': [
            {'Index': 1, 'Type': 'Audio', 'DisplayTitle': 'Português'},
            {'Index': 2, 'Type': 'Subtitle', 'DisplayTitle': 'Português'},
          ],
        },
      ],
    });

    expect(info.audioStreams.single.index, 1);
    expect(info.subtitleStreams.single.index, 2);
    expect(info.defaultAudioStreamIndex, 1);
  });

  test('media segments expose the correct skip label', () {
    final segment = MediaSegment.fromJson({
      'Type': 'Intro',
      'StartTicks': 100000000,
      'EndTicks': 300000000,
    });

    expect(segment.actionLabel, 'Pular abertura');
    expect(segment.contains(const Duration(seconds: 20)), isTrue);
  });

  test('offline download uses the Jellyfin direct-download endpoint', () {
    const session = JellyfinSession(
      baseUrl: 'https://netpobre.example.ts.net',
      token: 'token',
      userId: 'user-1',
      userName: 'netpobre',
      serverName: 'NetPobre',
    );
    const item = MediaItem(id: 'video-1', name: 'Filme', type: 'Movie');

    final url = JellyfinApi(session: session).downloadUrl(item);

    expect(url.path, '/Items/video-1/Download');
    expect(url.queryParameters, isEmpty);
  });
}
