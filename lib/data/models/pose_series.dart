import 'capture_viewport_ratio.dart';
import 'lens_facing.dart';

class PoseSeries {
  const PoseSeries({
    this.id,
    required this.name,
    required this.createdAt,
    required this.thumbnailPath,
    this.preferredLens,
    this.lastUsedZoomLevel,
    this.lastUsedAspectRatio = CaptureViewportRatio.threeByFour,
  });

  final int? id;
  final String name;
  final DateTime createdAt;
  final String thumbnailPath;
  final LensFacing? preferredLens;
  final double? lastUsedZoomLevel;
  final CaptureViewportRatio lastUsedAspectRatio;

  PoseSeries copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    String? thumbnailPath,
    LensFacing? preferredLens,
    double? lastUsedZoomLevel,
    CaptureViewportRatio? lastUsedAspectRatio,
  }) {
    return PoseSeries(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      preferredLens: preferredLens ?? this.preferredLens,
      lastUsedZoomLevel: lastUsedZoomLevel ?? this.lastUsedZoomLevel,
      lastUsedAspectRatio: lastUsedAspectRatio ?? this.lastUsedAspectRatio,
    );
  }

  factory PoseSeries.fromDatabaseMap(Map<String, Object?> map) {
    final storedZoomLevel = (map['last_used_zoom_level'] as num?)?.toDouble();
    return PoseSeries(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      thumbnailPath: map['thumbnail_path'] as String? ?? '',
      preferredLens: LensFacing.fromStorage(map['preferred_lens'] as String?),
      lastUsedZoomLevel: storedZoomLevel == null || storedZoomLevel <= 0
          ? null
          : storedZoomLevel,
      lastUsedAspectRatio: CaptureViewportRatio.fromStorage(
        map['last_used_aspect_ratio'] as String?,
      ),
    );
  }

  Map<String, Object?> toDatabaseMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'thumbnail_path': thumbnailPath,
      'preferred_lens': preferredLens?.storageValue ?? '',
      'last_used_zoom_level': lastUsedZoomLevel ?? 0,
      'last_used_aspect_ratio': lastUsedAspectRatio.storageValue,
    };
  }
}
