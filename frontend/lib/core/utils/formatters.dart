const List<String> _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Cricket over notation: 13 legal balls -> `2.1`.
String formatOvers(int legalBalls) => '${legalBalls ~/ 6}.${legalBalls % 6}';

/// `8 Oct 2026` in the device's local time zone.
String formatDate(DateTime value) {
  final DateTime local = value.toLocal();
  return '${local.day} ${_monthNames[local.month - 1]} ${local.year}';
}

/// `7:05 PM` in the device's local time zone.
String formatTime(DateTime value) {
  final DateTime local = value.toLocal();
  final int hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final String minutes = local.minute.toString().padLeft(2, '0');
  final String suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:$minutes $suffix';
}

/// `8 Oct 2026, 7:05 PM`.
String formatDateAndTime(DateTime value) => '${formatDate(value)}, ${formatTime(value)}';

/// 0.874 -> `87%`.
String formatPercent(double fraction) => '${(fraction * 100).round()}%';

/// One decimal place, e.g. strike rates and economy: 133.333 -> `133.3`.
String formatDecimal(double value) => value.toStringAsFixed(1);

/// `1 run`, `2 runs`.
String pluralize(int count, String singular, {String? plural}) =>
    count == 1 ? '$count $singular' : '$count ${plural ?? '${singular}s'}';
