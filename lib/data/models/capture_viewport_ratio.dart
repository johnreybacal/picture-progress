enum CaptureViewportRatio {
  threeByFour('threeByFour', '3:4', 3 / 4),
  nineBySixteen('nineBySixteen', '9:16', 9 / 16),
  square('square', '1:1', 1),
  full('full', 'Full', null);

  const CaptureViewportRatio(this.storageValue, this.label, this.aspectRatio);

  final String storageValue;
  final String label;
  final double? aspectRatio;

  bool get isFull => aspectRatio == null;

  static CaptureViewportRatio fromStorage(String? value) {
    for (final viewportRatio in CaptureViewportRatio.values) {
      if (viewportRatio.storageValue == value) {
        return viewportRatio;
      }
    }

    return CaptureViewportRatio.full;
  }
}
