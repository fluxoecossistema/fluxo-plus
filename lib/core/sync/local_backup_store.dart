import '../database/app_database.dart';

/// Acesso aos dados deste aparelho de que a sincronização precisa.
///
/// A interface existe para os testes: assim o orquestrador pode ser exercitado
/// sem abrir um banco de verdade.
abstract class LocalBackupStore {
  /// Cópia dos dados do usuário (sem as preferências do aparelho).
  Future<Map<String, dynamic>> exportSnapshot();

  /// Substitui os dados do usuário pelos do [snapshot].
  Future<void> restoreSnapshot(Map<String, dynamic> snapshot);

  /// `true` quando nada foi criado neste aparelho.
  Future<bool> isPristine();

  Future<String?> readSetting(String key);

  Future<void> writeSetting(String key, String value);

  Future<void> removeSetting(String key);
}

/// Implementação sobre o banco local do aplicativo.
class DatabaseBackupStore implements LocalBackupStore {
  const DatabaseBackupStore(this._database);

  final AppDatabase _database;

  @override
  Future<Map<String, dynamic>> exportSnapshot() => _database.exportSnapshot();

  @override
  Future<void> restoreSnapshot(Map<String, dynamic> snapshot) =>
      _database.restoreSnapshot(snapshot);

  @override
  Future<bool> isPristine() => _database.isPristine();

  @override
  Future<String?> readSetting(String key) => _database.readSetting(key);

  @override
  Future<void> writeSetting(String key, String value) =>
      _database.writeSetting(key, value);

  @override
  Future<void> removeSetting(String key) => _database.removeSetting(key);
}
