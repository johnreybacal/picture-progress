import 'dart:convert';

import 'baseline_pose_metadata.dart';

class PoseSeries {
  const PoseSeries({
    this.id,
    required this.name,
    required this.createdAt,
    required this.thumbnailPath,
    this.baselineMetadata,
  });

  final int? id;
  final String name;
  final DateTime createdAt;
  final String thumbnailPath;
  final BaselinePoseMetadata? baselineMetadata;

  PoseSeries copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    String? thumbnailPath,
    BaselinePoseMetadata? baselineMetadata,
  }) {
    return PoseSeries(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      baselineMetadata: baselineMetadata ?? this.baselineMetadata,
    );
  }

  factory PoseSeries.fromDatabaseMap(Map<String, Object?> map) {
    final baselineMetadataJson = map['baseline_metadata_json'] as String? ?? '';
    return PoseSeries(
      id: map['id'] as int?,
      name: map['name'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      thumbnailPath: map['thumbnail_path'] as String? ?? '',
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
      'baseline_metadata_json': baselineMetadata == null
          ? ''
          : jsonEncode(baselineMetadata!.toJson()),
    };
  }
}
