import '../../data/models/pose_connection.dart';
import '../../data/models/pose_landmark_point.dart';

class PoseSkeletonGraph {
  const PoseSkeletonGraph._();

  static const List<PoseConnection> connections = [
    PoseConnection(startType: 'nose', endType: 'leftEye'),
    PoseConnection(startType: 'nose', endType: 'rightEye'),
    PoseConnection(startType: 'leftEye', endType: 'leftEar'),
    PoseConnection(startType: 'rightEye', endType: 'rightEar'),
    PoseConnection(startType: 'leftShoulder', endType: 'rightShoulder'),
    PoseConnection(startType: 'leftShoulder', endType: 'leftElbow'),
    PoseConnection(startType: 'leftElbow', endType: 'leftWrist'),
    PoseConnection(startType: 'rightShoulder', endType: 'rightElbow'),
    PoseConnection(startType: 'rightElbow', endType: 'rightWrist'),
    PoseConnection(startType: 'leftShoulder', endType: 'leftHip'),
    PoseConnection(startType: 'rightShoulder', endType: 'rightHip'),
    PoseConnection(startType: 'leftHip', endType: 'rightHip'),
    PoseConnection(startType: 'leftHip', endType: 'leftKnee'),
    PoseConnection(startType: 'leftKnee', endType: 'leftAnkle'),
    PoseConnection(startType: 'leftAnkle', endType: 'leftHeel'),
    PoseConnection(startType: 'leftHeel', endType: 'leftFootIndex'),
    PoseConnection(startType: 'rightHip', endType: 'rightKnee'),
    PoseConnection(startType: 'rightKnee', endType: 'rightAnkle'),
    PoseConnection(startType: 'rightAnkle', endType: 'rightHeel'),
    PoseConnection(startType: 'rightHeel', endType: 'rightFootIndex'),
  ];

  static Map<String, PoseLandmarkPoint> indexByType(
    List<PoseLandmarkPoint> landmarks,
  ) {
    return {for (final landmark in landmarks) landmark.type: landmark};
  }

  static Iterable<PoseConnection> visibleConnections(
    List<PoseLandmarkPoint> landmarks,
  ) {
    final indexedLandmarks = indexByType(landmarks);
    return connections.where((connection) {
      return indexedLandmarks.containsKey(connection.startType) &&
          indexedLandmarks.containsKey(connection.endType);
    });
  }
}
