import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_backup_gateway.dart';
import 'local_backup_store.dart';
import 'snapshot_hash.dart';
import 'sync_planner.dart';

/// Como terminou uma sincronização.
enum SyncStatus {
  /// Os dados deste aparelho foram copiados para a nuvem.
  uploaded,

  /// Os dados deste aparelho foram substituídos pelo backup.
  restored,

  /// Os dois lados já representavam a mesma informação.
  alreadyInSync,

  /// Só o usuário pode decidir; nada foi alterado.
  conflict,

  /// Não havia o que fazer agora (sem conta conectada ou sem internet).
  skipped,

  /// Algo deu errado; a mensagem fica guardada para a tela de configurações.
  failed,
}

/// Por que a sincronização não chegou a acontecer.
enum SyncSkipReason { notConfigured, notSignedIn, offline }

/// Quantidades usadas para o usuário comparar as duas versões.
class SnapshotCounts {
  const SnapshotCounts({
    required this.transactions,
    required this.accounts,
    required this.goals,
  });

  factory SnapshotCounts.fromSnapshot(Map<String, dynamic> snapshot) {
    int count(String table) =>
        snapshot[table] is List ? (snapshot[table] as List).length : 0;
    return SnapshotCounts(
      transactions: count('transactions'),
      accounts: count('accounts'),
      goals: count('goals'),
    );
  }

  final int transactions;
  final int accounts;
  final int goals;
}

/// Tudo o que a tela precisa para explicar um conflito ao usuário.
class SyncConflictInfo {
  const SyncConflictInfo({
    required this.reason,
    required this.local,
    this.cloud,
    this.cloudUpdatedAt,
    this.accountEmail,
  });

  final SyncConflictReason reason;
  final SnapshotCounts local;

  /// Nulo quando o conteúdo do backup não pôde ser lido.
  final SnapshotCounts? cloud;
  final DateTime? cloudUpdatedAt;
  final String? accountEmail;
}

/// Resultado de uma sincronização.
class SyncOutcome {
  const SyncOutcome._(
    this.status, {
    this.at,
    this.skipReason,
    this.conflictReason,
    this.conflict,
    this.message,
  });

  const SyncOutcome.uploaded(DateTime at) : this._(SyncStatus.uploaded, at: at);

  const SyncOutcome.restored(DateTime at) : this._(SyncStatus.restored, at: at);

  const SyncOutcome.alreadyInSync({DateTime? at})
      : this._(SyncStatus.alreadyInSync, at: at);

  const SyncOutcome.conflict(SyncConflictReason reason,
      {SyncConflictInfo? info})
      : this._(SyncStatus.conflict, conflictReason: reason, conflict: info);

  const SyncOutcome.skipped(SyncSkipReason reason)
      : this._(SyncStatus.skipped, skipReason: reason);

  const SyncOutcome.failed(String message)
      : this._(SyncStatus.failed, message: message);

  final SyncStatus status;

  /// Momento do backup envolvido, quando existe.
  final DateTime? at;
  final SyncSkipReason? skipReason;
  final SyncConflictReason? conflictReason;
  final SyncConflictInfo? conflict;

  /// Mensagem curta em português, apenas para [SyncStatus.failed].
  final String? message;

  /// `true` quando os dados deste aparelho ou o backup mudaram.
  bool get changedData =>
      status == SyncStatus.uploaded || status == SyncStatus.restored;

  bool get isConflict => status == SyncStatus.conflict;
}

/// Situação do backup, para a tela de configurações.
class BackupStatus {
  const BackupStatus({
    this.accountEmail,
    this.lastBackupAt,
    this.errorMessage,
    this.errorAt,
    this.pendingConflict = false,
    this.canUndoRestore = false,
  });

  final String? accountEmail;
  final DateTime? lastBackupAt;
  final String? errorMessage;
  final DateTime? errorAt;
  final bool pendingConflict;
  final bool canUndoRestore;
}

/// Fotografia do momento usada para decidir e executar o plano.
class _Situation {
  const _Situation({
    required this.plan,
    required this.local,
    required this.localHash,
    required this.cloudUpdatedAt,
    required this.backup,
  });

  final SyncPlan plan;
  final Map<String, dynamic> local;
  final String localHash;
  final String? cloudUpdatedAt;
  final CloudBackup? backup;
}

class CloudSyncException implements Exception {
  const CloudSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Orquestra o backup na nuvem: consulta o [SyncPlanner], executa o plano e
/// guarda no próprio aparelho o que foi visto na última sincronização.
///
/// Nenhum caminho automático apaga dados sem o plano autorizar, e nenhum
/// caminho de segundo plano lança exceção: falhas viram registro visível em
/// Configurações.
class CloudSyncService {
  CloudSyncService({
    required LocalBackupStore store,
    CloudBackupGateway? gateway,
    SupabaseClient? client,
    SyncPlanner planner = const SyncPlanner(),
    DateTime Function() clock = DateTime.now,
  })  : _store = store,
        _gateway = gateway,
        _client = client,
        _planner = planner,
        _clock = clock;

  /// Conta à qual este aparelho está ligado.
  static const keyUserId = 'sync_user_id';

  /// Momento do backup na nuvem visto na última sincronização.
  static const keyCloudUpdatedAt = 'sync_cloud_updated_at';

  /// Impressão digital dos dados locais na última sincronização.
  static const keyLocalHash = 'sync_local_hash';
  static const keyLastBackupAt = 'last_backup_at';
  static const keyLastError = 'last_backup_error';
  static const keyPendingConflict = 'sync_pending_conflict';

  /// Cópia dos dados locais feita imediatamente antes da última restauração.
  static const keyPreRestoreSnapshot = 'pre_restore_snapshot';

  static const confirmationRedirect =
      'https://github.com/fluxoecossistema/fluxo-plus';

  final LocalBackupStore _store;
  final CloudBackupGateway? _gateway;
  final SupabaseClient? _client;
  final SyncPlanner _planner;
  final DateTime Function() _clock;

  bool get isConfigured => _gateway != null;

  bool get isSignedIn => _gateway?.currentUserId != null;

  String? get accountEmail => _gateway?.currentUserEmail;

  Stream<AuthState>? get authChanges => _client?.auth.onAuthStateChange;

  String? get displayName {
    final metadata = _client?.auth.currentUser?.userMetadata;
    final value = metadata?['full_name'] ?? metadata?['name'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    final emailName = accountEmail?.split('@').first.replaceAll(
          RegExp(r'[._-]+'),
          ' ',
        );
    if (emailName == null || emailName.trim().isEmpty) return null;
    return emailName
        .trim()
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Future<void> signIn(String email, String password) async {
    final client = _requireClient();
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      throw CloudSyncException(_friendlyAuthMessage(error.message));
    } catch (_) {
      throw const CloudSyncException(
        'Não foi possível conectar. Verifique sua internet e tente novamente.',
      );
    }
  }

  Future<void> signUp(String email, String password, {String? name}) async {
    final client = _requireClient();
    try {
      await client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: confirmationRedirect,
        data: name == null || name.trim().isEmpty
            ? null
            : {'full_name': name.trim()},
      );
    } on AuthException catch (error) {
      throw CloudSyncException(_friendlyAuthMessage(error.message));
    } catch (_) {
      throw const CloudSyncException(
        'Não foi possível criar a conta. Verifique sua internet.',
      );
    }
  }

  Future<void> resendConfirmation(String email) async {
    final client = _requireClient();
    try {
      await client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: confirmationRedirect,
      );
    } on AuthException catch (error) {
      throw CloudSyncException(_friendlyAuthMessage(error.message));
    } catch (_) {
      throw const CloudSyncException(
        'Não foi possível reenviar. Verifique sua internet.',
      );
    }
  }

  Future<void> verifyEmailCode(String email, String code) async {
    final client = _requireClient();
    try {
      await client.auth.verifyOTP(
        email: email,
        token: code.trim(),
        type: OtpType.signup,
      );
    } on AuthException catch (error) {
      throw CloudSyncException(_friendlyAuthMessage(error.message));
    } catch (_) {
      throw const CloudSyncException(
        'Não foi possível validar o código. Verifique sua internet.',
      );
    }
  }

  /// Sai da conta. Os dados continuam neste aparelho e o backup continua na
  /// nuvem; o vínculo guardado é mantido para reconhecer uma troca de conta.
  Future<void> signOut() async => _client?.auth.signOut();

  /// Decide e executa a sincronização.
  ///
  /// Com [interactive] falso (abertura, retomada e ida para segundo plano)
  /// nada é perguntado ao usuário: um conflito apenas fica marcado.
  Future<SyncOutcome> synchronize({
    required bool interactive,
    Duration? timeout,
  }) =>
      _guarded(
        () => _synchronize(interactive: interactive),
        timeout: timeout,
      );

  /// Backup pedido pelo usuário.
  ///
  /// Se o backup da nuvem estiver à frente deste aparelho, a escolha volta
  /// para o usuário em vez de apagar o que está lá.
  Future<SyncOutcome> uploadBackupNow() => _guarded(() async {
        final situation = await _situation();
        switch (situation.plan.action) {
          case SyncAction.uploadLocal:
            return _upload(situation.local);
          case SyncAction.nothing:
            if (situation.cloudUpdatedAt == null) {
              return _upload(situation.local);
            }
            await _recordSuccess(
              cloudUpdatedAt: situation.cloudUpdatedAt!,
              localHash: situation.localHash,
            );
            return SyncOutcome.alreadyInSync(
              at: DateTime.tryParse(situation.cloudUpdatedAt!),
            );
          case SyncAction.restoreCloud:
            return _conflict(
              SyncConflictReason.cloudIsNewer,
              interactive: true,
            );
          case SyncAction.conflict:
            return _conflict(situation.plan.reason!, interactive: true);
        }
      });

  /// Substitui os dados deste aparelho pelo backup, guardando antes uma cópia
  /// para o "Desfazer".
  Future<SyncOutcome> restoreFromCloud() => _guarded(_restore);

  /// Resolve o conflito mantendo o que está neste aparelho.
  Future<SyncOutcome> keepThisDevice() =>
      _guarded(() async => _upload(await _store.exportSnapshot()));

  /// Resolve o conflito trazendo o backup da nuvem.
  Future<SyncOutcome> useCloudVersion() => restoreFromCloud();

  /// Devolve os dados que existiam antes da última restauração.
  Future<SyncOutcome> undoLastRestore() async {
    try {
      final stored = await _store.readSetting(keyPreRestoreSnapshot);
      if (stored == null) {
        return const SyncOutcome.failed(
          'Não há restauração recente para desfazer.',
        );
      }
      await _store.restoreSnapshot(
        Map<String, dynamic>.from(jsonDecode(stored) as Map),
      );
      await _store.removeSetting(keyPreRestoreSnapshot);
      // A marca da última sincronização continua como estava de propósito:
      // assim o próximo backup reconhece que estes dados mudaram e os envia.
      return SyncOutcome.restored(_clock());
    } catch (error) {
      return _recordFailure(error);
    }
  }

  /// Conflito à espera de uma escolha do usuário, se houver.
  Future<SyncConflictInfo?> pendingConflict() async {
    if (!isSignedIn) return null;
    final stored = await _store.readSetting(keyPendingConflict);
    if (stored == null) return null;
    return _describeConflict(
      SyncConflictReason.values.firstWhere(
        (reason) => reason.name == stored,
        orElse: () => SyncConflictReason.bothChanged,
      ),
    );
  }

  /// Situação atual do backup para a tela de configurações.
  Future<BackupStatus> status() async {
    final rawError = await _store.readSetting(keyLastError);
    Map<String, dynamic>? error;
    if (rawError != null) {
      try {
        error = Map<String, dynamic>.from(jsonDecode(rawError) as Map);
      } catch (_) {
        error = null;
      }
    }
    final lastBackupAt = DateTime.tryParse(
      await _store.readSetting(keyLastBackupAt) ?? '',
    );
    return BackupStatus(
      accountEmail: accountEmail,
      lastBackupAt: lastBackupAt?.toLocal(),
      errorMessage: error?['message'] as String?,
      errorAt: DateTime.tryParse(error?['at'] as String? ?? '')?.toLocal(),
      pendingConflict: await _store.readSetting(keyPendingConflict) != null,
      canUndoRestore: await _store.readSetting(keyPreRestoreSnapshot) != null,
    );
  }

  /// Executa [action] sem nunca deixar uma exceção escapar: sem conta ou sem
  /// internet o aplicativo continua funcionando normalmente.
  Future<SyncOutcome> _guarded(
    Future<SyncOutcome> Function() action, {
    Duration? timeout,
  }) async {
    final gateway = _gateway;
    if (gateway == null) {
      return const SyncOutcome.skipped(SyncSkipReason.notConfigured);
    }
    if (gateway.currentUserId == null) {
      return const SyncOutcome.skipped(SyncSkipReason.notSignedIn);
    }
    try {
      final running = action();
      return await (timeout == null ? running : running.timeout(timeout));
    } catch (error) {
      return _recordFailure(error);
    }
  }

  Future<SyncOutcome> _synchronize({required bool interactive}) async {
    final situation = await _situation();
    switch (situation.plan.action) {
      case SyncAction.nothing:
        if (situation.cloudUpdatedAt != null) {
          await _recordSuccess(
            cloudUpdatedAt: situation.cloudUpdatedAt!,
            localHash: situation.localHash,
          );
        }
        return SyncOutcome.alreadyInSync(
          at: DateTime.tryParse(situation.cloudUpdatedAt ?? ''),
        );
      case SyncAction.uploadLocal:
        return _upload(situation.local);
      case SyncAction.restoreCloud:
        return _restore(backup: situation.backup);
      case SyncAction.conflict:
        return _conflict(situation.plan.reason!, interactive: interactive);
    }
  }

  Future<_Situation> _situation() async {
    final gateway = _gateway!;
    final userId = gateway.currentUserId!;
    final local = await _store.exportSnapshot();
    final localHash = snapshotHash(local);
    final pristine = await _store.isPristine();
    final linkedUserId = await _store.readSetting(keyUserId);
    final cloudUpdatedAt = _normalize(await gateway.fetchUpdatedAt());

    // O conteúdo do backup só é baixado quando pode evitar um conflito inútil:
    // primeira sincronização desta conta num aparelho que já tem dados.
    CloudBackup? backup;
    String? cloudPayloadHash;
    if (cloudUpdatedAt != null && !pristine && linkedUserId == null) {
      backup = await gateway.fetchBackup();
      if (backup != null) cloudPayloadHash = snapshotHash(backup.payload);
    }

    return _Situation(
      plan: _planner.plan(
        currentUserId: userId,
        localIsPristine: pristine,
        localHash: localHash,
        cloudUpdatedAt: cloudUpdatedAt,
        linkedUserId: linkedUserId,
        lastCloudUpdatedAt:
            _normalize(await _store.readSetting(keyCloudUpdatedAt)),
        lastLocalHash: await _store.readSetting(keyLocalHash),
        cloudPayloadHash: cloudPayloadHash,
      ),
      local: local,
      localHash: localHash,
      cloudUpdatedAt: cloudUpdatedAt,
      backup: backup,
    );
  }

  Future<SyncOutcome> _upload(Map<String, dynamic> snapshot) async {
    final stamp = _normalize(await _gateway!.upload(snapshot))!;
    await _recordSuccess(
      cloudUpdatedAt: stamp,
      localHash: snapshotHash(snapshot),
    );
    return SyncOutcome.uploaded(DateTime.parse(stamp));
  }

  Future<SyncOutcome> _restore({CloudBackup? backup}) async {
    final cloud = backup ?? await _gateway!.fetchBackup();
    if (cloud == null) {
      return _failWith('Ainda não há backup nesta conta.');
    }
    // A cópia de segurança é gravada antes de qualquer alteração.
    await _store.writeSetting(
      keyPreRestoreSnapshot,
      jsonEncode(await _store.exportSnapshot()),
    );
    await _store.restoreSnapshot(cloud.payload);
    final stamp = _normalize(cloud.updatedAt)!;
    await _recordSuccess(
      cloudUpdatedAt: stamp,
      localHash: snapshotHash(await _store.exportSnapshot()),
    );
    return SyncOutcome.restored(DateTime.parse(stamp));
  }

  Future<SyncOutcome> _conflict(
    SyncConflictReason reason, {
    required bool interactive,
  }) async {
    await _store.writeSetting(keyPendingConflict, reason.name);
    if (!interactive) return SyncOutcome.conflict(reason);
    return SyncOutcome.conflict(
      reason,
      info: await _describeConflict(reason),
    );
  }

  Future<SyncConflictInfo> _describeConflict(
    SyncConflictReason reason,
  ) async {
    final local = SnapshotCounts.fromSnapshot(await _store.exportSnapshot());
    CloudBackup? cloud;
    try {
      cloud = await _gateway?.fetchBackup();
    } catch (_) {
      // Sem internet dá para mostrar pelo menos o lado deste aparelho.
      cloud = null;
    }
    return SyncConflictInfo(
      reason: reason,
      local: local,
      cloud: cloud == null ? null : SnapshotCounts.fromSnapshot(cloud.payload),
      cloudUpdatedAt: cloud == null
          ? null
          : DateTime.tryParse(_normalize(cloud.updatedAt) ?? ''),
      accountEmail: accountEmail,
    );
  }

  Future<void> _recordSuccess({
    required String cloudUpdatedAt,
    required String localHash,
  }) async {
    await _store.writeSetting(keyUserId, _gateway!.currentUserId!);
    await _store.writeSetting(keyCloudUpdatedAt, cloudUpdatedAt);
    await _store.writeSetting(keyLocalHash, localHash);
    await _store.writeSetting(keyLastBackupAt, cloudUpdatedAt);
    await _store.removeSetting(keyLastError);
    await _store.removeSetting(keyPendingConflict);
  }

  Future<SyncOutcome> _failWith(String message) async {
    try {
      await _store.writeSetting(
        keyLastError,
        jsonEncode({
          'message': message,
          'at': _clock().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // Sem banco não há onde registrar, mas o erro não pode derrubar o app.
    }
    return SyncOutcome.failed(message);
  }

  Future<SyncOutcome> _recordFailure(Object error) async {
    final offline = _isNetworkError(error);
    final outcome = await _failWith(
      offline
          ? 'Sem conexão com a internet. O backup será feito mais tarde.'
          : _friendlyFailure(error),
    );
    return offline
        ? const SyncOutcome.skipped(SyncSkipReason.offline)
        : outcome;
  }

  bool _isNetworkError(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return true;
    }
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('clientexception') ||
        text.contains('connection') ||
        text.contains('timeout') ||
        text.contains('network');
  }

  String _friendlyFailure(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('jwt') ||
        text.contains('unauthorized') ||
        text.contains('not authenticated')) {
      return 'Entre na sua conta novamente para continuar o backup.';
    }
    if (text.contains('backup inválido') || text.contains('formatexception')) {
      return 'O backup da nuvem não pôde ser lido.';
    }
    return 'Não foi possível concluir o backup agora.';
  }

  /// Datas viram sempre o mesmo texto, venham do servidor ou daqui.
  String? _normalize(String? stamp) {
    if (stamp == null) return null;
    final parsed = DateTime.tryParse(stamp);
    return parsed == null ? stamp : parsed.toUtc().toIso8601String();
  }

  SupabaseClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const CloudSyncException(
        'Backup na nuvem indisponível nesta versão do aplicativo.',
      );
    }
    return client;
  }

  String _friendlyAuthMessage(String message) {
    final value = message.toLowerCase();
    if (value.contains('invalid login credentials')) {
      return 'E-mail ou senha incorretos.';
    }
    if (value.contains('email not confirmed')) {
      return 'Confirme o e-mail recebido antes de entrar.';
    }
    if (value.contains('already registered') ||
        value.contains('already been registered')) {
      return 'Este e-mail já possui uma conta.';
    }
    if (value.contains('rate limit')) {
      return 'Muitas tentativas. Aguarde alguns minutos e tente novamente.';
    }
    if (value.contains('token') &&
        (value.contains('expired') || value.contains('invalid'))) {
      return 'Código inválido ou expirado. Solicite um novo código.';
    }
    if (value.contains('password')) {
      return 'A senha não atende aos requisitos de segurança.';
    }
    return 'Não foi possível autenticar: $message';
  }
}
