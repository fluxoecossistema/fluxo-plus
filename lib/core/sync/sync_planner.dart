/// Decisão de sincronização, sem nenhum acesso a disco ou rede.
///
/// Toda a política de "quem sobrescreve quem" mora aqui para poder ser testada
/// exaustivamente. O orquestrador ([CloudSyncService]) apenas executa o plano.
library;

/// O que fazer com os dados deste aparelho e com o backup da conta.
enum SyncAction {
  /// Nada a fazer: os dois lados já representam a mesma informação.
  nothing,

  /// Enviar os dados deste aparelho para a nuvem.
  uploadLocal,

  /// Trazer o backup da nuvem para este aparelho.
  restoreCloud,

  /// Só o usuário pode decidir: nada é alterado automaticamente.
  conflict,
}

/// Por que a decisão precisa do usuário.
enum SyncConflictReason {
  /// O aparelho estava ligado a outra conta e já tem dados criados aqui.
  differentAccount,

  /// Primeira sincronização desta conta neste aparelho, com dados dos dois
  /// lados que não coincidem.
  firstSync,

  /// Houve mudança neste aparelho e em outro aparelho desde a última
  /// sincronização.
  bothChanged,
}

/// Resultado do [SyncPlanner].
class SyncPlan {
  const SyncPlan._(this.action, [this.reason]);

  const SyncPlan.nothing() : this._(SyncAction.nothing);

  const SyncPlan.uploadLocal() : this._(SyncAction.uploadLocal);

  const SyncPlan.restoreCloud() : this._(SyncAction.restoreCloud);

  const SyncPlan.conflict(SyncConflictReason reason)
      : this._(SyncAction.conflict, reason);

  final SyncAction action;

  /// Preenchido apenas quando [action] é [SyncAction.conflict].
  final SyncConflictReason? reason;

  bool get isConflict => action == SyncAction.conflict;

  @override
  bool operator ==(Object other) =>
      other is SyncPlan && other.action == action && other.reason == reason;

  @override
  int get hashCode => Object.hash(action, reason);

  @override
  String toString() =>
      reason == null ? 'SyncPlan(${action.name})' : 'SyncPlan(${reason!.name})';
}

/// Decide o que fazer comparando o estado local, o backup da nuvem e o que
/// este aparelho viu na última sincronização bem-sucedida.
class SyncPlanner {
  const SyncPlanner();

  /// [cloudUpdatedAt] é nulo quando a conta ainda não tem backup.
  ///
  /// [localIsPristine] indica que nada foi criado neste aparelho: sem
  /// transações, sem metas e com as contas e categorias iniciais intactas.
  ///
  /// [cloudPayloadHash] só é informado quando o conteúdo do backup já foi
  /// baixado; sem ele, uma primeira sincronização com dados dos dois lados é
  /// sempre tratada como conflito.
  SyncPlan plan({
    required String currentUserId,
    required bool localIsPristine,
    required String localHash,
    String? cloudUpdatedAt,
    String? linkedUserId,
    String? lastCloudUpdatedAt,
    String? lastLocalHash,
    String? cloudPayloadHash,
  }) {
    // 1. Aparelho ligado a outra conta.
    if (linkedUserId != null && linkedUserId != currentUserId) {
      if (!localIsPristine) {
        return const SyncPlan.conflict(SyncConflictReason.differentAccount);
      }
      // Nada foi criado aqui: o vínculo antigo não representa dado nenhum.
      return plan(
        currentUserId: currentUserId,
        localIsPristine: localIsPristine,
        localHash: localHash,
        cloudUpdatedAt: cloudUpdatedAt,
      );
    }

    // 2. A conta ainda não tem backup.
    if (cloudUpdatedAt == null) {
      return localIsPristine
          ? const SyncPlan.nothing()
          : const SyncPlan.uploadLocal();
    }

    // 3. Existe backup e não há nada para perder neste aparelho.
    if (localIsPristine) return const SyncPlan.restoreCloud();

    // 4a. Aparelho já ligado a esta conta.
    if (linkedUserId == currentUserId) {
      final cloudUntouched = cloudUpdatedAt == lastCloudUpdatedAt;
      final localUntouched = localHash == lastLocalHash;
      if (cloudUntouched) {
        return localUntouched
            ? const SyncPlan.nothing()
            : const SyncPlan.uploadLocal();
      }
      return localUntouched
          ? const SyncPlan.restoreCloud()
          : const SyncPlan.conflict(SyncConflictReason.bothChanged);
    }

    // 4b. Primeira sincronização desta conta neste aparelho.
    return cloudPayloadHash != null && cloudPayloadHash == localHash
        ? const SyncPlan.nothing()
        : const SyncPlan.conflict(SyncConflictReason.firstSync);
  }
}
