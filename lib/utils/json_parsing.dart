/// Small helpers for reading values out of API responses.
///
/// Backend responses are not assumed to be perfect: fields may be missing,
/// null, or sent as strings. These helpers return null instead of throwing so
/// each model can decide on a sensible fallback.
double? asDouble(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.trim());
  return null;
}

int? asInt(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  if (raw is String) return int.tryParse(raw.trim()) ?? double.tryParse(raw.trim())?.round();
  return null;
}

/// Returns a trimmed non-empty string, or null.
String? asText(Object? raw) {
  if (raw is! String) return null;
  final String trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Returns the value at [key] when it is a JSON object, otherwise null.
Map<String, dynamic>? asMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return raw.cast<String, dynamic>();
  return null;
}

/// Returns [raw] as a list of JSON objects, skipping anything malformed.
List<Map<String, dynamic>> asMapList(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .map(asMap)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}
