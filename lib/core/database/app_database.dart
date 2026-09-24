import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';

class AppDatabase {
  AppDatabase(this._factory);

  final DatabaseFactory _factory;
  Database? _database;

  /// Contas criadas junto com o banco, na primeira abertura.
  static const seedAccounts = <({String name, double initialBalance})>[
    (name: 'Conta principal', initialBalance: 0),
  ];

  /// Categorias criadas junto com o banco, na primeira abertura.
  static const seedCategories =
      <({String name, String type, String icon, int color})>[
    (name: 'Salário', type: 'income', icon: 'payments', color: 0xFF0F9D58),
    (name: 'Freelance', type: 'income', icon: 'work', color: 0xFF0B6B3A),
    (
      name: 'Outras receitas',
      type: 'income',
      icon: 'add_circle',
      color: 0xFF64748B
    ),
    (
      name: 'Alimentação',
      type: 'expense',
      icon: 'restaurant',
      color: 0xFFE53935
    ),
    (name: 'Moradia', type: 'expense', icon: 'home', color: 0xFF7C3AED),
    (
      name: 'Transporte',
      type: 'expense',
      icon: 'directions_car',
      color: 0xFF0284C7
    ),
    (
      name: 'Saúde',
      type: 'expense',
      icon: 'medical_services',
      color: 0xFFDB2777
    ),
    (name: 'Lazer', type: 'expense', icon: 'celebration', color: 0xFFF59E0B),
    (
      name: 'Cartão de crédito',
      type: 'expense',
      icon: 'credit_card',
      color: 0xFF7C3AED
    ),
    (name: 'Internet', type: 'expense', icon: 'wifi', color: 0xFF0284C7),
    (
      name: 'Outras despesas',
      type: 'expense',
      icon: 'more_horiz',
      color: 0xFF64748B
    ),
  ];

  Database get db {
    final value = _database;
    if (value == null) {
      throw StateError('Banco de dados ainda não inicializado.');
    }
    return value;
  }

  /// [path] existe para os testes abrirem um banco em memória; em produção o
  /// arquivo fica na pasta de suporte do aplicativo.
  Future<void> initialize({String? path}) async {
    if (_database != null) return;
    final directory =
        path != null ? null : await getApplicationSupportDirectory();
    _database = await _factory.openDatabase(
      path ?? p.join(directory!.path, AppConstants.databaseName),
      options: OpenDatabaseOptions(
        version: AppConstants.databaseVersion,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
  }

  Future<void> _create(Database database, int version) async {
    await database.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE accounts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          initial_balance REAL NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      ''');
      await txn.execute('''
        CREATE TABLE categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL CHECK(type IN ('income', 'expense')),
          icon TEXT NOT NULL,
          color INTEGER NOT NULL,
          is_default INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await txn.execute('''
        CREATE TABLE transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL CHECK(type IN ('income', 'expense')),
          amount REAL NOT NULL CHECK(amount > 0),
          category_id INTEGER NOT NULL,
          account_id INTEGER NOT NULL,
          date TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          is_paid INTEGER NOT NULL DEFAULT 1,
          installment_group TEXT,
          installment_number INTEGER NOT NULL DEFAULT 1,
          installment_count INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          FOREIGN KEY(category_id) REFERENCES categories(id),
          FOREIGN KEY(account_id) REFERENCES accounts(id)
        )
      ''');
      await txn.execute('''
        CREATE TABLE goals (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          target_amount REAL NOT NULL,
          current_amount REAL NOT NULL DEFAULT 0,
          deadline TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      await txn.execute('''
        CREATE TABLE settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
      await txn.execute(
        'CREATE INDEX idx_transactions_date ON transactions(date)',
      );
      await txn.execute(
        'CREATE INDEX idx_transactions_due_status '
        'ON transactions(is_paid, date)',
      );

      final now = DateTime.now().toIso8601String();
      for (final account in seedAccounts) {
        await txn.insert('accounts', {
          'name': account.name,
          'initial_balance': account.initialBalance,
          'created_at': now,
        });
      }
      for (final category in seedCategories) {
        await txn.insert('categories', {
          'name': category.name,
          'type': category.type,
          'icon': category.icon,
          'color': category.color,
          'is_default': 1,
        });
      }
      await txn.insert('settings', {'key': 'theme', 'value': 'dark'});
    });
  }

  Future<void> _upgrade(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await database.transaction((txn) async {
        await txn.execute(
          'ALTER TABLE transactions '
          'ADD COLUMN is_paid INTEGER NOT NULL DEFAULT 1',
        );
        await txn.execute(
          'ALTER TABLE transactions ADD COLUMN installment_group TEXT',
        );
        await txn.execute(
          'ALTER TABLE transactions '
          'ADD COLUMN installment_number INTEGER NOT NULL DEFAULT 1',
        );
        await txn.execute(
          'ALTER TABLE transactions '
          'ADD COLUMN installment_count INTEGER NOT NULL DEFAULT 1',
        );
        await txn.execute(
          'CREATE INDEX idx_transactions_due_status '
          'ON transactions(is_paid, date)',
        );
        await _ensureCategory(
          txn,
          name: 'Cartão de crédito',
          icon: 'credit_card',
          color: 0xFF7C3AED,
        );
        await _ensureCategory(
          txn,
          name: 'Internet',
          icon: 'wifi',
          color: 0xFF0284C7,
        );
        const iconUpdates = {
          'Alimentação': 'restaurant',
          'Moradia': 'home',
          'Transporte': 'directions_car',
          'Saúde': 'medical_services',
          'Lazer': 'celebration',
          'Outras despesas': 'more_horiz',
          'Salário': 'payments',
          'Freelance': 'work',
          'Outras receitas': 'add_circle',
        };
        for (final entry in iconUpdates.entries) {
          await txn.update(
            'categories',
            {'icon': entry.value},
            where: 'name = ?',
            whereArgs: [entry.key],
          );
        }
      });
    }
  }

  Future<void> _ensureCategory(
    DatabaseExecutor database, {
    required String name,
    required String icon,
    required int color,
  }) async {
    final existing = await database.query(
      'categories',
      columns: ['id'],
      where: 'name = ? AND type = ?',
      whereArgs: [name, 'expense'],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await database.insert('categories', {
      'name': name,
      'type': 'expense',
      'icon': icon,
      'color': color,
      'is_default': 1,
    });
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  /// `true` quando nada foi criado neste aparelho: sem transações, sem metas e
  /// com as contas e categorias iniciais exatamente como vieram.
  ///
  /// É o que autoriza uma restauração automática: não há o que perder.
  Future<bool> isPristine() async {
    final counts = await db.rawQuery(
      'SELECT (SELECT COUNT(*) FROM transactions) AS transactions, '
      '(SELECT COUNT(*) FROM goals) AS goals',
    );
    if ((counts.first['transactions'] as int? ?? 0) > 0) return false;
    if ((counts.first['goals'] as int? ?? 0) > 0) return false;

    final accounts = await db.query(
      'accounts',
      columns: ['name', 'initial_balance'],
    );
    final expectedAccounts = [
      for (final account in seedAccounts)
        '${account.name}|${account.initialBalance.toStringAsFixed(2)}',
    ]..sort();
    final currentAccounts = [
      for (final row in accounts)
        '${row['name']}|'
            '${(row['initial_balance'] as num).toDouble().toStringAsFixed(2)}',
    ]..sort();
    if (expectedAccounts.join('\n') != currentAccounts.join('\n')) return false;

    final categories = await db.query(
      'categories',
      columns: ['name', 'type', 'icon', 'color'],
    );
    final expectedCategories = [
      for (final category in seedCategories)
        '${category.name}|${category.type}|${category.icon}|${category.color}',
    ]..sort();
    final currentCategories = [
      for (final row in categories)
        '${row['name']}|${row['type']}|${row['icon']}|${row['color']}',
    ]..sort();
    return expectedCategories.join('\n') == currentCategories.join('\n');
  }

  /// Preferência deste aparelho (tema, biometria, estado do backup). Nunca vai
  /// para a nuvem — veja [exportSnapshot].
  Future<String?> readSetting(String key) async {
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> writeSetting(String key, String value) => db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> removeSetting(String key) => db.delete(
        'settings',
        where: 'key = ?',
        whereArgs: [key],
      );

  Future<Map<String, dynamic>> exportSnapshot() async {
    const tables = [
      'accounts',
      'categories',
      'transactions',
      'goals',
    ];
    final snapshot = <String, dynamic>{};
    for (final table in tables) {
      snapshot[table] = await db.query(table);
    }
    // Preferências de tema, biometria e onboarding pertencem ao dispositivo.
    snapshot['settings'] = <Map<String, Object?>>[];
    snapshot['exported_at'] = DateTime.now().toUtc().toIso8601String();
    snapshot['schema_version'] = AppConstants.databaseVersion;
    return snapshot;
  }

  Future<void> restoreSnapshot(Map<String, dynamic> snapshot) async {
    const tables = [
      'accounts',
      'categories',
      'transactions',
      'goals',
    ];
    for (final table in [...tables, 'settings']) {
      if (snapshot[table] is! List) {
        throw const FormatException('Backup inválido ou incompleto.');
      }
    }
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('goals');
      await txn.delete('categories');
      await txn.delete('accounts');
      for (final table in tables) {
        for (final raw in snapshot[table] as List<dynamic>) {
          await txn.insert(table, Map<String, Object?>.from(raw as Map));
        }
      }
    });
  }
}
