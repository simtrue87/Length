// 측정 이력 SQLite DB(drift). measurements 테이블 + CRUD.
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Measurements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get modeLabel => text().withLength(min: 1, max: 64)();
  RealColumn get value => real()();
  TextColumn get kind => text().withDefault(const Constant('distance'))();
  TextColumn get confidence => text().withLength(min: 1, max: 16)();
  TextColumn get note => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(tables: [Measurements])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'length_app'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1: valueMm 컬럼. v2: value(이름 변경) + kind 컬럼 추가.
            // SQLite는 ALTER TABLE RENAME COLUMN 지원(3.25+).
            await customStatement(
              'ALTER TABLE measurements RENAME COLUMN value_mm TO value',
            );
            await m.addColumn(measurements, measurements.kind);
          }
        },
      );

  Future<int> insertMeasurement(MeasurementsCompanion entry) =>
      into(measurements).insert(entry);

  Future<List<Measurement>> listMeasurements() =>
      (select(measurements)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Stream<List<Measurement>> watchMeasurements() =>
      (select(measurements)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<int> deleteMeasurement(int id) =>
      (delete(measurements)..where((t) => t.id.equals(id))).go();
}
