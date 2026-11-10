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
  bool _controls = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _controller =
        VideoPlayerController.networkUrl(
            widget.api.playbackUrl(widget.item),
            httpHeaders: widget.api.authHeaders,
          )
          ..initialize()
              .then((_) {
                if (!mounted) return;
                setState(() {});
                _controller.play();
              })
              .catchError((_) {
                if (mounted) {
                  setState(
                    () => _error =
                        'Não foi possível iniciar o vídeo. Verifique a conexão.',
                  );
                }
              });
    _controller.addListener(_tick);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_tick);
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
          ],
        ),
      ),
    );
  }
}
