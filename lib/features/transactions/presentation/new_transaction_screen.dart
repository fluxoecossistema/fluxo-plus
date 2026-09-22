import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/account.dart';
import '../../../shared/models/category.dart';
import '../../../shared/models/finance_transaction.dart';
import '../data/transaction_repository.dart';

class NewTransactionScreen extends StatefulWidget {
  const NewTransactionScreen({
    super.key,
    required this.repository,
    this.transaction,
  });

  final TransactionRepository repository;
  final FinanceTransaction? transaction;

  @override
  State<NewTransactionScreen> createState() => _NewTransactionScreenState();
}

class _NewTransactionScreenState extends State<NewTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _installmentsController = TextEditingController(text: '1');
  TransactionType _type = TransactionType.expense;
  DateTime _date = DateTime.now();
  List<Account> _accounts = const [];
  List<Category> _categories = const [];
  int? _accountId;
  int? _categoryId;
  bool _isPaid = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final transaction = widget.transaction;
    if (transaction != null) {
      _type = transaction.type;
      _date = transaction.date;
      _amountController.text =
          CurrencyInputFormatter.format(transaction.amount);
      _nameController.text = transaction.description;
      _installmentsController.text = transaction.installmentCount.toString();
      _isPaid = transaction.isPaid;
    } else {
      _isPaid = _type == TransactionType.income;
    }
    _amountController.addListener(_refreshCalculation);
    _loadOptions();
  }

  void _refreshCalculation() {
    if (mounted) setState(() {});
  }

  Future<void> _loadOptions() async {
    final accounts = await widget.repository.getAccounts();
    final categories = await widget.repository.getCategories(_type);
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _categories = categories;
      _accountId = widget.transaction?.accountId ??
          (accounts.isEmpty ? null : accounts.first.id);
      _categoryId = widget.transaction?.categoryId ??
          (categories.isEmpty ? null : categories.first.id);
      _loading = false;
    });
  }

  Future<void> _changeType(TransactionType type) async {
    setState(() {
      _type = type;
      _isPaid = type == TransactionType.income;
      _loading = true;
    });
    final categories = await widget.repository.getCategories(type);
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _categoryId = categories.isEmpty ? null : categories.first.id;
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final current = widget.transaction;
      final transaction = FinanceTransaction(
        id: current?.id,
        type: _type,
        amount: AppFormatters.parseCurrency(_amountController.text)!,
        categoryId: _categoryId!,
        accountId: _accountId!,
        date: _date,
        description: _nameController.text.trim(),
        createdAt: current?.createdAt ?? DateTime.now(),
        isPaid: _isPaid,
        installmentGroup: current?.installmentGroup,
        installmentNumber: current?.installmentNumber ?? 1,
        installmentCount: current?.installmentCount ?? 1,
      );
      if (current == null) {
        await widget.repository.createInstallments(
          transaction,
          int.parse(_installmentsController.text),
        );
      } else {
        await widget.repository.update(transaction);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar: $error')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _amountController
      ..removeListener(_refreshCalculation)
      ..dispose();
    _nameController.dispose();
    _installmentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Screen is forced dark: use AppColors.dark.* below this wrapper (the
    // context sits above the Theme) and context.colors only below the Theme.
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.transaction == null ? 'Nova transação' : 'Editar transação',
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<TransactionType>(
                            segments: const [
                              ButtonSegment(
                                value: TransactionType.income,
                                icon: Icon(Icons.arrow_downward_rounded),
                                label: Text('Receita'),
                              ),
                              ButtonSegment(
                                value: TransactionType.expense,
                                icon: Icon(Icons.arrow_upward_rounded),
                                label: Text('Despesa'),
                              ),
                            ],
                            selected: {_type},
                            onSelectionChanged: (value) =>
                                _changeType(value.first),
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: _nameController,
                            autofocus: true,
                            maxLength: 80,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Nome da transação',
                              hintText: 'Ex.: Internet de casa',
                              prefixIcon: Icon(Icons.edit_note_rounded),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Dê um nome para a transação'
                                    : null,
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: const [CurrencyInputFormatter()],
                            decoration: InputDecoration(
                              labelText: widget.transaction == null
                                  ? 'Valor de cada parcela'
                                  : 'Valor',
                              hintText: r'R$ 0,00',
                              prefixIcon:
                                  const Icon(Icons.attach_money_rounded),
                            ),
                            validator: (value) {
                              final amount =
                                  AppFormatters.parseCurrency(value ?? '');
                              return amount == null || amount <= 0
                                  ? 'Informe um valor maior que zero'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _installmentsController,
                            enabled: widget.transaction == null,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText: 'Parcelas',
                              helperText: widget.transaction == null
                                  ? 'Um vencimento será criado por mês'
                                  : 'O parcelamento não muda durante a edição',
                              prefixIcon:
                                  const Icon(Icons.view_timeline_rounded),
                            ),
                            validator: (value) {
                              final count = int.tryParse(value ?? '');
                              return count == null || count < 1 || count > 120
                                  ? 'Informe entre 1 e 120 parcelas'
                                  : null;
                            },
                            onChanged: (_) => setState(() {}),
                          ),
                          if (widget.transaction == null) ...[
                            const SizedBox(height: 10),
                            _InstallmentSummary(
                              amount: AppFormatters.parseCurrency(
                                    _amountController.text,
                                  ) ??
                                  0,
                              count: int.tryParse(
                                    _installmentsController.text,
                                  ) ??
                                  1,
                            ),
                          ],
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                            initialValue: _categoryId,
                            decoration: const InputDecoration(
                              labelText: 'Categoria',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: _categories
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item.id,
                                    child: Row(
                                      children: [
                                        Icon(
                                          CategoryIcons.resolve(item.icon),
                                          size: 20,
                                          color: Color(item.color),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(item.name),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _categoryId = value),
                            validator: (value) => value == null
                                ? 'Selecione uma categoria'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                            initialValue: _accountId,
                            decoration: const InputDecoration(
                              labelText: 'Conta',
                              prefixIcon:
                                  Icon(Icons.account_balance_wallet_outlined),
                            ),
                            items: _accounts
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item.id,
                                    child: Text(item.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _accountId = value),
                            validator: (value) =>
                                value == null ? 'Selecione uma conta' : null,
                          ),
                          const SizedBox(height: 16),
                          InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(14),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: _type == TransactionType.expense
                                    ? 'Primeiro vencimento'
                                    : 'Data de recebimento',
                                prefixIcon:
                                    const Icon(Icons.calendar_today_outlined),
                              ),
                              child: Text(AppFormatters.date(_date)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            value: _isPaid,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            secondary: Icon(
                              _isPaid
                                  ? Icons.check_circle_rounded
                                  : Icons.schedule_rounded,
                              color: _isPaid
                                  ? AppColors.dark.primary
                                  : AppColors.dark.warning,
                            ),
                            title: Text(
                              _type == TransactionType.income
                                  ? 'Recebido'
                                  : 'Pago',
                            ),
                            subtitle: Text(
                              _isPaid
                                  ? 'Este lançamento já foi concluído'
                                  : 'Manter pendente até você dar baixa',
                            ),
                            onChanged: (value) =>
                                setState(() => _isPaid = value),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                              backgroundColor: _type == TransactionType.income
                                  ? AppColors.dark.income
                                  : AppColors.dark.expense,
                              foregroundColor: AppColors.dark.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: _saving
                                ? SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.dark.onPrimary,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded),
                            label: Text(
                              widget.transaction == null
                                  ? 'Salvar transação'
                                  : 'Salvar alterações',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _InstallmentSummary extends StatelessWidget {
  const _InstallmentSummary({
    required this.amount,
    required this.count,
  });

  final double amount;
  final int count;

  @override
  Widget build(BuildContext context) {
    final safeCount = count.clamp(1, 120);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate_outlined, color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$safeCount × ${AppFormatters.currency(amount)}',
            ),
          ),
          Text(
            'Total ${AppFormatters.currency(amount * safeCount)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
