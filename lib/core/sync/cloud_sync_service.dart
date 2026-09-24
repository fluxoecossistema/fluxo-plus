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

  /// Não há nada neste aparelho para enviar e a conta ainda não tem backup.
  nothingToSend,

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
    this.cloudExists,
    this.cloudUpdatedAt,
    this.accountEmail,
  });

  final SyncConflictReason reason;
  final SnapshotCounts local;

  /// Nulo quando o conteúdo do backup não pôde ser lido.
  final SnapshotCounts? cloud;

  /// `true`/`false` quando dá para afirmar se a conta tem backup; `null`
  /// quando não foi possível consultar agora.
  final bool? cloudExists;
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

  const SyncOutcome.nothingToSend() : this._(SyncStatus.nothingToSend);

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
    this.undoAvailableAt,
  });

  final String? accountEmail;
  final DateTime? lastBackupAt;
  final String? errorMessage;
  final DateTime? errorAt;
  final bool pendingConflict;

  /// Momento da cópia guardada antes da última restauração, quando existe.
  final DateTime? undoAvailableAt;

  bool get canUndoRestore => undoAvailableAt != null;
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

  /// Momento dessa cópia. Serve de indicador barato de que ela existe.
  static const keyPreRestoreAt = 'pre_restore_at';

  /// Quando o usuário pediu para decidir o conflito depois.
  static const keyConflictSnoozed = 'sync_conflict_snoozed_at';

  static const confirmationRedirect =
      'https://github.com/fluxoecossistema/fluxo-plus';

  final LocalBackupStore _store;
  final CloudBackupGateway? _gateway;
  final SupabaseClient? _client;
  final SyncPlanner _planner;
  final DateTime Function() _clock;

  /// Quanto tempo a pergunta automática fica quieta depois de "decidir depois".
  static const _snoozeDuration = Duration(hours: 24);

  /// Fila das operações de backup: uma de cada vez, na ordem em que chegaram.
  Future<void> _queue = Future<void>.value();

  bool get isConfigured => _gateway != null;

  bool get isSignedIn => _gateway?.currentUserId != null;

  String? get accountEmail => _gateway?.currentUserEmail;

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
  ///
  /// [timeout] limita apenas a espera de quem chamou; a operação continua na
  /// fila até terminar, para não deixar nuvem e aparelho em estados
  /// diferentes.
  Future<SyncOutcome> synchronize({
    required bool interactive,
    Duration? timeout,
  }) =>
      _enqueue(
        () => _synchronize(interactive: interactive),
        timeout: timeout,
      );

  /// Backup pedido pelo usuário.
  ///
  /// Se o backup da nuvem estiver à frente deste aparelho, a escolha volta
  /// para o usuário em vez de apagar o que está lá.
  Future<SyncOutcome> uploadBackupNow() => _enqueue(_uploadBackupNow);

  /// Substitui os dados deste aparelho pelo backup, guardando antes uma cópia
  /// para o "Desfazer".
  Future<SyncOutcome> restoreFromCloud() =>
      _enqueue(() => _restore(replaceUndoCopy: true));

  /// Resolve o conflito mantendo o que está neste aparelho.
  Future<SyncOutcome> keepThisDevice() =>
      _enqueue(() async => _upload(await _store.exportSnapshot()));

  /// Resolve o conflito trazendo o backup da nuvem.
  Future<SyncOutcome> useCloudVersion() => restoreFromCloud();

  /// Devolve os dados que existiam antes da última restauração.
  Future<SyncOutcome> undoLastRestore() =>
      _enqueue(_undoLastRestore, requiresAccount: false);

  /// Conflito à espera de uma escolha do usuário, se houver.
  Future<SyncConflictInfo?> pendingConflict({bool ignoreSnooze = false}) async {
    if (!isSignedIn) return null;
    final stored = await _store.readSetting(keyPendingConflict);
    if (stored == null) return null;
    final reason = SyncConflictReason.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => SyncConflictReason.bothChanged,
    );
    if (!ignoreSnooze && await _isSnoozed(reason)) return null;
    return _describeConflict(reason);
  }

  /// O usuário pediu para decidir depois e o motivo continua o mesmo.
  Future<bool> _isSnoozed(SyncConflictReason reason) async {
    final raw = await _store.readSetting(keyConflictSnoozed);
    if (raw == null) return false;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (data['reason'] != reason.name) return false;
      final at = DateTime.tryParse(data['at'] as String? ?? '');
      if (at == null) return false;
      return _clock().toUtc().difference(at.toUtc()) < _snoozeDuration;
    } catch (_) {
      return false;
    }
  }

  /// Guarda que o usuário preferiu decidir depois: a pergunta automática fica
  /// quieta por [_snoozeDuration], mas o aviso continua em Configurações e o
  /// botão "Resolver" continua funcionando.
  Future<void> snoozeConflict() async {
    final reason = await _store.readSetting(keyPendingConflict);
    if (reason == null) return;
    await _store.writeSetting(
      keyConflictSnoozed,
      jsonEncode({
        'reason': reason,
        'at': _clock().toUtc().toIso8601String(),
      }),
    );
  }

  /// Quando o backup da conta foi gravado, consultado agora na nuvem.
  /// Nulo quando a conta não tem backup ou quando não deu para consultar.
  Future<DateTime?> cloudBackupDate() async {
    try {
      final stamp = _normalize(await _gateway?.fetchUpdatedAt());
      return stamp == null ? null : DateTime.tryParse(stamp);
    } catch (_) {
      return null;
    }
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
      undoAvailableAt:
          DateTime.tryParse(await _store.readSetting(keyPreRestoreAt) ?? '')
              ?.toLocal(),
    );
  }

  /// Enfileira [action]: as operações de backup nunca correm em paralelo, para
  /// uma não gravar por cima da decisão da outra. Cada uma só olha o estado
  /// quando chega a sua vez.
  Future<SyncOutcome> _enqueue(
    Future<SyncOutcome> Function() action, {
    bool requiresAccount = true,
    Duration? timeout,
  }) {
    final completer = Completer<SyncOutcome>();
    _queue = _queue.then((_) async {
      SyncOutcome result;
      try {
        result = await _guarded(action, requiresAccount: requiresAccount);
      } catch (_) {
        // Uma falha nunca pode quebrar a fila das operações seguintes.
        result = const SyncOutcome.failed(
          'Não foi possível concluir o backup agora.',
        );
      }
      if (!completer.isCompleted) completer.complete(result);
    });
    final queued = completer.future;
    if (timeout == null) return queued;
    // Só a espera termina: a operação continua na fila e é ela quem registra
    // o próprio resultado, bom ou ruim.
    return queued.timeout(
      timeout,
      onTimeout: () => const SyncOutcome.skipped(SyncSkipReason.offline),
    );
  }

  /// Executa [action] sem nunca deixar uma exceção escapar: sem conta ou sem
  /// internet o aplicativo continua funcionando normalmente.
  Future<SyncOutcome> _guarded(
    Future<SyncOutcome> Function() action, {
    bool requiresAccount = true,
  }) async {
    if (requiresAccount) {
      final gateway = _gateway;
      if (gateway == null) {
        return const SyncOutcome.skipped(SyncSkipReason.notConfigured);
      }
      if (gateway.currentUserId == null) {
        return const SyncOutcome.skipped(SyncSkipReason.notSignedIn);
      }
    }
    try {
      return await action();
    } catch (error) {
      return _recordFailure(error);
    }
  }

  Future<SyncOutcome> _synchronize({required bool interactive}) async {
    final situation = await _situation();
    switch (situation.plan.action) {
      case SyncAction.nothing:
        return _recordNothing(situation);
      case SyncAction.uploadLocal:
        return _upload(situation.local);
      case SyncAction.restoreCloud:
        return _restore(backup: situation.backup, replaceUndoCopy: false);
      case SyncAction.conflict:
        return _conflict(situation.plan.reason!, interactive: interactive);
    }
  }

  Future<SyncOutcome> _uploadBackupNow() async {
    final situation = await _situation();
    switch (situation.plan.action) {
      case SyncAction.uploadLocal:
        return _upload(situation.local);
      case SyncAction.nothing:
        return _recordNothing(situation);
      case SyncAction.restoreCloud:
        // A escolha volta para o usuário agora, mas isso não é um conflito
        // guardado: o backup automático continua liberado.
        return _conflict(
          SyncConflictReason.cloudIsNewer,
          interactive: true,
          persist: false,
        );
      case SyncAction.conflict:
        return _conflict(situation.plan.reason!, interactive: true);
    }
  }

  /// Nada a fazer: ainda assim vale registrar a que conta este aparelho está
  /// ligado, para uma troca de conta não virar conflito falso depois.
  Future<SyncOutcome> _recordNothing(_Situation situation) async {
    if (situation.cloudUpdatedAt != null) {
      await _recordSuccess(
        cloudUpdatedAt: situation.cloudUpdatedAt!,
        localHash: situation.localHash,
      );
      return SyncOutcome.alreadyInSync(
        at: DateTime.tryParse(situation.cloudUpdatedAt!),
      );
    }
    await _linkWithoutBackup(situation.localHash);
    return const SyncOutcome.nothingToSend();
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
    return SyncOutcome.uploaded(DateTime.tryParse(stamp) ?? _clock());
  }

  Future<SyncOutcome> _restore({
    CloudBackup? backup,
    required bool replaceUndoCopy,
  }) async {
    final cloud = backup ?? await _gateway!.fetchBackup();
    if (cloud == null) {
      return _failWith('Ainda não há backup nesta conta.');
    }
    await _saveUndoCopy(replaceExisting: replaceUndoCopy);
    await _store.restoreSnapshot(cloud.payload);
    final stamp = _normalize(cloud.updatedAt)!;
    await _recordSuccess(
      cloudUpdatedAt: stamp,
      localHash: snapshotHash(await _store.exportSnapshot()),
    );
    return SyncOutcome.restored(DateTime.tryParse(stamp) ?? _clock());
  }

  /// Guarda os dados atuais e as marcas da sincronização antes de substituir
  /// tudo. Só uma restauração pedida pelo usuário troca a cópia existente:
  /// qualquer restauração vinda de uma sincronização mantém a mais antiga, que
  /// é a que o usuário pode querer de volta.
  Future<void> _saveUndoCopy({required bool replaceExisting}) async {
    if (!replaceExisting && await _store.readSetting(keyPreRestoreAt) != null) {
      return;
    }
    final at = _clock().toUtc().toIso8601String();
    await _store.writeSetting(
      keyPreRestoreSnapshot,
      jsonEncode({
        'at': at,
        'snapshot': await _store.exportSnapshot(),
        'state': {
          'userId': await _store.readSetting(keyUserId),
          'cloudUpdatedAt': await _store.readSetting(keyCloudUpdatedAt),
          'localHash': await _store.readSetting(keyLocalHash),
          'lastBackupAt': await _store.readSetting(keyLastBackupAt),
        },
      }),
    );
    await _store.writeSetting(keyPreRestoreAt, at);
  }

  Future<SyncOutcome> _undoLastRestore() async {
    final stored = await _store.readSetting(keyPreRestoreSnapshot);
    if (stored == null) {
      return const SyncOutcome.failed(
        'Não há restauração recente para desfazer.',
      );
    }
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(stored) as Map);
      // Formato antigo: o valor guardado era só o snapshot.
      final snapshot = decoded['snapshot'] is Map
          ? Map<String, dynamic>.from(decoded['snapshot'] as Map)
          : decoded;
      final state = decoded['state'] is Map
          ? Map<String, dynamic>.from(decoded['state'] as Map)
          : const <String, dynamic>{};
      await _store.restoreSnapshot(snapshot);
      // As marcas voltam ao que eram antes da restauração: a próxima decisão é
      // a mesma de antes, e não o contrário dela.
      await _rewindSetting(keyUserId, state['userId'] as String?);
      await _rewindSetting(
        keyCloudUpdatedAt,
        state['cloudUpdatedAt'] as String?,
      );
      await _rewindSetting(keyLocalHash, state['localHash'] as String?);
      await _rewindSetting(keyLastBackupAt, state['lastBackupAt'] as String?);
      await _store.removeSetting(keyPreRestoreSnapshot);
      await _store.removeSetting(keyPreRestoreAt);
      return SyncOutcome.restored(_clock());
    } catch (_) {
      return _failWith('Não foi possível desfazer a restauração.');
    }
  }

  Future<void> _rewindSetting(String key, String? value) => value == null
      ? _store.removeSetting(key)
      : _store.writeSetting(key, value);

  Future<SyncOutcome> _conflict(
    SyncConflictReason reason, {
    required bool interactive,
    bool persist = true,
  }) async {
    if (persist) await _store.writeSetting(keyPendingConflict, reason.name);
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
    bool? exists;
    try {
      cloud = await _gateway?.fetchBackup();
      exists = cloud != null;
    } catch (_) {
      // Sem internet dá para mostrar pelo menos o lado deste aparelho, sem
      // afirmar que a conta está sem backup.
      cloud = null;
      exists = null;
    }
    return SyncConflictInfo(
      reason: reason,
      local: local,
      cloud: cloud == null ? null : SnapshotCounts.fromSnapshot(cloud.payload),
      cloudExists: exists,
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
    await _store.removeSetting(keyConflictSnoozed);
  }

  /// A conta ainda não tem backup: guarda só o vínculo e o estado local.
  Future<void> _linkWithoutBackup(String localHash) async {
    await _store.writeSetting(keyUserId, _gateway!.currentUserId!);
    await _store.writeSetting(keyLocalHash, localHash);
    await _store.removeSetting(keyCloudUpdatedAt);
    await _store.removeSetting(keyLastBackupAt);
    await _store.removeSetting(keyLastError);
    await _store.removeSetting(keyPendingConflict);
    await _store.removeSetting(keyConflictSnoozed);
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
