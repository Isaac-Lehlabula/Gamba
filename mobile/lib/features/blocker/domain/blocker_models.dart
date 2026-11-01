/// Where a blocked domain came from.
enum BlockedDomainSource {
  /// The starter list bundled with the app.
  seed,

  /// The shared list from Reclaim's servers.
  server,

  /// Added by the user.
  custom,
}

enum ProtectionLockStatus { active, ended }

enum RemovalRequestStatus { pending, cancelled, completed }

abstract final class ProtectionRules {
  /// Lock lengths offered, in days.
  static const durations = [1, 7, 30, 90, 180, 365];

  /// How long a request to remove the lock waits before it can be confirmed.
  static const coolingOff = Duration(hours: 24);
}

/// Domains typed by a user: lower case, no scheme, path or leading "www.".
/// Returns null when [input] isn't a usable domain.
String? normalizeDomain(String input) {
  var d = input.trim().toLowerCase();
  final scheme = d.indexOf('://');
  if (scheme >= 0) d = d.substring(scheme + 3);
  final end = d.indexOf(RegExp(r'[/?#:]'));
  if (end >= 0) d = d.substring(0, end);
  while (d.endsWith('.')) {
    d = d.substring(0, d.length - 1);
  }
  if (d.startsWith('www.')) d = d.substring(4);

  final label = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$');
  final labels = d.split('.');
  if (d.length > 253 || labels.length < 2 || !labels.every(label.hasMatch)) return null;
  return d;
}

/// Parses the bundled seed file: "`domain` `Category`" per line, with # comments.
List<String> parseSeedDomains(String text) => [
      for (final line in text.split('\n'))
        if (line.trim() case final t when t.isNotEmpty && !t.startsWith('#')) t.split(RegExp(r'\s+')).first.toLowerCase(),
    ];
