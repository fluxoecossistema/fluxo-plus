import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/account.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/account_repository.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, required this.repository});

  final AccountRepository repository;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  late Future<List<AccountBalance>> _accounts;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _accounts = widget.repository.list();

  Future<void> _edit([Account? account]) async {
    final name = TextEditingController(text: account?.name);
    final initialBalance = account?.initialBalance;
    final balance = TextEditingController(
      text: initialBalance == null
          ? null
          : CurrencyInputFormatter.format(initialBalance),
    );
    // The field holds the magnitude only; the sign is kept apart and applied
    // when the value is read.
    var negative = initialBalance != null && initialBalance < 0;
    final key = GlobalKey<FormState>();
    void submit(BuildContext context) {
      if (key.currentState!.validate()) Navigator.pop(context, true);
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(account == null ? 'Nova conta' : 'Editar conta'),
          content: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Informe o nome'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: balance,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: const [CurrencyInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Saldo inicial',
                    hintText: r'R$ 0,00',
                    prefixText: negative ? '- ' : null,
                    prefixStyle: TextStyle(color: context.colors.expense),
                    suffixIcon: IconButton(
                      tooltip: negative
                          ? 'Saldo negativo (toque para positivo)'
                          : 'Saldo positivo (toque para negativo)',
                      onPressed: () =>
                          setDialogState(() => negative = !negative),
                      icon: Icon(
                        negative
                            ? Icons.remove_circle_outline
                            : Icons.add_circle_outline,
                        color: negative
                            ? context.colors.expense
                            : context.colors.income,
                      ),
                    ),
                  ),
                  validator: (value) =>
                      AppFormatters.parseCurrency(value ?? '') == null
                          ? 'Informe um valor válido'
                          : null,
                  onFieldSubmitted: (_) => submit(context),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => submit(context),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final magnitude = AppFormatters.parseCurrency(balance.text)!;
    await widget.repository.save(
      Account(
        id: account?.id,
        name: name.text.trim(),
        initialBalance: negative && magnitude != 0 ? -magnitude : magnitude,
        createdAt: account?.createdAt ?? DateTime.now(),
      ),
    );
    setState(_reload);
  }

  Future<void> _delete(AccountBalance item) async {
    final deleted = await widget.repository.delete(item.account.id!);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Esta conta possui transações e não pode ser excluída.'),
        ),
      );
    } else {
      setState(_reload);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas'),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.add),
              label: const Text('Nova conta'),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<AccountBalance>>(
        future: _accounts,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.requireData;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Nenhuma conta',
              message: 'Crie uma conta para organizar seus lançamentos.',
            );
          }
          final total =
              items.fold<double>(0, (sum, item) => sum + item.balance);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                color: context.colors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Saldo em todas as contas',
                        style: TextStyle(color: context.colors.textMuted),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppFormatters.currency(total),
                        style: TextStyle(
                          color: context.colors.primary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ...items.map(
                (item) => Card(
                  child: ListTile(
                    onTap: () => _edit(item.account),
                    leading: CircleAvatar(
                      backgroundColor:
                          context.colors.primary.withValues(alpha: .16),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: context.colors.primary,
                      ),
                    ),
                    title: Text(
                      item.account.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${item.transactionCount} transações'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppFormatters.currency(item.balance),
                          style: TextStyle(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) => value == 'edit'
                              ? _edit(item.account)
                              : _delete(item),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Editar'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Excluir'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
