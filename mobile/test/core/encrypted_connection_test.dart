import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/core/storage/encrypted_connection.dart';
import 'package:reclaim_app/features/onboarding/data/profile_repository.dart';
import 'package:reclaim_app/features/onboarding/domain/onboarding_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

final keyA = 'a' * 64;
final keyB = 'b' * 64;

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dir = Directory.systemTemp.createTempSync('reclaim_db_test');
    file = File(p.join(dir.path, 'reclaim.db'));
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> writeSecret(String key) async {
    final db = AppDatabase(openEncryptedDatabase(file, key));
    await ProfileRepository(db, const Uuid(), DateTime.now).completeOnboarding(
      const OnboardingAnswers(
        frequencyBand: FrequencyBand.daily,
        goal: RecoveryGoalType.stop,
        moneyGoalPreference: 'school fees for Thandi',
      ),
    );
    await db.close();
  }

  test('the database file on disk is not readable as plain SQLite', () async {
    await writeSecret(keyA);

    final bytes = file.readAsBytesSync();
    expect(latin1.decode(bytes.sublist(0, 15)), isNot('SQLite format 3'));
    expect(latin1.decode(bytes).contains('Thandi'), isFalse);
  });

  test('the right key reads the data back', () async {
    await writeSecret(keyA);

    final db = AppDatabase(openEncryptedDatabase(file, keyA));
    final response = await db.select(db.onboardingResponses).getSingle();
    expect(response.moneyGoalPreference, 'school fees for Thandi');
    await db.close();
  });

  test('a wrong key cannot open it', () async {
    await writeSecret(keyA);

    final raw = sqlite3.open(file.path);
    addTearDown(raw.close);
    expect(() => applyEncryptionKey(raw, keyB), throwsA(isA<SqliteException>()));
  });

  test('keys that are not 64 hex characters are refused', () {
    expect(() => openEncryptedDatabase(file, "x'; DROP TABLE"), throwsArgumentError);
    expect(() => openEncryptedDatabase(file, 'A' * 64), throwsArgumentError);
  });
}
