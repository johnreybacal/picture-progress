import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseLandmarkPoint {
  const PoseLandmarkPoint({
    required this.type,
    required this.x,
    required this.y,
    required this.z,
    required this.likelihood,
  });

  final String type;
  final double x;
  final double y;
  final double z;
  final double likelihood;

  PoseLandmarkPoint copyWith({
    String? type,
    double? x,
    double? y,
    double? z,
    double? likelihood,
  }) {
    return PoseLandmarkPoint(
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      likelihood: likelihood ?? this.likelihood,
    );
  }

  factory PoseLandmarkPoint.fromPoseLandmark(PoseLandmark landmark) {
    return PoseLandmarkPoint(
      type: landmark.type.name,
      x: landmark.x,
      y: landmark.y,
      z: landmark.z,
      likelihood: landmark.likelihood,
    );
  }

  factory PoseLandmarkPoint.fromJson(Map<String, dynamic> json) {
    return PoseLandmarkPoint(
      type: json['type'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
      likelihood: (json['likelihood'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'type': type, 'x': x, 'y': y, 'z': z, 'likelihood': likelihood};
  }
}
