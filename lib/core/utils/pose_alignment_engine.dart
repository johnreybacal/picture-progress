import 'dart:math';

import '../constants/app_constants.dart';
import '../../data/models/pose_bounding_box.dart';
import '../../data/models/pose_landmark_point.dart';
import '../../data/models/pose_point.dart';

class PoseAlignmentResult {
  const PoseAlignmentResult({
    required this.score,
    required this.pointSimilarity,
    required this.vectorSimilarity,
    required this.angleSimilarity,
    required this.matchedLandmarks,
  });

  const PoseAlignmentResult.empty()
    : score = 0,
      pointSimilarity = 0,
      vectorSimilarity = 0,
      angleSimilarity = 0,
      matchedLandmarks = 0;

  final double score;
  final double pointSimilarity;
  final double vectorSimilarity;
  final double angleSimilarity;
  final int matchedLandmarks;
}

class PoseGeometry {
  const PoseGeometry._();

  static PoseBoundingBox boundingBoxFor(List<PoseLandmarkPoint> landmarks) {
    final source = _visibleLandmarks(landmarks);
    if (source.isEmpty) {
      return const PoseBoundingBox(left: 0, top: 0, right: 0, bottom: 0);
    }

    final xs = source.map((landmark) => landmark.x).toList();
    final ys = source.map((landmark) => landmark.y).toList();

    return PoseBoundingBox(
      left: xs.reduce(min),
      top: ys.reduce(min),
      right: xs.reduce(max),
      bottom: ys.reduce(max),
    );
  }

  static PosePoint anchorFor(List<PoseLandmarkPoint> landmarks) {
    final map = {for (final landmark in landmarks) landmark.type: landmark};
    final leftHip = map['leftHip'];
    final rightHip = map['rightHip'];
    if (leftHip != null && rightHip != null) {
      return PosePoint(
        x: (leftHip.x + rightHip.x) / 2,
        y: (leftHip.y + rightHip.y) / 2,
      );
    }

    final leftShoulder = map['leftShoulder'];
    final rightShoulder = map['rightShoulder'];
    if (leftShoulder != null && rightShoulder != null) {
      return PosePoint(
        x: (leftShoulder.x + rightShoulder.x) / 2,
        y: (leftShoulder.y + rightShoulder.y) / 2,
      );
    }

    return boundingBoxFor(landmarks).center;
  }

  static List<PoseLandmarkPoint> _visibleLandmarks(
    List<PoseLandmarkPoint> landmarks,
  ) {
    final visible = landmarks
        .where(
          (landmark) =>
              landmark.likelihood >= AppConstants.minimumLandmarkLikelihood,
        )
        .toList();
    return visible.isEmpty ? landmarks : visible;
  }
}

class PoseAlignmentEngine {
  const PoseAlignmentEngine._();

  static const List<(String, String)> _vectorPairs = [
    ('leftShoulder', 'leftElbow'),
    ('leftElbow', 'leftWrist'),
    ('rightShoulder', 'rightElbow'),
    ('rightElbow', 'rightWrist'),
    ('leftHip', 'leftKnee'),
    ('leftKnee', 'leftAnkle'),
    ('rightHip', 'rightKnee'),
    ('rightKnee', 'rightAnkle'),
    ('leftShoulder', 'rightShoulder'),
    ('leftHip', 'rightHip'),
    ('leftShoulder', 'leftHip'),
    ('rightShoulder', 'rightHip'),
  ];

  static const List<(String, String, String)> _angleTriples = [
    ('leftShoulder', 'leftElbow', 'leftWrist'),
    ('rightShoulder', 'rightElbow', 'rightWrist'),
    ('leftHip', 'leftKnee', 'leftAnkle'),
    ('rightHip', 'rightKnee', 'rightAnkle'),
    ('leftElbow', 'leftShoulder', 'leftHip'),
    ('rightElbow', 'rightShoulder', 'rightHip'),
  ];

  static PoseAlignmentResult compare({
    required List<PoseLandmarkPoint> liveLandmarks,
    required List<PoseLandmarkPoint> referenceLandmarks,
    bool mirrorReferenceHorizontally = false,
  }) {
    final directResult = _compareInternal(
      liveLandmarks: liveLandmarks,
      referenceLandmarks: referenceLandmarks,
      mirrorReferenceHorizontally: false,
    );
    if (!mirrorReferenceHorizontally) {
      return directResult;
    }

    final mirroredResult = _compareInternal(
      liveLandmarks: liveLandmarks,
      referenceLandmarks: referenceLandmarks,
      mirrorReferenceHorizontally: true,
    );
    return mirroredResult.score > directResult.score
        ? mirroredResult
        : directResult;
  }

  static PoseAlignmentResult _compareInternal({
    required List<PoseLandmarkPoint> liveLandmarks,
    required List<PoseLandmarkPoint> referenceLandmarks,
    required bool mirrorReferenceHorizontally,
  }) {
    if (liveLandmarks.isEmpty || referenceLandmarks.isEmpty) {
      return const PoseAlignmentResult.empty();
    }

    final live = _normalize(liveLandmarks);
    final reference = _normalize(
      referenceLandmarks,
      mirrorHorizontally: mirrorReferenceHorizontally,
    );

    final commonTypes = live.points.keys.toSet().intersection(
      reference.points.keys.toSet(),
    );
    if (commonTypes.length < 6) {
      return const PoseAlignmentResult.empty();
    }

    final pointScores = <double>[];
    for (final type in commonTypes) {
      final distance = _distanceBetweenPoints(
        live.points[type]!,
        reference.points[type]!,
      );
      pointScores.add((1 - (distance / 0.55)).clamp(0.0, 1.0).toDouble());
    }

    final vectorScores = <double>[];
    for (final (start, end) in _vectorPairs) {
      final startLive = live.points[start];
      final endLive = live.points[end];
      final startReference = reference.points[start];
      final endReference = reference.points[end];
      if (startLive == null ||
          endLive == null ||
          startReference == null ||
          endReference == null) {
        continue;
      }

      final liveVector = _PointVector(
        endLive.x - startLive.x,
        endLive.y - startLive.y,
      );
      final referenceVector = _PointVector(
        endReference.x - startReference.x,
        endReference.y - startReference.y,
      );
      final similarity = _cosineSimilarity(liveVector, referenceVector);
      vectorScores.add(((similarity + 1) / 2).clamp(0.0, 1.0).toDouble());
    }

    final angleScores = <double>[];
    for (final (start, middle, end) in _angleTriples) {
      final liveAngle = _jointAngle(
        live.points[start],
        live.points[middle],
        live.points[end],
      );
      final referenceAngle = _jointAngle(
        reference.points[start],
        reference.points[middle],
        reference.points[end],
      );
      if (liveAngle == null || referenceAngle == null) {
        continue;
      }

      final difference = (liveAngle - referenceAngle).abs();
      angleScores.add((1 - (difference / pi)).clamp(0.0, 1.0).toDouble());
    }

    final pointSimilarity = _average(pointScores);
    final vectorSimilarity = _average(vectorScores, fallback: pointSimilarity);
    final angleSimilarity = _average(angleScores, fallback: vectorSimilarity);

    final weightedScore =
        (pointSimilarity * 0.5) +
        (vectorSimilarity * 0.3) +
        (angleSimilarity * 0.2);

    return PoseAlignmentResult(
      score: (weightedScore * 100).clamp(0.0, 100.0).toDouble(),
      pointSimilarity: pointSimilarity,
      vectorSimilarity: vectorSimilarity,
      angleSimilarity: angleSimilarity,
      matchedLandmarks: commonTypes.length,
    );
  }

  static _NormalizedPose _normalize(
    List<PoseLandmarkPoint> landmarks, {
    bool mirrorHorizontally = false,
  }) {
    final filteredLandmarks = landmarks.where((landmark) {
      return landmark.likelihood >= AppConstants.minimumLandmarkLikelihood / 2;
    }).toList();
    final source = filteredLandmarks.isEmpty ? landmarks : filteredLandmarks;
    final map = {for (final landmark in source) landmark.type: landmark};
    final anchor = PoseGeometry.anchorFor(source);
    final box = PoseGeometry.boundingBoxFor(source);

    final shoulderMidpoint = _midpoint(
      map['leftShoulder'],
      map['rightShoulder'],
    );
    final hipMidpoint = _midpoint(map['leftHip'], map['rightHip']);
    final torsoDistance = shoulderMidpoint != null && hipMidpoint != null
        ? _distance(shoulderMidpoint, hipMidpoint)
        : 0.0;
    final shoulderWidth = _distanceOf(
      map['leftShoulder'],
      map['rightShoulder'],
    );
    final hipWidth = _distanceOf(map['leftHip'], map['rightHip']);
    final boundingScale = max(box.width, box.height) * 0.6;

    final scaleCandidates = [
      torsoDistance,
      shoulderWidth,
      hipWidth,
      boundingScale,
    ].where((value) => value > 0.0001).toList();

    final scale = scaleCandidates.isEmpty ? 1.0 : scaleCandidates.reduce(max);
    final normalized = <String, _Point2D>{};
    for (final landmark in source) {
      normalized[landmark.type] = _Point2D(
        ((landmark.x - anchor.x) / scale) * (mirrorHorizontally ? -1 : 1),
        (landmark.y - anchor.y) / scale,
      );
    }

    return _NormalizedPose(points: normalized, anchor: anchor, scale: scale);
  }

  static double _average(List<double> values, {double fallback = 0}) {
    if (values.isEmpty) {
      return fallback;
    }
    return values.reduce((total, value) => total + value) / values.length;
  }

  static double _distanceOf(PoseLandmarkPoint? start, PoseLandmarkPoint? end) {
    if (start == null || end == null) {
      return 0;
    }
    return sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2));
  }

  static double _distance(PosePoint start, PosePoint end) {
    return sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2));
  }

  static double _distanceBetweenPoints(_Point2D start, _Point2D end) {
    return sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2));
  }

  static double _cosineSimilarity(_PointVector first, _PointVector second) {
    final firstMagnitude = first.magnitude;
    final secondMagnitude = second.magnitude;
    if (firstMagnitude == 0 || secondMagnitude == 0) {
      return 0;
    }

    return ((first.x * second.x) + (first.y * second.y)) /
        (firstMagnitude * secondMagnitude);
  }

  static double? _jointAngle(_Point2D? start, _Point2D? middle, _Point2D? end) {
    if (start == null || middle == null || end == null) {
      return null;
    }

    final firstVector = _PointVector(start.x - middle.x, start.y - middle.y);
    final secondVector = _PointVector(end.x - middle.x, end.y - middle.y);
    if (firstVector.magnitude == 0 || secondVector.magnitude == 0) {
      return null;
    }

    final cosine = (_cosineSimilarity(
      firstVector,
      secondVector,
    )).clamp(-1.0, 1.0).toDouble();
    return acos(cosine);
  }

  static PosePoint? _midpoint(
    PoseLandmarkPoint? first,
    PoseLandmarkPoint? second,
  ) {
    if (first == null || second == null) {
      return null;
    }

    return PosePoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2);
  }
}

class _NormalizedPose {
  const _NormalizedPose({
    required this.points,
    required this.anchor,
    required this.scale,
  });

  final Map<String, _Point2D> points;
  final PosePoint anchor;
  final double scale;
}

class _Point2D {
  const _Point2D(this.x, this.y);

  final double x;
  final double y;
}

class _PointVector {
  const _PointVector(this.x, this.y);

  final double x;
  final double y;

  double get magnitude => sqrt((x * x) + (y * y));
}
