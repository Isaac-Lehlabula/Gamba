import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/storage_providers.dart';
import '../data/app_lock_repository.dart';

part 'app_lock_controller.g.dart';

class AppLockState {
  const AppLockState({
    required this.enabled,
    required this.locked,
    this.biometrics = false,
    this.failedAttempts = 0,
    this.lockedOutUntil,
  });

  final bool enabled;
  final bool locked;
  final bool biometrics;
  final int failedAttempts;

  /// Set after too many wrong PINs; no attempts are accepted before this time.
  final DateTime? lockedOutUntil;

  AppLockState copyWith({bool? enabled, bool? locked, bool? biometrics, int? failedAttempts, DateTime? Function()? lockedOutUntil}) =>
      AppLockState(
        enabled: enabled ?? this.enabled,
        locked: locked ?? this.locked,
        biometrics: biometrics ?? this.biometrics,
        failedAttempts: failedAttempts ?? this.failedAttempts,
        lockedOutUntil: lockedOutUntil != null ? lockedOutUntil() : this.lockedOutUntil,
      );
}

enum UnlockResult { unlocked, wrongPin, lockedOut }

/// Whether the app is locked. Locks at launch, and again when returning after more than
/// [backgroundGrace] away, so a borrowed or shared phone doesn't show the app.
@Riverpod(keepAlive: true)
class AppLock extends _$AppLock {
  static const backgroundGrace = Duration(seconds: 30);
  static const maxAttempts = 5;
  static const lockout = Duration(seconds: 30);

  DateTime? _backgroundedAt;

  AppLockRepository get _repo => ref.read(appLockRepositoryProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  Future<AppLockState> build() async {
    final enabled = await _repo.isEnabled();
    return AppLockState(enabled: enabled, locked: enabled, biometrics: enabled && await _repo.biometricsEnabled());
  }

  AppLockState? get _current => state.value;

  Future<UnlockResult> unlockWithPin(String pin) async {
    final s = _current!;
    if (s.lockedOutUntil case final until? when _now().isBefore(until)) return UnlockResult.lockedOut;

    if (await _repo.verify(pin)) {
      state = AsyncData(s.copyWith(locked: false, failedAttempts: 0, lockedOutUntil: () => null));
      return UnlockResult.unlocked;
    }
    final attempts = s.failedAttempts + 1;
    final lockedOut = attempts >= maxAttempts;
    state = AsyncData(s.copyWith(
      failedAttempts: lockedOut ? 0 : attempts,
      lockedOutUntil: () => lockedOut ? _now().add(lockout) : null,
    ));
    return lockedOut ? UnlockResult.lockedOut : UnlockResult.wrongPin;
  }

  Future<bool> unlockWithBiometrics() async {
    final s = _current!;
    if (!s.biometrics || !await ref.read(biometricAuthProvider).authenticate()) return false;
    state = AsyncData(s.copyWith(locked: false, failedAttempts: 0, lockedOutUntil: () => null));
    return true;
  }

  Future<void> enable(String pin, {required bool biometrics}) async {
    await _repo.enable(pin, biometrics: biometrics);
    state = AsyncData(AppLockState(enabled: true, locked: false, biometrics: biometrics));
  }

  Future<void> setBiometrics(bool enabled) async {
    await _repo.setBiometrics(enabled);
    state = AsyncData(_current!.copyWith(biometrics: enabled));
  }

  Future<void> disable() async {
    await _repo.disable();
    state = const AsyncData(AppLockState(enabled: false, locked: false));
  }

  void onBackgrounded() => _backgroundedAt = _now();

  void onForegrounded() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    final s = _current;
    if (s == null || !s.enabled || s.locked || since == null) return;
    if (_now().difference(since) > backgroundGrace) state = AsyncData(s.copyWith(locked: true));
  }
}
