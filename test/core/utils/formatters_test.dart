import 'package:flutter_test/flutter_test.dart';
import 'package:fluxo_plus/core/utils/currency_input_formatter.dart';
import 'package:fluxo_plus/core/utils/formatters.dart';

void main() {
  group('AppFormatters.parseCurrency', () {
    double? parse(String input) => AppFormatters.parseCurrency(input);

    test('interpreta valor brasileiro', () {
      expect(parse('R\$ 1.234,56'), 1234.56);
    });

    test('rejeita valor vazio', () {
      expect(parse(''), isNull);
    });

    test('rejeita texto sem dígitos', () {
      expect(parse('abc'), isNull);
      expect(parse('R\$'), isNull);
      expect(parse('-'), isNull);
      expect(parse(',.'), isNull);
    });

    test('rejeita texto malformado', () {
      expect(parse('1,2,3'), isNull);
      expect(parse('1-2'), isNull);
      expect(parse('1,5.0'), isNull);
    });

    test('entende o texto do próprio campo de valor', () {
      expect(parse(CurrencyInputFormatter.format(1234.56)), 1234.56);
      expect(parse(CurrencyInputFormatter.format(0.05)), 0.05);
      expect(parse(CurrencyInputFormatter.format(0)), 0);
      expect(parse(CurrencyInputFormatter.format(999999999.99)), 999999999.99);
    });

    test('vírgula é sempre o separador decimal', () {
      expect(parse('1,5'), 1.5);
      expect(parse('1,50'), 1.5);
      expect(parse('1.234,56'), 1234.56);
      expect(parse('1.250,5'), 1250.5);
      expect(parse('1.234.567,89'), 1234567.89);
      expect(parse('1.250,000'), 1250);
    });

    test('ponto com até 2 dígitos finais e sem vírgula é decimal', () {
      expect(parse('12.50'), 12.5);
      expect(parse('10.5'), 10.5);
      expect(parse('0.05'), 0.05);
    });

    test('ponto com 3 dígitos finais é separador de milhar', () {
      expect(parse('1.250'), 1250);
      expect(parse('1.250.000'), 1250000);
    });

    test('número inteiro simples', () {
      expect(parse('100'), 100);
      expect(parse('0'), 0);
    });

    test('mantém suporte a valores negativos', () {
      expect(parse('-R\$ 100,00'), -100);
      expect(parse('-100,50'), -100.5);
      expect(parse('R\$ -100,50'), -100.5);
      expect(parse('-1.234,56'), -1234.56);
      expect(parse('-12.50'), -12.5);
      expect(parse('-0'), isNot(isNegative));
    });
  });

  group('AppFormatters', () {
    test('formata data brasileira', () {
      expect(AppFormatters.date(DateTime(2026, 6, 26)), '26/06/2026');
    });
  });
}
