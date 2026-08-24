import '../core/constants/app_constants.dart';

class AppSettings {
  const AppSettings({
    this.autoCaptureEnabled = true,
    this.alignmentThreshold = AppConstants.defaultAutoCaptureThreshold,
    this.stabilitySensitivity = AppConstants.defaultStabilitySensitivity,
    this.autoCaptureDelay = AppConstants.defaultAutoCaptureDelay,
    this.showReferenceOverlay = true,
    this.referenceOverlayOpacity = AppConstants.defaultReferenceOverlayOpacity,
    this.photoStorageDirectoryPath = '',
    this.exportDirectoryPath = '',
  });

  final bool autoCaptureEnabled;
  final double alignmentThreshold;
  final double stabilitySensitivity;
  final Duration autoCaptureDelay;
  final bool showReferenceOverlay;
  final double referenceOverlayOpacity;
  final String photoStorageDirectoryPath;
  final String exportDirectoryPath;

  AppSettings copyWith({
    bool? autoCaptureEnabled,
    double? alignmentThreshold,
    double? stabilitySensitivity,
    Duration? autoCaptureDelay,
    bool? showReferenceOverlay,
    double? referenceOverlayOpacity,
    String? photoStorageDirectoryPath,
    String? exportDirectoryPath,
  }) {
    return AppSettings(
      autoCaptureEnabled: autoCaptureEnabled ?? this.autoCaptureEnabled,
      alignmentThreshold: alignmentThreshold ?? this.alignmentThreshold,
      stabilitySensitivity: stabilitySensitivity ?? this.stabilitySensitivity,
      autoCaptureDelay: autoCaptureDelay ?? this.autoCaptureDelay,
      showReferenceOverlay: showReferenceOverlay ?? this.showReferenceOverlay,
      referenceOverlayOpacity:
          referenceOverlayOpacity ?? this.referenceOverlayOpacity,
      photoStorageDirectoryPath:
          photoStorageDirectoryPath ?? this.photoStorageDirectoryPath,
      exportDirectoryPath: exportDirectoryPath ?? this.exportDirectoryPath,
    );
  }
}
