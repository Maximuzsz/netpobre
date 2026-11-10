import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/download_store.dart';
import '../theme.dart';

class OfflinePlayerScreen extends StatefulWidget {
  const OfflinePlayerScreen({super.key, required this.media});
  final DownloadedMedia media;

  @override
  State<OfflinePlayerScreen> createState() => _OfflinePlayerScreenState();
}

class _OfflinePlayerScreenState extends State<OfflinePlayerScreen> {
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
    _controller = VideoPlayerController.file(File(widget.media.path))
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.play();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Este arquivo não pôde ser reproduzido.');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
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
            if (_error != null) Center(child: Text(_error!)),
            if (_controls && value.isInitialized)
              SafeArea(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          autofocus: true,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        Expanded(
                          child: Text(
                            widget.media.item.seriesName ??
                                widget.media.item.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(
                            Icons.download_done_rounded,
                            color: CasaFlixColors.sky,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton.filled(
                      onPressed: () => value.isPlaying
                          ? _controller.pause()
                          : _controller.play(),
                      iconSize: 44,
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    const Spacer(),
                    Slider(
                      value: value.position.inMilliseconds
                          .clamp(0, value.duration.inMilliseconds)
                          .toDouble(),
                      max: value.duration.inMilliseconds.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                      onChanged: (position) => _controller.seekTo(
                        Duration(milliseconds: position.round()),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
