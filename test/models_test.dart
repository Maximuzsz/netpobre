import 'package:casaflix/src/models/jellyfin_session.dart';
import 'package:casaflix/src/models/media_item.dart';
import 'package:casaflix/src/services/jellyfin_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      'Type': 'Episode',
      'SeriesName': 'Ted Lasso',
      'ParentIndexNumber': 4,
      'IndexNumber': 1,
      'ImageTags': {'Primary': 'poster-tag'},
      'BackdropImageTags': ['backdrop-tag'],
    });

    expect(item.playable, isTrue);
    expect(item.seriesName, 'Ted Lasso');
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
}
