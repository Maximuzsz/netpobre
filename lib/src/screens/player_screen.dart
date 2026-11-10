import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
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
  late final VideoPlayerController _controller;
  late final String _playSessionId =
      '${widget.item.id}-${DateTime.now().microsecondsSinceEpoch}';
  bool _controls = true;
  bool _started = false;
  Duration _lastReported = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _controller = VideoPlayerController.networkUrl(
      widget.api.playbackUrl(widget.item),
      httpHeaders: widget.api.authHeaders,
    );
    _controller.addListener(_tick);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      final resume = widget.item.resumePosition;
      final duration = _controller.value.duration;
      if (resume > const Duration(seconds: 30) &&
          resume < duration - const Duration(seconds: 30)) {
        await _controller.seekTo(resume);
      }
      _started = true;
      _ignore(
        widget.api.reportPlaybackStarted(
          widget.item,
          _playSessionId,
          _controller.value.position,
        ),
      );
      await _controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Não foi possível iniciar o vídeo. Verifique a conexão.',
        );
      }
    }
  }

  void _tick() {
    if (!mounted) return;
    final value = _controller.value;
    if (_started &&
        (value.position - _lastReported).abs() >= const Duration(seconds: 10)) {
      _lastReported = value.position;
      _ignore(
        widget.api.reportPlaybackProgress(
          widget.item,
          _playSessionId,
          value.position,
          isPaused: !value.isPlaying,
        ),
      );
    }
    setState(() {});
  }

  void _ignore(Future<void> future) {
    unawaited(future.catchError((_) {}));
  }

  Future<void> _seekBy(Duration offset) async {
    final value = _controller.value;
    final target = value.position + offset;
    await _controller.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > value.duration
          ? value.duration
          : target,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_tick);
    if (_started) {
      _ignore(
        widget.api.reportPlaybackStopped(
          widget.item,
          _playSessionId,
          _controller.value.position,
        ),
      );
    }
    _controller.dispose();
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
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _controls = !_controls),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: VideoPlayer(_controller),
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
            if (_controls && value.isInitialized)
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xAA000000),
                      Colors.transparent,
                      Color(0xCC000000),
                    ],
                    stops: [0, .5, 1],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          Expanded(
                            child: Text(
                              widget.item.seriesName ?? widget.item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Voltar 10 segundos',
                            onPressed: () =>
                                _seekBy(const Duration(seconds: -10)),
                            iconSize: 38,
                            icon: const Icon(Icons.replay_10_rounded),
                          ),
                          const SizedBox(width: 26),
                          IconButton.filled(
                            onPressed: () => value.isPlaying
                                ? _controller.pause()
                                : _controller.play(),
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
                            onPressed: () =>
                                _seekBy(const Duration(seconds: 10)),
                            iconSize: 38,
                            icon: const Icon(Icons.forward_10_rounded),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                        child: Row(
                          children: [
                            Text(_time(value.position)),
                            Expanded(
                              child: Slider(
                                value: value.duration.inMilliseconds == 0
                                    ? 0
                                    : value.position.inMilliseconds
                                          .clamp(
                                            0,
                                            value.duration.inMilliseconds,
                                          )
                                          .toDouble(),
                                max: value.duration.inMilliseconds
                                    .toDouble()
                                    .clamp(1, double.infinity),
                                onChanged: (position) => _controller.seekTo(
                                  Duration(milliseconds: position.round()),
                                ),
                              ),
                            ),
                            Text(_time(value.duration)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (value.isBuffering && value.isInitialized)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
