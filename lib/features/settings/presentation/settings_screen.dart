import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/sync/cloud_sync_service.dart';
import '../../../core/update/update_prompt.dart';
import '../../../core/update/update_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.cloudSyncService,
    required this.biometricEnabled,
    required this.onBiometricChanged,
    required this.updateService,
    required this.onDataChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final CloudSyncService cloudSyncService;
  final bool biometricEnabled;
  final Future<bool> Function(bool) onBiometricChanged;
  final UpdateService updateService;
  final VoidCallback onDataChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Aparência',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: context.colors.primary.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          themeMode == ThemeMode.dark
                              ? Icons.nightlight_round
                              : Icons.wb_sunny_rounded,
                          color: context.colors.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tema do aplicativo',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 3),
                            Text('Escolha como o Fluxo+ aparece para você.'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Escuro'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Claro'),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (value) => onThemeChanged(value.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Segurança',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              value: biometricEnabled,
              secondary: const Icon(Icons.fingerprint_rounded),
              title: const Text('Bloqueio biométrico'),
              subtitle: const Text(
                'Solicitar biometria ao abrir o aplicativo.',
              ),
              onChanged: (value) async {
                final changed = await onBiometricChanged(value);
                if (!changed && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Biometria indisponível ou autenticação cancelada.',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Sincronização e backup',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _CloudSyncPanel(
            service: cloudSyncService,
            onDataChanged: onDataChanged,
          ),
          const SizedBox(height: 24),
          Text(
            'Privacidade e dados',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.lock_outline_rounded,
                    color: context.colors.primary,
                  ),
                  title: const Text('Dados locais'),
                  subtitle: const Text(
                    'Suas informações permanecem neste dispositivo.',
                  ),
                  trailing: Icon(Icons.check_circle_rounded,
                      color: context.colors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _UpdatePanel(service: updateService),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Fluxo+',
                applicationVersion: '0.5.0',
                applicationLegalese: '© 2026 Fluxo+ contributors\nLicença MIT',
                children: const [
                  SizedBox(height: 12),
                  Text(
                    'Finanças pessoais offline-first, seguras e open source.',
                  ),
                ],
              ),
              leading: Icon(
                dark ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                color: context.colors.primary,
              ),
              title: const Text('Fluxo+'),
              subtitle: const Text('Open source • Licença MIT'),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdatePanel extends StatefulWidget {
  const _UpdatePanel({required this.service});

  final UpdateService service;

  @override
  State<_UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<_UpdatePanel> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final update = await widget.service.check();
      if (!mounted) return;
      if (update == null) {
        final version = await widget.service.currentVersion();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Você já está na versão mais recente: $version')),
        );
      } else {
        await showUpdatePrompt(
          context,
          update: update,
          service: widget.service,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao verificar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: FutureBuilder<String>(
        future: widget.service.currentVersion(),
        builder: (context, snapshot) => ListTile(
          leading: const Icon(Icons.system_update_rounded),
          title: const Text('Atualização pela internet'),
          subtitle: Text(
            snapshot.hasData
                ? 'Versão instalada: ${snapshot.data}'
                : 'Consultando versão instalada…',
          ),
          trailing: FilledButton(
            onPressed: _checking ? null : _check,
            child: _checking
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.onPrimary,
                    ),
                  )
                : const Text('Verificar'),
          ),
        ),
      ),
    );
  }
}

class _CloudSyncPanel extends StatefulWidget {
  const _CloudSyncPanel({
    required this.service,
    required this.onDataChanged,
  });

  final CloudSyncService service;
  final VoidCallback onDataChanged;

  @override
  State<_CloudSyncPanel> createState() => _CloudSyncPanelState();
}

class _CloudSyncPanelState extends State<_CloudSyncPanel> {
  bool _busy = false;
  late Future<DateTime?> _lastSync;

  @override
  void initState() {
    super.initState();
    _lastSync = widget.service.lastSyncAt();
  }

  void _refreshLastSync() {
    if (mounted) setState(() => _lastSync = widget.service.lastSyncAt());
  }

  Future<void> _authenticate() async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    var createAccount = false;
    var obscurePassword = true;
    final key = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(createAccount ? 'Criar conta' : 'Entrar no Fluxo+'),
          content: Form(
            key: key,
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (createAccount) ...[
                    TextFormField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Como podemos chamar você?',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Informe seu nome'
                              : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    validator: (value) => value != null && value.contains('@')
                        ? null
                        : 'Informe um e-mail válido',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: password,
                    obscureText: obscurePassword,
                    autofillHints: [
                      createAccount
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      suffixIcon: IconButton(
                        tooltip:
                            obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                        onPressed: () => setDialogState(
                          () => obscurePassword = !obscurePassword,
                        ),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => (value?.length ?? 0) < 6
                        ? 'Use pelo menos 6 caracteres'
                        : null,
                    onFieldSubmitted: (_) {
                      if (key.currentState!.validate()) {
                        Navigator.pop(context, true);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        setDialogState(() => createAccount = !createAccount),
                    child: Text(
                      createAccount ? 'Já tenho uma conta' : 'Criar uma conta',
                    ),
                  ),
                ],
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
              child: Text(createAccount ? 'Criar' : 'Entrar'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final accountEmail = email.text.trim();
    final succeeded = await _run(() async {
      if (createAccount) {
        await widget.service.signUp(
          accountEmail,
          password.text,
          name: name.text,
        );
      } else {
        await widget.service.signIn(accountEmail, password.text);
      }
    },
        createAccount
            ? 'Código de confirmação enviado por e-mail.'
            : 'Conectado.');
    if (createAccount && succeeded && mounted) {
      await _confirmEmailCode(accountEmail);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = TextEditingController();
    final key = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reenviar confirmação'),
        content: Form(
          key: key,
          child: TextFormField(
            controller: email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-mail da conta'),
            validator: (value) => value != null && value.contains('@')
                ? null
                : 'Informe um e-mail válido',
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
            child: const Text('Reenviar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final accountEmail = email.text.trim();
    final succeeded = await _run(
      () => widget.service.resendConfirmation(accountEmail),
      'Novo código enviado por e-mail.',
    );
    if (succeeded && mounted) await _confirmEmailCode(accountEmail);
  }

  Future<void> _confirmEmailCode(String email) async {
    final code = TextEditingController();
    final key = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar e-mail'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Digite o código de 8 dígitos enviado para $email.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: code,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  // Also handles pasted text such as "12 34 56 78".
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'Código de confirmação',
                ),
                validator: (value) => (value?.trim().length ?? 0) == 8
                    ? null
                    : 'Informe os 8 dígitos',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Confirmar depois'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => widget.service.verifyEmailCode(email, code.text),
      'E-mail confirmado. Sincronização conectada.',
    );
  }

  Future<bool> _run(
    Future<void> Function() action,
    String success,
  ) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
        setState(() {});
        _refreshLastSync();
      }
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível concluir: $error')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.service.isConfigured) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('Supabase não configurado'),
          subtitle: Text(
            'Compile com SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY.',
          ),
        ),
      );
    }
    final user = widget.service.currentUser;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                user == null ? Icons.cloud_off_outlined : Icons.cloud_done,
                color: user == null ? null : context.colors.primary,
              ),
              title: Text(user?.email ?? 'Conecte sua conta'),
              subtitle: Text(
                user == null
                    ? 'Entre para sincronizar seus dispositivos.'
                    : 'Android e computador usam o mesmo backup.',
              ),
              trailing: user == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(
                          onPressed: _busy ? null : _authenticate,
                          child: const Text('Entrar'),
                        ),
                      ],
                    )
                  : TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              widget.service.signOut, 'Conta desconectada.'),
                      child: const Text('Sair'),
                    ),
            ),
            if (user == null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : _resendConfirmation,
                  icon: const Icon(Icons.mark_email_unread_outlined),
                  label: const Text('Reenviar confirmação'),
                ),
              ),
            if (user != null) ...[
              const Divider(),
              FutureBuilder<DateTime?>(
                future: _lastSync,
                builder: (context, snapshot) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('Última sincronização'),
                  subtitle: Text(
                    snapshot.data == null
                        ? 'Ainda não sincronizado'
                        : DateFormat(
                            'dd/MM/yyyy HH:mm',
                            'pt_BR',
                          ).format(snapshot.data!.toLocal()),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await widget.service.synchronize();
                                widget.onDataChanged();
                              }, 'Dispositivos sincronizados.'),
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Sincronizar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await widget.service.restoreBackup();
                                widget.onDataChanged();
                              }, 'Backup restaurado neste dispositivo.'),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Restaurar'),
                    ),
                  ),
                ],
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
