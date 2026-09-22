import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxo_plus/core/sync/cloud_backup_gateway.dart';
import 'package:fluxo_plus/core/sync/cloud_sync_service.dart';
import 'package:fluxo_plus/core/sync/local_backup_store.dart';
import 'package:fluxo_plus/core/sync/snapshot_hash.dart';
import 'package:fluxo_plus/core/sync/sync_planner.dart';

const _me = 'user-me';
const _other = 'user-other';

Map<String, dynamic> _snapshot(
  List<String> descriptions, {
  int accounts = 1,
  int goals = 0,
}) {
  return <String, dynamic>{
    'accounts': [
      for (var index = 1; index <= accounts; index++)
        {'id': index, 'name': 'Conta $index', 'initial_balance': 0.0},
    ],
    'categories': [
      {'id': 1, 'name': 'Salário', 'type': 'income'},
    ],
    'transactions': [
      for (var index = 0; index < descriptions.length; index++)
        {
          'id': index + 1,
          'amount': 10.0 + index,
          'description': descriptions[index],
        },
    ],
    'goals': [
      for (var index = 1; index <= goals; index++)
        {'id': index, 'name': 'Meta $index', 'target_amount': 100.0},
    ],
    'settings': <Map<String, Object?>>[],
    'exported_at': '2026-09-20T10:00:00.000Z',
    'schema_version': 2,
  };
}

class FakeLocalStore implements LocalBackupStore {
  FakeLocalStore({Map<String, dynamic>? snapshot, this.pristine = false})
      : snapshot = snapshot ?? _snapshot(['Café']);

  Map<String, dynamic> snapshot;
  bool pristine;
  final Map<String, String> settings = <String, String>{};
  int restores = 0;

  @override
  Future<Map<String, dynamic>> exportSnapshot() async =>
      jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;

  @override
  Future<void> restoreSnapshot(Map<String, dynamic> value) async {
    restores++;
    pristine = false;
    snapshot = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }

  @override
  Future<bool> isPristine() async => pristine;

  @override
  Future<String?> readSetting(String key) async => settings[key];

  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;

  @override
  Future<void> removeSetting(String key) async => settings.remove(key);
}

class FakeCloudGateway implements CloudBackupGateway {
  FakeCloudGateway({this.backup, String? userId = _me}) : _userId = userId;

  CloudBackup? backup;
  String? _userId;
  int uploads = 0;
  int payloadReads = 0;
  Object? failure;
  Duration? delay;
  int _stamp = 0;

  set userId(String? value) => _userId = value;

  @override
  String? get currentUserId => _userId;

  @override
  String? get currentUserEmail => _userId == null ? null : '$_userId@fluxo.app';

  Future<void> _maybeFail() async {
    if (delay != null) await Future<void>.delayed(delay!);
    if (failure != null) throw failure!;
  }

  @override
  Future<String?> fetchUpdatedAt() async {
    await _maybeFail();
    return backup?.updatedAt;
  }

  @override
  Future<CloudBackup?> fetchBackup() async {
    await _maybeFail();
    payloadReads++;
    return backup;
  }

  @override
  Future<String> upload(Map<String, dynamic> payload) async {
    await _maybeFail();
    uploads++;
    _stamp++;
    final updatedAt = '2026-09-21T1$_stamp:00:00.000Z';
    backup = CloudBackup(
      updatedAt: updatedAt,
      payload: jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
    );
    return updatedAt;
  }
}

CloudBackup _cloudBackup(
  Map<String, dynamic> payload, {
  String updatedAt = '2026-09-20T09:00:00.000Z',
}) =>
    CloudBackup(updatedAt: updatedAt, payload: payload);

CloudSyncService _service(FakeLocalStore store, FakeCloudGateway gateway) =>
    CloudSyncService(store: store, gateway: gateway);

void _link(
  FakeLocalStore store, {
  String user = _me,
  required String cloudUpdatedAt,
  required Map<String, dynamic> localSnapshot,
}) {
  store.settings[CloudSyncService.keyUserId] = user;
  store.settings[CloudSyncService.keyCloudUpdatedAt] =
      DateTime.parse(cloudUpdatedAt).toUtc().toIso8601String();
  store.settings[CloudSyncService.keyLocalHash] = snapshotHash(localSnapshot);
}

void main() {
  group('synchronize', () {
    test('(a) aparelho novo com backup na conta: restaura', () async {
      final cloud = _snapshot(['Mercado', 'Aluguel']);
      final store = FakeLocalStore(snapshot: _snapshot([]), pristine: true);
      final gateway = FakeCloudGateway(backup: _cloudBackup(cloud));

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.status, SyncStatus.restored);
      expect(store.snapshot['transactions'], cloud['transactions']);
      expect(gateway.uploads, 0);
      expect(store.settings[CloudSyncService.keyUserId], _me);
      expect(store.settings[CloudSyncService.keyLocalHash],
          snapshotHash(store.snapshot));
      expect(store.settings[CloudSyncService.keyLastBackupAt], isNotNull);
    });

    test('(b) aparelho com dados e conta sem backup: envia', () async {
      final store = FakeLocalStore(snapshot: _snapshot(['Café']));
      final gateway = FakeCloudGateway();

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.status, SyncStatus.uploaded);
      expect(gateway.uploads, 1);
      expect(gateway.backup!.payload['transactions'],
          store.snapshot['transactions']);
      expect(store.restores, 0);
      expect(store.settings[CloudSyncService.keyCloudUpdatedAt],
          DateTime.parse(gateway.backup!.updatedAt).toUtc().toIso8601String());
    });

    test('(c) já ligado, nuvem intocada e edição local: envia', () async {
      final synced = _snapshot(['Café']);
      final store = FakeLocalStore(snapshot: _snapshot(['Café', 'Padaria']));
      final gateway = FakeCloudGateway(backup: _cloudBackup(synced));
      _link(
        store,
        cloudUpdatedAt: gateway.backup!.updatedAt,
        localSnapshot: synced,
      );

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.status, SyncStatus.uploaded);
      expect(gateway.uploads, 1);
      expect(store.restores, 0);
    });

    test('(d) outro aparelho gravou e nada mudou aqui: restaura', () async {
      final synced = _snapshot(['Café']);
      final cloud = _snapshot(['Café', 'Farmácia']);
      final store = FakeLocalStore(snapshot: synced);
      final gateway = FakeCloudGateway(
        backup: _cloudBackup(cloud, updatedAt: '2026-09-21T08:00:00.000Z'),
      );
      _link(
        store,
        cloudUpdatedAt: '2026-09-20T09:00:00.000Z',
        localSnapshot: synced,
      );

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.status, SyncStatus.restored);
      expect(store.snapshot['transactions'], cloud['transactions']);
      expect(gateway.uploads, 0);
    });

    test('(e) mudou dos dois lados: conflito sem alterar nada', () async {
      final synced = _snapshot(['Café']);
      final cloud = _snapshot(['Café', 'Farmácia']);
      final local = _snapshot(['Café', 'Padaria']);
      final store = FakeLocalStore(snapshot: local);
      final gateway = FakeCloudGateway(
        backup: _cloudBackup(cloud, updatedAt: '2026-09-21T08:00:00.000Z'),
      );
      _link(
        store,
        cloudUpdatedAt: '2026-09-20T09:00:00.000Z',
        localSnapshot: synced,
      );

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.status, SyncStatus.conflict);
      expect(outcome.conflictReason, SyncConflictReason.bothChanged);
      expect(gateway.uploads, 0);
      expect(store.restores, 0);
      expect(store.snapshot['transactions'], local['transactions']);
      expect(gateway.backup!.payload['transactions'], cloud['transactions']);
      expect(
        store.settings[CloudSyncService.keyPendingConflict],
        SyncConflictReason.bothChanged.name,
      );
    });

    test('(f) outra conta com dados aqui: conflito sem mover dados', () async {
      final cloud = _snapshot(['Da outra conta']);
      final local = _snapshot(['Meus dados']);
      final store = FakeLocalStore(snapshot: local);
      final gateway = FakeCloudGateway(backup: _cloudBackup(cloud));
      store.settings[CloudSyncService.keyUserId] = _other;

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.conflictReason, SyncConflictReason.differentAccount);
      expect(gateway.uploads, 0);
      expect(store.restores, 0);
      expect(store.snapshot['transactions'], local['transactions']);
      expect(gateway.backup!.payload['transactions'], cloud['transactions']);
    });

    test('(i) segundo plano não lê nem grava o backup em conflito', () async {
      final local = _snapshot(['Meus dados']);
      final store = FakeLocalStore(snapshot: local);
      final gateway = FakeCloudGateway(
        backup: _cloudBackup(_snapshot(['Outros dados'])),
      );
      store.settings[CloudSyncService.keyUserId] = _other;

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.isConflict, isTrue);
      expect(outcome.conflict, isNull,
          reason: 'não busca dados em segundo plano');
      expect(gateway.payloadReads, 0);
      expect(gateway.uploads, 0);
      expect(store.restores, 0);
    });

    test('modo interativo descreve os dois lados do conflito', () async {
      final store = FakeLocalStore(snapshot: _snapshot(['A', 'B'], goals: 2));
      final gateway = FakeCloudGateway(
        backup: _cloudBackup(_snapshot(['C'], accounts: 3)),
      );
      store.settings[CloudSyncService.keyUserId] = _other;

      final outcome =
          await _service(store, gateway).synchronize(interactive: true);

      final info = outcome.conflict!;
      expect(info.reason, SyncConflictReason.differentAccount);
      expect(info.local.transactions, 2);
      expect(info.local.goals, 2);
      expect(info.cloud!.transactions, 1);
      expect(info.cloud!.accounts, 3);
      expect(info.cloudUpdatedAt, DateTime.parse('2026-09-20T09:00:00.000Z'));
    });

    test('primeira sincronização com o mesmo conteúdo apenas vincula',
        () async {
      final same = _snapshot(['Café']);
      final store = FakeLocalStore(snapshot: same);
      final gateway = FakeCloudGateway(backup: _cloudBackup(same));

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.status, SyncStatus.alreadyInSync);
      expect(gateway.uploads, 0);
      expect(store.restores, 0);
      expect(store.settings[CloudSyncService.keyUserId], _me);
    });

    test('nada a fazer quando os dois lados seguem iguais', () async {
      final synced = _snapshot(['Café']);
      final store = FakeLocalStore(snapshot: synced);
      final gateway = FakeCloudGateway(backup: _cloudBackup(synced));
      _link(
        store,
        cloudUpdatedAt: gateway.backup!.updatedAt,
        localSnapshot: synced,
      );

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.status, SyncStatus.alreadyInSync);
      expect(gateway.uploads, 0);
      expect(store.restores, 0);
    });

    test('sem conta conectada não faz nada', () async {
      final store = FakeLocalStore();
      final gateway = FakeCloudGateway(userId: null);

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.status, SyncStatus.skipped);
      expect(outcome.skipReason, SyncSkipReason.notSignedIn);
      expect(store.settings[CloudSyncService.keyLastError], isNull);
    });

    test('sem Supabase configurado não faz nada', () async {
      final store = FakeLocalStore();
      final outcome =
          await CloudSyncService(store: store).synchronize(interactive: false);

      expect(outcome.skipReason, SyncSkipReason.notConfigured);
    });
  });

  group('falhas', () {
    test('(g) registra o erro e não lança', () async {
      final store = FakeLocalStore();
      final gateway = FakeCloudGateway()..failure = StateError('sem permissão');

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.status, SyncStatus.failed);
      expect(outcome.message, isNotNull);
      expect(outcome.message, isNot(contains('StateError')));
      final recorded = jsonDecode(
        store.settings[CloudSyncService.keyLastError]!,
      ) as Map<String, dynamic>;
      expect(recorded['message'], outcome.message);
      expect(DateTime.tryParse(recorded['at'] as String), isNotNull);
    });

    test('sem internet o backup fica para depois', () async {
      final store = FakeLocalStore();
      final gateway = FakeCloudGateway()
        ..failure = const SocketException('sem rota');

      final outcome =
          await _service(store, gateway).synchronize(interactive: false);

      expect(outcome.status, SyncStatus.skipped);
      expect(outcome.skipReason, SyncSkipReason.offline);
      expect(store.settings[CloudSyncService.keyLastError], isNotNull);
    });

    test('o backup do segundo plano respeita o tempo limite', () async {
      final store = FakeLocalStore();
      final gateway = FakeCloudGateway()..delay = const Duration(seconds: 30);

      final outcome = await _service(store, gateway).synchronize(
        interactive: false,
        timeout: const Duration(milliseconds: 20),
      );

      expect(outcome.status, SyncStatus.skipped);
      expect(outcome.skipReason, SyncSkipReason.offline);
      expect(gateway.uploads, 0);
    });

    test('uma sincronização bem-sucedida limpa o erro anterior', () async {
      final store = FakeLocalStore();
      final gateway = FakeCloudGateway();
      store.settings[CloudSyncService.keyLastError] = '{"message":"x"}';
      store.settings[CloudSyncService.keyPendingConflict] = 'bothChanged';

      await _service(store, gateway).synchronize(interactive: false);

      expect(store.settings[CloudSyncService.keyLastError], isNull);
      expect(store.settings[CloudSyncService.keyPendingConflict], isNull);
    });
  });

  group('ações do usuário', () {
    test('(h) restaurar guarda os dados anteriores e o desfazer os devolve',
        () async {
      final local = _snapshot(['Meus dados'], goals: 1);
      final cloud = _snapshot(['Backup antigo'], accounts: 2);
      final store = FakeLocalStore(snapshot: local);
      final gateway = FakeCloudGateway(backup: _cloudBackup(cloud));
      final service = _service(store, gateway);

      final restored = await service.restoreFromCloud();
      expect(restored.status, SyncStatus.restored);
      expect(store.snapshot['transactions'], cloud['transactions']);
      expect(store.settings[CloudSyncService.keyPreRestoreSnapshot], isNotNull);

      final undone = await service.undoLastRestore();
      expect(undone.status, SyncStatus.restored);
      expect(snapshotHash(store.snapshot), snapshotHash(local));
      expect(store.settings[CloudSyncService.keyPreRestoreSnapshot], isNull);
      expect(gateway.uploads, 0, reason: 'desfazer não mexe no backup');
    });

    test('depois de desfazer, a próxima sincronização envia o que voltou',
        () async {
      final local = _snapshot(['Meus dados']);
      final store = FakeLocalStore(snapshot: local);
      final gateway = FakeCloudGateway(
        backup: _cloudBackup(_snapshot(['Backup antigo'])),
      );
      final service = _service(store, gateway);

      await service.restoreFromCloud();
      await service.undoLastRestore();
      final outcome = await service.synchronize(interactive: false);

      expect(outcome.status, SyncStatus.uploaded);
      expect(
        gateway.backup!.payload['transactions'],
        local['transactions'],
      );
    });

    test('desfazer sem restauração anterior avisa em vez de falhar', () async {
      final store = FakeLocalStore();
      final outcome =
          await _service(store, FakeCloudGateway()).undoLastRestore();

      expect(outcome.status, SyncStatus.failed);
      expect(store.restores, 0);
    });

    test('manter este aparelho substitui o backup e encerra o conflito',
        () async {
      final local = _snapshot(['Meus dados']);
      final store = FakeLocalStore(snapshot: local);
      final gateway = FakeCloudGateway(
        backup: _cloudBackup(_snapshot(['Da nuvem'])),
      );
      store.settings[CloudSyncService.keyUserId] = _other;
      store.settings[CloudSyncService.keyPendingConflict] = 'differentAccount';

      final outcome = await _service(store, gateway).keepThisDevice();

      expect(outcome.status, SyncStatus.uploaded);
      expect(gateway.backup!.payload['transactions'], local['transactions']);
      expect(store.settings[CloudSyncService.keyPendingConflict], isNull);
      expect(store.settings[CloudSyncService.keyUserId], _me);
      expect(store.restores, 0);
    });

    test('usar a nuvem substitui os dados e encerra o conflito', () async {
      final cloud = _snapshot(['Da nuvem']);
      final store = FakeLocalStore(snapshot: _snapshot(['Meus dados']));
      final gateway = FakeCloudGateway(backup: _cloudBackup(cloud));
      store.settings[CloudSyncService.keyPendingConflict] = 'firstSync';

      final outcome = await _service(store, gateway).useCloudVersion();

      expect(outcome.status, SyncStatus.restored);
      expect(store.snapshot['transactions'], cloud['transactions']);
      expect(store.settings[CloudSyncService.keyPendingConflict], isNull);
    });

    test('backup manual envia quando há mudanças aqui', () async {
      final store = FakeLocalStore(snapshot: _snapshot(['Café']));
      final gateway = FakeCloudGateway();

      final outcome = await _service(store, gateway).uploadBackupNow();

      expect(outcome.status, SyncStatus.uploaded);
      expect(gateway.uploads, 1);
    });

    test('backup manual pergunta antes de apagar um backup mais novo',
        () async {
      final synced = _snapshot(['Café']);
      final store = FakeLocalStore(snapshot: synced);
      final gateway = FakeCloudGateway(
        backup: _cloudBackup(
          _snapshot(['Café', 'Outro aparelho']),
          updatedAt: '2026-09-21T08:00:00.000Z',
        ),
      );
      _link(
        store,
        cloudUpdatedAt: '2026-09-20T09:00:00.000Z',
        localSnapshot: synced,
      );

      final outcome = await _service(store, gateway).uploadBackupNow();

      expect(outcome.conflictReason, SyncConflictReason.cloudIsNewer);
      expect(gateway.uploads, 0);
      expect(store.restores, 0);
    });

    test('restaurar sem backup na conta avisa o usuário', () async {
      final store = FakeLocalStore();
      final outcome =
          await _service(store, FakeCloudGateway()).restoreFromCloud();

      expect(outcome.status, SyncStatus.failed);
      expect(store.restores, 0);
    });
  });

  group('estado para a tela', () {
    test('resume último backup, erro, conflito e desfazer', () async {
      final store = FakeLocalStore();
      final gateway = FakeCloudGateway();
      final service = _service(store, gateway);

      var status = await service.status();
      expect(status.lastBackupAt, isNull);
      expect(status.pendingConflict, isFalse);
      expect(status.canUndoRestore, isFalse);
      expect(status.accountEmail, '$_me@fluxo.app');

      await service.uploadBackupNow();
      status = await service.status();
      expect(status.lastBackupAt, isNotNull);
      expect(status.errorMessage, isNull);

      store.settings[CloudSyncService.keyPendingConflict] = 'bothChanged';
      store.settings[CloudSyncService.keyPreRestoreSnapshot] = '{}';
      store.settings[CloudSyncService.keyLastError] = jsonEncode({
        'message': 'Sem conexão com a internet.',
        'at': '2026-09-21T10:00:00.000Z',
      });
      status = await service.status();
      expect(status.pendingConflict, isTrue);
      expect(status.canUndoRestore, isTrue);
      expect(status.errorMessage, 'Sem conexão com a internet.');
      expect(status.errorAt, isNotNull);
    });

    test('conflito pendente é descrito com os dois lados', () async {
      final store = FakeLocalStore(snapshot: _snapshot(['A', 'B']));
      final gateway = FakeCloudGateway(
        backup: _cloudBackup(_snapshot(['C'], goals: 1)),
      );
      store.settings[CloudSyncService.keyPendingConflict] = 'firstSync';

      final info = await _service(store, gateway).pendingConflict();

      expect(info!.reason, SyncConflictReason.firstSync);
      expect(info.local.transactions, 2);
      expect(info.cloud!.transactions, 1);
      expect(info.cloud!.goals, 1);
    });

    test('sem conflito pendente não há nada a perguntar', () async {
      final store = FakeLocalStore();
      expect(
        await _service(store, FakeCloudGateway()).pendingConflict(),
        isNull,
      );
    });

    test('conflito pendente sem internet ainda descreve este aparelho',
        () async {
      final store = FakeLocalStore(snapshot: _snapshot(['A']));
      final gateway = FakeCloudGateway()
        ..failure = const SocketException('sem rota');
      store.settings[CloudSyncService.keyPendingConflict] = 'bothChanged';

      final info = await _service(store, gateway).pendingConflict();

      expect(info!.cloud, isNull);
      expect(info.local.transactions, 1);
    });
  });
}
