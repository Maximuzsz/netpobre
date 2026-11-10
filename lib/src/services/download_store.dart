import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import 'jellyfin_api.dart';

class DownloadedMedia {
  const DownloadedMedia({required this.item, required this.path});
  final MediaItem item;
  final String path;

  Map<String, dynamic> toJson() => {'item': item.toJson(), 'path': path};

  factory DownloadedMedia.fromJson(Map<String, dynamic> json) =>
      DownloadedMedia(
        item: MediaItem.fromJson((json['item'] as Map).cast<String, dynamic>()),
        path: json['path'] as String,
      );
}

class DownloadStore {
  Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/netpobre_downloads');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> _indexFile() async =>
      File('${(await _directory()).path}/index.json');

  Future<List<DownloadedMedia>> list() async {
    final index = await _indexFile();
    if (!await index.exists()) return const [];
    try {
      final entries = (jsonDecode(await index.readAsString()) as List)
          .cast<Map<String, dynamic>>()
          .map(DownloadedMedia.fromJson)
          .toList();
      final available = <DownloadedMedia>[];
      for (final entry in entries) {
        if (await File(entry.path).exists()) available.add(entry);
      }
      return available;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> contains(String itemId) async =>
      (await list()).any((entry) => entry.item.id == itemId);

  Future<DownloadedMedia> download(
    JellyfinApi api,
    MediaItem item, {
    required void Function(double progress) onProgress,
  }) async {
    final directory = await _directory();
    final target = File('${directory.path}/${item.id}.mp4');
    final request = http.Request('GET', api.offlineDownloadUrl(item));
    request.headers.addAll(api.authHeaders);
    final response = await http.Client().send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JellyfinException('O download respondeu ${response.statusCode}.');
    }
    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = target.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
    } catch (_) {
      await sink.close();
      if (await target.exists()) await target.delete();
      rethrow;
    }
    await sink.close();
    final downloaded = DownloadedMedia(item: item, path: target.path);
    final entries = [
      downloaded,
      ...(await list()).where((entry) => entry.item.id != item.id),
    ];
    await _writeIndex(entries);
    onProgress(1);
    return downloaded;
  }

  Future<void> remove(DownloadedMedia media) async {
    final file = File(media.path);
    if (await file.exists()) await file.delete();
    await _writeIndex(
      (await list()).where((entry) => entry.item.id != media.item.id).toList(),
    );
  }

  Future<void> _writeIndex(List<DownloadedMedia> entries) async {
    final index = await _indexFile();
    await index.writeAsString(
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
      flush: true,
    );
  }
}
