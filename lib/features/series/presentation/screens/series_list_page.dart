import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../data/models/pose_series.dart';
import '../../../capture/presentation/screens/capture_page.dart';
import 'series_detail_page.dart';

class SeriesListPage extends ConsumerWidget {
  const SeriesListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesAsync = ref.watch(seriesListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Picture Progress'),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(seriesListControllerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createSeries(context, ref),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('New series'),
      ),
      body: seriesAsync.when(
        data: (series) {
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
                        'Gym posture timelapse',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Create a pose series for each angle, save one baseline stance, then align every future capture against the onion-skin overlay for cleaner progress comparisons.',
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
                      'No series yet. Start with a baseline like Front Biceps, Side Profile, or Back Double Biceps.',
                    ),
                  ),
                )
              else
                ...series.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SeriesCard(series: item),
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

  Future<void> _createSeries(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final seriesName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create Pose Series'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Series label',
              hintText: 'Front Biceps',
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
              onPressed: () =>
                  Navigator.of(context).pop(nameController.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (!context.mounted || seriesName == null || seriesName.isEmpty) {
      return;
    }

    try {
      final createdSeries = await ref
          .read(seriesListControllerProvider.notifier)
          .createSeries(seriesName);
      if (!context.mounted) {
        return;
      }

      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) =>
              PoseCapturePage(series: createdSeries, isBaselineCapture: true),
        ),
      );

      if (!context.mounted) {
        return;
      }

      ref.invalidate(seriesBaselineProvider(createdSeries.id!));
      ref.invalidate(seriesRecordsProvider(createdSeries.id!));
      await ref.read(seriesListControllerProvider.notifier).refresh();
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _SeriesCard extends ConsumerWidget {
  const _SeriesCard({required this.series});

  final PoseSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => SeriesDetailPage(series: series),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              FutureBuilder<String>(
                future: ref
                    .read(fileStorageServiceProvider)
                    .resolveAbsolutePath(series.thumbnailPath),
                builder: (context, snapshot) {
                  final imagePath = snapshot.data;
                  final hasImage = imagePath != null && imagePath.isNotEmpty;

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      width: 96,
                      height: 128,
                      child: hasImage
                          ? Image.file(File(imagePath), fit: BoxFit.cover)
                          : const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFFBBD8C6),
                                    Color(0xFFE8E1CF),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              child: Icon(
                                Icons.accessibility_new_rounded,
                                size: 34,
                              ),
                            ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Created ${MaterialLocalizations.of(context).formatShortDate(series.createdAt)}',
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(Icons.layers_outlined, size: 18),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Baseline overlay, alignment scoring, and export preview ready.',
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
