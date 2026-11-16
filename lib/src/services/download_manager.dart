import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import 'jellyfin_api.dart';

class ManagedDownload {
  const ManagedDownload({required this.record, required this.item, this.path});

  final TaskRecord record;
  final MediaItem item;
  final String? path;

  DownloadTask get task => record.task as DownloadTask;
  TaskStatus get status => record.status;
  double get progress => record.progress.clamp(0, 1);
  bool get complete => status == TaskStatus.complete && path != null;
  bool get active => switch (status) {
    TaskStatus.enqueued ||
    TaskStatus.running ||
    TaskStatus.waitingToRetry ||
    TaskStatus.paused => true,
    _ => false,
  };
}

class DownloadManager {
  DownloadManager._();

  static final instance = DownloadManager._();
  static const group = 'netpobre_media';
  static const _playbackPauseFileName =
      'netpobre_playback_paused_downloads.json';
  static const _legacyRecoveryFileName =
      'netpobre_download_recovery_1_8_2.done';
  static const _canceledRecoveryFileName =
      'netpobre_download_recovery_1_9_1.done';

  final ValueNotifier<List<ManagedDownload>> downloads = ValueNotifier(
    const [],
  );
  final Map<String, TaskRecord> _records = {};
  final Set<String> _removedTaskIds = {};
  StreamSubscription<TaskRecord>? _databaseSubscription;
  Timer? _emitTimer;
  bool _initialized = false;

  FileDownloader get _downloader => FileDownloader();

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _databaseSubscription = _downloader.database.updates.listen((record) {
        if (record.group != group) return;
        if (_removedTaskIds.contains(record.taskId)) {
          unawaited(_downloader.database.deleteRecordWithId(record.taskId));
          return;
        }
        _records[record.taskId] = record;
        _scheduleEmit();
      });

      _downloader.configureNotificationForGroup(
        group,
        running: const TaskNotification(
          'NetPobre está baixando',
          '{displayName} · {progress}',
        ),
        complete: const TaskNotification(
          'Pronto para assistir',
          '{displayName} está disponível offline.',
        ),
        error: const TaskNotification(
          'Download interrompido',
          'Abra o NetPobre para tentar novamente.',
        ),
        paused: const TaskNotification('Download pausado', '{displayName}'),
        canceled: const TaskNotification('Download cancelado', '{displayName}'),
        progressBar: true,
        groupNotificationId: 'netpobre_downloads',
      );

      await _downloader.configure(
        globalConfig: [
          (Config.requestTimeout, const Duration(seconds: 30)),
          (Config.holdingQueue, (2, 1, 1)),
          (Config.checkAvailableSpace, 250),
        ],
        androidConfig: [
          (Config.useCacheDir, Config.never),
          (Config.runInForegroundIfFileLargerThan, 25),
        ],
        iOSConfig: [
          (Config.excludeFromCloudBackup, Config.always),
          (
            Config.localize,
            {'Cancel': 'Cancelar', 'Pause': 'Pausar', 'Resume': 'Continuar'},
          ),
        ],
      );

      await _downloader.start(autoCleanDatabase: false);
      _initialized = true;
      await refresh();
      await _recoverPlaybackPausedDownloads();
      await _recoverDownloadsPausedByPreviousVersion();
      await _recoverDownloadsCanceledByPreviousVersion();
    } catch (_) {
      await _databaseSubscription?.cancel();
      _databaseSubscription = null;
      _initialized = false;
      rethrow;
    }
  }

  Future<void> refresh() async {
    final records = await _downloader.database.allRecords(group: group);
    _records
      ..clear()
      ..addEntries(records.map((record) => MapEntry(record.taskId, record)));
    await _emit();
  }

  Future<bool> contains(String itemId) async {
    if (!_initialized) await initialize();
    return downloads.value.any(
      (entry) =>
          entry.item.id == itemId &&
          entry.status != TaskStatus.canceled &&
          entry.status != TaskStatus.notFound,
    );
  }

  Future<bool> enqueue(JellyfinApi api, MediaItem item) async {
    if (!_initialized) await initialize();
    if (await contains(item.id)) return false;

    final permission = await _downloader.permissions.status(
      PermissionType.notifications,
    );
    if (permission != PermissionStatus.granted) {
      await _downloader.permissions.request(PermissionType.notifications);
    }

    DownloadTask task = DownloadTask(
      taskId: 'netpobre_${item.id}_${DateTime.now().millisecondsSinceEpoch}',
      url: api.downloadUrl(item).toString(),
      filename: DownloadTask.suggestedFilename,
      headers: api.authHeaders,
      directory: 'netpobre_downloads',
      baseDirectory: BaseDirectory.applicationDocuments,
      group: group,
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: true,
      // Large media already runs in a foreground service. Avoid Android's
      // special UIDT path, which some devices cancel while changing apps.
      priority: 5,
      metaData: jsonEncode(item.toJson()),
      displayName: item.seriesName == null
          ? item.name
          : '${item.seriesName} · ${item.name}',
    );
    task = await task.withSuggestedFilename(unique: true);
    final accepted = await _downloader.enqueue(task);
    if (!accepted) {
      throw const JellyfinException(
        'Não foi possível adicionar este título à fila.',
      );
    }
    await refresh();
    return true;
  }

  Future<bool> pause(ManagedDownload entry) => _downloader.pause(entry.task);

  Future<bool> resume(ManagedDownload entry) => _resumeOrRestart(entry);

  Future<bool> retry(ManagedDownload entry) => _resumeOrRestart(entry);

  Future<bool> _resumeOrRestart(ManagedDownload entry) async {
    try {
      if (await _downloader.resume(entry.task)) return true;
    } catch (_) {
      // A partial file can become invalid after Android stops the process.
      // Restarting the same media is safer than leaving a stuck queue entry.
    }
    try {
      return await _restart(entry);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _restart(ManagedDownload entry) async {
    _removedTaskIds.add(entry.record.taskId);
    await _downloader.cancel(entry.task);
    await _downloader.database.deleteRecordWithId(entry.record.taskId);
    final replacement = entry.task.copyWith(
      taskId:
          'netpobre_${entry.item.id}_${DateTime.now().millisecondsSinceEpoch}',
      creationTime: DateTime.now(),
      retries: 3,
      priority: 5,
    );
    final accepted = await _downloader.enqueue(replacement);
    await refresh();
    return accepted;
  }

  Future<void> remove(ManagedDownload entry) async {
    _removedTaskIds.add(entry.record.taskId);
    await _downloader.cancel(entry.task);
    final path = entry.path ?? await entry.task.filePath();
    final file = File(path);
    if (await file.exists()) await file.delete();
    await _downloader.database.deleteRecordWithId(entry.record.taskId);
    _records.remove(entry.record.taskId);
    await _emit();
  }

  Future<void> pauseAll() async {
    await _downloader.pauseAll(group: group);
  }

  Future<void> resumeAll() async {
    if (!_initialized) await initialize();
    await refresh();
    for (final entry in downloads.value.where(
      (entry) => entry.status == TaskStatus.paused,
    )) {
      await _resumeOrRestart(entry);
    }
    await refresh();
  }

  Future<Set<String>> pauseActiveForPlayback() async {
    if (!_initialized) await initialize();
    await refresh();
    final active = downloads.value.where(
      (entry) =>
          entry.status == TaskStatus.running ||
          entry.status == TaskStatus.waitingToRetry,
    );
    final markerIds = await _readPlaybackPauseIds();
    final candidates = active.map((entry) => entry.record.taskId).toSet();
    await _writePlaybackPauseIds({...markerIds, ...candidates});
    final paused = <String>{};
    for (final entry in active) {
      try {
        if (await _downloader.pause(entry.task)) {
          paused.add(entry.record.taskId);
        }
      } catch (_) {
        // The final marker below removes tasks that were not paused.
      }
    }
    await _writePlaybackPauseIds({...markerIds, ...paused});
    if (paused.isNotEmpty) await refresh();
    return paused;
  }

  Future<void> resumeAfterPlayback(Set<String> taskIds) async {
    if (taskIds.isEmpty) return;
    if (!_initialized) await initialize();
    await refresh();
    final storedIds = await _readPlaybackPauseIds();
    final remaining = storedIds.difference(taskIds);
    for (final entry in downloads.value) {
      if (taskIds.contains(entry.record.taskId) &&
          (entry.status == TaskStatus.paused ||
              entry.status == TaskStatus.failed ||
              entry.status == TaskStatus.canceled ||
              entry.status == TaskStatus.notFound)) {
        if (await _resumeOrRestart(entry)) {
          remaining.remove(entry.record.taskId);
        } else {
          remaining.add(entry.record.taskId);
        }
      } else if (taskIds.contains(entry.record.taskId)) {
        remaining.remove(entry.record.taskId);
      }
    }
    await _writePlaybackPauseIds(remaining);
    await refresh();
  }

  Future<void> _recoverPlaybackPausedDownloads() async {
    final taskIds = await _readPlaybackPauseIds();
    if (taskIds.isEmpty) return;
    await resumeAfterPlayback(taskIds);
  }

  Future<void> _recoverDownloadsPausedByPreviousVersion() async {
    final directory = await getApplicationSupportDirectory();
    final marker = File(
      '${directory.path}${Platform.pathSeparator}$_legacyRecoveryFileName',
    );
    if (await marker.exists()) return;

    // 1.8.1 could lose the in-memory list when Android closed the player/app.
    // Resume paused records once so existing affected installations self-heal.
    await refresh();
    var recovered = true;
    for (final entry in downloads.value.where(
      (entry) => entry.status == TaskStatus.paused,
    )) {
      if (!await _resumeOrRestart(entry)) recovered = false;
    }
    if (recovered) {
      await marker.parent.create(recursive: true);
      await marker.writeAsString('recovered');
    }
    await refresh();
  }

  Future<void> _recoverDownloadsCanceledByPreviousVersion() async {
    final directory = await getApplicationSupportDirectory();
    final marker = File(
      '${directory.path}${Platform.pathSeparator}$_canceledRecoveryFileName',
    );
    if (await marker.exists()) return;

    await refresh();
    var recovered = true;
    for (final entry in downloads.value.where(
      (entry) =>
          entry.status == TaskStatus.failed ||
          entry.status == TaskStatus.canceled,
    )) {
      if (!await _resumeOrRestart(entry)) recovered = false;
    }
    if (recovered) {
      await marker.parent.create(recursive: true);
      await marker.writeAsString('recovered');
    }
    await refresh();
  }

  Future<File> _playbackPauseFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}$_playbackPauseFileName',
    );
  }

  Future<Set<String>> _readPlaybackPauseIds() async {
    try {
      final file = await _playbackPauseFile();
      if (!await file.exists()) return <String>{};
      final values = jsonDecode(await file.readAsString()) as List<dynamic>;
      return values.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _writePlaybackPauseIds(Set<String> taskIds) async {
    final file = await _playbackPauseFile();
    if (taskIds.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(taskIds.toList()..sort()));
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  void _scheduleEmit() {
    _emitTimer?.cancel();
    _emitTimer = Timer(const Duration(milliseconds: 100), _emit);
  }

  Future<void> _emit() async {
    final result = <ManagedDownload>[];
    final staleIds = <String>[];
    for (final record in _records.values) {
      try {
        final raw = jsonDecode(record.task.metaData) as Map<String, dynamic>;
        final item = MediaItem.fromJson(raw);
        String? path;
        if (record.status == TaskStatus.complete) {
          path = await record.task.filePath();
          if (!await File(path).exists()) {
            staleIds.add(record.taskId);
            continue;
          }
        }
        result.add(ManagedDownload(record: record, item: item, path: path));
      } catch (_) {
        // Ignore records that do not belong to the NetPobre media schema.
      }
    }
    result.sort((a, b) {
      final aRank = a.complete ? 1 : 0;
      final bRank = b.complete ? 1 : 0;
      if (aRank != bRank) return aRank.compareTo(bRank);
      return b.record.task.creationTime.compareTo(a.record.task.creationTime);
    });
    downloads.value = List.unmodifiable(result);
    for (final id in staleIds) {
      _records.remove(id);
      await _downloader.database.deleteRecordWithId(id);
    }
  }

  @visibleForTesting
  Future<void> dispose() async {
    _emitTimer?.cancel();
    await _databaseSubscription?.cancel();
    _initialized = false;
  }
}
