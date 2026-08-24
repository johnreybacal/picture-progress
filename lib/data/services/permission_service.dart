import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  PermissionService({DeviceInfoPlugin? deviceInfoPlugin})
    : _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfoPlugin;

  Future<StoragePermissionState> checkStorageAccess() async {
    final target = await _permissionTarget();
    if (target == null) {
      return const StoragePermissionState.granted();
    }

    final status = await target.permission.status;
    return StoragePermissionState.fromPermissionStatus(
      status,
      permissionLabel: target.label,
    );
  }

  Future<StoragePermissionState> requestStorageAccess() async {
    final target = await _permissionTarget();
    if (target == null) {
      return const StoragePermissionState.granted();
    }

    final status = await target.permission.request();
    return StoragePermissionState.fromPermissionStatus(
      status,
      permissionLabel: target.label,
    );
  }

  Future<void> ensureStorageAccess() async {
    final current = await checkStorageAccess();
    if (current.isGranted) {
      return;
    }

    final requested = await requestStorageAccess();
    if (requested.isGranted) {
      return;
    }

    throw StoragePermissionException(requested.permissionLabel);
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }

  Future<_PermissionTarget?> _permissionTarget() async {
    if (Platform.isIOS) {
      return const _PermissionTarget(
        permission: Permission.photos,
        label: 'Photos access',
      );
    }

    if (!Platform.isAndroid) {
      return null;
    }

    final androidInfo = await _deviceInfoPlugin.androidInfo;
    if (androidInfo.version.sdkInt >= 30) {
      return const _PermissionTarget(
        permission: Permission.manageExternalStorage,
        label: 'Files and media access',
      );
    }

    return const _PermissionTarget(
      permission: Permission.storage,
      label: 'Storage access',
    );
  }
}

class StoragePermissionState {
  const StoragePermissionState({
    required this.status,
    required this.permissionLabel,
  });

  const StoragePermissionState.granted()
    : status = PermissionStatus.granted,
      permissionLabel = 'Storage access';

  final PermissionStatus status;
  final String permissionLabel;

  bool get isGranted =>
      status == PermissionStatus.granted || status == PermissionStatus.limited;

  bool get shouldOpenSettings =>
      status == PermissionStatus.permanentlyDenied ||
      status == PermissionStatus.restricted;

  String get helperText {
    if (shouldOpenSettings) {
      return 'Picture Progress needs $permissionLabel to save photos, create export folders, and write timelapse videos into a location you can reach outside the app.';
    }

    return 'Picture Progress needs $permissionLabel before it can save progress photos or let you choose export folders.';
  }

  factory StoragePermissionState.fromPermissionStatus(
    PermissionStatus status, {
    required String permissionLabel,
  }) {
    return StoragePermissionState(
      status: status,
      permissionLabel: permissionLabel,
    );
  }
}

class StoragePermissionException implements Exception {
  const StoragePermissionException(this.permissionLabel);

  final String permissionLabel;

  @override
  String toString() {
    return 'Storage permission is required to continue. Grant $permissionLabel and try again.';
  }
}

class _PermissionTarget {
  const _PermissionTarget({required this.permission, required this.label});

  final Permission permission;
  final String label;
}
