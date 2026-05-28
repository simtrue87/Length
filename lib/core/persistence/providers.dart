// 측정 이력 DB·Repository·목록 스트림 Riverpod provider.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'measurement_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final measurementRepositoryProvider = Provider<MeasurementRepository>((ref) {
  return MeasurementRepository(ref.watch(appDatabaseProvider));
});

final measurementsStreamProvider =
    StreamProvider<List<MeasurementEntry>>((ref) {
  return ref.watch(measurementRepositoryProvider).watchAll();
});
