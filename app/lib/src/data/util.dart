// util.dart — shared JS-parity helpers for the Dart normalizer port. The worker's
// normalizers are written in JS; these reproduce the JS semantics the ports lean
// on (truthiness, `||` short-circuit, parseInt, the two `pick` variants) so the
// Dart output matches byte-for-byte. Used by normalize.dart / summary.dart /
// standings.dart / etc.

/// Nullable field read off a possibly-non-map value (JS `o?.k`).
dynamic field(dynamic o, String k) => o is Map ? o[k] : null;

/// First element of a possibly-non-list value (JS `arr?.[0]`).
dynamic first(dynamic v) => v is List && v.isNotEmpty ? v[0] : null;

/// Force https (JS `u.replace(/^http:/, 'https:')`); null passes through.
String? https(dynamic u) =>
    u is String ? u.replaceFirst(RegExp(r'^http:'), 'https:') : null;

/// JS truthiness: null/false/0/''/NaN are falsy, everything else truthy.
bool truthy(dynamic v) {
  if (v == null || v == false || v == '') return false;
  if (v is num) return v != 0 && !v.isNaN;
  return true;
}

/// JS `a || b || …` short-circuit: the first truthy operand, else the last.
dynamic or(List<dynamic> vals) {
  for (var i = 0; i < vals.length; i++) {
    if (i == vals.length - 1 || truthy(vals[i])) return vals[i];
  }
  return null;
}

/// JS `String(v)` for our uses: '' for null, else toString.
String jsStr(dynamic v) => v == null ? '' : v.toString();

/// JS parseInt(s, 10): leading (optionally signed) integer, ignoring trailing
/// junk; null when there's no leading digit. (int.tryParse is stricter.)
int? jsParseInt(dynamic v) {
  if (v == null) return null;
  final m = RegExp(r'^[+-]?\d+').firstMatch(v.toString().trim());
  return m == null ? null : int.tryParse(m.group(0)!);
}

/// normalize.js's `pick`: keep keys whose value is non-null (JS `!= null`).
Map<String, dynamic> pickNN(Map src, List<String> keys) => {
      for (final k in keys)
        if (src[k] != null) k: src[k]
    };

/// summary.js's `pick`: keep keys whose value is non-null AND non-empty-string
/// (JS `o[k] != null && o[k] !== ''`).
Map<String, dynamic> pickT(Map src, List<String> keys) => {
      for (final k in keys)
        if (src[k] != null && src[k] != '') k: src[k]
    };

/// Dark-mode logo derived from a team's `logos[]` alone (standings.js /
/// rankings.js variant — no sport gate): explicit 'dark' rel, else the /500/ ->
/// /500-dark/ CDN derivation. Null when neither applies.
String? darkFromLogos(dynamic team) {
  final ls = field(team, 'logos');
  if (ls is List) {
    Map? pickDark(bool Function(List rel) test) {
      for (final l in ls) {
        final rel = field(l, 'rel');
        if (rel is List && test(rel)) return l as Map;
      }
      return null;
    }

    final d = pickDark((rel) => rel.contains('dark') && !rel.contains('scoreboard')) ??
        pickDark((rel) => rel.contains('dark'));
    final href = field(d, 'href');
    if (href != null) return https(href);
  }
  final light = https(field(first(ls), 'href'));
  return (light != null && light.contains('/i/teamlogos/') && light.contains('/500/'))
      ? light.replaceFirst('/500/', '/500-dark/')
      : null;
}
