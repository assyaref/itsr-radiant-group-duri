/// Helpers for reading PostgREST embedded resources, e.g.
/// `select=*,reporter:profiles!tickets_reporter_id_fkey(full_name)`.
///
/// For a field named `reporter_name` this reads `json['reporter']['full_name']`.
Object? readEmbeddedName(Map<dynamic, dynamic> json, String key) {
  final embedded = json[key.replaceAll('_name', '')];
  if (embedded is Map) return embedded['full_name'];
  return json[key];
}
