import 'package:intl/intl.dart';

abstract final class AppFormatters {
  static final _currency = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: r'R$',
    decimalDigits: 2,
  );
  static final _date = DateFormat('dd/MM/yyyy');
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm');

  static String currency(double value) => _currency.format(value);
  static String date(DateTime value) => _date.format(value);

  /// Data e hora no formato brasileiro (`20/09/2026 18:30`).
  static String dateTime(DateTime value) => _dateTime.format(value.toLocal());

  /// Parses a money amount typed, pasted or produced by
  /// `CurrencyInputFormatter` (`R$ 1.234,56` -> 1234.56).
  ///
  /// - A comma is always the decimal separator and dots are thousands
  ///   separators (`1.234,56`, `1,5`).
  /// - Without a comma, a dot is a decimal separator only when at most 2 digits
  ///   follow the last dot (`12.50` -> 12.5, `10.5` -> 10.5); otherwise dots are
  ///   thousands separators (`1.250` -> 1250).
  /// - A leading minus makes the value negative (`-R$ 100,00`).
  ///
  /// Returns null for empty or invalid input.
  static double? parseCurrency(String input) {
    var text = input.replaceAll(RegExp(r'[^\d,.-]'), '');
    final negative = text.startsWith('-');
    if (negative) text = text.substring(1);
    if (text.isEmpty || text.contains('-') || !text.contains(RegExp(r'\d'))) {
      return null;
    }

    String integer;
    String fraction;
    if (text.contains(',')) {
      final parts = text.split(',');
      if (parts.length != 2 || parts[1].contains('.')) return null;
      integer = parts[0].replaceAll('.', '');
      fraction = parts[1];
    } else {
      final lastDot = text.lastIndexOf('.');
      if (lastDot != -1 && text.length - lastDot - 1 <= 2) {
        integer = text.substring(0, lastDot).replaceAll('.', '');
        fraction = text.substring(lastDot + 1);
      } else {
        integer = text.replaceAll('.', '');
        fraction = '';
      }
    }

    final value = double.tryParse(
      '${integer.isEmpty ? '0' : integer}.${fraction.isEmpty ? '0' : fraction}',
    );
    if (value == null) return null;
    return negative && value != 0 ? -value : value;
  }
}
