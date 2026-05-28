// in-memory drift로 Repository CRUD + 스키마 v1 검증.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:length/core/persistence/app_database.dart';
import 'package:length/core/persistence/measurement_repository.dart';
import 'package:length/features/result/domain/measurement_result.dart';

void main() {
  late AppDatabase db;
  late MeasurementRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MeasurementRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('스키마 버전 2', () {
    expect(db.schemaVersion, 2);
  });

  test('save → watchAll에서 즉시 노출', () async {
    const result = MeasurementResult(
      kind: MeasureKind.distance,
      value: 85.6,
      modeLabel: '사진 — 신용카드',
      confidence: MeasurementConfidence.medium,
      note: '수동 4점 보정',
    );

    await repo.save(result);
    final items = await repo.watchAll().first;

    expect(items, hasLength(1));
    expect(items.first.result.value, 85.6);
    expect(items.first.result.modeLabel, '사진 — 신용카드');
    expect(items.first.result.confidence, MeasurementConfidence.medium);
    expect(items.first.result.note, '수동 4점 보정');
  });

  test('여러 건 저장 시 createdAt 내림차순', () async {
    await repo.save(_make(10));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await repo.save(_make(20));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await repo.save(_make(30));

    final items = await repo.watchAll().first;
    expect(items.map((e) => e.result.value).toList(), [30, 20, 10]);
  });

  test('delete로 단일 항목 제거', () async {
    final id = await repo.save(_make(1));
    await repo.save(_make(2));

    await repo.delete(id);

    final items = await repo.watchAll().first;
    expect(items, hasLength(1));
    expect(items.first.result.value, 2);
  });

  test('note가 null이어도 저장·복원 가능', () async {
    await repo.save(const MeasurementResult(
      kind: MeasureKind.distance,
      value: 5,
      modeLabel: 'test',
      confidence: MeasurementConfidence.high,
    ));
    final items = await repo.watchAll().first;
    expect(items.first.result.note, isNull);
  });
}

MeasurementResult _make(double mm) => MeasurementResult(
      kind: MeasureKind.distance,
      value: mm,
      modeLabel: 'test',
      confidence: MeasurementConfidence.high,
    );
