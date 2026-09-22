import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxo_plus/core/sync/cloud_sync_service.dart';
import 'package:fluxo_plus/core/sync/sync_planner.dart';
import 'package:fluxo_plus/core/theme/app_theme.dart';
import 'package:fluxo_plus/features/settings/presentation/cloud_backup_panel.dart';

SyncConflictInfo _info({
  SyncConflictReason reason = SyncConflictReason.bothChanged,
  SnapshotCounts? cloud = const SnapshotCounts(
    transactions: 12,
    accounts: 2,
    goals: 1,
  ),
  DateTime? cloudUpdatedAt,
}) {
  return SyncConflictInfo(
    reason: reason,
    local: const SnapshotCounts(transactions: 1, accounts: 1, goals: 0),
    cloud: cloud,
    cloudUpdatedAt: cloudUpdatedAt ?? DateTime(2026, 9, 20, 18, 30),
    accountEmail: 'pessoa@fluxo.app',
  );
}

void main() {
  late SyncConflictChoice? choice;
  late bool completed;

  Future<void> open(WidgetTester tester, SyncConflictInfo info) async {
    resetSyncConflictDialogGuard();
    choice = null;
    completed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await showSyncConflictDialog(context, info);
                completed = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('mostra o motivo e os dois lados', (tester) async {
    await open(tester, _info());

    expect(find.text('Escolha qual versão manter'), findsOneWidget);
    expect(
      find.textContaining('mudaram aqui e em outro aparelho'),
      findsOneWidget,
    );
    expect(find.text('12 transações · 2 contas · 1 meta'), findsOneWidget);
    expect(find.text('1 transação · 1 conta · 0 metas'), findsOneWidget);
    expect(find.textContaining('20/09/2026 18:30'), findsOneWidget);
    expect(find.text('Nada é alterado até você escolher.'), findsOneWidget);
  });

  testWidgets('usar a nuvem exige uma segunda confirmação', (tester) async {
    await open(tester, _info());

    await tester.tap(find.text('Usar os dados da nuvem'));
    await tester.pumpAndSettle();

    expect(find.text('Usar os dados da nuvem?'), findsOneWidget);
    expect(find.textContaining('desfazer'), findsOneWidget);

    await tester.tap(find.text('Usar o backup'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(choice, SyncConflictChoice.useCloud);
  });

  testWidgets('cancelar a confirmação não decide nada', (tester) async {
    await open(tester, _info());

    await tester.tap(find.text('Usar os dados da nuvem'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(choice, isNull);
  });

  testWidgets('manter este aparelho avisa que o backup será trocado',
      (tester) async {
    await open(tester, _info());

    await tester.tap(find.text('Manter os dados deste aparelho'));
    await tester.pumpAndSettle();

    expect(find.text('Manter os dados deste aparelho?'), findsOneWidget);
    expect(
      find.textContaining('backup na nuvem será substituído'),
      findsOneWidget,
    );

    await tester.tap(find.text('Manter estes dados'));
    await tester.pumpAndSettle();

    expect(choice, SyncConflictChoice.keepDevice);
  });

  testWidgets('decidir depois mantém tudo como está', (tester) async {
    await open(tester, _info());

    await tester.tap(find.text('Decidir depois'));
    await tester.pumpAndSettle();

    expect(choice, SyncConflictChoice.later);
  });

  testWidgets('explica cada motivo com palavras do usuário', (tester) async {
    for (final reason in SyncConflictReason.values) {
      await open(tester, _info(reason: reason));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Text),
        ),
        findsWidgets,
        reason: reason.name,
      );
      expect(find.textContaining('conta'), findsWidgets, reason: reason.name);
      await tester.tap(find.text('Decidir depois'));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('sem conseguir ler o backup, ainda mostra este aparelho',
      (tester) async {
    await open(tester, _info(cloud: null));

    expect(
      find.text('Não foi possível ler o conteúdo agora.'),
      findsOneWidget,
    );
    expect(find.text('1 transação · 1 conta · 0 metas'), findsOneWidget);
  });
}
