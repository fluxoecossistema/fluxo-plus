import 'package:flutter_test/flutter_test.dart';
import 'package:fluxo_plus/core/sync/sync_planner.dart';

const _planner = SyncPlanner();

const _me = 'user-me';
const _other = 'user-other';

const _localHash = 'hash-local';
const _syncedHash = 'hash-sincronizado';
const _cloudSeen = '2026-09-20T10:00:00Z';
const _cloudNewer = '2026-09-21T18:30:00Z';

class _Case {
  const _Case(
    this.description, {
    required this.expected,
    this.localIsPristine = false,
    this.localHash = _localHash,
    this.cloudUpdatedAt,
    this.linkedUserId,
    this.lastCloudUpdatedAt,
    this.lastLocalHash,
    this.cloudPayloadHash,
  });

  final String description;
  final SyncPlan expected;
  final bool localIsPristine;
  final String localHash;
  final String? cloudUpdatedAt;
  final String? linkedUserId;
  final String? lastCloudUpdatedAt;
  final String? lastLocalHash;
  final String? cloudPayloadHash;

  SyncPlan run() => _planner.plan(
        currentUserId: _me,
        localIsPristine: localIsPristine,
        localHash: localHash,
        cloudUpdatedAt: cloudUpdatedAt,
        linkedUserId: linkedUserId,
        lastCloudUpdatedAt: lastCloudUpdatedAt,
        lastLocalHash: lastLocalHash,
        cloudPayloadHash: cloudPayloadHash,
      );
}

const _cases = <_Case>[
  // Regra 1 — aparelho ligado a outra conta.
  _Case(
    'outra conta com dados criados aqui vira conflito',
    linkedUserId: _other,
    cloudUpdatedAt: _cloudSeen,
    lastCloudUpdatedAt: _cloudSeen,
    lastLocalHash: _localHash,
    expected: SyncPlan.conflict(SyncConflictReason.differentAccount),
  ),
  _Case(
    'outra conta com dados aqui e sem backup na nuvem vira conflito',
    linkedUserId: _other,
    expected: SyncPlan.conflict(SyncConflictReason.differentAccount),
  ),
  _Case(
    'outra conta com hashes iguais ainda vira conflito',
    linkedUserId: _other,
    cloudUpdatedAt: _cloudSeen,
    cloudPayloadHash: _localHash,
    expected: SyncPlan.conflict(SyncConflictReason.differentAccount),
  ),
  _Case(
    'outra conta sem nada criado aqui: restaura o backup da conta atual',
    linkedUserId: _other,
    localIsPristine: true,
    cloudUpdatedAt: _cloudSeen,
    lastCloudUpdatedAt: _cloudSeen,
    lastLocalHash: _localHash,
    expected: SyncPlan.restoreCloud(),
  ),
  _Case(
    'outra conta sem nada criado aqui e sem backup: nada a fazer',
    linkedUserId: _other,
    localIsPristine: true,
    expected: SyncPlan.nothing(),
  ),

  // Regra 2 — a conta ainda não tem backup.
  _Case(
    'sem backup e sem nada criado aqui: nada a fazer',
    localIsPristine: true,
    expected: SyncPlan.nothing(),
  ),
  _Case(
    'sem backup e com dados aqui: envia para a nuvem',
    expected: SyncPlan.uploadLocal(),
  ),
  _Case(
    'sem backup, já ligado a esta conta e com dados aqui: envia',
    linkedUserId: _me,
    lastLocalHash: _syncedHash,
    lastCloudUpdatedAt: _cloudSeen,
    expected: SyncPlan.uploadLocal(),
  ),
  _Case(
    'sem backup, já ligado a esta conta e sem nada criado aqui: nada a fazer',
    linkedUserId: _me,
    localIsPristine: true,
    lastLocalHash: _syncedHash,
    lastCloudUpdatedAt: _cloudSeen,
    expected: SyncPlan.nothing(),
  ),

  // Regra 3 — aparelho zerado e backup existente.
  _Case(
    'aparelho zerado e nunca ligado: restaura o backup',
    localIsPristine: true,
    cloudUpdatedAt: _cloudSeen,
    expected: SyncPlan.restoreCloud(),
  ),
  _Case(
    'aparelho zerado já ligado a esta conta: restaura o backup',
    localIsPristine: true,
    linkedUserId: _me,
    cloudUpdatedAt: _cloudNewer,
    lastCloudUpdatedAt: _cloudSeen,
    lastLocalHash: _localHash,
    expected: SyncPlan.restoreCloud(),
  ),

  // Regra 4a — já ligado a esta conta, com dados aqui.
  _Case(
    'nuvem intocada e nada mudou aqui: nada a fazer',
    linkedUserId: _me,
    cloudUpdatedAt: _cloudSeen,
    lastCloudUpdatedAt: _cloudSeen,
    localHash: _syncedHash,
    lastLocalHash: _syncedHash,
    expected: SyncPlan.nothing(),
  ),
  _Case(
    'nuvem intocada e mudanças aqui: envia para a nuvem',
    linkedUserId: _me,
    cloudUpdatedAt: _cloudSeen,
    lastCloudUpdatedAt: _cloudSeen,
    lastLocalHash: _syncedHash,
    expected: SyncPlan.uploadLocal(),
  ),
  _Case(
    'outro aparelho gravou e nada mudou aqui: restaura o backup',
    linkedUserId: _me,
    cloudUpdatedAt: _cloudNewer,
    lastCloudUpdatedAt: _cloudSeen,
    localHash: _syncedHash,
    lastLocalHash: _syncedHash,
    expected: SyncPlan.restoreCloud(),
  ),
  _Case(
    'outro aparelho gravou e também houve mudanças aqui: conflito',
    linkedUserId: _me,
    cloudUpdatedAt: _cloudNewer,
    lastCloudUpdatedAt: _cloudSeen,
    lastLocalHash: _syncedHash,
    expected: SyncPlan.conflict(SyncConflictReason.bothChanged),
  ),
  _Case(
    'ligado sem registro do backup visto, mas sem mudanças aqui: restaura',
    linkedUserId: _me,
    cloudUpdatedAt: _cloudSeen,
    localHash: _syncedHash,
    lastLocalHash: _syncedHash,
    expected: SyncPlan.restoreCloud(),
  ),
  _Case(
    'ligado sem registro nenhum da última sincronização: conflito',
    linkedUserId: _me,
    cloudUpdatedAt: _cloudSeen,
    expected: SyncPlan.conflict(SyncConflictReason.bothChanged),
  ),

  // Regra 4b — primeira sincronização desta conta neste aparelho.
  _Case(
    'primeira sincronização com backup idêntico aos dados daqui: nada a fazer',
    cloudUpdatedAt: _cloudSeen,
    cloudPayloadHash: _localHash,
    expected: SyncPlan.nothing(),
  ),
  _Case(
    'primeira sincronização com backup diferente: conflito',
    cloudUpdatedAt: _cloudSeen,
    cloudPayloadHash: _syncedHash,
    expected: SyncPlan.conflict(SyncConflictReason.firstSync),
  ),
  _Case(
    'primeira sincronização sem conhecer o conteúdo do backup: conflito',
    cloudUpdatedAt: _cloudSeen,
    expected: SyncPlan.conflict(SyncConflictReason.firstSync),
  ),
  _Case(
    'primeira sincronização ignora marcas de sincronização órfãs',
    cloudUpdatedAt: _cloudSeen,
    lastCloudUpdatedAt: _cloudSeen,
    lastLocalHash: _localHash,
    cloudPayloadHash: _syncedHash,
    expected: SyncPlan.conflict(SyncConflictReason.firstSync),
  ),
];

void main() {
  group('SyncPlanner', () {
    for (final testCase in _cases) {
      test(testCase.description, () {
        expect(testCase.run(), testCase.expected);
      });
    }

    test('cobre as quatro decisões possíveis', () {
      expect(
        _cases.map((item) => item.expected.action).toSet(),
        SyncAction.values.toSet(),
      );
      expect(
        _cases
            .map((item) => item.expected.reason)
            .whereType<SyncConflictReason>()
            .toSet(),
        {
          SyncConflictReason.differentAccount,
          SyncConflictReason.firstSync,
          SyncConflictReason.bothChanged,
        },
      );
    });
  });

  group('SyncPlanner — varredura de todas as combinações', () {
    final combinations = <Map<String, Object?>>[
      for (final pristine in [false, true])
        for (final linked in [null, _me, _other])
          for (final cloud in [null, _cloudSeen, _cloudNewer])
            for (final lastCloud in [null, _cloudSeen])
              for (final lastLocal in [null, _localHash, _syncedHash])
                for (final payload in [null, _localHash, _syncedHash])
                  {
                    'pristine': pristine,
                    'linked': linked,
                    'cloud': cloud,
                    'lastCloud': lastCloud,
                    'lastLocal': lastLocal,
                    'payload': payload,
                  },
    ];

    SyncPlan planFor(Map<String, Object?> combination) => _planner.plan(
          currentUserId: _me,
          localIsPristine: combination['pristine']! as bool,
          localHash: _localHash,
          cloudUpdatedAt: combination['cloud'] as String?,
          linkedUserId: combination['linked'] as String?,
          lastCloudUpdatedAt: combination['lastCloud'] as String?,
          lastLocalHash: combination['lastLocal'] as String?,
          cloudPayloadHash: combination['payload'] as String?,
        );

    test('nenhuma combinação deixa de ter um plano', () {
      expect(combinations.length, 324);
      for (final combination in combinations) {
        expect(planFor(combination).action, isA<SyncAction>(),
            reason: '$combination');
      }
    });

    test('nunca restaura por cima de mudanças locais', () {
      for (final combination in combinations) {
        final unsyncedLocalEdits = combination['pristine'] == false &&
            combination['lastLocal'] != _localHash;
        if (!unsyncedLocalEdits) continue;
        expect(
          planFor(combination).action,
          isNot(SyncAction.restoreCloud),
          reason: '$combination',
        );
      }
    });

    test('nunca envia por cima de um backup que outro aparelho mudou', () {
      for (final combination in combinations) {
        final cloudChangedSinceLastSync = combination['cloud'] != null &&
            combination['cloud'] != combination['lastCloud'];
        if (!cloudChangedSinceLastSync) continue;
        expect(
          planFor(combination).action,
          isNot(SyncAction.uploadLocal),
          reason: '$combination',
        );
      }
    });

    test('aparelho sem nada criado nunca gera conflito', () {
      for (final combination in combinations) {
        if (combination['pristine'] == false) continue;
        expect(planFor(combination).isConflict, isFalse,
            reason: '$combination');
      }
    });

    test('o planejador nunca decide sozinho por "nuvem mais recente"', () {
      for (final combination in combinations) {
        expect(
          planFor(combination).reason,
          isNot(SyncConflictReason.cloudIsNewer),
          reason: '$combination',
        );
      }
    });

    test('conflito de conta diferente só aparece com dados locais', () {
      for (final combination in combinations) {
        final plan = planFor(combination);
        if (plan.reason != SyncConflictReason.differentAccount) continue;
        expect(combination['linked'], _other, reason: '$combination');
        expect(combination['pristine'], isFalse, reason: '$combination');
      }
    });
  });
}
