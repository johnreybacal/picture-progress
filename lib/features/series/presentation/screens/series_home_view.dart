import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/pose_thumbnail.dart';
import '../../../../data/models/pose_record.dart';
import '../../../../data/models/pose_series.dart';
import '../../../capture/presentation/screens/camera_view.dart';
import '../../../settings/presentation/screens/app_settings_view.dart';
import 'series_detail_view.dart';

class SeriesHomeView extends ConsumerWidget {
  const SeriesHomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesAsync = ref.watch(seriesListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Picture Progress'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AppSettingsView(),
                ),
              );
            },
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            onPressed: () =>
                ref.read(seriesListControllerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createSeries(context, ref),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('New timeline'),
      ),
      body: SafeArea(
        child: seriesAsync.when(
          data: (series) {
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(seriesListControllerProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Personal photo timelines',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Create a timeline for posture, outfits, growth, or visual check-ins. Save one baseline photo, add matching updates over time, and export a clean comparison video when you are ready.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (series.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text(
                          'No timelines yet. Start with a repeatable view like Front View, Side View, or a weekly check-in angle.',
                        ),
                      ),
                    )
                  else
                    ...series.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SeriesCard(
                          series: item,
                          onEdit: () => _renameSeries(context, ref, item),
                          onDelete: () => _deleteSeries(context, ref, item),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(error.toString(), textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createSeries(BuildContext context, WidgetRef ref) async {
    final name = await _promptForSeriesName(
      context,
      title: 'Create Photo Timeline',
    );
    if (!context.mounted || name == null || name.isEmpty) {
      return;
    }

    final createdSeries = await ref
        .read(seriesListControllerProvider.notifier)
        .createSeries(name);
    if (!context.mounted) {
      return;
    }

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) =>
            CameraView(series: createdSeries, isBaselineCapture: true),
      ),
    );

    if (!context.mounted) {
      return;
    }

    ref.invalidate(seriesBaselineProvider(createdSeries.id!));
    ref.invalidate(seriesRecordsProvider(createdSeries.id!));
    await ref.read(seriesListControllerProvider.notifier).refresh();
  }

  Future<void> _renameSeries(
    BuildContext context,
    WidgetRef ref,
    PoseSeries series,
  ) async {
    final updatedName = await _promptForSeriesName(
      context,
      title: 'Rename Timeline',
      initialValue: series.name,
    );
    if (!context.mounted || updatedName == null || updatedName.isEmpty) {
      return;
    }
    await ref
        .read(seriesListControllerProvider.notifier)
        .renameSeries(series, updatedName);
  }

  Future<void> _deleteSeries(
    BuildContext context,
    WidgetRef ref,
    PoseSeries series,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete timeline?'),
        content: Text(
          'This removes ${series.name}, all progress photos, and local exports for that timeline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) {
      return;
    }

    await ref.read(seriesListControllerProvider.notifier).deleteSeries(series);
  }

  Future<String?> _promptForSeriesName(
    BuildContext context, {
    required String title,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Timeline name',
            hintText: 'Front view',
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _SeriesCard extends ConsumerWidget {
  const _SeriesCard({
    required this.series,
    required this.onEdit,
    required this.onDelete,
  });

  final PoseSeries series;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(seriesRecordsProvider(series.id!));
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => SeriesDetailView(initialSeries: series),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                height: 128,
                child: _SeriesPreview(
                  recordsAsync: recordsAsync,
                  series: series,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            series.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        PopupMenuButton<_SeriesCardAction>(
                          onSelected: (action) {
                            switch (action) {
                              case _SeriesCardAction.edit:
                                onEdit();
                                break;
                              case _SeriesCardAction.delete:
                                onDelete();
                                break;
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _SeriesCardAction.edit,
                              child: Text('Rename timeline'),
                            ),
                            PopupMenuItem(
                              value: _SeriesCardAction.delete,
                              child: Text('Delete timeline'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Created ${MaterialLocalizations.of(context).formatShortDate(series.createdAt)}',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            series.baselineMetadata == null
                                ? 'Baseline needed'
                                : 'Baseline ready',
                          ),
                        ),
                        if (series.preferredLens != null)
                          Chip(
                            label: Text(
                              'Default: ${series.preferredLens!.label.toLowerCase()}',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeriesPreview extends StatelessWidget {
  const _SeriesPreview({required this.recordsAsync, required this.series});

  final AsyncValue<List<PoseRecord>> recordsAsync;
  final PoseSeries series;

  @override
  Widget build(BuildContext context) {
    final thumbnailRecord = recordsAsync.maybeWhen(
      data: (records) {
        for (final record in records) {
          if (record.imagePath == series.thumbnailPath) {
            return record;
          }
        }
        return records.isEmpty ? null : records.last;
      },
      orElse: () => null,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: thumbnailRecord == null
          ? const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFDDE2E8), Color(0xFFF2EEE7)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Icon(Icons.photo_library_outlined, size: 34),
            )
          : PoseThumbnail(record: thumbnailRecord),
    );
  }
}

enum _SeriesCardAction { edit, delete }
