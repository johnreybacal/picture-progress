import '../core/constants/app_constants.dart';

class AppSettings {
  const AppSettings({
    this.autoCaptureEnabled = true,
    this.alignmentThreshold = AppConstants.defaultAutoCaptureThreshold,
    this.stabilitySensitivity = AppConstants.defaultStabilitySensitivity,
    this.autoCaptureDelay = AppConstants.defaultAutoCaptureDelay,
    this.showBaselineOverlay = true,
    this.baselineOverlayOpacity = AppConstants.defaultBaselineOverlayOpacity,
    this.photoStorageDirectoryPath = '',
    this.exportDirectoryPath = '',
  });

  final bool autoCaptureEnabled;
  final double alignmentThreshold;
  final double stabilitySensitivity;
  final Duration autoCaptureDelay;
  final bool showBaselineOverlay;
  final double baselineOverlayOpacity;
  final String photoStorageDirectoryPath;
  final String exportDirectoryPath;

  AppSettings copyWith({
    bool? autoCaptureEnabled,
    double? alignmentThreshold,
    double? stabilitySensitivity,
    Duration? autoCaptureDelay,
    bool? showBaselineOverlay,
    double? baselineOverlayOpacity,
    String? photoStorageDirectoryPath,
    String? exportDirectoryPath,
  }) {
    return AppSettings(
      autoCaptureEnabled: autoCaptureEnabled ?? this.autoCaptureEnabled,
      alignmentThreshold: alignmentThreshold ?? this.alignmentThreshold,
      stabilitySensitivity: stabilitySensitivity ?? this.stabilitySensitivity,
      autoCaptureDelay: autoCaptureDelay ?? this.autoCaptureDelay,
      showBaselineOverlay: showBaselineOverlay ?? this.showBaselineOverlay,
      baselineOverlayOpacity:
          baselineOverlayOpacity ?? this.baselineOverlayOpacity,
      photoStorageDirectoryPath:
          photoStorageDirectoryPath ?? this.photoStorageDirectoryPath,
      exportDirectoryPath: exportDirectoryPath ?? this.exportDirectoryPath,
    );
  }
}
