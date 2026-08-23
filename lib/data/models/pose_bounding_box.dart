import 'pose_point.dart';

class PoseBoundingBox {
  const PoseBoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  PosePoint get center =>
      PosePoint(x: (left + right) / 2, y: (top + bottom) / 2);

  factory PoseBoundingBox.fromJson(Map<String, dynamic> json) {
    return PoseBoundingBox(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      right: (json['right'] as num).toDouble(),
      bottom: (json['bottom'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'left': left, 'top': top, 'right': right, 'bottom': bottom};
  }
}
