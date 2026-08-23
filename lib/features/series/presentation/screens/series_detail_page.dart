import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../data/models/pose_record.dart';
import '../../../../data/models/pose_series.dart';
import '../../../capture/presentation/screens/capture_page.dart';
import '../../../export/presentation/screens/export_preview_page.dart';

class SeriesDetailPage extends ConsumerWidget {
  const SeriesDetailPage({super.key, required this.series});

  final PoseSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(seriesRecordsProvider(series.id!));
    final baselineAsync = ref.watch(seriesBaselineProvider(series.id!));
    final baseline = baselineAsync.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(title: Text(series.name)),
      body: recordsAsync.when(
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
                        'Series Summary',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Created ${MaterialLocalizations.of(context).formatFullDate(series.createdAt)}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Reference pose: ${baseline == null ? 'Not captured yet' : 'Ready'}',
                      ),
                      const SizedBox(height: 6),
                      Text('Total captures: ${orderedRecords.length}'),
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
                    onPressed: () => _openCapture(
                      context,
                      ref,
                      isBaselineCapture: true,
                      baselineRecord: baseline,
                    ),
                    icon: const Icon(Icons.accessibility_new_rounded),
                    label: Text(
                      baseline == null ? 'Capture baseline' : 'Retake baseline',
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: baseline == null
                        ? null
                        : () => _openCapture(
                            context,
                            ref,
                            isBaselineCapture: false,
                            baselineRecord: baseline,
                          ),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Add progress shot'),
                  ),
                  OutlinedButton.icon(
                    onPressed: orderedRecords.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    ExportPreviewPage(series: series),
                              ),
                            );
                          },
                    icon: const Icon(Icons.movie_filter_outlined),
                    label: const Text('Preview export'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Timeline', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (orderedRecords.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'No captures yet. Start by saving the baseline pose, then add aligned progress shots over time.',
                    ),
                  ),
                )
              else
                ...orderedRecords.map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RecordTile(record: record),
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
    );
  }

  Future<void> _openCapture(
    BuildContext context,
    WidgetRef ref, {
    required bool isBaselineCapture,
    required PoseRecord? baselineRecord,
  }) async {
    final didCapture = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => PoseCapturePage(
          series: series,
          isBaselineCapture: isBaselineCapture,
          baselineRecord: baselineRecord,
        ),
      ),
    );

    if (didCapture == true) {
      ref.invalidate(seriesRecordsProvider(series.id!));
      ref.invalidate(seriesBaselineProvider(series.id!));
      await ref.read(seriesListControllerProvider.notifier).refresh();
    }
  }
}

class _RecordTile extends ConsumerWidget {
  const _RecordTile({required this.record});

  final PoseRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            FutureBuilder<String>(
              future: ref
                  .read(fileStorageServiceProvider)
                  .resolveAbsolutePath(record.imagePath),
              builder: (context, snapshot) {
                final imagePath = snapshot.data;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: 84,
                    height: 112,
                    child: imagePath == null || imagePath.isEmpty
                        ? const ColoredBox(
                            color: Color(0xFFE7E2D7),
                            child: Icon(Icons.image_not_supported_outlined),
                          )
                        : Image.file(File(imagePath), fit: BoxFit.cover),
                  ),
                );
              },
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
                      Chip(label: Text('${record.landmarks.length} landmarks')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    MaterialLocalizations.of(context)
                        .formatFullDate(record.timestamp),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatTimeOfDay(TimeOfDay.fromDateTime(record.timestamp)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
