enum CaptureOrientation {
  portrait('portrait'),
  landscapeLeft('landscapeLeft'),
  landscapeRight('landscapeRight');

  const CaptureOrientation(this.storageValue);

  final String storageValue;

  bool get isLandscape => this != portrait;

  static CaptureOrientation fromStorage(String? value) {
    return CaptureOrientation.values.firstWhere(
      (orientation) => orientation.storageValue == value,
      orElse: () => CaptureOrientation.portrait,
    );
  }

  int quarterTurnsForDisplay({required int rawWidth, required int rawHeight}) {
    if (!isLandscape ||
        rawWidth <= 0 ||
        rawHeight <= 0 ||
        rawWidth <= rawHeight) {
      return 0;
    }

    switch (this) {
      case CaptureOrientation.portrait:
        return 0;
      case CaptureOrientation.landscapeLeft:
        return 1;
      case CaptureOrientation.landscapeRight:
        return 3;
    }
  }
}
