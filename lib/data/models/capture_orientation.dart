enum CaptureOrientation {
  portrait('portrait'),
  landscapeLeft('landscapeLeft'),
  portraitDown('portraitDown'),
  landscapeRight('landscapeRight');

  const CaptureOrientation(this.storageValue);

  final String storageValue;

  bool get isLandscape =>
      this == CaptureOrientation.landscapeLeft ||
      this == CaptureOrientation.landscapeRight;

  static CaptureOrientation fromStorage(String? value) {
    return CaptureOrientation.values.firstWhere(
      (orientation) => orientation.storageValue == value,
      orElse: () => CaptureOrientation.portrait,
    );
  }

  int get referenceQuarterTurns {
    switch (this) {
      case CaptureOrientation.portrait:
        return 0;
      case CaptureOrientation.landscapeLeft:
        return 1;
      case CaptureOrientation.portraitDown:
        return 2;
      case CaptureOrientation.landscapeRight:
        return 3;
    }
  }

  int quarterTurnsForDisplay({required int rawWidth, required int rawHeight}) {
    switch (this) {
      case CaptureOrientation.portrait:
        return 0;
      case CaptureOrientation.landscapeLeft:
        return 1;
      case CaptureOrientation.portraitDown:
        return 2;
      case CaptureOrientation.landscapeRight:
        return 3;
    }
  }
}
