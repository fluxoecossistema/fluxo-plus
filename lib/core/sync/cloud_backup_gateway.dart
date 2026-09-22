import 'package:supabase_flutter/supabase_flutter.dart';

/// O backup guardado na nuvem: um único snapshot JSON por conta.
class CloudBackup {
  const CloudBackup({required this.updatedAt, required this.payload});

  /// Momento em que o backup foi gravado, como veio do servidor.
  final String updatedAt;

  final Map<String, dynamic> payload;
}

/// Acesso ao backup da conta na nuvem.
///
/// A interface isola o Supabase para que o orquestrador possa ser testado sem
/// rede e sem servidor.
abstract class CloudBackupGateway {
  String? get currentUserId;

  String? get currentUserEmail;

  /// Quando o backup desta conta foi gravado, ou `null` se ainda não existe.
  Future<String?> fetchUpdatedAt();

  /// O backup completo desta conta, ou `null` se ainda não existe.
  Future<CloudBackup?> fetchBackup();

  /// Grava [payload] como o backup da conta e devolve o novo momento de
  /// gravação, exatamente como o servidor passará a informá-lo.
  Future<String> upload(Map<String, dynamic> payload);
}

/// Implementação real, sobre a tabela `user_backups`.
class SupabaseCloudBackupGateway implements CloudBackupGateway {
  const SupabaseCloudBackupGateway(this._client);

  static const _table = 'user_backups';

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  String? get currentUserEmail => _client.auth.currentUser?.email;

  @override
  Future<String?> fetchUpdatedAt() async {
    final row = await _client
        .from(_table)
        .select('updated_at')
        .eq('user_id', _userId)
        .maybeSingle();
    return row?['updated_at'] as String?;
  }

  @override
  Future<CloudBackup?> fetchBackup() async {
    final row = await _client
        .from(_table)
        .select('payload, updated_at')
        .eq('user_id', _userId)
        .maybeSingle();
    if (row == null) return null;
    return CloudBackup(
      updatedAt: row['updated_at'] as String,
      payload: Map<String, dynamic>.from(row['payload'] as Map),
    );
  }

  @override
  Future<String> upload(Map<String, dynamic> payload) async {
    // O valor gravado é lido de volta para comparar com o que os outros
    // aparelhos verão, sem depender do formato de data do servidor.
    final row = await _client
        .from(_table)
        .upsert({
          'user_id': _userId,
          'payload': payload,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select('updated_at')
        .single();
    return row['updated_at'] as String;
  }

  String get _userId {
    final id = currentUserId;
    if (id == null) throw StateError('Nenhuma conta conectada.');
    return id;
  }
}
