import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/category_icons.dart';
import '../../../shared/models/category.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/category_repository.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, required this.repository});

  final CategoryRepository repository;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<List<CategoryUsage>> _categories;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _categories = widget.repository.list();

  Future<void> _edit([Category? category]) async {
    final name = TextEditingController(text: category?.name);
    var type = category?.type ?? TransactionType.expense;
    var icon = category?.icon ?? 'category';
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(category == null ? 'Nova categoria' : 'Editar categoria'),
          content: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Informe o nome'
                      : null,
                ),
                const SizedBox(height: 14),
                SegmentedButton<TransactionType>(
                  segments: const [
                    ButtonSegment(
                      value: TransactionType.income,
                      label: Text('Receita'),
                    ),
                    ButtonSegment(
                      value: TransactionType.expense,
                      label: Text('Despesa'),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (value) =>
                      setDialogState(() => type = value.first),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: icon,
                  decoration: const InputDecoration(
                    labelText: 'Ícone',
                    prefixIcon: Icon(Icons.auto_awesome_outlined),
                  ),
                  items: CategoryIcons.choices
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.$1,
                          child: Row(
                            children: [
                              Icon(item.$2, size: 20),
                              const SizedBox(width: 10),
                              Text(item.$3),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => icon = value ?? 'category'),
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
      Category(
        id: category?.id,
        name: name.text.trim(),
        type: type,
        icon: icon,
        color: category?.color ??
            (type == TransactionType.income
                // Stored in the DB: must be theme-independent (fixed values).
                ? AppColors.light.income.toARGB32()
                : AppColors.light.expense.toARGB32()),
        isDefault: category?.isDefault ?? false,
      ),
    );
    setState(_reload);
  }

  Future<void> _delete(CategoryUsage usage) async {
    final deleted = await widget.repository.delete(usage.category.id!);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('A categoria possui transações e não pode ser excluída.'),
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
        title: const Text('Categorias'),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.add),
              label: const Text('Nova'),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<CategoryUsage>>(
        future: _categories,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.requireData;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.category_outlined,
              title: 'Nenhuma categoria',
              message: 'Crie categorias para classificar seus lançamentos.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final usage = items[index];
              final item = usage.category;
              return Card(
                child: ListTile(
                  onTap: () => _edit(item),
                  leading: CircleAvatar(
                    backgroundColor: Color(item.color).withValues(alpha: .16),
                    child: Icon(
                      CategoryIcons.resolve(item.icon),
                      color: Color(item.color),
                    ),
                  ),
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${item.type == TransactionType.income ? 'Receita' : 'Despesa'} • ${usage.usageCount} usos${item.isDefault ? ' • Padrão' : ''}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) =>
                        value == 'edit' ? _edit(item) : _delete(usage),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'delete', child: Text('Excluir')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
