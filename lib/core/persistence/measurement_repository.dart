// 측정 이력 Repository. DB 접근을 도메인 모델(MeasurementResult)로 감싼다.
import 'package:drift/drift.dart';

import '../../features/result/domain/measurement_result.dart';
import 'app_database.dart';

class MeasurementRepository {
  MeasurementRepository(this._db);
  final AppDatabase _db;

  Future<int> save(MeasurementResult r) {
    return _db.insertMeasurement(
      MeasurementsCompanion(
        modeLabel: Value(r.modeLabel),
        value: Value(r.value),
        kind: Value(r.kind.name),
        confidence: Value(r.confidence.name),
        note: Value(r.note),
        imagePath: Value(r.imagePath),
        createdAt: Value(DateTime.now()),
      ),
    );
  }

  Stream<List<MeasurementEntry>> watchAll() {
    return _db.watchMeasurements().map(
          (rows) => rows.map(_toEntry).toList(),
        );
  }

  Future<void> delete(int id) => _db.deleteMeasurement(id).then((_) {});

  MeasurementEntry _toEntry(Measurement row) {
    return MeasurementEntry(
      id: row.id,
      result: MeasurementResult(
        kind: MeasureKind.values.firstWhere(
          (k) => k.name == row.kind,
          orElse: () => MeasureKind.distance,
        ),
        value: row.value,
        modeLabel: row.modeLabel,
        confidence: MeasurementConfidence.values
            .firstWhere((c) => c.name == row.confidence),
        note: row.note,
        imagePath: row.imagePath,
      ),
      imagePath: row.imagePath,
      createdAt: row.createdAt,
    );
  }
}

class MeasurementEntry {
  const MeasurementEntry({
    required this.id,
    required this.result,
    required this.createdAt,
    this.imagePath,
  });
  final int id;
  final MeasurementResult result;
  final DateTime createdAt;
  final String? imagePath;
}
