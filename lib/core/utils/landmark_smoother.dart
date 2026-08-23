import 'dart:math';

import '../constants/app_constants.dart';
import '../../data/models/pose_landmark_point.dart';

class LandmarkSmoother {
  LandmarkSmoother({this.alpha = AppConstants.defaultLandmarkSmoothingFactor});

  final double alpha;
  final Map<String, PoseLandmarkPoint> _smoothedByType = {};

  double _lastAverageMotion = 1.0;

  double get lastAverageMotion => _lastAverageMotion;

  bool isStable(double sensitivity) {
    return _lastAverageMotion <= sensitivity;
  }

  List<PoseLandmarkPoint> smooth(List<PoseLandmarkPoint> landmarks) {
    final reliableLandmarks = landmarks
        .where(
          (landmark) =>
              landmark.likelihood >= AppConstants.minimumLandmarkLikelihood,
        )
        .toList(growable: false);

    if (reliableLandmarks.isEmpty) {
      reset();
      return const [];
    }

    final currentTypes = reliableLandmarks
        .map((landmark) => landmark.type)
        .toSet();
    _smoothedByType.removeWhere((type, _) => !currentTypes.contains(type));

    final scale = _poseScaleFor(reliableLandmarks);
    var totalMotion = 0.0;
    var motionCount = 0;
    final smoothedLandmarks = <PoseLandmarkPoint>[];

    for (final landmark in reliableLandmarks) {
      final previous = _smoothedByType[landmark.type];
      final smoothed = previous == null
          ? landmark
          : PoseLandmarkPoint(
              type: landmark.type,
              x: _blend(current: landmark.x, previous: previous.x),
              y: _blend(current: landmark.y, previous: previous.y),
              z: _blend(current: landmark.z, previous: previous.z),
              likelihood: max(
                landmark.likelihood,
                _blend(
                  current: landmark.likelihood,
                  previous: previous.likelihood,
                ),
              ),
            );

      if (previous != null) {
        totalMotion += _distanceBetween(previous, smoothed) / scale;
        motionCount += 1;
      }

      _smoothedByType[landmark.type] = smoothed;
      smoothedLandmarks.add(smoothed);
    }

    _lastAverageMotion = motionCount == 0 ? 0.0 : totalMotion / motionCount;
    return smoothedLandmarks;
  }

  void reset() {
    _smoothedByType.clear();
    _lastAverageMotion = 1.0;
  }

  double _blend({required double current, required double previous}) {
    final clampedAlpha = alpha.clamp(0.0, 1.0).toDouble();
    return (clampedAlpha * current) + ((1 - clampedAlpha) * previous);
  }

  double _poseScaleFor(List<PoseLandmarkPoint> landmarks) {
    final xs = landmarks.map((landmark) => landmark.x).toList(growable: false);
    final ys = landmarks.map((landmark) => landmark.y).toList(growable: false);
    final width = xs.reduce(max) - xs.reduce(min);
    final height = ys.reduce(max) - ys.reduce(min);
    return max(max(width, height), 1.0);
  }

  double _distanceBetween(PoseLandmarkPoint first, PoseLandmarkPoint second) {
    return sqrt(
      pow(second.x - first.x, 2) +
          pow(second.y - first.y, 2) +
          pow((second.z - first.z) / 2, 2),
    );
  }
}
