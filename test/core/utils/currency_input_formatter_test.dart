import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxo_plus/core/utils/currency_input_formatter.dart';

/// The app currency format separates the symbol from the amount with a
/// non-breaking space (U+00A0).
String money(String amount) => 'R\$ $amount';

TextEditingValue typed(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

void main() {
  const formatter = CurrencyInputFormatter();

  /// Applies each edit in [edits] on top of the previous formatted value, the
  /// way the text field does: every edit is the previous text plus one change.
  TextEditingValue apply(TextEditingValue old, String newText) =>
      formatter.formatEditUpdate(old, typed(newText));

  TextEditingValue typeDigits(String digits, {TextEditingValue? from}) {
    var value = from ?? TextEditingValue.empty;
    for (final digit in digits.split('')) {
      value = apply(value, '${value.text}$digit');
    }
    return value;
  }

  TextEditingValue backspace(TextEditingValue value) =>
      apply(value, value.text.substring(0, value.text.length - 1));

  group('CurrencyInputFormatter typing', () {
    test('digits slide in from the right as cents', () {
      var value = TextEditingValue.empty;
      final expected = {
        '1': money('0,01'),
        '2': money('0,12'),
        '5': money('1,25'),
        '0': money('12,50'),
      };
      for (final entry in expected.entries) {
        value = apply(value, '${value.text}${entry.key}');
        expect(value.text, entry.value);
      }
    });

    test('shows thousands separators', () {
      expect(typeDigits('125000').text, money('1.250,00'));
    });

    test('backspace removes the last digit', () {
      final value = typeDigits('1250');
      expect(value.text, money('12,50'));
      expect(backspace(value).text, money('1,25'));
    });

    test('backspace down to nothing yields the empty string', () {
      var value = typeDigits('12');
      value = backspace(value);
      expect(value.text, money('0,01'));
      value = backspace(value);
      expect(value.text, isEmpty);
    });

    test('clearing the field keeps it empty', () {
      final value = apply(typeDigits('1250'), '');
      expect(value.text, isEmpty);
      expect(value.selection, const TextSelection.collapsed(offset: 0));
    });

    test('non digit keys are ignored', () {
      final value = typeDigits('12');
      expect(apply(value, '${value.text},').text, value.text);
      expect(apply(value, '${value.text}a').text, value.text);
      expect(apply(value, '${value.text}-').text, value.text);
    });
  });

  group('CurrencyInputFormatter paste', () {
    test('extracts only the digits of the pasted text', () {
      expect(apply(TextEditingValue.empty, 'R\$ 1.250,00').text,
          money('1.250,00'));
      expect(apply(TextEditingValue.empty, ' 12 34 ').text, money('12,34'));
      expect(apply(TextEditingValue.empty, 'abc9x8').text, money('0,98'));
    });

    test('pasting text without digits yields the empty string', () {
      expect(apply(TextEditingValue.empty, 'abc').text, isEmpty);
      expect(apply(typeDigits('12'), 'R\$ ,').text, isEmpty);
    });

    test('pasted digits are appended to what is already typed', () {
      final value = typeDigits('12');
      expect(apply(value, '${value.text}34').text, money('12,34'));
    });
  });

  group('CurrencyInputFormatter limits', () {
    test('accepts up to 11 digits', () {
      expect(typeDigits('99999999999').text, money('999.999.999,99'));
    });

    test('ignores the 12th digit', () {
      final full = typeDigits('99999999999');
      final next = apply(full, '${full.text}1');
      expect(next.text, money('999.999.999,99'));
      expect(next.selection.baseOffset, next.text.length);
    });

    test('truncates a pasted text longer than 11 digits', () {
      expect(apply(TextEditingValue.empty, '123456789012345').text,
          money('123.456.789,01'));
    });
  });

  group('CurrencyInputFormatter leading zeros', () {
    test('a single zero shows a zero amount', () {
      expect(typeDigits('0').text, money('0,00'));
    });

    test('repeated zeros stay at zero', () {
      expect(typeDigits('00').text, money('0,00'));
      expect(typeDigits('000').text, money('0,00'));
    });

    test('leading zeros are dropped before other digits', () {
      expect(typeDigits('007').text, money('0,07'));
      expect(apply(TextEditingValue.empty, '00123').text, money('1,23'));
    });

    test('backspace on a zero amount empties the field', () {
      expect(backspace(typeDigits('0')).text, isEmpty);
      expect(backspace(typeDigits('00')).text, isEmpty);
    });

    test('leading zeros do not count towards the limit', () {
      expect(apply(TextEditingValue.empty, '00099999999999').text,
          money('999.999.999,99'));
    });
  });

  group('CurrencyInputFormatter cursor', () {
    test('cursor is always at the end', () {
      var value = TextEditingValue.empty;
      for (final digit in '125000'.split('')) {
        value = apply(value, '${value.text}$digit');
        expect(value.selection,
            TextSelection.collapsed(offset: value.text.length));
        expect(value.composing, TextRange.empty);
      }
    });

    test('cursor goes back to the end when editing in the middle', () {
      final old = typeDigits('1250');
      final edited = TextEditingValue(
        text: old.text.replaceFirst('1', '19'),
        selection: const TextSelection.collapsed(offset: 4),
      );
      final value = formatter.formatEditUpdate(old, edited);
      expect(value.text, money('192,50'));
      expect(
          value.selection, TextSelection.collapsed(offset: value.text.length));
    });
  });

  group('CurrencyInputFormatter.format', () {
    test('formats values for pre-filling the field', () {
      expect(CurrencyInputFormatter.format(0.05), money('0,05'));
      expect(CurrencyInputFormatter.format(1234.56), money('1.234,56'));
      expect(
          CurrencyInputFormatter.format(999999999.99), money('999.999.999,99'));
      expect(CurrencyInputFormatter.format(0), money('0,00'));
    });

    test('uses the magnitude of negative values', () {
      expect(CurrencyInputFormatter.format(-100.5), money('100,50'));
    });

    test('a pre-filled value keeps sliding when the user types', () {
      final prefilled = typed(CurrencyInputFormatter.format(1234.56));
      expect(apply(prefilled, '${prefilled.text}7').text, money('12.345,67'));
      expect(backspace(prefilled).text, money('123,45'));
    });
  });
}
