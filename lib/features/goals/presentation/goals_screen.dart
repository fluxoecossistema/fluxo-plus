import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/goal.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/goal_repository.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, required this.repository});

  final GoalRepository repository;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late Future<List<Goal>> _goals;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _goals = widget.repository.list();

  Future<void> _edit([Goal? goal]) async {
    final name = TextEditingController(text: goal?.name);
    final target = TextEditingController(
      text: goal == null
          ? null
          : CurrencyInputFormatter.format(goal.targetAmount),
    );
    final current = TextEditingController(
      text: CurrencyInputFormatter.format(goal?.currentAmount ?? 0),
    );
    DateTime? deadline = goal?.deadline;
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(goal == null ? 'Nova meta' : 'Editar meta'),
          content: SizedBox(
            width: 430,
            child: Form(
              key: key,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Objetivo'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Informe o objetivo'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: target,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: const [CurrencyInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Valor alvo',
                        hintText: r'R$ 0,00',
                      ),
                      validator: (value) {
                        final parsed = AppFormatters.parseCurrency(value ?? '');
                        return parsed == null || parsed <= 0
                            ? 'Informe um valor maior que zero'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: current,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: const [CurrencyInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Valor atual',
                        hintText: r'R$ 0,00',
                      ),
                      validator: (value) =>
                          AppFormatters.parseCurrency(value ?? '') == null
                              ? 'Informe um valor válido'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Prazo opcional'),
                      subtitle: Text(
                        deadline == null
                            ? 'Sem prazo'
                            : AppFormatters.date(deadline!),
                      ),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: deadline ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (date != null) {
                          setDialogState(() => deadline = date);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await widget.repository.save(
      Goal(
        id: goal?.id,
        name: name.text.trim(),
        targetAmount: AppFormatters.parseCurrency(target.text)!,
        currentAmount: AppFormatters.parseCurrency(current.text)!,
        deadline: deadline,
        createdAt: goal?.createdAt ?? DateTime.now(),
      ),
    );
    setState(_reload);
  }

  Future<void> _delete(Goal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir meta?'),
        content: Text('A meta “${goal.name}” será removida.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.expense,
              foregroundColor: context.colors.onPrimary,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.delete(goal.id!);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Metas'),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.add),
              label: const Text('Nova meta'),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Goal>>(
        future: _goals,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.requireData;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.track_changes_rounded,
              title: 'Transforme planos em metas',
              message: 'Defina um valor e acompanhe seu progresso.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 3
                  : constraints.maxWidth >= 620
                      ? 2
                      : 1;
              return GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 230,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final goal = items[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: context.colors.primary
                                    .withValues(alpha: .16),
                                child: Icon(
                                  Icons.flag_rounded,
                                  color: context.colors.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  goal.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) => value == 'edit'
                                    ? _edit(goal)
                                    : _delete(goal),
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
                          const Spacer(),
                          Text(
                            '${AppFormatters.currency(goal.currentAmount)} de ${AppFormatters.currency(goal.targetAmount)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: goal.progress,
                            minHeight: 9,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          const SizedBox(height: 9),
                          Row(
                            children: [
                              Text(
                                '${(goal.progress * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                  color: context.colors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Spacer(),
                              if (goal.deadline != null)
                                Text(
                                  'até ${AppFormatters.date(goal.deadline!)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
