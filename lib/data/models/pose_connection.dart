class PoseConnection {
  const PoseConnection({required this.startType, required this.endType});

  final String startType;
  final String endType;

  factory PoseConnection.fromJson(Map<String, dynamic> json) {
    return PoseConnection(
      startType: json['startType'] as String,
      endType: json['endType'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'startType': startType, 'endType': endType};
  }
}
