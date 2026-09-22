import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxo_plus/core/sync/snapshot_hash.dart';

Map<String, dynamic> _snapshot({
  List<Map<String, Object?>>? transactions,
  String exportedAt = '2026-09-20T10:00:00Z',
}) {
  return <String, dynamic>{
    'accounts': [
      {'id': 1, 'name': 'Conta principal', 'initial_balance': 0.0},
      {'id': 2, 'name': 'Poupança', 'initial_balance': 150.5},
    ],
    'categories': [
      {'id': 1, 'name': 'Salário', 'type': 'income'},
    ],
    'transactions': transactions ??
        [
          {'id': 1, 'amount': 10.0, 'description': 'Café'},
          {'id': 2, 'amount': 20.0, 'description': 'Ônibus'},
        ],
    'goals': <Map<String, Object?>>[],
    'settings': <Map<String, Object?>>[],
    'exported_at': exportedAt,
    'schema_version': 2,
  };
}

void main() {
  group('canonicalSnapshotJson', () {
    test('ordena as chaves de cada linha', () {
      expect(
        canonicalSnapshotJson({'b': 1, 'a': 2}),
        canonicalSnapshotJson({'a': 2, 'b': 1}),
      );
      expect(canonicalSnapshotJson({'b': 1, 'a': 2}), '{"a":2,"b":1}');
    });

    test('ignora o momento da exportação', () {
      expect(
        canonicalSnapshotJson(_snapshot(exportedAt: '2020-01-01T00:00:00Z')),
        canonicalSnapshotJson(_snapshot(exportedAt: '2026-12-31T23:59:59Z')),
      );
    });

    test('trata inteiros e decimais equivalentes como o mesmo valor', () {
      expect(canonicalSnapshotJson({'v': 100}),
          canonicalSnapshotJson({'v': 100.0}));
      expect(
        canonicalSnapshotJson({'v': 10.5}),
        isNot(canonicalSnapshotJson({'v': 10.05})),
      );
    });

    test('sobrevive à ida e volta por JSON', () {
      final original = _snapshot();
      final roundTrip =
          jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
      expect(
        canonicalSnapshotJson(roundTrip),
        canonicalSnapshotJson(original),
      );
    });
  });

  group('snapshotHash', () {
    test('mesma informação em outra ordem de linhas gera o mesmo hash', () {
      final direct = _snapshot();
      final reversed = _snapshot(
        transactions: [
          {'description': 'Ônibus', 'amount': 20.0, 'id': 2},
          {'description': 'Café', 'amount': 10.0, 'id': 1},
        ],
      );
      expect(snapshotHash(reversed), snapshotHash(direct));
    });

    test('um valor alterado muda o hash', () {
      final changed = _snapshot(
        transactions: [
          {'id': 1, 'amount': 10.0, 'description': 'Café'},
          {'id': 2, 'amount': 20.01, 'description': 'Ônibus'},
        ],
      );
      expect(snapshotHash(changed), isNot(snapshotHash(_snapshot())));
    });

    test('uma linha a mais muda o hash', () {
      final extra = _snapshot(
        transactions: [
          {'id': 1, 'amount': 10.0, 'description': 'Café'},
          {'id': 2, 'amount': 20.0, 'description': 'Ônibus'},
          {'id': 3, 'amount': 20.0, 'description': 'Ônibus'},
        ],
      );
      expect(snapshotHash(extra), isNot(snapshotHash(_snapshot())));
    });

    test('é estável entre execuções e tem formato fixo', () {
      final hash = snapshotHash(_snapshot());
      expect(hash, snapshotHash(_snapshot()));
      expect(hash, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('snapshots vazio e nulo não colidem', () {
      expect(snapshotHash(<String, dynamic>{}), isNot(snapshotHash(null)));
    });
  });
}
