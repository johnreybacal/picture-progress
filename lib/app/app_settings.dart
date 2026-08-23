import '../core/constants/app_constants.dart';

class AppSettings {
  const AppSettings({
    this.autoCaptureEnabled = true,
    this.alignmentThreshold = AppConstants.defaultAutoCaptureThreshold,
    this.stabilitySensitivity = AppConstants.defaultStabilitySensitivity,
    this.autoCaptureDelay = AppConstants.defaultAutoCaptureDelay,
  });

  final bool autoCaptureEnabled;
  final double alignmentThreshold;
  final double stabilitySensitivity;
  final Duration autoCaptureDelay;

  AppSettings copyWith({
    bool? autoCaptureEnabled,
    double? alignmentThreshold,
    double? stabilitySensitivity,
    Duration? autoCaptureDelay,
  }) {
    return AppSettings(
      autoCaptureEnabled: autoCaptureEnabled ?? this.autoCaptureEnabled,
      alignmentThreshold: alignmentThreshold ?? this.alignmentThreshold,
      stabilitySensitivity: stabilitySensitivity ?? this.stabilitySensitivity,
      autoCaptureDelay: autoCaptureDelay ?? this.autoCaptureDelay,
    );
  }
}
