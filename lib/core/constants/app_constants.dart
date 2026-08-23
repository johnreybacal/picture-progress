class AppConstants {
  const AppConstants._();

  static const double defaultAutoCaptureThreshold = 90;
  static const double defaultZoomLevel = 1.0;
  static const double defaultExposureOffset = 0.0;
  static const Duration autoCaptureHoldDuration = Duration(milliseconds: 1500);
  static const int exportWidth = 1080;
  static const int exportHeight = 1920;
  static const double targetAnchorX = 0.5;
  static const double targetAnchorY = 0.58;
  static const double exportBodyPaddingMultiplier = 1.45;
  static const double minimumLandmarkLikelihood = 0.2;
}
