import 'dart:io';

import 'package:flutter/services.dart';

/// The phone's blocking mechanism. Android: the local DNS VPN in
/// android/app/src/main/kotlin/.../blocker. iOS: the Screen Time scaffold in
/// ios/Runner/AppDelegate.swift, off unless built with RECLAIM_IOS_SCREEN_TIME=true because it
/// hasn't been verified on a device yet (see docs/BLOCKING.md).
abstract interface class BlockerPlatform {
  Future<bool> isSupported();
  Future<bool> isRunning();

  /// Shows the system consent dialog if needed; true once permission is granted.
  Future<bool> requestPermission();
  Future<bool> start();
  Future<void> stop();
  Future<void> setBlocklist(List<String> domains);

  /// Recent blocked lookups, newest last.
  Future<List<BlockedAttempt>> blockedLog();
  Future<void> clearBlockedLog();
  Future<void> openVpnSettings();
}

class BlockedAttempt {
  const BlockedAttempt(this.at, this.domain);
  final DateTime at;
  final String domain;
}

class MethodChannelBlocker implements BlockerPlatform {
  static const _channel = MethodChannel('za.reclaim/blocker');

  static const _iosEnabled = bool.fromEnvironment('RECLAIM_IOS_SCREEN_TIME');

  /// Whether this platform's native side may be used at all.
  bool get _available => Platform.isAndroid || (Platform.isIOS && _iosEnabled);

  @override
  Future<bool> isSupported() async => _available && (await _channel.invokeMethod<bool>('isSupported') ?? false);

  @override
  Future<bool> isRunning() async => _available && (await _channel.invokeMethod<bool>('isRunning') ?? false);

  @override
  Future<bool> requestPermission() async => await _channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<bool> start() async => await _channel.invokeMethod<bool>('start') ?? false;

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  @override
  Future<void> setBlocklist(List<String> domains) async {
    if (_available) await _channel.invokeMethod<void>('setBlocklist', {'domains': domains});
  }

  @override
  Future<List<BlockedAttempt>> blockedLog() async {
    if (!_available) return const [];
    final lines = await _channel.invokeListMethod<String>('blockedLog') ?? const [];
    return [
      for (final line in lines)
        if (line.split('\t') case [final ms, final domain] when int.tryParse(ms) != null)
          BlockedAttempt(DateTime.fromMillisecondsSinceEpoch(int.parse(ms)), domain),
    ];
  }

  @override
  Future<void> clearBlockedLog() async {
    if (_available) await _channel.invokeMethod<void>('clearBlockedLog');
  }

  @override
  Future<void> openVpnSettings() => _channel.invokeMethod<void>('openVpnSettings');
}
