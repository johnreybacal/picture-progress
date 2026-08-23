import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/constants/app_constants.dart';

class AppSettingsView extends ConsumerWidget {
  const AppSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final delayMs = settings.autoCaptureDelay.inMilliseconds.toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Capture settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: SwitchListTile.adaptive(
                value: settings.autoCaptureEnabled,
                onChanged: controller.setAutoCaptureEnabled,
                title: const Text('Enable auto-capture'),
                subtitle: const Text(
                  'Automatically save a progress shot when alignment, stability, and delay requirements are met.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SettingCard(
              title: 'Alignment threshold',
              subtitle: 'Higher values demand a closer match to the baseline pose before arming auto-capture.',
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
              subtitle: 'Lower values are stricter and require the body to settle more before auto-capture starts counting down.',
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
              subtitle: 'Adds a short hold timer after the posture is aligned and stable so last-second jitter does not trigger a shot.',
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
