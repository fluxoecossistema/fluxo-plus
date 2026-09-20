import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxo_plus/core/utils/currency_input_formatter.dart';
import 'package:fluxo_plus/core/utils/formatters.dart';

void main() {
  testWidgets('campo de valor formata em centavos e o parse devolve o número', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: const [CurrencyInputFormatter()],
              decoration: const InputDecoration(hintText: 'R\$ 0,00'),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField), '125000');
    await tester.pump();

    expect(controller.text, 'R\$ 1.250,00');
    expect(AppFormatters.parseCurrency(controller.text), 1250.0);
    expect(controller.selection.baseOffset, controller.text.length);
  });
}
