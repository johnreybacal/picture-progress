import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../data/models/pose_record.dart';
import '../../../../data/models/pose_series.dart';

class ExportPreviewPage extends ConsumerStatefulWidget {
  const ExportPreviewPage({super.key, required this.series});

  final PoseSeries series;

  @override
  ConsumerState<ExportPreviewPage> createState() => _ExportPreviewPageState();
}

class _ExportPreviewPageState extends ConsumerState<ExportPreviewPage> {
  int _selectedIndex = 0;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(seriesRecordsProvider(widget.series.id!));

    return Scaffold(
      appBar: AppBar(title: const Text('Timelapse Preview')),
      body: SafeArea(
        child: recordsAsync.when(
          data: (records) {
            final orderedRecords = [...records]
              ..sort(
                (first, second) => first.timestamp.compareTo(second.timestamp),
              );
            if (orderedRecords.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Add at least one capture before previewing the timelapse.',
                  ),
                ),
              );
            }

            final selectedIndex = min(
              _selectedIndex,
              orderedRecords.length - 1,
            );
            final selectedRecord = orderedRecords[selectedIndex];

            return Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.series.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Scrub through captures in chronological order before generating the stabilized export.',
                            ),
                            const SizedBox(height: 16),
                            FutureBuilder<String>(
                              future: ref
                                  .read(fileStorageServiceProvider)
                                  .resolveAbsolutePath(
                                    selectedRecord.imagePath,
                                  ),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData ||
                                    snapshot.data!.isEmpty) {
                                  return const AspectRatio(
                                    aspectRatio: 9 / 16,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: AspectRatio(
                                    aspectRatio: 9 / 16,
                                    child: Image.file(
                                      File(snapshot.data!),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Frame ${selectedIndex + 1} of ${orderedRecords.length}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(_formatTimestamp(context, selectedRecord)),
                            const SizedBox(height: 12),
                            Slider(
                              value: selectedIndex.toDouble(),
                              min: 0,
                              max: max(orderedRecords.length - 1, 1).toDouble(),
                              divisions: orderedRecords.length > 1
                                  ? orderedRecords.length - 1
                                  : 1,
                              label: '${selectedIndex + 1}',
                              onChanged: (value) {
                                setState(() {
                                  _selectedIndex = value.round();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Export',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Each frame is re-centered with the saved anchor point, cropped to a consistent body box, then stitched into the final timelapse.',
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _exporting
                                        ? null
                                        : () => _exportMp4(orderedRecords),
                                    icon: const Icon(
                                      Icons.movie_creation_outlined,
                                    ),
                                    label: const Text('Export MP4'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _exporting
                                        ? null
                                        : () => _exportGif(orderedRecords),
                                    icon: const Icon(Icons.gif_box_outlined),
                                    label: const Text('Export GIF'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_exporting)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.25),
                      child: const Center(child: CircularProgressIndicator()),
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

  Future<void> _exportMp4(List<PoseRecord> records) async {
    await _runExport(
      () => ref
          .read(timelapseExportServiceProvider)
          .exportMp4(series: widget.series, records: records),
    );
  }

  Future<void> _exportGif(List<PoseRecord> records) async {
    await _runExport(
      () => ref
          .read(timelapseExportServiceProvider)
          .exportGif(series: widget.series, records: records),
    );
  }

  Future<void> _runExport(Future<String> Function() action) async {
    setState(() {
      _exporting = true;
    });

    try {
      final outputPath = await action();
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export created at $outputPath')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  String _formatTimestamp(BuildContext context, PoseRecord record) {
    final localizations = MaterialLocalizations.of(context);
    final timeOfDay = TimeOfDay.fromDateTime(record.timestamp);
    return '${localizations.formatFullDate(record.timestamp)} at ${localizations.formatTimeOfDay(timeOfDay)}';
  }
}
