import 'package:camera/camera.dart';

enum LensFacing {
  front('front', 'Front camera'),
  back('back', 'Rear camera');

  const LensFacing(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static LensFacing? fromStorage(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    for (final lensFacing in LensFacing.values) {
      if (lensFacing.storageValue == value) {
        return lensFacing;
      }
    }

    return null;
  }

  static LensFacing fromCameraLensDirection(CameraLensDirection direction) {
    switch (direction) {
      case CameraLensDirection.front:
        return LensFacing.front;
      case CameraLensDirection.back:
      case CameraLensDirection.external:
        return LensFacing.back;
    }
  }

  static LensFacing fromCameraLensName(String value) {
    return value == CameraLensDirection.front.name
        ? LensFacing.front
        : LensFacing.back;
  }

  CameraLensDirection get cameraLensDirection {
    switch (this) {
      case LensFacing.front:
        return CameraLensDirection.front;
      case LensFacing.back:
        return CameraLensDirection.back;
    }
  }
}
