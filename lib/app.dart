import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite/sqflite.dart';

import 'core/constants/app_constants.dart';
import 'core/database/app_database.dart';
import 'core/theme/app_theme.dart';
import 'core/update/update_prompt.dart';
import 'core/update/app_update.dart';
import 'core/update/update_service.dart';
import 'core/security/biometric_service.dart';
import 'core/sync/cloud_sync_service.dart';
import 'core/premium/premium_service.dart';
import 'features/dashboard/data/dashboard_repository.dart';
import 'features/accounts/data/account_repository.dart';
import 'features/categories/data/category_repository.dart';
import 'features/goals/data/goal_repository.dart';
import 'features/reports/data/report_repository.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/settings/presentation/cloud_backup_panel.dart';
import 'features/shell/presentation/main_shell.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'features/transactions/data/transaction_repository.dart';

class FluxoApp extends StatefulWidget {
  const FluxoApp({
    super.key,
    required this.database,
    required this.dashboardRepository,
    required this.transactionRepository,
    required this.updateService,
    required this.accountRepository,
    required this.categoryRepository,
    required this.goalRepository,
    required this.reportRepository,
    required this.cloudSyncService,
    required this.biometricService,
    required this.premiumService,
  });

  final AppDatabase database;
  final DashboardRepository dashboardRepository;
  final TransactionRepository transactionRepository;
  final UpdateService updateService;
  final AccountRepository accountRepository;
  final CategoryRepository categoryRepository;
  final GoalRepository goalRepository;
  final ReportRepository reportRepository;
  final CloudSyncService cloudSyncService;
  final BiometricService biometricService;
  final PremiumService premiumService;

  @override
  State<FluxoApp> createState() => _FluxoAppState();
}

class _FluxoAppState extends State<FluxoApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool? _onboardingComplete;
  bool _updateChecked = false;
  DateTime? _lastUpdateCheck;
  AppUpdate? _availableUpdate;
  ThemeMode _themeMode = ThemeMode.dark;
  bool _biometricEnabled = false;
  bool _unlocked = true;

  /// Muda quando um backup substitui os dados deste aparelho, para as telas
  /// serem reconstruídas com as informações novas.
  int _dataRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStartupState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_biometricEnabled &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      setState(() => _unlocked = false);
    }
    if (state == AppLifecycleState.paused &&
        widget.cloudSyncService.isSignedIn) {
      // Melhor esforço ao sair: o backup nunca segura o fechamento do app e
      // uma falha fica registrada para aparecer em Configurações.
      unawaited(
        widget.cloudSyncService.synchronize(
          interactive: false,
          timeout: const Duration(seconds: 8),
        ),
      );
    }
    if (state == AppLifecycleState.resumed &&
        (_lastUpdateCheck == null ||
            DateTime.now().difference(_lastUpdateCheck!) >
                const Duration(minutes: 15))) {
      _updateChecked = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
    }
    if (state == AppLifecycleState.resumed &&
        widget.cloudSyncService.isSignedIn) {
      unawaited(_syncSilently());
    }
  }

  Future<void> _loadStartupState() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final rows = await widget.database.db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['onboarding_complete'],
    );
    final themeRows = await widget.database.db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['theme'],
    );
    final biometricRows = await widget.database.db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['biometric_enabled'],
    );
    final biometricEnabled =
        biometricRows.isNotEmpty && biometricRows.first['value'] == 'true';
    if (mounted) {
      setState(
        () {
          _onboardingComplete =
              rows.isNotEmpty && rows.first['value'] == 'true';
          _themeMode =
              themeRows.isNotEmpty && themeRows.first['value'] == 'light'
                  ? ThemeMode.light
                  : ThemeMode.dark;
          _biometricEnabled = biometricEnabled;
          _unlocked = !biometricEnabled;
        },
      );
      if (biometricEnabled) await _unlock();
      if (widget.cloudSyncService.isSignedIn) {
        unawaited(_syncSilently());
      }
    }
  }

  Future<void> _completeOnboarding() async {
    await widget.database.db.insert(
      'settings',
      {'key': 'onboarding_complete', 'value': 'true'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (mounted) setState(() => _onboardingComplete = true);
  }

  /// Sincronização automática: nunca pergunta nada e nunca apaga dados sem o
  /// plano autorizar. Um conflito só fica marcado e é perguntado depois, com o
  /// aplicativo em primeiro plano.
  Future<void> _syncSilently() async {
    final outcome =
        await widget.cloudSyncService.synchronize(interactive: false);
    if (!mounted) return;
    if (outcome.changedData) setState(() => _dataRevision++);
    if (outcome.isConflict) await _askAboutConflict();
  }

  Future<void> _askAboutConflict() async {
    if (!_onboardingDone || !_unlocked) return;
    final info = await widget.cloudSyncService.pendingConflict();
    final context = _navigatorKey.currentContext;
    if (info == null || context == null || !context.mounted) return;
    final choice = await showSyncConflictDialog(context, info);
    if (choice == SyncConflictChoice.later) {
      // Decidir depois não vira insistência: a pergunta automática fica quieta
      // e o aviso continua em Configurações.
      await widget.cloudSyncService.snoozeConflict();
    }
    if (choice == null || choice == SyncConflictChoice.later) return;
    final outcome = choice == SyncConflictChoice.useCloud
        ? await widget.cloudSyncService.useCloudVersion()
        : await widget.cloudSyncService.keepThisDevice();
    if (mounted && outcome.changedData) setState(() => _dataRevision++);
  }

  bool get _onboardingDone => _onboardingComplete == true;

  Future<void> _checkForUpdates() async {
    if (_updateChecked || !widget.updateService.isConfigured) return;
    _updateChecked = true;
    _lastUpdateCheck = DateTime.now();
    try {
      final update = await widget.updateService.check();
      if (mounted) setState(() => _availableUpdate = update);
    } catch (error) {
      debugPrint('Falha ao verificar atualizações: $error');
      // Atualizações nunca impedem o uso offline do aplicativo.
    }
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await widget.database.db.insert(
      'settings',
      {'key': 'theme', 'value': mode == ThemeMode.light ? 'light' : 'dark'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> _unlock() async {
    final success = await widget.biometricService.authenticate();
    if (mounted && success) setState(() => _unlocked = true);
    return success;
  }

  Future<bool> _changeBiometric(bool enabled) async {
    if (enabled && !await widget.biometricService.authenticate()) return false;
    await widget.database.db.insert(
      'settings',
      {'key': 'biometric_enabled', 'value': enabled ? 'true' : 'false'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (mounted) setState(() => _biometricEnabled = enabled);
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.database.close();
    widget.updateService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_onboardingComplete == true && _unlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
    }
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: switch (_onboardingComplete) {
        null => const SplashScreen(),
        false => OnboardingScreen(onComplete: _completeOnboarding),
        true when !_unlocked => _LockScreen(onUnlock: _unlock),
        true => MainShell(
            dataRevision: _dataRevision,
            dashboardRepository: widget.dashboardRepository,
            transactionRepository: widget.transactionRepository,
            themeMode: _themeMode,
            onThemeChanged: _changeTheme,
            accountRepository: widget.accountRepository,
            categoryRepository: widget.categoryRepository,
            goalRepository: widget.goalRepository,
            reportRepository: widget.reportRepository,
            cloudSyncService: widget.cloudSyncService,
            biometricEnabled: _biometricEnabled,
            onBiometricChanged: _changeBiometric,
            updateService: widget.updateService,
            availableUpdate: _availableUpdate,
            onOpenUpdate: _openAvailableUpdate,
            premiumService: widget.premiumService,
          ),
      },
    );
  }

  Future<void> _openAvailableUpdate() async {
    final update = _availableUpdate;
    final context = _navigatorKey.currentContext;
    if (update == null || context == null || !context.mounted) return;
    await showUpdatePrompt(
      context,
      update: update,
      service: widget.updateService,
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});

  final Future<bool> Function() onUnlock;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, size: 72),
            const SizedBox(height: 20),
            Text(
              'Fluxo+ bloqueado',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            const Text('Use sua biometria para continuar.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.fingerprint_rounded),
              label: const Text('Desbloquear'),
            ),
          ],
        ),
      ),
    );
  }
}
