import 'dart:convert';

import 'package:drift/drift.dart';

/// Stores a list of enums as a JSON array of their names.
abstract class EnumListConverter<T extends Enum> extends TypeConverter<List<T>, String> {
  const EnumListConverter();

  List<T> get values;

  @override
  List<T> fromSql(String fromDb) {
    final names = (jsonDecode(fromDb) as List<Object?>).cast<String>();
    return [for (final name in names) values.byName(name)];
  }

  @override
  String toSql(List<T> value) => jsonEncode([for (final v in value) v.name]);
}

/// Stores a string-to-int map (assessment answers) as JSON.
class IntMapConverter extends TypeConverter<Map<String, int>, String> {
  const IntMapConverter();

  @override
  Map<String, int> fromSql(String fromDb) => (jsonDecode(fromDb) as Map<String, Object?>).cast<String, int>();

  @override
  String toSql(Map<String, int> value) => jsonEncode(value);
}
