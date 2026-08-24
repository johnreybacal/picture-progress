import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers.dart';
import '../../data/services/permission_service.dart';

class StoragePermissionGate extends ConsumerStatefulWidget {
  const StoragePermissionGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StoragePermissionGate> createState() =>
      _StoragePermissionGateState();
}

class _StoragePermissionGateState extends ConsumerState<StoragePermissionGate>
    with WidgetsBindingObserver {
  StoragePermissionState? _permissionState;
  bool _checking = true;
  bool _busy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshPermission(requestIfNeeded: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermission());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissionState =
        _permissionState ??
        StoragePermissionState.fromPermissionStatus(
          PermissionStatus.denied,
          permissionLabel: 'Storage access',
        );

    if (_checking) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 18),
                Text(
                  'Preparing storage access…',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (permissionState.isGranted) {
      return widget.child;
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              Icons.folder_copy_outlined,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Storage access is required',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 10),
                          Text(permissionState.helperText),
                          const SizedBox(height: 12),
                          Text(
                            'You can change photo and export folders later after access is granted.',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _errorMessage!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _refreshPermission(requestIfNeeded: true),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      permissionState.shouldOpenSettings
                          ? 'Try again'
                          : 'Allow access',
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _openSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open app settings'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshPermission({bool requestIfNeeded = false}) async {
    setState(() {
      _checking = true;
      _busy = true;
      _errorMessage = null;
    });

    try {
      final permissionService = ref.read(permissionServiceProvider);
      var permissionState = await permissionService.checkStorageAccess();
      if (!permissionState.isGranted && requestIfNeeded) {
        permissionState = await permissionService.requestStorageAccess();
      }

      if (permissionState.isGranted) {
        await ref
            .read(fileStorageServiceProvider)
            .initializeStorageDirectories();
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _permissionState = permissionState;
        _checking = false;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _permissionState = StoragePermissionState.fromPermissionStatus(
          PermissionStatus.denied,
          permissionLabel: 'Storage access',
        );
        _checking = false;
        _busy = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _openSettings() async {
    setState(() {
      _busy = true;
    });
    try {
      await ref.read(permissionServiceProvider).openSettings();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }
}
