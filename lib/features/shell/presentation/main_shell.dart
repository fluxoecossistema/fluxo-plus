import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../accounts/data/account_repository.dart';
import '../../categories/data/category_repository.dart';
import '../../goals/data/goal_repository.dart';
import '../../reports/data/report_repository.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/presentation/new_transaction_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../accounts/presentation/accounts_screen.dart';
import '../../categories/presentation/categories_screen.dart';
import '../../goals/presentation/goals_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../transactions/presentation/transactions_screen.dart';
import '../../../core/sync/cloud_sync_service.dart';
import '../../../core/update/update_service.dart';
import '../../../core/update/app_update.dart';
import '../../../core/premium/premium_service.dart';
import '../../premium/presentation/premium_screen.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import '../../../shared/models/category.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.dashboardRepository,
    required this.transactionRepository,
    required this.themeMode,
    required this.onThemeChanged,
    required this.accountRepository,
    required this.categoryRepository,
    required this.goalRepository,
    required this.reportRepository,
    required this.cloudSyncService,
    required this.biometricEnabled,
    required this.onBiometricChanged,
    required this.updateService,
    required this.availableUpdate,
    required this.onOpenUpdate,
    required this.premiumService,
  });

  final DashboardRepository dashboardRepository;
  final TransactionRepository transactionRepository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final AccountRepository accountRepository;
  final CategoryRepository categoryRepository;
  final GoalRepository goalRepository;
  final ReportRepository reportRepository;
  final CloudSyncService cloudSyncService;
  final bool biometricEnabled;
  final Future<bool> Function(bool) onBiometricChanged;
  final UpdateService updateService;
  final AppUpdate? availableUpdate;
  final VoidCallback onOpenUpdate;
  final PremiumService premiumService;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  int _dashboardRevision = 0;
  bool _showMobileMore = false;
  TransactionType? _transactionType;
  int _transactionRevision = 0;

  static const _items = [
    (Icons.grid_view_rounded, 'Dashboard'),
    (Icons.swap_horiz_rounded, 'Transações'),
    (Icons.account_balance_wallet_outlined, 'Contas'),
    (Icons.track_changes_rounded, 'Metas'),
    (Icons.bar_chart_rounded, 'Relatórios'),
    (Icons.category_outlined, 'Categorias'),
    (Icons.settings_outlined, 'Configurações'),
    (Icons.workspace_premium_outlined, 'Premium'),
  ];

  Future<void> _addTransaction() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewTransactionScreen(
          repository: widget.transactionRepository,
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _selectedIndex = 0;
        _dashboardRevision++;
      });
    }
  }

  void _openTransactions(TransactionType? type) {
    setState(() {
      _transactionType = type;
      _transactionRevision++;
      _selectedIndex = 1;
      _showMobileMore = false;
    });
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NotificationCenterScreen(
          repository: widget.transactionRepository,
          availableUpdate: widget.availableUpdate,
          onOpenUpdate: widget.onOpenUpdate,
          onChanged: () => setState(() => _dashboardRevision++),
        ),
      ),
    );
    if (mounted) setState(() => _dashboardRevision++);
  }

  Future<void> _handleBack() async {
    if (_showMobileMore || _selectedIndex != 0) {
      setState(() {
        _showMobileMore = false;
        _selectedIndex = 0;
      });
      return;
    }
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair do Fluxo+?'),
        content: const Text(
          'Se preferir continuar, suas finanças permanecem abertas e seguras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (exit == true) await SystemNavigator.pop();
  }

  Widget _page() {
    return switch (_selectedIndex) {
      0 => DashboardScreen(
          key: ValueKey(_dashboardRevision),
          repository: widget.dashboardRepository,
          onAddTransaction: _addTransaction,
          updateAvailable: widget.availableUpdate != null,
          onNotifications: _openNotifications,
          onOpenTransactions: _openTransactions,
          userName: widget.cloudSyncService.displayName,
        ),
      1 => TransactionsScreen(
          key: ValueKey(_transactionRevision),
          repository: widget.transactionRepository,
          onChanged: () => setState(() => _dashboardRevision++),
          initialType: _transactionType,
        ),
      2 => AccountsScreen(repository: widget.accountRepository),
      3 => GoalsScreen(repository: widget.goalRepository),
      4 => ReportsScreen(repository: widget.reportRepository),
      5 => CategoriesScreen(repository: widget.categoryRepository),
      6 => SettingsScreen(
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
          cloudSyncService: widget.cloudSyncService,
          biometricEnabled: widget.biometricEnabled,
          onBiometricChanged: widget.onBiometricChanged,
          updateService: widget.updateService,
          onDataChanged: () => setState(() => _dashboardRevision++),
        ),
      _ => PremiumScreen(service: widget.premiumService),
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 980;
          if (!desktop) {
            return Scaffold(
              backgroundColor: context.colors.background,
              body: _showMobileMore
                  ? _MobileMore(
                      userName: widget.cloudSyncService.displayName,
                      email: widget.cloudSyncService.accountEmail,
                      onSelected: (index) => setState(() {
                        _selectedIndex = index;
                        _showMobileMore = false;
                      }),
                    )
                  : _page(),
              bottomNavigationBar: _MobileNavigation(
                selectedIndex: _showMobileMore
                    ? 3
                    : switch (_selectedIndex) {
                        0 => 0,
                        1 => 1,
                        4 => 2,
                        _ => 3,
                      },
                onSelected: (value) => setState(() {
                  if (value == 3) {
                    _showMobileMore = true;
                  } else {
                    _showMobileMore = false;
                    if (value == 1) {
                      _transactionType = null;
                      _transactionRevision++;
                    }
                    _selectedIndex = const [0, 1, 4][value];
                  }
                }),
                onAdd: _addTransaction,
              ),
            );
          }

          return Scaffold(
            body: Row(
              children: [
                _DesktopSidebar(
                  selectedIndex: _selectedIndex,
                  onSelected: (value) => setState(() {
                    if (value == 1) {
                      _transactionType = null;
                      _transactionRevision++;
                    }
                    _selectedIndex = value;
                  }),
                ),
                Expanded(child: _page()),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MobileMore extends StatelessWidget {
  const _MobileMore({
    required this.onSelected,
    required this.userName,
    required this.email,
  });

  final ValueChanged<int> onSelected;
  final String? userName;
  final String? email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mais'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border.all(color: context.colors.border),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 27,
                  backgroundColor: context.colors.primary,
                  child: Icon(
                    Icons.person_rounded,
                    color: context.colors.onPrimary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName ?? 'Seu espaço financeiro',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        email ?? 'Dados protegidos neste dispositivo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.colors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _MoreSectionTitle(
            title: 'Organize sua vida financeira',
            subtitle: 'Tudo que você usa no dia a dia',
          ),
          const SizedBox(height: 10),
          _MoreTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Contas e carteiras',
            subtitle: 'Acompanhe onde está o seu dinheiro',
            onTap: () => onSelected(2),
          ),
          _MoreTile(
            icon: Icons.category_outlined,
            title: 'Categorias',
            subtitle: 'Crie e personalize seus tipos de gasto',
            onTap: () => onSelected(5),
          ),
          _MoreTile(
            icon: Icons.track_changes_rounded,
            title: 'Metas',
            subtitle: 'Transforme planos em progresso',
            onTap: () => onSelected(3),
          ),
          const SizedBox(height: 22),
          const _MoreSectionTitle(
            title: 'Conta e aplicativo',
            subtitle: 'Preferências, segurança e recursos',
          ),
          const SizedBox(height: 10),
          _MoreTile(
            icon: Icons.workspace_premium_outlined,
            title: 'Fluxo+ Premium',
            subtitle: 'Nuvem, automação e análises avançadas',
            onTap: () => onSelected(7),
            highlighted: true,
          ),
          _MoreTile(
            icon: Icons.settings_outlined,
            title: 'Configurações',
            subtitle: 'Tema, segurança, backup e privacidade',
            onTap: () => onSelected(6),
          ),
        ],
      ),
    );
  }
}

class _MoreSectionTitle extends StatelessWidget {
  const _MoreSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? context.colors.warning : context.colors.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .14),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 238,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(right: BorderSide(color: context.colors.border)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Row(
                children: [
                  const _FluxoMark(size: 34),
                  const SizedBox(width: 12),
                  const Text(
                    'Fluxo',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    '+',
                    style: TextStyle(
                      fontSize: 28,
                      color: context.colors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _MainShellState._items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final item = _MainShellState._items[index];
                  final selected = selectedIndex == index;
                  return Material(
                    color: selected
                        ? context.colors.primary.withValues(alpha: .16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => onSelected(index),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.$1,
                              size: 20,
                              color: selected
                                  ? context.colors.primary
                                  : context.colors.textMuted,
                            ),
                            const SizedBox(width: 14),
                            Text(
                              item.$2,
                              style: TextStyle(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: selected
                                    ? context.colors.primary
                                    : context.colors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: context.colors.primary.withValues(
                      alpha: .16,
                    ),
                    child: Icon(
                      Icons.person_outline,
                      color: context.colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Meu perfil',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Dados locais',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileNavigation extends StatelessWidget {
  const _MobileNavigation({
    required this.selectedIndex,
    required this.onSelected,
    required this.onAdd,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_rounded, 'Início'),
      (Icons.swap_horiz_rounded, 'Transações'),
      (Icons.bar_chart_rounded, 'Relatórios'),
      (Icons.more_horiz_rounded, 'Mais'),
    ];
    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          ...List.generate(
            2,
            (index) => _mobileItem(context, items[index], index),
          ),
          Semantics(
            button: true,
            label: 'Nova transação',
            child: InkWell(
              onTap: onAdd,
              customBorder: const CircleBorder(),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.primary,
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.primary.withValues(alpha: .4),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: context.colors.onPrimary,
                ),
              ),
            ),
          ),
          ...List.generate(
            2,
            (offset) => _mobileItem(context, items[offset + 2], offset + 2),
          ),
        ],
      ),
    );
  }

  Widget _mobileItem(BuildContext context, (IconData, String) item, int index) {
    final selected = selectedIndex == index;
    return InkWell(
      onTap: () => onSelected(index),
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.$1,
              color:
                  selected ? context.colors.primary : context.colors.textMuted,
            ),
            const SizedBox(height: 4),
            Text(
              item.$2,
              style: TextStyle(
                fontSize: 10,
                color: selected
                    ? context.colors.primary
                    : context.colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FluxoMark extends StatelessWidget {
  const _FluxoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(-0.5, -0.65),
            child: Container(
              width: size * .78,
              height: size * .28,
              decoration: BoxDecoration(
                color: context.colors.primary,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(-0.65, 0.4),
            child: Transform.rotate(
              angle: -.35,
              child: Container(
                width: size * .32,
                height: size * .7,
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
