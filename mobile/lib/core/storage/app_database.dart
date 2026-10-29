import 'package:drift/drift.dart';

import '../../features/assessment/domain/questionnaire.dart';
import '../../features/onboarding/domain/onboarding_models.dart';
import '../../features/tracker/domain/money.dart';
import '../../features/urges/domain/urge_models.dart';
import 'app_database.drift.dart';
import 'enum_converters.dart';

// Local mirror of the backend schema (docs/DATABASE.md). Ids are client-generated UUIDs so a
// record keeps its identity when it is later synced to an account.

/// The single on-device profile. Exists from the end of onboarding; no account needed.
class LocalProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get recoveryGoalType => textEnum<RecoveryGoalType>().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get onboardingCompletedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class GamblingTypeListConverter extends EnumListConverter<GamblingType> {
  const GamblingTypeListConverter();
  @override
  List<GamblingType> get values => GamblingType.values;
}

class TriggerTypeListConverter extends EnumListConverter<TriggerType> {
  const TriggerTypeListConverter();
  @override
  List<TriggerType> get values => TriggerType.values;
}

class OnboardingResponses extends Table {
  TextColumn get id => text()();
  TextColumn get gamblingTypes => text().map(const GamblingTypeListConverter())();
  TextColumn get frequencyBand => textEnum<FrequencyBand>()();
  IntColumn get approxMonthlySpendRands => integer().nullable()();
  TextColumn get triggers => text().map(const TriggerTypeListConverter())();
  TextColumn get goal => textEnum<RecoveryGoalType>()();
  TextColumn get moneyGoalPreference => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SelfAssessmentResults extends Table {
  TextColumn get id => text()();
  IntColumn get questionnaireVersion => integer()();
  TextColumn get answers => text().map(const IntMapConverter())();
  IntColumn get score => integer()();
  TextColumn get riskLevel => textEnum<RiskLevel>()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A self-reported money movement or outcome. Amounts are whole cents to avoid float error.
class GamblingEntries extends Table {
  TextColumn get id => text()();
  TextColumn get entryType => textEnum<GamblingEntryType>()();
  IntColumn get amountCents => integer()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get gamblingType => textEnum<GamblingType>()();
  TextColumn get platformName => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One "I feel like gambling" session: what triggered it, the pause chosen, and how it ended.
class Urges extends Table {
  TextColumn get id => text()();
  TextColumn get trigger => textEnum<TriggerType>()();

  /// 1 (mild) to 5 (very strong); optional.
  IntColumn get intensity => integer().nullable()();

  /// Can grow if the user asks for more time.
  IntColumn get coolingOffMinutes => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  TextColumn get outcome => textEnum<UrgeOutcome>().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [LocalProfiles, OnboardingResponses, SelfAssessmentResults, GamblingEntries, Urges])
class AppDatabase extends $AppDatabase {
  AppDatabase(super.executor);

  static final _entriesByDate = Index('gambling_entries_occurred_at', 'CREATE INDEX gambling_entries_occurred_at ON gambling_entries (occurred_at)');

  /// 1: profile, onboarding, self-assessment. 2: gambling entries. 3: urges.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(gamblingEntries);
            await m.createIndex(_entriesByDate);
          }
          if (from < 3) {
            await m.createTable(urges);
          }
        },
        onCreate: (m) async {
          await m.createAll();
          await m.createIndex(_entriesByDate);
        },
      );
}
