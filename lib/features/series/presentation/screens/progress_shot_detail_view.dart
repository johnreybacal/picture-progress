import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/widgets/pose_thumbnail.dart';
import '../../../../data/models/pose_record.dart';
import '../../../../data/models/pose_record_update.dart';
import '../../../../data/models/pose_series.dart';

class ProgressShotDetailView extends ConsumerStatefulWidget {
  const ProgressShotDetailView({
    super.key,
    required this.series,
    required this.record,
  });

  final PoseSeries series;
  final PoseRecord record;

  @override
  ConsumerState<ProgressShotDetailView> createState() =>
      _ProgressShotDetailViewState();
}

class _ProgressShotDetailViewState
    extends ConsumerState<ProgressShotDetailView> {
  late final TextEditingController _labelController;
  late DateTime _selectedTimestamp;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.record.label);
    _selectedTimestamp = widget.record.timestamp;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress photo')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AspectRatio(
              aspectRatio: widget.record.displayAspectRatio,
              child: PoseThumbnail(
                record: widget.record,
                borderRadius: BorderRadius.circular(24),
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Photo details',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _labelController,
                      decoration: const InputDecoration(
                        labelText: 'Photo note',
                        hintText: 'Week 8 check-in',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: const Text('Capture date'),
                      subtitle: Text(
                        MaterialLocalizations.of(context)
                            .formatFullDate(_selectedTimestamp),
                      ),
                      onTap: _pickDate,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_rounded),
                      title: const Text('Capture time'),
                      subtitle: Text(
                        MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(_selectedTimestamp),
                        ),
                      ),
                      onTap: _pickTime,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            widget.record.cameraLens == 'front'
                                ? 'Front camera'
                                : 'Rear camera',
                          ),
                        ),
                        Chip(
                          label: Text(
                            widget.record.captureOrientation.storageValue
                                .replaceAll('Left', ' left')
                                .replaceAll('Right', ' right'),
                          ),
                        ),
                        Chip(
                          label: Text(
                            '${widget.record.landmarks.length} alignment markers',
                          ),
                        ),
                        if (widget.record.isReference)
                          const Chip(label: Text('Baseline photo')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _saveMetadata,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Save details'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saving ? null : _deleteRecord,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete photo'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _selectedTimestamp,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selectedDate == null || !mounted) {
      return;
    }

    final time = TimeOfDay.fromDateTime(_selectedTimestamp);
    setState(() {
      _selectedTimestamp = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedTimestamp),
    );
    if (selectedTime == null || !mounted) {
      return;
    }

    setState(() {
      _selectedTimestamp = DateTime(
        _selectedTimestamp.year,
        _selectedTimestamp.month,
        _selectedTimestamp.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  Future<void> _saveMetadata() async {
    setState(() {
      _saving = true;
    });
    try {
      await ref
          .read(poseRepositoryProvider)
          .updateRecordMetadata(
            widget.record.id!,
            PoseRecordUpdate(
              label: _labelController.text.trim(),
              timestamp: _selectedTimestamp,
            ),
          );
      ref.invalidate(seriesRecordsProvider(widget.series.id!));
      ref.invalidate(seriesBaselineProvider(widget.series.id!));
      await ref.read(seriesListControllerProvider.notifier).refresh();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _deleteRecord() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text(
          'This removes the stored image and metadata for this progress photo.',
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

    setState(() {
      _saving = true;
    });
    try {
      await ref.read(poseRepositoryProvider).deleteRecord(widget.record);
      ref.invalidate(seriesRecordsProvider(widget.series.id!));
      ref.invalidate(seriesBaselineProvider(widget.series.id!));
      await ref.read(seriesListControllerProvider.notifier).refresh();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}
