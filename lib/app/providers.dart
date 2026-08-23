import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/timelapse_command_builder.dart';
import '../data/models/pose_record.dart';
import '../data/models/pose_series.dart';
import '../data/repositories/pose_repository.dart';
import '../data/services/database_service.dart';
import '../data/services/file_storage_service.dart';
import '../data/services/timelapse_export_service.dart';

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

final fileStorageServiceProvider = Provider<FileStorageService>((ref) {
  return FileStorageService();
});

final poseRepositoryProvider = Provider<PoseRepository>((ref) {
  return PoseRepository(
    databaseService: ref.watch(databaseServiceProvider),
    fileStorageService: ref.watch(fileStorageServiceProvider),
  );
});

final timelapseCommandBuilderProvider = Provider<TimelapseCommandBuilder>((
  ref,
) {
  return const TimelapseCommandBuilder();
});

final timelapseExportServiceProvider = Provider<TimelapseExportService>((ref) {
  return TimelapseExportService(
    fileStorageService: ref.watch(fileStorageServiceProvider),
    commandBuilder: ref.watch(timelapseCommandBuilderProvider),
  );
});

final seriesListControllerProvider =
    StateNotifierProvider<SeriesListController, AsyncValue<List<PoseSeries>>>((
      ref,
    ) {
      final controller = SeriesListController(ref);
      controller.load();
      return controller;
    });

final seriesRecordsProvider = FutureProvider.family<List<PoseRecord>, int>((
  ref,
  seriesId,
) async {
  return ref.watch(poseRepositoryProvider).fetchRecords(seriesId);
});

final seriesBaselineProvider = FutureProvider.family<PoseRecord?, int>((
  ref,
  seriesId,
) async {
  return ref.watch(poseRepositoryProvider).fetchBaselineRecord(seriesId);
});

class SeriesListController extends StateNotifier<AsyncValue<List<PoseSeries>>> {
  SeriesListController(this._ref) : super(const AsyncValue.loading());

  final Ref _ref;

  Future<void> load() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return _ref.read(poseRepositoryProvider).fetchSeries();
    });
  }

  Future<PoseSeries> createSeries(String name) async {
    final series = await _ref.read(poseRepositoryProvider).createSeries(name);
    await load();
    return series;
  }

  Future<void> refresh() async {
    await load();
  }
}
