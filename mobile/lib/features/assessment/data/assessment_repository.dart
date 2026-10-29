import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/app_database.drift.dart';
import '../../../core/storage/storage_providers.dart';
import '../domain/questionnaire.dart';

part 'assessment_repository.g.dart';

class AssessmentRepository {
  AssessmentRepository(this._db, this._uuid, this._now);

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _now;

  /// Scores the answers and stores the result. Past results are kept, never overwritten.
  Future<SelfAssessmentResult> submit(Map<String, int> answers) async {
    final score = Questionnaire.score(answers);
    final result = SelfAssessmentResult(
      id: _uuid.v4(),
      questionnaireVersion: Questionnaire.version,
      answers: Map.unmodifiable(answers),
      score: score,
      riskLevel: Questionnaire.riskLevelFor(score),
      createdAt: _now(),
    );
    await _db.into(_db.selfAssessmentResults).insert(result);
    return result;
  }

  Stream<List<SelfAssessmentResult>> watchHistory() =>
      (_db.select(_db.selfAssessmentResults)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  Future<SelfAssessmentResult?> find(String id) =>
      (_db.select(_db.selfAssessmentResults)..where((t) => t.id.equals(id))).getSingleOrNull();
}

@Riverpod(keepAlive: true)
AssessmentRepository assessmentRepository(Ref ref) =>
    AssessmentRepository(ref.watch(appDatabaseProvider), ref.watch(uuidProvider), ref.watch(clockProvider));

@riverpod
Stream<List<SelfAssessmentResult>> assessmentHistory(Ref ref) => ref.watch(assessmentRepositoryProvider).watchHistory();

@riverpod
Future<SelfAssessmentResult?> assessmentResult(Ref ref, String id) => ref.watch(assessmentRepositoryProvider).find(id);
