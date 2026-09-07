import 'dart:convert';
import 'package:crypto/crypto.dart';

dynamic _canonical(dynamic value) {
  if (value is List) return value.map(_canonical).toList();
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  return value;
}

String uploadStateHash(String operation, Map<String, dynamic> payload) {
  return sha256
      .convert(
        utf8.encode(
          jsonEncode(
            _canonical({
              'operation': operation == 'delete' ? 'delete' : 'upsert',
              'payload': payload,
            }),
          ),
        ),
      )
      .toString();
}
