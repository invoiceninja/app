/// File name patterns — Settings → Generated Numbers → File Names
/// (invoiceninja/invoiceninja discussion #12610). The server names the PDF and
/// e-invoice a client or vendor receives from these; this file holds the keys,
/// the one rule a pattern must keep, the presets, and a port of the server's
/// resolver (`app/Utils/FileNamePattern.php`) that drives the page's "e.g."
/// example and nothing else — a real download takes the name the server sends
/// (docs/file-downloads.md).
///
/// Imports nothing.
library;

/// The pattern settings, in the order the page lists them.
const List<String> kFileNamePatternKeys = [
  'invoice_filename_pattern',
  'quote_filename_pattern',
  'credit_filename_pattern',
  'purchase_order_filename_pattern',
];

/// The "Simplified File Names" switch.
const String kFileNameSlugKey = 'filename_slug';

/// Whether the server supports file name patterns: its company settings carry
/// the keys. The server writes every known key into a company's settings on
/// its next save, so a server without the feature never has them.
bool fileNamePatternsSupported(Map<String, dynamic> rawCompanySettings) =>
    rawCompanySettings.containsKey(kFileNamePatternKeys.first);

/// A pattern the server would ignore: one without `$number`, which is what
/// keeps two documents from sharing a name. Blank is fine (the default name).
bool fileNamePatternMissingNumber(String? pattern) {
  final value = pattern ?? '';
  return value.trim().isNotEmpty && !value.contains(r'$number');
}

/// The patterns the Presets menu offers, after "Standard" (blank).
const List<String> kFileNamePresets = [
  r'$number',
  r'$company.name - $entity - $number',
  r'$client.name - $entity - $number',
  r'$date - $entity - $number',
];

/// [pattern] for a purchase order: the client variables a preset or the
/// invoice pattern uses become their vendor ones, and `$po_number` (a client
/// document's purchase order number) is dropped.
String fileNamePatternForPurchaseOrder(String pattern) => pattern
    .replaceAll(r'$client.', r'$vendor.')
    .replaceAll(RegExp(r'\s*\$po_number'), '');

/// The file name [pattern] gives a document whose variables have [values]
/// (keyed `$number`, `$client.name`, …), as the server builds it, with the
/// extension; null when the pattern can't be used. Close to the server, not
/// identical: Latin accents fold to plain letters here, where the server
/// folds by the client's language (ü → ue in German) and transliterates other
/// scripts (Cyrillic, Greek…), which this drops.
String? fileNameExample(
  String pattern,
  Map<String, String> values, {
  bool slug = false,
  String extension = 'pdf',
}) {
  if (!pattern.contains(r'$number') || (values[r'$number'] ?? '').isEmpty) {
    return null;
  }
  final keys = values.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final map = <String, String>{};
  for (final key in keys) {
    final raw = values[key]!;
    // A long client name or custom value must not push the number out.
    final value = key == r'$number' || raw.length <= 40
        ? raw
        : raw.substring(0, 40).trimRight();
    map[key] = value;
    map['{$key}'] = value;
  }
  final tokens = map.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  var name = pattern.replaceAllMapped(
    RegExp(tokens.map(RegExp.escape).join('|')),
    (m) => map[m.group(0)!]!,
  );
  name = _foldAccents(name)
      .replaceAll(RegExp(r'[^A-Za-z0-9\s\-_~,;\[\]().]'), '')
      .replaceAll(RegExp(r'\.{2,}'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (slug) {
    name = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]+'), '-');
  }
  if (name.length > 150) name = name.substring(0, 150);
  name = name.replaceAll(RegExp(r'^[ .\-_]+|[ .\-_]+$'), '');
  return name.isEmpty ? null : '$name.$extension';
}

const _kAccents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae', //
  'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i', //
  'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', //
  'ö': 'o', 'ø': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', //
  'ÿ': 'y', 'ß': 'ss', 'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', //
  'Å': 'A', 'Æ': 'AE', 'Ç': 'C', 'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E', //
  'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I', 'Ñ': 'N', 'Ò': 'O', 'Ó': 'O', //
  'Ô': 'O', 'Õ': 'O', 'Ö': 'O', 'Ø': 'O', 'Ù': 'U', 'Ú': 'U', 'Û': 'U', //
  'Ü': 'U', 'Ý': 'Y', 'ā': 'a', 'ă': 'a', 'ą': 'a', 'ć': 'c', 'č': 'c', //
  'ď': 'd', 'đ': 'd', 'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e', 'ğ': 'g', //
  'ī': 'i', 'į': 'i', 'ı': 'i', 'ķ': 'k', 'ļ': 'l', 'ł': 'l', 'ľ': 'l', //
  'ń': 'n', 'ň': 'n', 'ņ': 'n', 'ō': 'o', 'ő': 'o', 'œ': 'oe', 'ŕ': 'r', //
  'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ș': 's', 'ť': 't', 'ţ': 't', //
  'ț': 't', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u', 'ź': 'z', 'ż': 'z', //
  'ž': 'z', 'Ā': 'A', 'Ă': 'A', 'Ą': 'A', 'Ć': 'C', 'Č': 'C', 'Ď': 'D', //
  'Đ': 'D', 'Ē': 'E', 'Ė': 'E', 'Ę': 'E', 'Ě': 'E', 'Ğ': 'G', 'Ī': 'I', //
  'Į': 'I', 'İ': 'I', 'Ķ': 'K', 'Ļ': 'L', 'Ł': 'L', 'Ľ': 'L', 'Ń': 'N', //
  'Ň': 'N', 'Ņ': 'N', 'Ō': 'O', 'Ő': 'O', 'Œ': 'OE', 'Ŕ': 'R', 'Ř': 'R', //
  'Ś': 'S', 'Š': 'S', 'Ş': 'S', 'Ș': 'S', 'Ť': 'T', 'Ţ': 'T', 'Ț': 'T', //
  'Ū': 'U', 'Ů': 'U', 'Ű': 'U', 'Ų': 'U', 'Ź': 'Z', 'Ż': 'Z', 'Ž': 'Z', //
  // Typographic dashes, which a Mac substitutes as you type.
  '–': '-', '—': '-', '‐': '-', '‑': '-',
};

String _foldAccents(String s) {
  final out = StringBuffer();
  for (final rune in s.runes) {
    final char = String.fromCharCode(rune);
    out.write(_kAccents[char] ?? char);
  }
  return out.toString();
}
