import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
import '../models/playback.dart';
import '../services/jellyfin_api.dart';
import '../theme.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.api, required this.item});

  final JellyfinApi api;
  final MediaItem item;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  late MediaItem _item = widget.item;
  PlaybackInfo _playbackInfo = const PlaybackInfo();
  List<MediaSegment> _segments = const [];
  MediaItem? _nextEpisode;
  PlaybackQuality _quality = PlaybackQuality.automatic;
  int? _audioStreamIndex;
  int _subtitleStreamIndex = -1;
  String _playSessionId = '';
  bool _controls = true;
  bool _started = false;
  bool _loading = true;
  bool _switchingSource = false;
  Duration _lastReported = Duration.zero;
  String? _error;
  Timer? _autoplayTimer;
  int? _autoplaySeconds;
  Duration? _seekPreview;

  VideoPlayerValue? get _value => _controller?.value;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadItem(_item);
  }

  Future<void> _loadItem(MediaItem item, {Duration? startAt}) async {
    _autoplayTimer?.cancel();
    final previous = _controller;
    if (previous != null) {
      previous.removeListener(_tick);
      if (_started) {
        _ignore(
          widget.api.reportPlaybackStopped(
            _item,
            _playSessionId,
            previous.value.position,
          ),
        );
      }
      await previous.dispose();
    }

    if (mounted) {
      setState(() {
        _item = item;
        _controller = null;
        _loading = true;
        _started = false;
        _error = null;
        _autoplaySeconds = null;
        _lastReported = Duration.zero;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        widget.api.playbackInfo(item),
        widget.api.mediaSegments(item),
        if (item.type == 'Episode')
          widget.api.nextUp(seriesId: item.seriesId, limit: 4),
      ]);
      if (!mounted) return;
      _playbackInfo = results[0] as PlaybackInfo;
      _segments = results[1] as List<MediaSegment>;
      _nextEpisode = item.type == 'Episode'
          ? (results[2] as List<MediaItem>)
                .where((candidate) => candidate.id != item.id)
                .firstOrNull
          : null;
      _audioStreamIndex ??= _playbackInfo.defaultAudioStreamIndex;
      if (_subtitleStreamIndex < 0 &&
          _playbackInfo.defaultSubtitleStreamIndex != null) {
        _subtitleStreamIndex = _playbackInfo.defaultSubtitleStreamIndex!;
      }
      _playSessionId =
          _playbackInfo.playSessionId ??
          '${item.id}-${DateTime.now().microsecondsSinceEpoch}';

      final controller = VideoPlayerController.networkUrl(
        widget.api.playbackUrl(
          item,
          quality: _quality,
          audioStreamIndex: _audioStreamIndex,
          subtitleStreamIndex: _subtitleStreamIndex,
        ),
        httpHeaders: widget.api.authHeaders,
      );
      _controller = controller;
      controller.addListener(_tick);
      await controller.initialize();
      if (!mounted || _controller != controller) return;
      final resume = startAt ?? item.resumePosition;
      final duration = controller.value.duration;
      if (resume > const Duration(seconds: 5) &&
          resume < duration - const Duration(seconds: 5)) {
        await controller.seekTo(resume);
      }
      _started = true;
      _ignore(
        widget.api.reportPlaybackStarted(
          item,
          _playSessionId,
          controller.value.position,
        ),
      );
      await controller.play();
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível iniciar o vídeo. Verifique a conexão.';
        });
      }
    }
  }

  void _tick() {
    if (!mounted || _switchingSource) return;
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (_started &&
        (value.position - _lastReported).abs() >= const Duration(seconds: 10)) {
      _lastReported = value.position;
      _ignore(
        widget.api.reportPlaybackProgress(
          _item,
          _playSessionId,
          value.position,
          isPaused: !value.isPlaying,
        ),
      );
    }
    if (_nextEpisode != null &&
        value.duration > Duration.zero &&
        value.position >= value.duration - const Duration(seconds: 2) &&
        _autoplaySeconds == null) {
      _startAutoplay();
    }
    setState(() {});
  }

  void _startAutoplay() {
    _autoplaySeconds = 10;
    _controls = true;
    _autoplayTimer?.cancel();
    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      final remaining = (_autoplaySeconds ?? 1) - 1;
      if (remaining <= 0) {
        timer.cancel();
        _playNext();
      } else {
        setState(() => _autoplaySeconds = remaining);
      }
    });
  }

  Future<void> _playNext() async {
    final next = _nextEpisode;
    if (next == null) return;
    _audioStreamIndex = null;
    _subtitleStreamIndex = -1;
    await _loadItem(next);
  }

  void _cancelAutoplay() {
    _autoplayTimer?.cancel();
    setState(() => _autoplaySeconds = null);
  }

  void _ignore(Future<void> future) {
    unawaited(future.catchError((_) {}));
  }

  Future<void> _seekBy(Duration offset) async {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    final target = value.position + offset;
    await controller.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > value.duration
          ? value.duration
          : target,
    );
  }

  Future<void> _changeSource({
    PlaybackQuality? quality,
    int? audio,
    int? subtitle,
    bool changeAudio = false,
    bool changeSubtitle = false,
  }) async {
    final position = _controller?.value.position ?? Duration.zero;
    setState(() {
      _switchingSource = true;
      if (quality != null) _quality = quality;
      if (changeAudio) _audioStreamIndex = audio;
      if (changeSubtitle) _subtitleStreamIndex = subtitle ?? -1;
    });
    await _loadItem(_item, startAt: position);
    if (mounted) setState(() => _switchingSource = false);
  }

  MediaSegment? get _activeSegment {
    final position = _value?.position;
    if (position == null) return null;
    return _segments.where((segment) => segment.contains(position)).firstOrNull;
  }

  Future<void> _showPlaybackSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: CasaFlixColors.deepSea,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Qualidade',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              RadioGroup<PlaybackQuality>(
                groupValue: _quality,
                onChanged: (value) {
                  Navigator.pop(context);
                  if (value != null) _changeSource(quality: value);
                },
                child: Column(
                  children: [
                    for (final option in PlaybackQuality.values)
                      RadioListTile<PlaybackQuality>(
                        value: option,
                        title: Text(option.label),
                      ),
                  ],
                ),
              ),
              if (_playbackInfo.audioStreams.isNotEmpty) ...[
                const Divider(),
                const Text(
                  'Áudio',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                RadioGroup<int>(
                  groupValue: _audioStreamIndex,
                  onChanged: (value) {
                    Navigator.pop(context);
                    _changeSource(audio: value, changeAudio: true);
                  },
                  child: Column(
                    children: [
                      for (final stream in _playbackInfo.audioStreams)
                        RadioListTile<int>(
                          value: stream.index,
                          title: Text(stream.displayTitle),
                          subtitle: stream.codec == null
                              ? null
                              : Text(stream.codec!.toUpperCase()),
                        ),
                    ],
                  ),
                ),
              ],
              if (_playbackInfo.subtitleStreams.isNotEmpty) ...[
                const Divider(),
                const Text(
                  'Legendas',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                RadioGroup<int>(
                  groupValue: _subtitleStreamIndex,
                  onChanged: (value) {
                    Navigator.pop(context);
                    _changeSource(subtitle: value, changeSubtitle: true);
                  },
                  child: Column(
                    children: [
                      const RadioListTile<int>(
                        value: -1,
                        title: Text('Desativadas'),
                      ),
                      for (final stream in _playbackInfo.subtitleStreams)
                        RadioListTile<int>(
                          value: stream.index,
                          title: Text(stream.displayTitle),
                          subtitle: Text(
                            '${stream.codec?.toUpperCase() ?? 'Legenda'}${stream.isExternal ? ' · externa' : ''}',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    final controller = _controller;
    controller?.removeListener(_tick);
    if (_started && controller != null) {
      _ignore(
        widget.api.reportPlaybackStopped(
          _item,
          _playSessionId,
          controller.value.position,
        ),
      );
    }
    controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  String _time(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:$minutes:$seconds'
        : '${value.inMinutes}:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final value = _value;
    final activeSegment = _activeSegment;
    return Scaffold(
      backgroundColor: Colors.black,
      body: FocusTraversalGroup(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _controls = !_controls),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (controller != null && value?.isInitialized == true)
                Center(
                  child: AspectRatio(
                    aspectRatio: value!.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                )
              else if (_error == null)
                const Center(child: CircularProgressIndicator()),
              if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                ),
              if (_controls && value?.isInitialized == true)
                _PlayerControls(
                  api: widget.api,
                  item: _item,
                  value: value!,
                  time: _time,
                  onBack: () => Navigator.pop(context),
                  onSeekBack: () => _seekBy(const Duration(seconds: -10)),
                  onSeekForward: () => _seekBy(const Duration(seconds: 10)),
                  onPlayPause: () => value.isPlaying
                      ? controller!.pause()
                      : controller!.play(),
                  onSettings: _showPlaybackSettings,
                  seekPreview: _seekPreview,
                  onSeekPreview: (position) =>
                      setState(() => _seekPreview = position),
                  onSeekEnd: (position) {
                    controller!.seekTo(position);
                    setState(() => _seekPreview = null);
                  },
                ),
              if (activeSegment != null && _autoplaySeconds == null)
                Positioned(
                  right: 28,
                  bottom: 88,
                  child: FilledButton(
                    onPressed: () => controller?.seekTo(activeSegment.end),
                    child: Text(activeSegment.actionLabel),
                  ),
                ),
              if (_autoplaySeconds != null && _nextEpisode != null)
                _NextEpisodeCard(
                  next: _nextEpisode!,
                  seconds: _autoplaySeconds!,
                  onPlay: _playNext,
                  onCancel: _cancelAutoplay,
                ),
              if ((value?.isBuffering == true &&
                      value?.isInitialized == true) ||
                  _loading ||
                  _switchingSource)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  const _PlayerControls({
    required this.item,
    required this.api,
    required this.value,
    required this.time,
    required this.onBack,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onPlayPause,
    required this.onSettings,
    required this.seekPreview,
    required this.onSeekPreview,
    required this.onSeekEnd,
  });

  final JellyfinApi api;
  final MediaItem item;
  final VideoPlayerValue value;
  final String Function(Duration) time;
  final VoidCallback onBack;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final VoidCallback onPlayPause;
  final VoidCallback onSettings;
  final Duration? seekPreview;
  final ValueChanged<Duration> onSeekPreview;
  final ValueChanged<Duration> onSeekEnd;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xAA000000), Colors.transparent, Color(0xCC000000)],
          stops: [0, .5, 1],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  autofocus: true,
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.seriesName ?? item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (item.seriesName != null)
                        Text(
                          'T${item.parentIndexNumber ?? '-'} E${item.indexNumber ?? '-'} · ${item.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: CasaFlixColors.muted),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Áudio, legenda e qualidade',
                  onPressed: onSettings,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Voltar 10 segundos',
                  onPressed: onSeekBack,
                  iconSize: 38,
                  icon: const Icon(Icons.replay_10_rounded),
                ),
                const SizedBox(width: 26),
                IconButton.filled(
                  onPressed: onPlayPause,
                  style: IconButton.styleFrom(
                    backgroundColor: CasaFlixColors.amber,
                    foregroundColor: CasaFlixColors.night,
                  ),
                  iconSize: 42,
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 26),
                IconButton(
                  tooltip: 'Avançar 10 segundos',
                  onPressed: onSeekForward,
                  iconSize: 38,
                  icon: const Icon(Icons.forward_10_rounded),
                ),
              ],
            ),
            const Spacer(),
            if (seekPreview != null && item.trickplay != null) ...[
              _TrickplayThumbnail(
                api: api,
                item: item,
                info: item.trickplay!,
                position: seekPreview!,
              ),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
              child: Row(
                children: [
                  Text(time(value.position)),
                  Expanded(
                    child: Slider(
                      value: value.duration.inMilliseconds == 0
                          ? 0
                          : value.position.inMilliseconds
                                .clamp(0, value.duration.inMilliseconds)
                                .toDouble(),
                      max: value.duration.inMilliseconds.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                      onChanged: (position) => onSeekPreview(
                        Duration(milliseconds: position.round()),
                      ),
                      onChangeEnd: (position) =>
                          onSeekEnd(Duration(milliseconds: position.round())),
                    ),
                  ),
                  Text(time(value.duration)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrickplayThumbnail extends StatelessWidget {
  const _TrickplayThumbnail({
    required this.api,
    required this.item,
    required this.info,
    required this.position,
  });

  final JellyfinApi api;
  final MediaItem item;
  final TrickplayInfo info;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    final thumbnail = (position.inMilliseconds ~/ info.intervalMs).clamp(
      0,
      (info.thumbnailCount - 1).clamp(0, 1 << 30),
    );
    final sprite = thumbnail ~/ info.cellsPerSheet;
    final cell = thumbnail % info.cellsPerSheet;
    final column = cell % info.tileWidth;
    final row = cell ~/ info.tileWidth;
    return Container(
      width: info.width.toDouble(),
      height: info.height.toDouble() + 30,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CasaFlixColors.deepSea,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white54),
      ),
      child: Column(
        children: [
          SizedBox(
            width: info.width.toDouble(),
            height: info.height.toDouble(),
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: info.width * info.tileWidth.toDouble(),
                maxWidth: info.width * info.tileWidth.toDouble(),
                minHeight: info.height * info.tileHeight.toDouble(),
                maxHeight: info.height * info.tileHeight.toDouble(),
                child: Transform.translate(
                  offset: Offset(
                    -column * info.width.toDouble(),
                    -row * info.height.toDouble(),
                  ),
                  child: Image.network(
                    api.trickplayUrl(item, info, sprite).toString(),
                    headers: api.authHeaders,
                    width: info.width * info.tileWidth.toDouble(),
                    height: info.height * info.tileHeight.toDouble(),
                    fit: BoxFit.fill,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: CasaFlixColors.ink),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                _previewTime(position),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _previewTime(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _NextEpisodeCard extends StatelessWidget {
  const _NextEpisodeCard({
    required this.next,
    required this.seconds,
    required this.onPlay,
    required this.onCancel,
  });

  final MediaItem next;
  final int seconds;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xDD000000),
      child: Center(
        child: Container(
          width: 430,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: CasaFlixColors.deepSea,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A seguir',
                style: TextStyle(color: CasaFlixColors.sky, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'T${next.parentIndexNumber ?? '-'} E${next.indexNumber ?? '-'} · ${next.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                autofocus: true,
                onPressed: onPlay,
                icon: const Icon(Icons.skip_next_rounded),
                label: Text('Assistir agora · $seconds'),
              ),
              Center(
                child: TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancelar reprodução automática'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
