class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.type,
    this.overview,
    this.seriesName,
    this.imageTag,
    this.backdropTag,
    this.year,
    this.indexNumber,
    this.parentIndexNumber,
    this.playbackPositionTicks = 0,
    this.playedPercentage = 0,
    this.isFavorite = false,
    this.played = false,
  });

  final String id;
  final String name;
  final String type;
  final String? overview;
  final String? seriesName;
  final String? imageTag;
  final String? backdropTag;
  final int? year;
  final int? indexNumber;
  final int? parentIndexNumber;
  final int playbackPositionTicks;
  final double playedPercentage;
  final bool isFavorite;
  final bool played;

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
      overview: json['Overview'] as String?,
      seriesName: json['SeriesName'] as String?,
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
    );
  }

  MediaItem copyWith({bool? isFavorite}) => MediaItem(
    id: id,
    name: name,
    type: type,
    overview: overview,
    seriesName: seriesName,
    imageTag: imageTag,
    backdropTag: backdropTag,
    year: year,
    indexNumber: indexNumber,
    parentIndexNumber: parentIndexNumber,
    playbackPositionTicks: playbackPositionTicks,
    playedPercentage: playedPercentage,
    isFavorite: isFavorite ?? this.isFavorite,
    played: played,
  );
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
