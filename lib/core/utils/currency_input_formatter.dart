import 'package:flutter/services.dart';

import 'formatters.dart';

/// Formats a money field while the user types ("sliding cents").
///
/// Only digits are considered: they fill the value from the right, in cents,
/// and the text is rendered with the app currency format (`R$ 12,50`). The
/// text this produces is understood by [AppFormatters.parseCurrency].
///
/// - Typing `1`, `2`, `5`, `0` shows `R$ 0,01`, `R$ 0,12`, `R$ 1,25`,
///   `R$ 12,50`.
/// - Backspace removes the last digit; removing every digit empties the field.
/// - Pasted text contributes only its digits.
/// - At most [maxDigits] digits are kept (the extra ones are ignored).
/// - The cursor is always kept at the end of the text.
///
/// The formatter has no sign: fields that accept negative values keep the sign
/// apart (see the account form) and apply it after parsing.
class CurrencyInputFormatter extends TextInputFormatter {
  const CurrencyInputFormatter();

  /// 11 digits: up to R$ 999.999.999,99.
  static const maxDigits = 11;

  /// Formats [value] to pre-fill a field, e.g. `1234.56` -> `R$ 1.234,56`.
  ///
  /// Uses the magnitude of [value]: the field has no sign.
  static String format(double value) => _fromCents((value.abs() * 100).round());

  static const _empty = TextEditingValue(
    selection: TextSelection.collapsed(offset: 0),
  );

  static String _fromCents(int cents) => AppFormatters.currency(cents / 100);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return _empty;

    // Leading zeros carry no value and must not use up the digit limit.
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);
    final cents = digits.isEmpty ? 0 : int.parse(digits);

    // An explicit zero (typed `0`) is shown as a zero amount, but deleting
    // digits down to zero must be able to clear the field.
    final deleting = newValue.text.length < oldValue.text.length;
    if (cents == 0 && deleting) return _empty;

    final text = _fromCents(cents);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
