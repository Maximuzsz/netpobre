class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.type,
    this.originalTitle,
    this.overview,
    this.seriesName,
    this.seriesId,
    this.imageTag,
    this.backdropTag,
    this.year,
    this.indexNumber,
    this.parentIndexNumber,
    this.playbackPositionTicks = 0,
    this.playedPercentage = 0,
    this.isFavorite = false,
    this.played = false,
    this.trickplay,
  });

  final String id;
  final String name;
  final String type;
  final String? originalTitle;
  final String? overview;
  final String? seriesName;
  final String? seriesId;
  final String? imageTag;
  final String? backdropTag;
  final int? year;
  final int? indexNumber;
  final int? parentIndexNumber;
  final int playbackPositionTicks;
  final double playedPercentage;
  final bool isFavorite;
  final bool played;
  final TrickplayInfo? trickplay;

  bool get playable => type == 'Movie' || type == 'Episode' || type == 'Video';
  Duration get resumePosition =>
      Duration(microseconds: playbackPositionTicks ~/ 10);
  double get progress => (playedPercentage / 100).clamp(0, 1);

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final backdrops = (json['BackdropImageTags'] as List?)?.cast<String>();
    final userData = (json['UserData'] as Map?)?.cast<String, dynamic>();
    return MediaItem(
      id: json['Id'] as String,
      name: (json['Name'] as String?) ?? 'Sem título',
      type: (json['Type'] as String?) ?? 'Unknown',
      originalTitle: json['OriginalTitle'] as String?,
      overview: json['Overview'] as String?,
      seriesName: json['SeriesName'] as String?,
      seriesId: json['SeriesId'] as String?,
      imageTag: (json['ImageTags'] as Map?)?['Primary'] as String?,
      backdropTag: backdrops == null || backdrops.isEmpty
          ? null
          : backdrops.first,
      year: json['ProductionYear'] as int?,
      indexNumber: json['IndexNumber'] as int?,
      parentIndexNumber: json['ParentIndexNumber'] as int?,
      playbackPositionTicks:
          (userData?['PlaybackPositionTicks'] as num?)?.toInt() ?? 0,
      playedPercentage:
          (userData?['PlayedPercentage'] as num?)?.toDouble() ?? 0,
      isFavorite: userData?['IsFavorite'] as bool? ?? false,
      played: userData?['Played'] as bool? ?? false,
      trickplay: TrickplayInfo.tryParse(json['Trickplay']),
    );
  }

  Map<String, dynamic> toJson() => {
    'Id': id,
    'Name': name,
    'Type': type,
    if (originalTitle != null) 'OriginalTitle': originalTitle,
    if (overview != null) 'Overview': overview,
    if (seriesName != null) 'SeriesName': seriesName,
    if (seriesId != null) 'SeriesId': seriesId,
    if (imageTag != null) 'ImageTags': {'Primary': imageTag},
    if (backdropTag != null) 'BackdropImageTags': [backdropTag],
    if (year != null) 'ProductionYear': year,
    if (indexNumber != null) 'IndexNumber': indexNumber,
    if (parentIndexNumber != null) 'ParentIndexNumber': parentIndexNumber,
    'UserData': {
      'PlaybackPositionTicks': playbackPositionTicks,
      'PlayedPercentage': playedPercentage,
      'IsFavorite': isFavorite,
      'Played': played,
    },
  };

  MediaItem copyWith({bool? isFavorite}) => MediaItem(
    id: id,
    name: name,
    type: type,
    originalTitle: originalTitle,
    overview: overview,
    seriesName: seriesName,
    seriesId: seriesId,
    imageTag: imageTag,
    backdropTag: backdropTag,
    year: year,
    indexNumber: indexNumber,
    parentIndexNumber: parentIndexNumber,
    playbackPositionTicks: playbackPositionTicks,
    playedPercentage: playedPercentage,
    isFavorite: isFavorite ?? this.isFavorite,
    played: played,
    trickplay: trickplay,
  );
}

class TrickplayInfo {
  const TrickplayInfo({
    required this.mediaSourceId,
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.thumbnailCount,
    required this.intervalMs,
  });

  final String mediaSourceId;
  final int width;
  final int height;
  final int tileWidth;
  final int tileHeight;
  final int thumbnailCount;
  final int intervalMs;

  int get cellsPerSheet => tileWidth * tileHeight;

  static TrickplayInfo? tryParse(dynamic raw) {
    if (raw is! Map || raw.isEmpty) return null;
    final sourceEntry = raw.entries.first;
    if (sourceEntry.value is! Map || (sourceEntry.value as Map).isEmpty) {
      return null;
    }
    final widthEntries = (sourceEntry.value as Map).entries.toList()
      ..sort(
        (a, b) =>
            int.parse(a.key.toString()).compareTo(int.parse(b.key.toString())),
      );
    final data = (widthEntries.first.value as Map).cast<String, dynamic>();
    return TrickplayInfo(
      mediaSourceId: sourceEntry.key.toString(),
      width: (data['Width'] as num?)?.toInt() ?? 320,
      height: (data['Height'] as num?)?.toInt() ?? 180,
      tileWidth: (data['TileWidth'] as num?)?.toInt() ?? 10,
      tileHeight: (data['TileHeight'] as num?)?.toInt() ?? 10,
      thumbnailCount: (data['ThumbnailCount'] as num?)?.toInt() ?? 0,
      intervalMs: (data['Interval'] as num?)?.toInt() ?? 10000,
    );
  }
}

class MediaView {
  const MediaView({required this.id, required this.name, this.collectionType});

  final String id;
  final String name;
  final String? collectionType;

  factory MediaView.fromJson(Map<String, dynamic> json) => MediaView(
    id: json['Id'] as String,
    name: json['Name'] as String,
    collectionType: json['CollectionType'] as String?,
  );
}
