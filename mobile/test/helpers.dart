import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:reclaim_app/app.dart';
import 'package:reclaim_app/core/network/api_client.dart';
import 'package:reclaim_app/core/storage/app_database.dart';
import 'package:reclaim_app/core/storage/secure_store.dart';
import 'package:reclaim_app/core/storage/storage_providers.dart';
import 'package:reclaim_app/features/blocker/data/blocker_platform.dart';
import 'package:reclaim_app/features/blocker/data/blocker_repositories.dart';
import 'package:reclaim_app/features/settings/data/app_lock_repository.dart';

import 'fake_api.dart';

/// A fixed "now": Thursday 29 October 2026, 19:30.
final testNow = DateTime(2026, 10, 29, 19, 30);

/// An unencrypted in-memory database; encryption itself is covered in encrypted_connection_test.
AppDatabase createTestDatabase() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

/// Shared by [testLockRepository] so a test can prepare it before pumping the app.
final testSecureStore = InMemorySecureStore();

/// App-lock storage in memory; cleared each time unless [keep] is set.
AppLockRepository testLockRepository({bool keep = false}) {
  if (!keep) testSecureStore.values.clear();
  return AppLockRepository(testSecureStore, iterations: 1000, useIsolate: false);
}

class FakeBiometrics implements BiometricAuth {
  FakeBiometrics({this.available = false, this.succeeds = true});

  final bool available;
  final bool succeeds;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate() async => available && succeeds;
}

/// Stands in for the Android VPN blocker.
class FakeBlocker implements BlockerPlatform {
  FakeBlocker({this.supported = true, this.grantPermission = true});

  final bool supported;
  bool grantPermission;
  bool running = false;
  List<String> domains = const [];
  final log = <BlockedAttempt>[];

  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<bool> isRunning() async => running;
  @override
  Future<bool> requestPermission() async => grantPermission;
  @override
  Future<bool> start() async => running = grantPermission;
  @override
  Future<void> stop() async => running = false;
  @override
  Future<void> setBlocklist(List<String> domains) async => this.domains = domains;
  @override
  Future<List<BlockedAttempt>> blockedLog() async => log;
  @override
  Future<void> clearBlockedLog() async => log.clear();
  @override
  Future<void> openVpnSettings() async {}
}

/// [clock] lets a test move time forward (e.g. to finish a pause); defaults to [testNow].
/// Pass [keepSecureStorage] to start with secure storage a test has already prepared.
/// [apiClient] swaps the HTTP client (see fake_api.dart); by default nothing reaches a network.
Future<void> pumpApp(
  WidgetTester tester,
  AppDatabase db, {
  DateTime Function()? clock,
  bool keepSecureStorage = false,
  Dio Function(SecureStore store)? apiClient,
  FakeBlocker? blocker,
}) async {
  // A typical phone screen (411 x 914 logical pixels) rather than the 800 x 600 test default.
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock ?? () => testNow),
        secureStoreProvider.overrideWithValue(testSecureStore),
        apiClientProvider.overrideWithValue((apiClient ?? (store) => fakeDio(FakeApi(), TokenStore(store)))(testSecureStore)),
        appLockRepositoryProvider.overrideWithValue(testLockRepository(keep: keepSecureStorage)),
        biometricAuthProvider.overrideWithValue(FakeBiometrics()),
        blockerPlatformProvider.overrideWithValue(blocker ?? FakeBlocker()),
        // Asset loading does real I/O that widget tests' fake clock never finishes; read it directly.
        blocklistSeedLoaderProvider.overrideWithValue(() async => File('assets/blocklist-seed.txt').readAsStringSync()),
      ],
      child: const ReclaimApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// The vertical list on the screen in front, not one on a route underneath or a horizontal row of chips.
final _mainList = find
    .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
    .hitTestable()
    .first;

extension Taps on WidgetTester {
  /// Scrolls [finder] into view if needed, then taps it and lets the UI settle.
  Future<void> tapText(String text) => _revealAndTap(find.text(text));

  /// Taps any Material button (filled, outlined, text) labelled [text].
  Future<void> tapButton(String text) =>
      _revealAndTap(find.ancestor(of: find.text(text), matching: find.bySubtype<ButtonStyleButton>()));

  /// Taps any widget (scrolling to it first) and lets the work it starts finish.
  Future<void> tapOn(Finder finder) => _revealAndTap(finder);

  /// Lists build lazily, so a target below the fold may not exist until scrolled to.
  Future<void> _revealAndTap(Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await scrollUntilVisible(finder, 200, scrollable: _mainList);
    }
    await ensureVisible(finder.first);
    await pumpAndSettle();
    // ensureVisible can stop with the target just past the edge of the screen; nudge until tappable.
    for (var i = 0; i < 5 && finder.hitTestable().evaluate().isEmpty; i++) {
      await drag(_mainList, const Offset(0, -150));
      await pumpAndSettle();
    }
    await tap(finder.hitTestable().first);
    // A tap that might be the first half of a double tap only resolves once the double-tap
    // window passes; advance fake time past it so the tap always lands before the next step.
    await pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
    await pumpAndSettle();
  }

  /// Scrolls the screen's list (down, then up) until [finder] is built, and returns it.
  Future<Finder> reveal(Finder finder) async {
    if (finder.evaluate().isNotEmpty) return finder;
    final list = _mainList;
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
