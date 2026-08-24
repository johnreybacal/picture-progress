import 'dart:convert';

import 'baseline_pose_metadata.dart';
import 'lens_facing.dart';

class PoseSeries {
  const PoseSeries({
    this.id,
    required this.name,
    required this.createdAt,
    required this.thumbnailPath,
    this.baselineMetadata,
    this.preferredLens,
  });

  final int? id;
  final String name;
  final DateTime createdAt;
  final String thumbnailPath;
  final BaselinePoseMetadata? baselineMetadata;
  final LensFacing? preferredLens;

  PoseSeries copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    String? thumbnailPath,
    BaselinePoseMetadata? baselineMetadata,
    LensFacing? preferredLens,
  }) {
    return PoseSeries(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      baselineMetadata: baselineMetadata ?? this.baselineMetadata,
      preferredLens: preferredLens ?? this.preferredLens,
    );
  }

  factory PoseSeries.fromDatabaseMap(Map<String, Object?> map) {
    final baselineMetadataJson = map['baseline_metadata_json'] as String? ?? '';
    return PoseSeries(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      thumbnailPath: map['thumbnail_path'] as String? ?? '',
      preferredLens: LensFacing.fromStorage(map['preferred_lens'] as String?),
      baselineMetadata: baselineMetadataJson.isEmpty
          ? null
          : BaselinePoseMetadata.fromJson(
              Map<String, dynamic>.from(
                jsonDecode(baselineMetadataJson) as Map<dynamic, dynamic>,
              ),
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
      'baseline_metadata_json': baselineMetadata == null
          ? ''
          : jsonEncode(baselineMetadata!.toJson()),
    };
  }
}
