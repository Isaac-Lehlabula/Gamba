import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reclaim_app/app.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/core/storage/storage_providers.dart';

/// A fixed "now": Thursday 29 October 2026, 19:30.
final testNow = DateTime(2026, 10, 29, 19, 30);

/// An unencrypted in-memory database; encryption itself is covered in encrypted_connection_test.
AppDatabase createTestDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// [clock] lets a test move time forward (e.g. to finish a pause); defaults to [testNow].
Future<void> pumpApp(WidgetTester tester, AppDatabase db, {DateTime Function()? clock}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock ?? () => testNow),
      ],
      child: const ReclaimApp(),
    ),
  );
  await tester.pumpAndSettle();
}

extension Taps on WidgetTester {
  /// Scrolls [finder] into view if needed, then taps it and lets the UI settle.
  Future<void> tapText(String text) => _revealAndTap(find.text(text));

  /// Taps any Material button (filled, outlined, text) labelled [text].
  Future<void> tapButton(String text) =>
      _revealAndTap(find.ancestor(of: find.text(text), matching: find.bySubtype<ButtonStyleButton>()));

  /// Lists build lazily, so a target below the fold may not exist until scrolled to.
  Future<void> _revealAndTap(Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
    }
    await ensureVisible(finder.first);
    await tap(finder.first);
    await pumpAndSettle();
  }

  /// Scrolls the screen's list (down, then up) until [finder] is built, and returns it.
  Future<Finder> reveal(Finder finder) async {
    if (finder.evaluate().isNotEmpty) return finder;
    final list = find.byType(Scrollable).first;
    try {
      await scrollUntilVisible(finder, 200, scrollable: list, maxScrolls: 20);
    } on StateError {
      await scrollUntilVisible(finder, -200, scrollable: list, maxScrolls: 20);
    }
    return finder;
  }

  /// Unmounts the app so Drift can close its stream queries before the test ends;
  /// otherwise their cleanup timer is reported as pending.
  Future<void> disposeApp() async {
    await pumpWidget(const SizedBox());
    await pump(Duration.zero);
  }
}
