/// Money is kept in integer sen (1 RM = 100 sen) so splits add up exactly.
library;

final RegExp _amount = RegExp(r'^(\d{1,7})(?:\.(\d{1,2}))?$');

/// "RM 1,234.50" (negative amounts get a leading minus).
String formatRm(int sen) {
  final sign = sen < 0 ? '-' : '';
  final abs = sen.abs();
  final ringgit = (abs ~/ 100).toString();
  final grouped = ringgit.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final cents = (abs % 100).toString().padLeft(2, '0');
  return '${sign}RM $grouped.$cents';
}

/// Parses "12", "12.5", "RM 1,200.00" into sen. Returns null for anything else
/// (negative, more than two decimals, empty, or over RM 9,999,999.99).
int? parseRm(String input) {
  final cleaned = input
      .trim()
      .replaceFirst(RegExp(r'^RM\s*', caseSensitive: false), '')
      .replaceAll(',', '');
  final match = _amount.firstMatch(cleaned);
  if (match == null) return null;
  final ringgit = int.parse(match.group(1)!);
  final cents = int.parse((match.group(2) ?? '0').padRight(2, '0'));
  return ringgit * 100 + cents;
}
