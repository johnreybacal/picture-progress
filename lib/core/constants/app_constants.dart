class AppConstants {
  const AppConstants._();

  static const double defaultAutoCaptureThreshold = 90;
  static const double defaultAccuracyDebounceAlpha = 0.32;
  static const Duration accuracyDebounceInterval = Duration(milliseconds: 200);
  static const double defaultStabilitySensitivity = 0.035;
  static const double minimumStabilitySensitivity = 0.015;
  static const double maximumStabilitySensitivity = 0.105;
  static const Duration defaultAutoCaptureDelay = Duration(milliseconds: 1400);
  static const Duration minimumAutoCaptureDelay = Duration(milliseconds: 500);
  static const Duration maximumAutoCaptureDelay = Duration(milliseconds: 2500);
  static const double defaultReferenceOverlayOpacity = 0.42;
  static const double defaultLandmarkSmoothingFactor = 0.32;
  static const double defaultZoomLevel = 1.0;
  static const int defaultTimelapseFps = 8;
  static const int exportWidth = 1080;
  static const int exportHeight = 1920;
  static const double targetAnchorX = 0.5;
  static const double targetAnchorY = 0.58;
  static const double exportBodyPaddingMultiplier = 1.45;
  static const double minimumLandmarkLikelihood = 0.5;
}
