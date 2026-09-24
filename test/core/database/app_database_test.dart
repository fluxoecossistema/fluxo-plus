import 'package:flutter_test/flutter_test.dart';
import 'package:fluxo_plus/core/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(databaseFactoryFfi);
    await database.initialize(path: inMemoryDatabasePath);
  });

  tearDown(() => database.close());

  Future<void> addTransaction() async {
    final account = await database.db.query('accounts', limit: 1);
    final category = await database.db.query('categories', limit: 1);
    await database.db.insert('transactions', {
      'type': 'expense',
      'amount': 12.5,
      'category_id': category.first['id'],
      'account_id': account.first['id'],
      'date': '2026-09-20',
      'description': 'Padaria',
      'created_at': '2026-09-20T09:00:00.000',
    });
  }

  group('isPristine', () {
    test('banco recém-criado está intocado', () async {
      expect(await database.isPristine(), isTrue);
    });

    test('uma transação tira o banco do estado intocado', () async {
      await addTransaction();
      expect(await database.isPristine(), isFalse);
    });

    test('uma meta tira o banco do estado intocado', () async {
      await database.db.insert('goals', {
        'name': 'Viagem',
        'target_amount': 1000.0,
        'current_amount': 0.0,
        'created_at': '2026-09-20T09:00:00.000',
      });
      expect(await database.isPristine(), isFalse);
    });

    test('conta renomeada tira o banco do estado intocado', () async {
      await database.db.update('accounts', {'name': 'Nubank'});
      expect(await database.isPristine(), isFalse);
    });

    test('saldo inicial editado tira o banco do estado intocado', () async {
      await database.db.update('accounts', {'initial_balance': 500.0});
      expect(await database.isPristine(), isFalse);
    });

    test('conta nova tira o banco do estado intocado', () async {
      await database.db.insert('accounts', {
        'name': 'Poupança',
        'initial_balance': 0.0,
        'created_at': '2026-09-20T09:00:00.000',
      });
      expect(await database.isPristine(), isFalse);
    });

    test('categoria apagada tira o banco do estado intocado', () async {
      await database.db.delete(
        'categories',
        where: 'name = ?',
        whereArgs: ['Lazer'],
      );
      expect(await database.isPristine(), isFalse);
    });

    test('categoria editada tira o banco do estado intocado', () async {
      await database.db.update(
        'categories',
        {'name': 'Diversão'},
        where: 'name = ?',
        whereArgs: ['Lazer'],
      );
      expect(await database.isPristine(), isFalse);
    });

    test('preferências do aparelho não tiram o estado intocado', () async {
      await database.writeSetting('theme', 'light');
      await database.writeSetting('onboarding_complete', 'true');
      expect(await database.isPristine(), isTrue);
    });
  });

  group('preferências do aparelho', () {
    test('grava, lê e apaga um valor', () async {
      expect(await database.readSetting('sync_user_id'), isNull);
      await database.writeSetting('sync_user_id', 'user-1');
      expect(await database.readSetting('sync_user_id'), 'user-1');
      await database.writeSetting('sync_user_id', 'user-2');
      expect(await database.readSetting('sync_user_id'), 'user-2');
      await database.removeSetting('sync_user_id');
      expect(await database.readSetting('sync_user_id'), isNull);
    });
  });

  group('snapshot', () {
    test('não leva as preferências do aparelho para a nuvem', () async {
      await database.writeSetting('theme', 'light');
      final snapshot = await database.exportSnapshot();
      expect(snapshot['settings'], isEmpty);
    });

    test('restaurar devolve exatamente as linhas exportadas', () async {
      await addTransaction();
      final snapshot = await database.exportSnapshot();

      await database.db.delete('transactions');
      await database.db.insert('accounts', {
        'name': 'Conta extra',
        'initial_balance': 3.0,
        'created_at': '2026-09-20T09:00:00.000',
      });
      await database.restoreSnapshot(snapshot);

      expect(
        await database.db.query('transactions'),
        snapshot['transactions'],
      );
      expect(await database.db.query('accounts'), snapshot['accounts']);
      expect(await database.readSetting('theme'), 'dark');
    });
  });
}
