class AccuracyDebouncer {
  AccuracyDebouncer({required this.alpha, required this.updateInterval});

  final double alpha;
  final Duration updateInterval;

  double _displayedScore = 0;
  DateTime? _lastUpdateAt;

  double get displayedScore => _displayedScore;

  double update(double rawScore, {DateTime? timestamp}) {
    final now = timestamp ?? DateTime.now();
    if (_lastUpdateAt == null) {
      _displayedScore = rawScore;
      _lastUpdateAt = now;
      return _displayedScore;
    }

    if (now.difference(_lastUpdateAt!) < updateInterval) {
      return _displayedScore;
    }

    final clampedAlpha = alpha.clamp(0.0, 1.0).toDouble();
    _displayedScore += (rawScore - _displayedScore) * clampedAlpha;
    _lastUpdateAt = now;
    return _displayedScore;
  }

  void reset([double seed = 0]) {
    _displayedScore = seed;
    _lastUpdateAt = null;
  }
}
