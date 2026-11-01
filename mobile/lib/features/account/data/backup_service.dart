import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/storage/storage_providers.dart';
import 'account_repository.dart';

part 'backup_service.g.dart';

class BackupResult {
  const BackupResult({required this.created, required this.updated, required this.skipped});

  final int created;
  final int updated;
  final int skipped;
}

/// "Back up my data": sends everything stored on the phone to the account in one request.
/// The server matches records on their ids, so running it again updates rather than duplicates.
class BackupService {
  BackupService(this._db, this._dio, this._store, this._now);

  static const _lastBackupKey = 'reclaim.backup.last.v1';

  final AppDatabase _db;
  final Dio _dio;
  final SecureStore _store;
  final DateTime Function() _now;

  Future<DateTime?> lastBackupAt() async => DateTime.tryParse(await _store.read(_lastBackupKey) ?? '');

  Future<BackupResult> backUp() async {
    final payload = await buildPayload();
    try {
      final response = await _dio.post<Map<String, dynamic>>('/api/v1/backup', data: payload);
      final body = response.data!;
      await _store.write(_lastBackupKey, _now().toUtc().toIso8601String());
      return BackupResult(
        created: body['created'] as int,
        updated: body['updated'] as int,
        skipped: body['skipped'] as int,
      );
    } on DioException catch (e) {
      if (e.error is SignedOutException) throw const AccountException('Please sign in again to back up.');
      throw const AccountException("The backup didn't go through. Check your connection and try again.");
    }
  }

  /// The request body, in the backend's shapes (see Reclaim.Application/Backup).
  Future<Map<String, Object?>> buildPayload() async {
    final profile = await _db.select(_db.localProfiles).getSingleOrNull();
    final onboarding = await _db.select(_db.onboardingResponses).get();
    final assessments = await _db.select(_db.selfAssessmentResults).get();
    final entries = await _db.select(_db.gamblingEntries).get();
    final urges = await _db.select(_db.urges).get();
    final goals = await _db.select(_db.recoveryGoals).get();
    final contributions = await _db.select(_db.goalContributions).get();
    final journal = await _db.select(_db.journalEntries).get();

    return {
      'profile': profile == null
          ? null
          : {
              'recoveryGoalType': _enum(profile.recoveryGoalType),
              'quitOrReductionStartDateUtc': _utc(profile.startDate),
            },
      'onboardingResponses': [
        for (final r in onboarding)
          {
            'id': r.id,
            'gamblingTypes': [for (final t in r.gamblingTypes) _enum(t)],
            'frequencyBand': _enum(r.frequencyBand),
            'approxMonthlySpend': r.approxMonthlySpendRands,
            'triggers': [for (final t in r.triggers) _enum(t)],
            'goal': _enum(r.goal),
            'moneyGoalPreference': r.moneyGoalPreference,
          },
      ],
      'assessments': [
        for (final a in assessments) {'id': a.id, 'answers': a.answers, 'createdAtUtc': _utc(a.createdAt)},
      ],
      'entries': [
        for (final e in entries)
          {
            'id': e.id,
            'entryType': _enum(e.entryType),
            'amount': _rands(e.amountCents),
            'occurredAtUtc': _utc(e.occurredAt),
            'gamblingType': _enum(e.gamblingType),
            'platformName': e.platformName,
            'notes': e.notes,
          },
      ],
      'urges': [
        for (final u in urges)
          {
            'id': u.id,
            'trigger': _enum(u.trigger),
            'intensity': u.intensity,
            'coolingOffMinutes': u.coolingOffMinutes,
            'startedAtUtc': _utc(u.startedAt),
            'outcome': _enum(u.outcome),
            'resolvedAtUtc': _utc(u.resolvedAt),
            'notes': u.notes,
          },
      ],
      'goals': [
        for (final g in goals)
          {
            'id': g.id,
            'name': g.name,
            'category': _enum(g.category),
            'targetAmount': _rands(g.targetCents),
            'targetDateUtc': _utc(g.targetDate),
            'contributions': [
              for (final c in contributions)
                if (c.goalId == g.id)
                  {'id': c.id, 'amount': _rands(c.amountCents), 'source': _enum(c.source), 'occurredAtUtc': _utc(c.occurredAt)},
            ],
          },
      ],
      'journalEntries': [
        for (final j in journal)
          {
            'id': j.id,
            'occurredAtUtc': _utc(j.occurredAt),
            'mood': j.mood,
            'trigger': _enum(j.trigger),
            'urgeIntensity': j.urgeIntensity,
            'outcome': _enum(j.outcome),
            'helped': [for (final h in j.helped) _enum(h)],
            'note': j.note,
          },
      ],
    };
  }

  /// Dart enums are camelCase; the API's are PascalCase.
  static String? _enum(Enum? value) =>
      value == null ? null : value.name[0].toUpperCase() + value.name.substring(1);

  static String? _utc(DateTime? value) => value?.toUtc().toIso8601String();

  /// Cents to a rand amount with exactly two decimals.
  static num _rands(int cents) => num.parse((cents / 100).toStringAsFixed(2));
}

@riverpod
BackupService backupService(Ref ref) => BackupService(
      ref.watch(appDatabaseProvider),
      ref.watch(apiClientProvider),
      ref.watch(secureStoreProvider),
      ref.watch(clockProvider),
    );

@riverpod
Future<DateTime?> lastBackupAt(Ref ref) => ref.watch(backupServiceProvider).lastBackupAt();
