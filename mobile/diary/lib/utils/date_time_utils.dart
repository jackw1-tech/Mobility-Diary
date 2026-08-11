import 'package:intl/intl.dart';

class DateTimeUtils {
  static String formatDate(DateTime date, {String format = 'dd/MM/yyyy'}) {
    final formatter = DateFormat(format);
    return formatter.format(date.toLocal());
  }

  static String formatTime(DateTime time, {String format = 'HH:mm'}) {
    final formatter = DateFormat(format);
    return formatter.format(time.toLocal());
  }

  static String formatDateTime(DateTime dateTime,
      {String format = 'dd/MM/yyyy HH:mm'}) {
    final formatter = DateFormat(format);
    return formatter.format(dateTime.toLocal());
  }

  /// ISO 8601 UTC con precisione al microsecondo (a differenza di
  /// [DateTime.toIso8601String], che si ferma ai millisecondi), usato dai
  /// payload di ingestion. Omette del tutto la parte frazionaria se zero.
  static String toUtcIso(DateTime value) {
    final utc = value.toUtc();
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    final second = utc.second.toString().padLeft(2, '0');
    final fractionMicros = utc.millisecond * 1000 + utc.microsecond;
    final base = '$year-$month-${day}T$hour:$minute:$second';
    if (fractionMicros == 0) return '${base}Z';
    return '$base.${fractionMicros.toString().padLeft(6, '0')}Z';
  }

  static String? toUtcIsoOrNull(DateTime? value) =>
      value == null ? null : toUtcIso(value);
}
