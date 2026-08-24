import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../../../app/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/path_formatter.dart';
import '../../../../core/widgets/pose_thumbnail.dart';
import '../../../../data/models/pose_record.dart';
import '../../../../data/models/pose_series.dart';

class TimelapseExportView extends ConsumerStatefulWidget {
  const TimelapseExportView({super.key, required this.series});

  final PoseSeries series;

  @override
  ConsumerState<TimelapseExportView> createState() =>
      _TimelapseExportViewState();
}

class ExportPreviewPage extends TimelapseExportView {
  const ExportPreviewPage({super.key, required super.series});
}

class _TimelapseExportViewState extends ConsumerState<TimelapseExportView> {
  static const List<double> _speedPresets = [0.5, 1, 2, 5];

  Timer? _playbackTimer;
  int _selectedIndex = 0;
  int _selectedSpeedIndex = 1;
  bool _isPlaying = false;
  bool _loopPlayback = true;
  bool _exporting = false;
  bool _loadingExportDirectory = true;
  String? _exportDirectoryPath;
  String? _exportDirectoryLabel;

  double get _speedMultiplier => _speedPresets[_selectedSpeedIndex];

  int get _resolvedFps =>
      max(1, (AppConstants.defaultTimelapseFps * _speedMultiplier).round());

  Duration get _frameInterval =>
      Duration(milliseconds: max(40, (1000 / _resolvedFps).round()));

  @override
  void initState() {
    super.initState();
    unawaited(_loadExportDirectory());
  }

  @override
  void dispose() {
    _stopPlayback(updateState: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(seriesRecordsProvider(widget.series.id!));

    return Scaffold(
      appBar: AppBar(title: const Text('Video export')),
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
            final currentExportDirectory =
                _exportDirectoryLabel ?? 'Loading...';

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
                              'Preview the saved photo sequence at the same speed and loop setting that will drive the final export.',
                            ),
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: AspectRatio(
                                aspectRatio: selectedRecord.displayAspectRatio,
                                child: PoseThumbnail(
                                  record: selectedRecord,
                                  borderRadius: BorderRadius.circular(0),
                                  fit: BoxFit.contain,
                                  showSkeletonOverlay: false,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilledButton.icon(
                                  onPressed: orderedRecords.length < 2
                                      ? null
                                      : () => _togglePlayback(orderedRecords),
                                  icon: Icon(
                                    _isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  label: Text(
                                    _isPlaying
                                        ? 'Pause preview'
                                        : 'Play preview',
                                  ),
                                ),
                                FilterChip(
                                  selected: _loopPlayback,
                                  onSelected: (value) {
                                    setState(() {
                                      _loopPlayback = value;
                                    });
                                  },
                                  label: const Text('Loop playback'),
                                ),
                                Chip(label: Text('${_speedMultiplier}x')),
                                Chip(label: Text('$_resolvedFps FPS')),
                              ],
                            ),
                            const SizedBox(height: 12),
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
                              'Playback speed',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'This speed controls the interactive preview timing and the final MP4 or GIF frame rate.',
                            ),
                            const SizedBox(height: 16),
                            Slider(
                              value: _selectedSpeedIndex.toDouble(),
                              min: 0,
                              max: (_speedPresets.length - 1).toDouble(),
                              divisions: _speedPresets.length - 1,
                              label: '${_speedMultiplier}x',
                              onChanged: (value) {
                                setState(() {
                                  _selectedSpeedIndex = value.round();
                                });
                                _restartPlaybackIfNeeded(orderedRecords);
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: _speedPresets
                                  .map(
                                    (speed) => Text(
                                      '${speed}x',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                                  )
                                  .toList(growable: false),
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
                              'Export destination',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Exports stay inside a dated folder for this timeline. You can keep the default storage root or point future exports somewhere else.',
                            ),
                            const SizedBox(height: 12),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(currentExportDirectory),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _loadingExportDirectory
                                        ? null
                                        : _changeExportDirectory,
                                    icon: const Icon(Icons.folder_open_rounded),
                                    label: const Text('Change directory'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: _loadingExportDirectory
                                        ? null
                                        : _useDefaultExportDirectory,
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
                            Text(
                              'Each frame is rotated upright if needed, translated around the baseline body center, and rendered full-frame at $_resolvedFps FPS without zoom cropping.',
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed:
                                        _exporting || _loadingExportDirectory
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
                                    onPressed:
                                        _exporting || _loadingExportDirectory
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

  Future<void> _loadExportDirectory() async {
    final settings = ref.read(appSettingsProvider);
    final fileStorage = ref.read(fileStorageServiceProvider);
    final exportRoot = settings.exportDirectoryPath.isNotEmpty
        ? settings.exportDirectoryPath
        : await fileStorage.defaultExportRootPath();
    final previewDirectory = await fileStorage.defaultExportDirectoryPath(
      series: widget.series,
      preferredRootPath: exportRoot,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _exportDirectoryPath = exportRoot;
      _exportDirectoryLabel = PathFormatter.formatDirectoryLabel(
        previewDirectory,
      );
      _loadingExportDirectory = false;
    });
  }

  Future<void> _changeExportDirectory() async {
    final fileStorage = ref.read(fileStorageServiceProvider);
    if (!mounted) {
      return;
    }
    final selectedPath = await fileStorage.pickExportDirectory();
    if (!mounted || selectedPath == null) {
      return;
    }
    final previewDirectory = await fileStorage.defaultExportDirectoryPath(
      series: widget.series,
      preferredRootPath: selectedPath,
    );
    ref.read(appSettingsProvider.notifier).setExportDirectoryPath(selectedPath);
    setState(() {
      _exportDirectoryPath = selectedPath;
      _exportDirectoryLabel = PathFormatter.formatDirectoryLabel(
        previewDirectory,
      );
    });
  }

  Future<void> _useDefaultExportDirectory() async {
    final fileStorage = ref.read(fileStorageServiceProvider);
    final defaultRoot = await fileStorage.defaultExportRootPath();
    final previewDirectory = await fileStorage.defaultExportDirectoryPath(
      series: widget.series,
      preferredRootPath: defaultRoot,
    );
    ref.read(appSettingsProvider.notifier).setExportDirectoryPath(defaultRoot);
    if (!mounted) {
      return;
    }
    setState(() {
      _exportDirectoryPath = defaultRoot;
      _exportDirectoryLabel = PathFormatter.formatDirectoryLabel(
        previewDirectory,
      );
    });
  }

  void _togglePlayback(List<PoseRecord> records) {
    if (_isPlaying) {
      _stopPlayback();
      return;
    }
    _startPlayback(records.length);
  }

  void _startPlayback(int frameCount) {
    if (frameCount < 2) {
      return;
    }

    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = true;
    });
    _playbackTimer = Timer.periodic(_frameInterval, (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (_selectedIndex >= frameCount - 1) {
          if (_loopPlayback) {
            _selectedIndex = 0;
            return;
          }
          _stopPlayback(updateState: false);
          return;
        }
        _selectedIndex += 1;
      });
    });
  }

  void _restartPlaybackIfNeeded(List<PoseRecord> records) {
    if (_isPlaying) {
      _startPlayback(records.length);
    }
  }

  void _stopPlayback({bool updateState = true}) {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (updateState && mounted) {
      setState(() {
        _isPlaying = false;
      });
      return;
    }
    _isPlaying = false;
  }

  Future<void> _exportMp4(List<PoseRecord> records) async {
    await _runExport(
      () => ref
          .read(timelapseExportServiceProvider)
          .exportMp4(
            series: widget.series,
            records: records,
            fps: _resolvedFps,
            exportDirectoryPath: _exportDirectoryPath,
          ),
    );
  }

  Future<void> _exportGif(List<PoseRecord> records) async {
    await _runExport(
      () => ref
          .read(timelapseExportServiceProvider)
          .exportGif(
            series: widget.series,
            records: records,
            fps: _resolvedFps,
            exportDirectoryPath: _exportDirectoryPath,
          ),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Export saved to ${PathFormatter.formatDirectoryLabel(path.dirname(outputPath))}',
          ),
        ),
      );
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
