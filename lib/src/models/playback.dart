enum PlaybackQuality {
  automatic('Automática'),
  economy('Economia · 480p'),
  balanced('Equilibrada · 720p'),
  home('Casa · 1080p');

  const PlaybackQuality(this.label);
  final String label;
}

class MediaStreamInfo {
  const MediaStreamInfo({
    required this.index,
    required this.type,
    required this.displayTitle,
    this.language,
    this.codec,
    this.isDefault = false,
    this.isExternal = false,
  });

  final int index;
  final String type;
  final String displayTitle;
  final String? language;
  final String? codec;
  final bool isDefault;
  final bool isExternal;

  factory MediaStreamInfo.fromJson(Map<String, dynamic> json) =>
      MediaStreamInfo(
        index: (json['Index'] as num?)?.toInt() ?? -1,
        type: (json['Type'] as String?) ?? 'Unknown',
        displayTitle:
            (json['DisplayTitle'] as String?) ??
            (json['Title'] as String?) ??
            (json['Language'] as String?) ??
            'Faixa',
        language: json['Language'] as String?,
        codec: json['Codec'] as String?,
        isDefault: json['IsDefault'] as bool? ?? false,
        isExternal: json['IsExternal'] as bool? ?? false,
      );
}

class PlaybackInfo {
  const PlaybackInfo({
    this.playSessionId,
    this.audioStreams = const [],
    this.subtitleStreams = const [],
    this.defaultAudioStreamIndex,
    this.defaultSubtitleStreamIndex,
  });

  final String? playSessionId;
  final List<MediaStreamInfo> audioStreams;
  final List<MediaStreamInfo> subtitleStreams;
  final int? defaultAudioStreamIndex;
  final int? defaultSubtitleStreamIndex;

  factory PlaybackInfo.fromJson(Map<String, dynamic> json) {
    final sources = (json['MediaSources'] as List?) ?? const [];
    final source = sources.isEmpty
        ? const <String, dynamic>{}
        : (sources.first as Map).cast<String, dynamic>();
    final streams = ((source['MediaStreams'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(MediaStreamInfo.fromJson)
        .toList();
    return PlaybackInfo(
      playSessionId: json['PlaySessionId'] as String?,
      audioStreams: streams.where((stream) => stream.type == 'Audio').toList(),
      subtitleStreams: streams
          .where((stream) => stream.type == 'Subtitle')
          .toList(),
      defaultAudioStreamIndex: (source['DefaultAudioStreamIndex'] as num?)
          ?.toInt(),
      defaultSubtitleStreamIndex: (source['DefaultSubtitleStreamIndex'] as num?)
          ?.toInt(),
    );
  }
}

class MediaSegment {
  const MediaSegment({
    required this.type,
    required this.start,
    required this.end,
  });

  final String type;
  final Duration start;
  final Duration end;

  String get actionLabel => switch (type) {
    'Intro' => 'Pular abertura',
    'Recap' => 'Pular resumo',
    'Outro' => 'Pular créditos',
    'Preview' => 'Pular prévia',
    _ => 'Pular trecho',
  };

  bool contains(Duration position) => position >= start && position < end;

  factory MediaSegment.fromJson(Map<String, dynamic> json) => MediaSegment(
    type: (json['Type'] as String?) ?? 'Unknown',
    start: Duration(
      microseconds: ((json['StartTicks'] as num?)?.toInt() ?? 0) ~/ 10,
    ),
    end: Duration(
      microseconds: ((json['EndTicks'] as num?)?.toInt() ?? 0) ~/ 10,
    ),
  );
}
