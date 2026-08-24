import 'package:camera/camera.dart';

import '../../data/models/pose_landmark_point.dart';
import '../../data/models/pose_record.dart';
import 'pose_alignment_engine.dart';

class DynamicAlignmentService {
  const DynamicAlignmentService();

  PoseRecord? resolveReferenceRecord(List<PoseRecord> records) {
    if (records.isEmpty) {
      return null;
    }

    final orderedRecords = [...records]
      ..sort((first, second) => first.timestamp.compareTo(second.timestamp));
    return orderedRecords.last;
  }

  DynamicAlignmentComparison compareToReference({
    required List<PoseLandmarkPoint> liveLandmarks,
    required PoseRecord referenceRecord,
    required CameraLensDirection activeLensDirection,
  }) {
    final mirrorReferenceHorizontally =
        referenceRecord.cameraLens != activeLensDirection.name;
    final alignment = PoseAlignmentEngine.compare(
      liveLandmarks: liveLandmarks,
      referenceLandmarks: referenceRecord.landmarks,
      mirrorReferenceHorizontally: mirrorReferenceHorizontally,
    );
    return DynamicAlignmentComparison(
      referenceRecord: referenceRecord,
      alignment: alignment,
      mirrorReferenceHorizontally: mirrorReferenceHorizontally,
    );
  }
}

class DynamicAlignmentComparison {
  const DynamicAlignmentComparison({
    required this.referenceRecord,
    required this.alignment,
    required this.mirrorReferenceHorizontally,
  });

  const DynamicAlignmentComparison.empty()
    : referenceRecord = null,
      alignment = const PoseAlignmentResult.empty(),
      mirrorReferenceHorizontally = false;

  final PoseRecord? referenceRecord;
  final PoseAlignmentResult alignment;
  final bool mirrorReferenceHorizontally;
}
