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

  test('JellyfinSession serializes without losing fields', () {
    const session = JellyfinSession(
      baseUrl: 'https://jellyfin-casa.example.ts.net',
      token: 'secret',
      userId: 'user-1',
      userName: 'netpobre',
      serverName: 'Jellyfin Casa',
    );

    expect(
      JellyfinSession.fromJson(session.toJson()).serverName,
      'Jellyfin Casa',
    );
  });
}
