/// Impressão digital determinística de um snapshot do banco local.
///
/// O hash precisa ser estável entre dispositivos e entre exportações: a mesma
/// informação gravada em ordens diferentes (linhas ou chaves) tem de produzir o
/// mesmo valor. Por isso o snapshot é convertido em um JSON canônico — chaves
/// em ordem alfabética, listas de linhas ordenadas pelo próprio conteúdo — e só
/// então resumido com FNV-1a de 64 bits.
///
/// FNV-1a é usado no lugar de um hash criptográfico porque aqui ele só compara
/// versões dos próprios dados do usuário; assim o aplicativo não ganha nenhuma
/// dependência nova.
library;

import 'dart:convert';

/// Chaves ignoradas no hash por mudarem a cada exportação, sem representarem
/// mudança real nos dados do usuário.
const Set<String> _volatileKeys = {'exported_at'};

/// JSON canônico de [value]: chaves ordenadas e listas ordenadas pelo conteúdo.
String canonicalSnapshotJson(Object? value) {
  final buffer = StringBuffer();
  _write(buffer, value);
  return buffer.toString();
}

/// Resumo FNV-1a de 64 bits do JSON canônico de [snapshot], em hexadecimal.
String snapshotHash(Object? snapshot) =>
    _fnv1a64(canonicalSnapshotJson(snapshot));

void _write(StringBuffer buffer, Object? value) {
  if (value == null) {
    buffer.write('null');
    return;
  }
  if (value is bool) {
    buffer.write(value ? 'true' : 'false');
    return;
  }
  if (value is num) {
    buffer.write(_number(value));
    return;
  }
  if (value is Map) {
    final keys = value.keys
        .map((key) => key.toString())
        .where((key) => !_volatileKeys.contains(key))
        .toList()
      ..sort();
    buffer.write('{');
    for (var index = 0; index < keys.length; index++) {
      if (index > 0) buffer.write(',');
      buffer
        ..write(jsonEncode(keys[index]))
        ..write(':');
      _write(buffer, value[keys[index]]);
    }
    buffer.write('}');
    return;
  }
  if (value is Iterable) {
    // As listas de um snapshot são linhas de tabela: o conteúdo importa, a
    // ordem em que o banco as devolveu não.
    final items = value.map(canonicalSnapshotJson).toList()..sort();
    buffer
      ..write('[')
      ..writeAll(items, ',')
      ..write(']');
    return;
  }
  buffer.write(jsonEncode(value.toString()));
}

/// Números inteiros e decimais de mesmo valor viram o mesmo texto: o banco
/// devolve `100.0` onde o JSON da nuvem pode devolver `100`.
String _number(num value) {
  if (value is int) return value.toString();
  final asDouble = value.toDouble();
  if (asDouble.isFinite && asDouble == asDouble.roundToDouble()) {
    return asDouble.toInt().toString();
  }
  return asDouble.toString();
}

/// FNV-1a de 64 bits sobre os bytes UTF-8 do texto canônico.
String _fnv1a64(String text) {
  const offsetBasis = 0xCBF29CE484222325;
  const prime = 0x100000001B3;
  var hash = offsetBasis;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    // Multiplicação de inteiros de 64 bits: o estouro é intencional.
    hash = hash * prime;
  }
  final high = (hash >> 32) & 0xFFFFFFFF;
  final low = hash & 0xFFFFFFFF;
  return high.toRadixString(16).padLeft(8, '0') +
      low.toRadixString(16).padLeft(8, '0');
}
