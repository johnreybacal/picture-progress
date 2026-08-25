import '../../data/models/pose_bounding_box.dart';
import '../../data/models/pose_landmark_point.dart';
import '../../data/models/pose_point.dart';
import '../../data/models/pose_record.dart';

class ReferenceSkeletonTransformer {
  const ReferenceSkeletonTransformer();

  ReferenceSkeletonFrame transform(PoseRecord record) {
    final rawWidth = record.imageWidth > 0 ? record.imageWidth : 1;
    final rawHeight = record.imageHeight > 0 ? record.imageHeight : 1;
    final quarterTurns = record.captureOrientation.referenceQuarterTurns;
    final transformedLandmarks = record.landmarks
        .map((landmark) {
          final transformedPoint = _transformPoint(
            PosePoint(x: landmark.x, y: landmark.y),
            rawWidth: rawWidth,
            rawHeight: rawHeight,
            quarterTurns: quarterTurns,
          );
          return landmark.copyWith(
            x: transformedPoint.x,
            y: transformedPoint.y,
          );
        })
        .toList(growable: false);
    final transformedBoundingBox = _transformBoundingBox(
      record.boundingBox,
      rawWidth: rawWidth,
      rawHeight: rawHeight,
      quarterTurns: quarterTurns,
    );
    final transformedAnchorCenter = _transformPoint(
      record.anchorCenter,
      rawWidth: rawWidth,
      rawHeight: rawHeight,
      quarterTurns: quarterTurns,
    );

    return ReferenceSkeletonFrame(
      landmarks: transformedLandmarks,
      boundingBox: transformedBoundingBox,
      anchorCenter: transformedAnchorCenter,
      imageWidth: quarterTurns.isOdd ? rawHeight : rawWidth,
      imageHeight: quarterTurns.isOdd ? rawWidth : rawHeight,
    );
  }

  PoseBoundingBox _transformBoundingBox(
    PoseBoundingBox boundingBox, {
    required int rawWidth,
    required int rawHeight,
    required int quarterTurns,
  }) {
    final corners = [
      _transformPoint(
        PosePoint(x: boundingBox.left, y: boundingBox.top),
        rawWidth: rawWidth,
        rawHeight: rawHeight,
        quarterTurns: quarterTurns,
      ),
      _transformPoint(
        PosePoint(x: boundingBox.right, y: boundingBox.top),
        rawWidth: rawWidth,
        rawHeight: rawHeight,
        quarterTurns: quarterTurns,
      ),
      _transformPoint(
        PosePoint(x: boundingBox.left, y: boundingBox.bottom),
        rawWidth: rawWidth,
        rawHeight: rawHeight,
        quarterTurns: quarterTurns,
      ),
      _transformPoint(
        PosePoint(x: boundingBox.right, y: boundingBox.bottom),
        rawWidth: rawWidth,
        rawHeight: rawHeight,
        quarterTurns: quarterTurns,
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

  PosePoint _transformPoint(
    PosePoint point, {
    required int rawWidth,
    required int rawHeight,
    required int quarterTurns,
  }) {
    switch (quarterTurns % 4) {
      case 1:
        return PosePoint(x: rawHeight - point.y, y: point.x);
      case 2:
        return PosePoint(x: rawWidth - point.x, y: rawHeight - point.y);
      case 3:
        return PosePoint(x: point.y, y: rawWidth - point.x);
      default:
        return point;
    }
  }
}

class ReferenceSkeletonFrame {
  const ReferenceSkeletonFrame({
    required this.landmarks,
    required this.boundingBox,
    required this.anchorCenter,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<PoseLandmarkPoint> landmarks;
  final PoseBoundingBox boundingBox;
  final PosePoint anchorCenter;
  final int imageWidth;
  final int imageHeight;
}
