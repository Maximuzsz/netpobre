import 'dart:async';
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
    final request = http.Request('GET', api.downloadUrl(item));
    request.headers.addAll(api.authHeaders);
    final client = http.Client();
    File? partial;
    IOSink? sink;
    try {
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 401) {
        throw const JellyfinException(
          'Sua sessão expirou. Entre novamente para baixar.',
        );
      }
      if (response.statusCode == 403) {
        throw const JellyfinException(
          'O usuário não tem permissão para baixar no Jellyfin.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw JellyfinException(
          'O servidor recusou o download (${response.statusCode}).',
        );
      }

      final extension = _fileExtension(response.headers);
      final target = File('${directory.path}/${item.id}$extension');
      partial = File('${target.path}.part');
      if (await partial.exists()) await partial.delete();

      final total = response.contentLength ?? 0;
      var received = 0;
      var lastReported = 0.0;
      var lastUpdate = DateTime.now();
      sink = partial.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final progress = received / total;
          final now = DateTime.now();
          if (progress - lastReported >= .01 ||
              now.difference(lastUpdate) >= const Duration(milliseconds: 300)) {
            lastReported = progress;
            lastUpdate = now;
            onProgress(progress.clamp(0, 1));
          }
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (received == 0) {
        throw const JellyfinException('O servidor enviou um arquivo vazio.');
      }
      if (await target.exists()) await target.delete();
      final completed = await partial.rename(target.path);
      partial = null;

      final previous = await list();
      for (final old in previous.where((entry) => entry.item.id == item.id)) {
        final oldFile = File(old.path);
        if (old.path != completed.path && await oldFile.exists()) {
          await oldFile.delete();
        }
      }
      final downloaded = DownloadedMedia(item: item, path: completed.path);
      final entries = [
        downloaded,
        ...previous.where((entry) => entry.item.id != item.id),
      ];
      await _writeIndex(entries);
      onProgress(1);
      return downloaded;
    } on JellyfinException {
      rethrow;
    } on FileSystemException {
      throw const JellyfinException(
        'Não foi possível salvar. Verifique o espaço livre do aparelho.',
      );
    } on http.ClientException {
      throw const JellyfinException(
        'A conexão caiu durante o download. Tente novamente.',
      );
    } on SocketException {
      throw const JellyfinException(
        'A conexão caiu durante o download. Tente novamente.',
      );
    } on TimeoutException {
      throw const JellyfinException(
        'O servidor demorou para iniciar o download. Tente novamente.',
      );
    } finally {
      client.close();
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          // A falha original é mais útil do que um erro ao fechar o arquivo.
        }
      }
      if (partial != null) {
        try {
          if (await partial.exists()) await partial.delete();
        } catch (_) {
          // Um arquivo parcial antigo será substituído na próxima tentativa.
        }
      }
    }
  }

  String _fileExtension(Map<String, String> headers) {
    final disposition = headers['content-disposition'];
    if (disposition != null) {
      final match = RegExp(
        r'''filename\*?=(?:UTF-8''|\")?([^\";]+)''',
        caseSensitive: false,
      ).firstMatch(disposition);
      final rawName = match?.group(1)?.trim();
      if (rawName != null) {
        final name = Uri.decodeComponent(rawName);
        final dot = name.lastIndexOf('.');
        if (dot >= 0) {
          final extension = name.substring(dot).toLowerCase();
          if (RegExp(r'^\.[a-z0-9]{2,5}$').hasMatch(extension)) {
            return extension;
          }
        }
      }
    }

    final contentType = headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('matroska')) return '.mkv';
    if (contentType.contains('webm')) return '.webm';
    if (contentType.contains('avi')) return '.avi';
    if (contentType.contains('quicktime')) return '.mov';
    return '.mp4';
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
