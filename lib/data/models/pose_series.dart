class PoseSeries {
  const PoseSeries({
    this.id,
    required this.name,
    required this.createdAt,
    required this.thumbnailPath,
  });

  final int? id;
  final String name;
  final DateTime createdAt;
  final String thumbnailPath;

  PoseSeries copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    String? thumbnailPath,
  }) {
    return PoseSeries(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  factory PoseSeries.fromDatabaseMap(Map<String, Object?> map) {
    return PoseSeries(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      thumbnailPath: map['thumbnail_path'] as String? ?? '',
    );
  }

  Map<String, Object?> toDatabaseMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'thumbnail_path': thumbnailPath,
    };
  }
}
