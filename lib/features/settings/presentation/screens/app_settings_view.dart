import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/path_formatter.dart';

class AppSettingsView extends ConsumerWidget {
  const AppSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final delayMs = settings.autoCaptureDelay.inMilliseconds.toDouble();
    final fileStorage = ref.read(fileStorageServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Photo settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: SwitchListTile.adaptive(
                value: settings.autoCaptureEnabled,
                onChanged: controller.setAutoCaptureEnabled,
                title: const Text('Enable guided auto-capture'),
                subtitle: const Text(
                  'Automatically save a progress photo when alignment, stability, and delay requirements are met.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Photo storage location',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'New progress photos are saved inside a timeline folder under this location.',
                    ),
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: FutureBuilder<String>(
                          future: settings.photoStorageDirectoryPath.isNotEmpty
                              ? Future.value(settings.photoStorageDirectoryPath)
                              : fileStorage.defaultPhotoLibraryRootPath(),
                          builder: (context, snapshot) {
                            final resolvedPath = snapshot.data ?? 'Loading...';
                            return Text(
                              snapshot.hasData
                                  ? PathFormatter.formatDirectoryLabel(
                                      resolvedPath,
                                    )
                                  : resolvedPath,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final selectedPath = await fileStorage
                                  .pickPhotoStorageDirectory();
                              if (selectedPath == null) {
                                return;
                              }
                              controller.setPhotoStorageDirectoryPath(
                                selectedPath,
                              );
                            },
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text('Choose folder'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () async {
                              final defaultPath = await fileStorage
                                  .defaultPhotoLibraryRootPath();
                              controller.setPhotoStorageDirectoryPath(
                                defaultPath,
                              );
                            },
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Use default'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile.adaptive(
                value: settings.showReferenceOverlay,
                onChanged: controller.setReferenceOverlayEnabled,
                title: const Text('Show guide overlay'),
                subtitle: const Text(
                  'Draw the latest saved guide pose on top of the live camera feed so positioning is easier before each photo.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile.adaptive(
                value: settings.showLiveSkeletonOverlay,
                onChanged: controller.setLiveSkeletonOverlayEnabled,
                title: const Text('Show live pose skeleton'),
                subtitle: const Text(
                  'Draw the current detected pose on top of the live camera preview.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SettingCard(
              title: 'Guide overlay opacity',
              subtitle: 'Adjust how visible the saved guide appears over the camera preview.',
              valueLabel:
                  '${(settings.referenceOverlayOpacity * 100).round()}%',
              child: Slider.adaptive(
                value: settings.referenceOverlayOpacity,
                min: 0,
                max: 1,
                divisions: 20,
                label: '${(settings.referenceOverlayOpacity * 100).round()}%',
                onChanged: settings.showReferenceOverlay
                    ? controller.setReferenceOverlayOpacity
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            _SettingCard(
              title: 'Alignment sensitivity',
              subtitle: 'Higher values demand a closer match to the latest saved photo before auto-capture can start.',
              valueLabel: '${settings.alignmentThreshold.round()}%',
              child: Slider.adaptive(
                value: settings.alignmentThreshold,
                min: 75,
                max: 98,
                divisions: 23,
                label: '${settings.alignmentThreshold.round()}%',
                onChanged: controller.setAlignmentThreshold,
              ),
            ),
            const SizedBox(height: 16),
            _SettingCard(
              title: 'Stability sensitivity',
              subtitle: 'Lower values are stricter and require the body to settle more before the countdown begins.',
              valueLabel: _stabilityLabel(settings.stabilitySensitivity),
              child: Slider.adaptive(
                value: settings.stabilitySensitivity,
                min: AppConstants.minimumStabilitySensitivity,
                max: AppConstants.maximumStabilitySensitivity,
                divisions: 18,
                label: _stabilityLabel(settings.stabilitySensitivity),
                onChanged: controller.setStabilitySensitivity,
              ),
            ),
            const SizedBox(height: 16),
            _SettingCard(
              title: 'Auto-capture delay',
              subtitle: 'Adds a short hold timer after alignment and stability are reached so last-second movement does not trigger a photo.',
              valueLabel: '${settings.autoCaptureDelay.inMilliseconds / 1000}s',
              child: Slider.adaptive(
                value: delayMs,
                min: AppConstants.minimumAutoCaptureDelay.inMilliseconds
                    .toDouble(),
                max: AppConstants.maximumAutoCaptureDelay.inMilliseconds
                    .toDouble(),
                divisions:
                    ((AppConstants.maximumAutoCaptureDelay.inMilliseconds -
                                AppConstants
                                    .minimumAutoCaptureDelay
                                    .inMilliseconds) /
                            100)
                        .round(),
                label: '${(delayMs / 1000).toStringAsFixed(1)}s',
                onChanged: (value) {
                  controller.setAutoCaptureDelay(
                    Duration(milliseconds: value.round()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stabilityLabel(double value) {
    final percent = (value * 100).toStringAsFixed(1);
    return '$percent% movement';
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    required this.child,
  });

  final String title;
  final String subtitle;
  final String valueLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Text(valueLabel, style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            child,
          ],
        ),
      ),
    );
  }
}
