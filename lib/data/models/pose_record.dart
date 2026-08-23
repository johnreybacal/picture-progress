import 'dart:convert';

import 'pose_bounding_box.dart';
import 'pose_landmark_point.dart';
import 'pose_point.dart';

class PoseRecord {
  const PoseRecord({
    this.id,
    required this.seriesId,
    required this.imagePath,
    required this.timestamp,
    required this.landmarks,
    required this.boundingBox,
    required this.anchorCenter,
    this.isReference = false,
  });

  final int? id;
  final int seriesId;
  final String imagePath;
  final DateTime timestamp;
  final List<PoseLandmarkPoint> landmarks;
  final PoseBoundingBox boundingBox;
  final PosePoint anchorCenter;
  final bool isReference;

  PoseRecord copyWith({
    int? id,
    int? seriesId,
    String? imagePath,
    DateTime? timestamp,
    List<PoseLandmarkPoint>? landmarks,
    PoseBoundingBox? boundingBox,
    PosePoint? anchorCenter,
    bool? isReference,
  }) {
    return PoseRecord(
      id: id ?? this.id,
      seriesId: seriesId ?? this.seriesId,
      imagePath: imagePath ?? this.imagePath,
      timestamp: timestamp ?? this.timestamp,
      landmarks: landmarks ?? this.landmarks,
      boundingBox: boundingBox ?? this.boundingBox,
      anchorCenter: anchorCenter ?? this.anchorCenter,
      isReference: isReference ?? this.isReference,
    );
  }

  factory PoseRecord.fromDatabaseMap(Map<String, Object?> map) {
    final landmarksJson =
        jsonDecode(map['landmarks_json'] as String) as List<dynamic>;
    final boundingBoxJson = Map<String, dynamic>.from(
      jsonDecode(map['bounding_box_json'] as String) as Map<dynamic, dynamic>,
    );
    final anchorCenterJson = Map<String, dynamic>.from(
      jsonDecode(map['anchor_center_json'] as String) as Map<dynamic, dynamic>,
    );

    return PoseRecord(
      id: map['id'] as int?,
      seriesId: map['series_id'] as int,
      imagePath: map['image_path'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      landmarks: landmarksJson
          .map(
            (item) => PoseLandmarkPoint.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
            ),
          )
          .toList(),
      boundingBox: PoseBoundingBox.fromJson(boundingBoxJson),
      anchorCenter: PosePoint.fromJson(anchorCenterJson),
      isReference: (map['is_reference'] as int? ?? 0) == 1,
    );
  }

  Map<String, Object?> toDatabaseMap() {
    return {
      'id': id,
      'series_id': seriesId,
      'image_path': imagePath,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'landmarks_json': jsonEncode(
        landmarks.map((landmark) => landmark.toJson()).toList(),
      ),
      'bounding_box_json': jsonEncode(boundingBox.toJson()),
      'anchor_center_json': jsonEncode(anchorCenter.toJson()),
      'is_reference': isReference ? 1 : 0,
    };
  }
}
