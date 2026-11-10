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

  bool get playable => type == 'Movie' || type == 'Episode' || type == 'Video';

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final backdrops = (json['BackdropImageTags'] as List?)?.cast<String>();
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
