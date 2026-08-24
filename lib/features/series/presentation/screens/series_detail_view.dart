import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/pose_thumbnail.dart';
import '../../../../data/models/pose_record.dart';
import '../../../../data/models/pose_series.dart';
import '../../../capture/presentation/screens/camera_view.dart';
import '../../../export/presentation/screens/export_preview_page.dart';
import '../../../settings/presentation/screens/app_settings_view.dart';
import 'progress_shot_detail_view.dart';

class SeriesDetailView extends ConsumerStatefulWidget {
  const SeriesDetailView({super.key, required this.initialSeries});

  final PoseSeries initialSeries;

  @override
  ConsumerState<SeriesDetailView> createState() => _SeriesDetailViewState();
}

class _SeriesDetailViewState extends ConsumerState<SeriesDetailView> {
  late PoseSeries _series;

  @override
  void initState() {
    super.initState();
    _series = widget.initialSeries;
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(seriesRecordsProvider(_series.id!));
    final baselineAsync = ref.watch(seriesBaselineProvider(_series.id!));
    final baseline = baselineAsync.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_series.name),
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
          PopupMenuButton<_SeriesDetailAction>(
            onSelected: (action) {
              switch (action) {
                case _SeriesDetailAction.edit:
                  _renameSeries();
                  break;
                case _SeriesDetailAction.delete:
                  _deleteSeries();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _SeriesDetailAction.edit,
                child: Text('Rename timeline'),
              ),
              PopupMenuItem(
                value: _SeriesDetailAction.delete,
                child: Text('Delete timeline'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: recordsAsync.when(
          data: (records) {
            final orderedRecords = [...records]
              ..sort(
                (first, second) => first.timestamp.compareTo(second.timestamp),
              );

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Timeline summary',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Created ${MaterialLocalizations.of(context).formatFullDate(_series.createdAt)}',
                        ),
                        const SizedBox(height: 6),
                        Text(
                          baseline == null
                              ? 'Baseline photo not captured yet.'
                              : 'Baseline photo saved on ${MaterialLocalizations.of(context).formatShortDate(baseline.timestamp)} with the ${baseline.cameraLens == 'front' ? 'front camera' : 'rear camera'}.',
                        ),
                        if (_series.preferredLens != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Default camera: ${_series.preferredLens!.label}',
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text('Total photos: ${orderedRecords.length}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openCamera(
                        isBaselineCapture: true,
                        baselineRecord: baseline,
                      ),
                      icon: const Icon(Icons.accessibility_new_rounded),
                      label: Text(
                        baseline == null
                            ? 'Capture baseline photo'
                            : 'Retake baseline photo',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: baseline == null
                          ? null
                          : () => _openCamera(
                              isBaselineCapture: false,
                              baselineRecord: baseline,
                            ),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Add progress photo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: orderedRecords.isEmpty
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      TimelapseExportView(series: _series),
                                ),
                              );
                            },
                      icon: const Icon(Icons.movie_filter_outlined),
                      label: const Text('Preview export'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Photo timeline',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (orderedRecords.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'No photos yet. Save the baseline photo first, then add aligned progress photos over time.',
                      ),
                    ),
                  )
                else
                  ...orderedRecords.map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RecordTile(
                        record: record,
                        onTap: () => _openRecord(record),
                      ),
                    ),
                  ),
              ],
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

  Future<void> _openCamera({
    required bool isBaselineCapture,
    required PoseRecord? baselineRecord,
  }) async {
    final didCapture = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => CameraView(
          series: _series,
          isBaselineCapture: isBaselineCapture,
          baselineRecord: baselineRecord,
        ),
      ),
    );
    if (didCapture == true) {
      ref.invalidate(seriesRecordsProvider(_series.id!));
      ref.invalidate(seriesBaselineProvider(_series.id!));
      await ref.read(seriesListControllerProvider.notifier).refresh();
      final updatedSeries = await ref
          .read(poseRepositoryProvider)
          .getSeries(_series.id!);
      if (updatedSeries != null && mounted) {
        setState(() {
          _series = updatedSeries;
        });
      }
    }
  }

  Future<void> _openRecord(PoseRecord record) async {
    final didChange = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) =>
            ProgressShotDetailView(series: _series, record: record),
      ),
    );
    if (didChange == true) {
      ref.invalidate(seriesRecordsProvider(_series.id!));
      ref.invalidate(seriesBaselineProvider(_series.id!));
      await ref.read(seriesListControllerProvider.notifier).refresh();
      final updatedSeries = await ref
          .read(poseRepositoryProvider)
          .getSeries(_series.id!);
      if (updatedSeries != null && mounted) {
        setState(() {
          _series = updatedSeries;
        });
      }
    }
  }

  Future<void> _renameSeries() async {
    final controller = TextEditingController(text: _series.name);
    final updatedName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename timeline'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Timeline name'),
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
    if (!mounted || updatedName == null || updatedName.isEmpty) {
      return;
    }

    final updatedSeries = await ref
        .read(seriesListControllerProvider.notifier)
        .renameSeries(_series, updatedName);
    if (!mounted) {
      return;
    }
    setState(() {
      _series = updatedSeries;
    });
  }

  Future<void> _deleteSeries() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete timeline?'),
        content: Text(
          'This removes ${_series.name}, all stored photos, and the local export folders.',
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
    if (shouldDelete != true || !mounted) {
      return;
    }

    await ref.read(seriesListControllerProvider.notifier).deleteSeries(_series);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, required this.onTap});

  final PoseRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(
                width: 92,
                height: 124,
                child: PoseThumbnail(record: record),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (record.isReference)
                          const Chip(label: Text('Baseline')),
                        Chip(
                          label: Text(
                            record.cameraLens == 'front'
                                ? 'Front camera'
                                : 'Rear camera',
                          ),
                        ),
                        Chip(
                          label: Text(
                            '${record.landmarks.length} alignment markers',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      record.label.isEmpty ? 'Untitled photo' : record.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      MaterialLocalizations.of(context)
                          .formatFullDate(record.timestamp),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      MaterialLocalizations.of(context).formatTimeOfDay(
                        TimeOfDay.fromDateTime(record.timestamp),
                      ),
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

enum _SeriesDetailAction { edit, delete }
