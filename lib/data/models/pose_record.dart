import 'dart:convert';

import 'capture_orientation.dart';
import 'pose_bounding_box.dart';
import 'pose_landmark_point.dart';
import 'pose_point.dart';

class PoseRecord {
  const PoseRecord({
    this.id,
    required this.seriesId,
    required this.imagePath,
    required this.label,
    required this.timestamp,
    required this.landmarks,
    required this.boundingBox,
    required this.anchorCenter,
    required this.cameraLens,
    required this.captureOrientation,
    required this.imageWidth,
    required this.imageHeight,
    this.baselinePose = false,
  });

  final int? id;
  final int seriesId;
  final String imagePath;
  final String label;
  final DateTime timestamp;
  final List<PoseLandmarkPoint> landmarks;
  final PoseBoundingBox boundingBox;
  final PosePoint anchorCenter;
  final String cameraLens;
  final CaptureOrientation captureOrientation;
  final int imageWidth;
  final int imageHeight;
  final bool baselinePose;

  bool get hasSourceDimensions => imageWidth > 0 && imageHeight > 0;
  bool get isReference => baselinePose;

  int get displayQuarterTurns => captureOrientation.quarterTurnsForDisplay(
    rawWidth: imageWidth,
    rawHeight: imageHeight,
  );

  int get displayImageWidth =>
      displayQuarterTurns.isOdd ? imageHeight : imageWidth;

  int get displayImageHeight =>
      displayQuarterTurns.isOdd ? imageWidth : imageHeight;

  double get displayAspectRatio {
    if (!hasSourceDimensions) {
      return 3 / 4;
    }
    return displayImageWidth / displayImageHeight;
  }

  PoseRecord copyWith({
    int? id,
    int? seriesId,
    String? imagePath,
    String? label,
    DateTime? timestamp,
    List<PoseLandmarkPoint>? landmarks,
    PoseBoundingBox? boundingBox,
    PosePoint? anchorCenter,
    String? cameraLens,
    CaptureOrientation? captureOrientation,
    int? imageWidth,
    int? imageHeight,
    bool? baselinePose,
  }) {
    return PoseRecord(
      id: id ?? this.id,
      seriesId: seriesId ?? this.seriesId,
      imagePath: imagePath ?? this.imagePath,
      label: label ?? this.label,
      timestamp: timestamp ?? this.timestamp,
      landmarks: landmarks ?? this.landmarks,
      boundingBox: boundingBox ?? this.boundingBox,
      anchorCenter: anchorCenter ?? this.anchorCenter,
      cameraLens: cameraLens ?? this.cameraLens,
      captureOrientation: captureOrientation ?? this.captureOrientation,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      baselinePose: baselinePose ?? this.baselinePose,
    );
  }

  PosePoint displayAnchorCenter({int? rawWidth, int? rawHeight}) {
    return _transformPoint(
      anchorCenter,
      rawWidth: rawWidth ?? imageWidth,
      rawHeight: rawHeight ?? imageHeight,
    );
  }

  PoseBoundingBox displayBoundingBox({int? rawWidth, int? rawHeight}) {
    final width = rawWidth ?? imageWidth;
    final height = rawHeight ?? imageHeight;
    final corners = [
      _transformPoint(
        PosePoint(x: boundingBox.left, y: boundingBox.top),
        rawWidth: width,
        rawHeight: height,
      ),
      _transformPoint(
        PosePoint(x: boundingBox.right, y: boundingBox.top),
        rawWidth: width,
        rawHeight: height,
      ),
      _transformPoint(
        PosePoint(x: boundingBox.left, y: boundingBox.bottom),
        rawWidth: width,
        rawHeight: height,
      ),
      _transformPoint(
        PosePoint(x: boundingBox.right, y: boundingBox.bottom),
        rawWidth: width,
        rawHeight: height,
      ),
    ];

    final xs = corners.map((point) => point.x).toList(growable: false);
    final ys = corners.map((point) => point.y).toList(growable: false);
    return PoseBoundingBox(
      left: xs.reduce((first, second) => first < second ? first : second),
      top: ys.reduce((first, second) => first < second ? first : second),
      right: xs.reduce((first, second) => first > second ? first : second),
      bottom: ys.reduce((first, second) => first > second ? first : second),
    );
  }

  List<PoseLandmarkPoint> displayLandmarks({int? rawWidth, int? rawHeight}) {
    final width = rawWidth ?? imageWidth;
    final height = rawHeight ?? imageHeight;
    return landmarks
        .map((landmark) {
          final point = _transformPoint(
            PosePoint(x: landmark.x, y: landmark.y),
            rawWidth: width,
            rawHeight: height,
          );
          return landmark.copyWith(x: point.x, y: point.y);
        })
        .toList(growable: false);
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
      label: map['label'] as String? ?? '',
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
      cameraLens: map['camera_lens'] as String? ?? 'front',
      captureOrientation: CaptureOrientation.fromStorage(
        map['capture_orientation'] as String?,
      ),
      imageWidth: map['image_width'] as int? ?? 0,
      imageHeight: map['image_height'] as int? ?? 0,
      baselinePose:
          ((map['baseline_pose'] as int?) ??
              (map['is_reference'] as int?) ??
              0) ==
          1,
    );
  }

  Map<String, Object?> toDatabaseMap() {
    return {
      'id': id,
      'series_id': seriesId,
      'image_path': imagePath,
      'label': label,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'landmarks_json': jsonEncode(
        landmarks.map((landmark) => landmark.toJson()).toList(),
      ),
      'bounding_box_json': jsonEncode(boundingBox.toJson()),
      'anchor_center_json': jsonEncode(anchorCenter.toJson()),
      'camera_lens': cameraLens,
      'capture_orientation': captureOrientation.storageValue,
      'image_width': imageWidth,
      'image_height': imageHeight,
      'baseline_pose': baselinePose ? 1 : 0,
      'is_reference': baselinePose ? 1 : 0,
    };
  }

  PosePoint _transformPoint(
    PosePoint point, {
    required int rawWidth,
    required int rawHeight,
  }) {
    final quarterTurns = captureOrientation.quarterTurnsForDisplay(
      rawWidth: rawWidth,
      rawHeight: rawHeight,
    );
    switch (quarterTurns) {
      case 1:
        return PosePoint(x: rawHeight - point.y, y: point.x);
      case 3:
        return PosePoint(x: point.y, y: rawWidth - point.x);
      default:
        return point;
    }
  }
}
