import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.fileSize,
    required this.digest,
    required this.releaseUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri downloadUrl;
  final int fileSize;
  final String? digest;
  final Uri releaseUrl;

  bool get updateAvailable => AppUpdater.isVersionNewer(
    latestVersion: latestVersion,
    currentVersion: currentVersion,
  );
}

class AppUpdaterException implements Exception {
  const AppUpdaterException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppUpdater {
  AppUpdater({http.Client? client}) : _client = client ?? http.Client();

  static const _repository = 'Maximuzsz/netpobre';
  static const _channel = MethodChannel('netpobre/app_update');
  final http.Client _client;

  Future<AppUpdateInfo> check() async {
    if (!Platform.isAndroid) {
      throw const AppUpdaterException(
        'A atualização automática está disponível apenas no Android.',
      );
    }

    final response = await _client
        .get(
          Uri.parse(
            'https://api.github.com/repos/$_repository/releases/latest',
          ),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'NetPobre-App-Updater',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw AppUpdaterException(
        'O GitHub respondeu com o código ${response.statusCode}. Tente novamente.',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final assets = (body['assets'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final asset = assets.cast<Map<String, dynamic>?>().firstWhere(
      (candidate) => candidate?['name'] == 'NetPobre.apk',
      orElse: () => null,
    );
    if (asset == null) {
      throw const AppUpdaterException(
        'A versão mais recente não contém o instalador Android.',
      );
    }

    final currentVersion =
        await _channel.invokeMethod<String>('getVersion') ?? '0.0.0';
    final latestVersion = (body['tag_name'] as String? ?? '0.0.0').replaceFirst(
      RegExp(r'^[vV]'),
      '',
    );
    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      downloadUrl: Uri.parse(asset['browser_download_url'] as String),
      fileSize: (asset['size'] as num?)?.toInt() ?? 0,
      digest: asset['digest'] as String?,
      releaseUrl: Uri.parse(body['html_url'] as String),
    );
  }

  Future<File> download(
    AppUpdateInfo update, {
    required void Function(int received, int total) onProgress,
  }) async {
    final request = http.Request('GET', update.downloadUrl)
      ..headers['User-Agent'] = 'NetPobre-App-Updater';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw AppUpdaterException(
        'Não foi possível baixar a atualização (${response.statusCode}).',
      );
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final updateDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}updates',
    );
    await updateDirectory.create(recursive: true);
    await _removeOldInstallers(updateDirectory);
    final target = File(
      '${updateDirectory.path}${Platform.pathSeparator}NetPobre-${update.latestVersion}.apk',
    );
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();

    final output = partial.openWrite();
    final digestOutput = _DigestSink();
    final digestSink = sha256.startChunkedConversion(digestOutput);
    var received = 0;
    final total = update.fileSize > 0
        ? update.fileSize
        : response.contentLength ?? 0;
    try {
      await for (final chunk in response.stream) {
        output.add(chunk);
        digestSink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await output.flush();
      await output.close();
      digestSink.close();
    } catch (_) {
      await output.close();
      digestSink.close();
      rethrow;
    }

    if (total > 0 && received != total) {
      await partial.delete();
      throw AppUpdaterException(
        'O download terminou incompleto: $received de $total bytes.',
      );
    }
    final expectedDigest = update.digest
        ?.replaceFirst('sha256:', '')
        .toLowerCase();
    if (expectedDigest != null &&
        expectedDigest.isNotEmpty &&
        digestOutput.value.toString().toLowerCase() != expectedDigest) {
      await partial.delete();
      throw const AppUpdaterException(
        'A atualização baixada não passou na verificação de segurança.',
      );
    }

    if (await target.exists()) await target.delete();
    return partial.rename(target.path);
  }

  Future<String> install(File apk) async {
    return await _channel.invokeMethod<String>('installApk', {
          'path': apk.path,
        }) ??
        'started';
  }

  Future<void> _removeOldInstallers(Directory directory) async {
    await for (final entity in directory.list()) {
      if (entity is File &&
          (entity.path.endsWith('.apk') || entity.path.endsWith('.part'))) {
        await entity.delete();
      }
    }
  }

  void dispose() => _client.close();

  static bool isVersionNewer({
    required String latestVersion,
    required String currentVersion,
  }) {
    final latest = _versionParts(latestVersion);
    final current = _versionParts(currentVersion);
    final length = latest.length > current.length
        ? latest.length
        : current.length;
    for (var index = 0; index < length; index++) {
      final left = index < latest.length ? latest[index] : 0;
      final right = index < current.length ? current[index] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  static List<int> _versionParts(String version) {
    return version
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
