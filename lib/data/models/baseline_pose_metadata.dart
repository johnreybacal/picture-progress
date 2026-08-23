import 'capture_orientation.dart';
import 'pose_bounding_box.dart';
import 'pose_point.dart';

class BaselinePoseMetadata {
  const BaselinePoseMetadata({
    required this.recordId,
    required this.imagePath,
    required this.capturedAt,
    required this.anchorCenter,
    required this.boundingBox,
    required this.cameraLens,
    required this.captureOrientation,
  });

  final int recordId;
  final String imagePath;
  final DateTime capturedAt;
  final PosePoint anchorCenter;
  final PoseBoundingBox boundingBox;
  final String cameraLens;
  final CaptureOrientation captureOrientation;

  factory BaselinePoseMetadata.fromJson(Map<String, dynamic> json) {
    return BaselinePoseMetadata(
      recordId: json['recordId'] as int,
      imagePath: json['imagePath'] as String,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        json['capturedAt'] as int,
      ),
      anchorCenter: PosePoint.fromJson(
        Map<String, dynamic>.from(
          json['anchorCenter'] as Map<dynamic, dynamic>,
        ),
      ),
      boundingBox: PoseBoundingBox.fromJson(
        Map<String, dynamic>.from(json['boundingBox'] as Map<dynamic, dynamic>),
      ),
      cameraLens: json['cameraLens'] as String,
      captureOrientation: CaptureOrientation.fromStorage(
        json['captureOrientation'] as String?,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'recordId': recordId,
      'imagePath': imagePath,
      'capturedAt': capturedAt.millisecondsSinceEpoch,
      'anchorCenter': anchorCenter.toJson(),
      'boundingBox': boundingBox.toJson(),
      'cameraLens': cameraLens,
      'captureOrientation': captureOrientation.storageValue,
    };
  }
}
