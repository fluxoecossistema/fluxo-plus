import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/sync/cloud_sync_service.dart';
import '../../../core/sync/sync_planner.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';

/// O que o usuário decidiu quando as duas versões não coincidem.
enum SyncConflictChoice { useCloud, keepDevice, later }

/// Evita duas perguntas ao mesmo tempo: a tela de configurações e a volta do
/// aplicativo ao primeiro plano podem pedir a mesma decisão.
bool _conflictDialogOpen = false;

/// Libera a trava entre testes de widget, onde a tela é descartada antes de a
/// escolha terminar. Em produção a trava é sempre liberada ao fim da pergunta.
@visibleForTesting
void resetSyncConflictDialogGuard() => _conflictDialogOpen = false;

/// Pergunta ao usuário qual versão manter. Nunca decide sozinha.
Future<SyncConflictChoice?> showSyncConflictDialog(
  BuildContext context,
  SyncConflictInfo info,
) async {
  if (_conflictDialogOpen) return null;
  _conflictDialogOpen = true;
  try {
    final choice = await showDialog<SyncConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SyncConflictDialog(info: info),
    );
    if (choice == null) return null;
    if (!context.mounted) return null;
    switch (choice) {
      case SyncConflictChoice.useCloud:
        final confirmed = await _confirm(
          context,
          title: 'Usar os dados da nuvem?',
          message: info.cloudUpdatedAt == null
              ? 'Os dados deste aparelho serão substituídos pelo backup da '
                  'sua conta. Dá para desfazer logo em seguida, aqui em '
                  'Configurações.'
              : 'Os dados deste aparelho serão substituídos pelo backup de '
                  '${AppFormatters.dateTime(info.cloudUpdatedAt!)}. Dá para '
                  'desfazer logo em seguida, aqui em Configurações.',
          confirmLabel: 'Usar o backup',
        );
        return confirmed ? SyncConflictChoice.useCloud : null;
      case SyncConflictChoice.keepDevice:
        final confirmed = await _confirm(
          context,
          title: 'Manter os dados deste aparelho?',
          message: 'O backup na nuvem será substituído pelos dados deste '
              'aparelho. A versão que está na nuvem hoje não poderá ser '
              'recuperada.',
          confirmLabel: 'Manter estes dados',
        );
        return confirmed ? SyncConflictChoice.keepDevice : null;
      case SyncConflictChoice.later:
        return SyncConflictChoice.later;
    }
  } finally {
    _conflictDialogOpen = false;
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

String _conflictExplanation(SyncConflictReason reason) {
  return switch (reason) {
    SyncConflictReason.differentAccount =>
      'Este aparelho estava conectado a outra conta e tem dados que não '
          'fazem parte do backup desta conta.',
    SyncConflictReason.firstSync =>
      'Esta conta já tinha um backup e este aparelho já tinha dados. As duas '
          'versões são diferentes.',
    SyncConflictReason.bothChanged =>
      'Seus dados mudaram aqui e em outro aparelho depois do último backup.',
    SyncConflictReason.cloudIsNewer =>
      'O backup na nuvem é mais recente do que os dados deste aparelho.',
  };
}

String _countsSummary(SnapshotCounts counts) {
  String plural(int value, String singular, String many) =>
      '$value ${value == 1 ? singular : many}';
  return '${plural(counts.transactions, 'transação', 'transações')} · '
      '${plural(counts.accounts, 'conta', 'contas')} · '
      '${plural(counts.goals, 'meta', 'metas')}';
}

class _SyncConflictDialog extends StatelessWidget {
  const _SyncConflictDialog({required this.info});

  final SyncConflictInfo info;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Escolha qual versão manter'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_conflictExplanation(info.reason)),
            const SizedBox(height: 16),
            _SideSummary(
              icon: Icons.cloud_outlined,
              title: 'Na nuvem',
              detail: switch (info.cloudExists) {
                false => 'Esta conta ainda não tem backup',
                _ when info.cloudUpdatedAt == null => 'Backup da sua conta',
                _ => 'Backup de '
                    '${AppFormatters.dateTime(info.cloudUpdatedAt!)}',
              },
              summary: switch (info.cloudExists) {
                false => 'Não há nada para trazer para este aparelho.',
                _ when info.cloud == null =>
                  'Não foi possível ler o conteúdo agora.',
                _ => _countsSummary(info.cloud!),
              },
            ),
            const SizedBox(height: 10),
            _SideSummary(
              icon: Icons.phone_iphone_rounded,
              title: 'Neste aparelho',
              detail: 'Como está agora',
              summary: _countsSummary(info.local),
            ),
            const SizedBox(height: 14),
            Text(
              'Nada é alterado até você escolher.',
              style: TextStyle(color: context.colors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, SyncConflictChoice.later),
          child: const Text('Decidir depois'),
        ),
        OutlinedButton(
          onPressed: () =>
              Navigator.pop(context, SyncConflictChoice.keepDevice),
          child: const Text('Manter os dados deste aparelho'),
        ),
        // Sem backup na conta não há versão da nuvem para escolher.
        if (info.cloudExists != false)
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, SyncConflictChoice.useCloud),
            child: const Text('Usar os dados da nuvem'),
          ),
      ],
    );
  }
}

class _SideSummary extends StatelessWidget {
  const _SideSummary({
    required this.icon,
    required this.title,
    required this.detail,
    required this.summary,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(detail),
                const SizedBox(height: 4),
                Text(summary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Painel de backup da tela de configurações.
class CloudBackupPanel extends StatefulWidget {
  const CloudBackupPanel({
    super.key,
    required this.service,
    required this.onDataChanged,
  });

  final CloudSyncService service;

  /// Avisa a tela inicial quando os dados deste aparelho mudaram.
  final VoidCallback onDataChanged;

  @override
  State<CloudBackupPanel> createState() => _CloudBackupPanelState();
}

class _CloudBackupPanelState extends State<CloudBackupPanel> {
  bool _busy = false;
  late Future<BackupStatus> _status;

  @override
  void initState() {
    super.initState();
    _status = widget.service.status();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askIfPending());
  }

  Future<void> _askIfPending() async {
    if (!mounted || !widget.service.isSignedIn) return;
    final status = await widget.service.status();
    if (!mounted || !status.pendingConflict) return;
    // Quem escolheu "decidir depois" não é perguntado de novo sozinho.
    await _resolveConflict(ignoreSnooze: false);
  }

  void _refresh() {
    if (mounted) setState(() => _status = widget.service.status());
  }

  Future<void> _resolveConflict({
    SyncConflictInfo? known,
    bool ignoreSnooze = true,
  }) async {
    final info = known ??
        await widget.service.pendingConflict(ignoreSnooze: ignoreSnooze);
    if (!mounted || info == null) {
      _refresh();
      return;
    }
    final choice = await showSyncConflictDialog(context, info);
    if (choice == SyncConflictChoice.later) {
      await widget.service.snoozeConflict();
    }
    if (!mounted || choice == null || choice == SyncConflictChoice.later) {
      _refresh();
      return;
    }
    await _run(
      choice == SyncConflictChoice.useCloud
          ? widget.service.useCloudVersion
          : widget.service.keepThisDevice,
    );
  }

  /// Executa uma ação de backup e conta ao usuário o que aconteceu.
  Future<void> _run(Future<SyncOutcome> Function() action) async {
    setState(() => _busy = true);
    try {
      final outcome = await action();
      if (!mounted) return;
      if (outcome.changedData) widget.onDataChanged();
      if (outcome.isConflict) {
        _refresh();
        await _resolveConflict(known: outcome.conflict);
        return;
      }
      _message(_outcomeMessage(outcome));
      _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _outcomeMessage(SyncOutcome outcome) {
    return switch (outcome.status) {
      SyncStatus.uploaded => 'Backup enviado para a nuvem.',
      SyncStatus.restored => 'Os dados do backup estão neste aparelho.',
      SyncStatus.alreadyInSync => 'Seu backup já está em dia.',
      SyncStatus.nothingToSend => 'Ainda não há nada para enviar — seu backup '
          'começa quando você registrar algo.',
      SyncStatus.conflict => 'Escolha qual versão manter.',
      SyncStatus.failed =>
        outcome.message ?? 'Não foi possível concluir o backup agora.',
      SyncStatus.skipped => switch (outcome.skipReason) {
          SyncSkipReason.offline =>
            'Sem conexão agora. O backup será feito quando a internet voltar.',
          SyncSkipReason.notSignedIn => 'Entre na sua conta para fazer backup.',
          _ => 'Backup na nuvem indisponível nesta versão do aplicativo.',
        },
    };
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Entrada e criação de conta, com preenchimento automático do aparelho.
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
    final succeeded = await _auth(
      () => createAccount
          ? widget.service.signUp(accountEmail, password.text, name: name.text)
          : widget.service.signIn(accountEmail, password.text),
      createAccount
          ? 'Código de confirmação enviado por e-mail.'
          : 'Conta conectada.',
    );
    if (!mounted || !succeeded) return;
    if (createAccount) {
      await _confirmEmailCode(accountEmail);
    } else {
      await _run(() => widget.service.synchronize(interactive: true));
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
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enableSuggestions: false,
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
    final succeeded = await _auth(
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
    final succeeded = await _auth(
      () => widget.service.verifyEmailCode(email, code.text),
      'E-mail confirmado.',
    );
    if (succeeded && mounted) {
      await _run(() => widget.service.synchronize(interactive: true));
    }
  }

  /// Ações de conta continuam avisando o usuário com mensagens curtas.
  Future<bool> _auth(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      _message(success);
      _refresh();
      return true;
    } on CloudSyncException catch (error) {
      _message(error.message);
      return false;
    } catch (_) {
      _message('Não foi possível concluir. Tente novamente.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRestore() async {
    // A data vem da nuvem agora: a última que este aparelho viu pode estar
    // velha e descrever outro backup.
    setState(() => _busy = true);
    final cloudDate = await widget.service.cloudBackupDate();
    if (!mounted) return;
    setState(() => _busy = false);
    final confirmed = await _confirm(
      context,
      title: 'Restaurar o backup?',
      message: cloudDate == null
          ? 'Os dados deste aparelho serão substituídos pelo backup mais '
              'recente da nuvem. Dá para desfazer logo em seguida, aqui em '
              'Configurações.'
          : 'Os dados deste aparelho serão substituídos pelo backup de '
              '${AppFormatters.dateTime(cloudDate)}. Dá para '
              'desfazer logo em seguida, aqui em Configurações.',
      confirmLabel: 'Restaurar',
    );
    if (!confirmed || !mounted) return;
    await _run(widget.service.restoreFromCloud);
  }

  Future<void> _confirmUndo() async {
    final confirmed = await _confirm(
      context,
      title: 'Desfazer a restauração?',
      message: 'Os dados que estavam neste aparelho antes da restauração '
          'voltam para o lugar. O backup na nuvem não muda agora.',
      confirmLabel: 'Desfazer',
    );
    if (!confirmed || !mounted) return;
    await _run(widget.service.undoLastRestore);
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await _confirm(
      context,
      title: 'Sair da conta?',
      message: 'Seus dados continuam neste aparelho e o backup continua '
          'guardado na nuvem. Você pode entrar de novo quando quiser.',
      confirmLabel: 'Sair',
    );
    if (!confirmed || !mounted) return;
    await _auth(widget.service.signOut, 'Conta desconectada.');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.service.isConfigured) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('Backup na nuvem'),
          subtitle: Text(
            'Backup na nuvem indisponível nesta versão do aplicativo.',
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<BackupStatus>(
          future: _status,
          builder: (context, snapshot) {
            final status = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.service.isSignedIn)
                  ..._signedOut()
                else
                  ..._signedIn(status ?? const BackupStatus()),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _signedOut() {
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cloud_off_outlined),
        title: const Text('Backup na nuvem'),
        subtitle: const Text(
          'Guarde uma cópia dos seus dados na sua conta. Em outro aparelho, '
          'você escolhe qual versão manter.',
        ),
      ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _busy ? null : _authenticate,
        icon: const Icon(Icons.login_rounded),
        label: const Text('Entrar / Criar conta'),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _busy ? null : _resendConfirmation,
          icon: const Icon(Icons.mark_email_unread_outlined),
          label: const Text('Reenviar confirmação'),
        ),
      ),
    ];
  }

  List<Widget> _signedIn(BackupStatus status) {
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.cloud_done_rounded, color: context.colors.primary),
        title: Text(status.accountEmail ?? 'Conta conectada'),
        subtitle: Text(
          status.lastBackupAt == null
              ? 'Ainda não há backup'
              : 'Último backup: ${AppFormatters.dateTime(status.lastBackupAt!)}',
        ),
      ),
      if (status.errorMessage != null)
        _Notice(
          color: context.colors.expense,
          icon: Icons.error_outline_rounded,
          message: status.errorAt == null
              ? status.errorMessage!
              : '${status.errorMessage!} '
                  '(${AppFormatters.dateTime(status.errorAt!)})',
          actionLabel: 'Tentar de novo',
          onPressed: _busy
              ? null
              : () => _run(() => widget.service.synchronize(interactive: true)),
        ),
      if (status.pendingConflict)
        _Notice(
          color: context.colors.warning,
          icon: Icons.warning_amber_rounded,
          message: 'O backup está pausado até você escolher qual versão '
              'manter.',
          actionLabel: 'Resolver',
          onPressed: _busy ? null : () => _resolveConflict(),
        ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed:
                  _busy ? null : () => _run(widget.service.uploadBackupNow),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Fazer backup agora'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _confirmRestore,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Restaurar do backup'),
            ),
          ),
        ],
      ),
      if (status.undoAvailableAt != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _confirmUndo,
            icon: const Icon(Icons.undo_rounded),
            label: Text(
              'Desfazer a restauração de '
              '${AppFormatters.shortDateTime(status.undoAvailableAt!)}',
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _busy ? null : _confirmSignOut,
          child: const Text('Sair da conta'),
        ),
      ),
    ];
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.color,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
