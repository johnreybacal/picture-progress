class PosePoint {
  const PosePoint({required this.x, required this.y});

  final double x;
  final double y;

  factory PosePoint.fromJson(Map<String, dynamic> json) {
    return PosePoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'x': x, 'y': y};
  }
}
