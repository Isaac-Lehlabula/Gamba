import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/storage_providers.dart';
import '../data/blocker_platform.dart';
import '../data/blocker_repositories.dart';

part 'blocker_controller.g.dart';

class BlockerState {
  const BlockerState({required this.supported, required this.running, this.recentAttempts = const []});

  final bool supported;
  final bool running;

  /// Blocked lookups in the last 7 days, newest first.
  final List<BlockedAttempt> recentAttempts;
}

enum DisableResult { stopped, locked }

@Riverpod(keepAlive: true)
class Blocker extends _$Blocker {
  BlockerPlatform get _platform => ref.read(blockerPlatformProvider);
  BlocklistRepository get _blocklist => ref.read(blocklistRepositoryProvider);

  @override
  Future<BlockerState> build() async {
    final supported = await _platform.isSupported();
    if (supported) {
      await _blocklist.ensureSeeded();
      await pushBlocklist();
    }
    return _read(supported);
  }

  Future<BlockerState> _read(bool supported) async {
    if (!supported) return const BlockerState(supported: false, running: false);
    final weekAgo = ref.read(clockProvider)().subtract(const Duration(days: 7));
    final attempts = (await _platform.blockedLog()).where((a) => a.at.isAfter(weekAgo)).toList().reversed.toList();
    return BlockerState(supported: true, running: await _platform.isRunning(), recentAttempts: attempts);
  }

  /// Re-reads whether protection is running and what it has blocked. Does nothing until the
  /// first load has finished, so it can't briefly report the platform as unsupported.
  Future<void> refresh() async {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(await _read(current.supported));
  }

  /// Sends the current list to the running service.
  Future<void> pushBlocklist() async => _platform.setBlocklist(await _blocklist.activeDomains());

  /// Asks for the VPN permission if needed, then starts protection. False if the user declined.
  Future<bool> enable() async {
    if (!await _platform.requestPermission()) return false;
    await pushBlocklist();
    final started = await _platform.start();
    await refresh();
    return started;
  }

  /// Turns protection off, unless a protection lock is in force.
  Future<DisableResult> disable() async {
    if (await ref.read(protectionRepositoryProvider).isLocked()) return DisableResult.locked;
    await _platform.stop();
    await refresh();
    return DisableResult.stopped;
  }

  /// Fetches blocklist changes and applies them. Failures are quiet: the existing list stays.
  Future<bool> syncBlocklist() async {
    try {
      await _blocklist.syncFromServer();
      await pushBlocklist();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> addCustomDomain(String input) async {
    final domain = await _blocklist.addCustom(input);
    if (domain != null) await pushBlocklist();
    return domain;
  }

  /// False while a protection lock is in force.
  Future<bool> removeCustomDomain(String domain) async {
    if (await ref.read(protectionRepositoryProvider).isLocked()) return false;
    await _blocklist.removeCustom(domain);
    await pushBlocklist();
    return true;
  }
}
