import 'package:drift/drift.dart';

import '../../features/assessment/domain/questionnaire.dart';
import '../../features/blocker/domain/blocker_models.dart';
import '../../features/goals/domain/goal_models.dart';
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

/// Something the user is putting money toward instead of gambling.
class RecoveryGoals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => textEnum<GoalCategory>()();
  IntColumn get targetCents => integer()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Money counted toward a goal: set aside by the user, or moved from the estimated savings.
class GoalContributions extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text().references(RecoveryGoals, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountCents => integer()();
  TextColumn get source => textEnum<ContributionSource>()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Domains the blocker refuses to resolve: the starter list, the server list and the user's own.
class BlockedDomains extends Table {
  TextColumn get domain => text()();
  TextColumn get source => textEnum<BlockedDomainSource>()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {domain};
}

/// A commitment not to turn protection off for a set time (see ProtectionRules).
class ProtectionLocks extends Table {
  TextColumn get id => text()();
  IntColumn get durationDays => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime()();
  TextColumn get status => textEnum<ProtectionLockStatus>()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Asking to end a lock early starts a cooling-off period instead of ending it at once.
class ProtectionRemovalRequests extends Table {
  TextColumn get id => text()();
  TextColumn get lockId => text().references(ProtectionLocks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get requestedAt => dateTime()();
  DateTimeColumn get coolingOffEndsAt => dateTime()();
  TextColumn get status => textEnum<RemovalRequestStatus>()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Small non-secret values, such as the blocklist sync cursor.
class LocalSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    LocalProfiles,
    OnboardingResponses,
    SelfAssessmentResults,
    GamblingEntries,
    Urges,
    RecoveryGoals,
    GoalContributions,
    BlockedDomains,
    ProtectionLocks,
    ProtectionRemovalRequests,
    LocalSettings,
  ],
)
class AppDatabase extends $AppDatabase {
  AppDatabase(super.executor);

  static final _entriesByDate = Index('gambling_entries_occurred_at', 'CREATE INDEX gambling_entries_occurred_at ON gambling_entries (occurred_at)');

  /// 1: profile, onboarding, self-assessment. 2: gambling entries. 3: urges. 4: goals.
  /// 5: blocker (domains, protection lock, settings).
  @override
  int get schemaVersion => 5;

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
          if (from < 4) {
            await m.createTable(recoveryGoals);
            await m.createTable(goalContributions);
          }
          if (from < 5) {
            await m.createTable(blockedDomains);
            await m.createTable(protectionLocks);
            await m.createTable(protectionRemovalRequests);
            await m.createTable(localSettings);
          }
        },
        onCreate: (m) async {
          await m.createAll();
          await m.createIndex(_entriesByDate);
        },
        // SQLite leaves foreign keys off by default; deleting a goal relies on the cascade.
        beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
      );
}
