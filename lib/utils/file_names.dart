import 'dart:convert';
import 'dart:typed_data';

import 'package:admin/utils/bidi.dart';

/// Characters no platform this app shares files to will accept in a **file
/// name**, plus the ASCII control range.
///
/// `/` is the POSIX path separator and `\` the Windows one, so either turns a
/// name into a path and the write lands in a directory that does not exist. The
/// rest (`:*?"<>|`) are rejected outright by Win32.
final _kIllegal = RegExp(r'[/\\:*?"<>|\x00-\x1f]');

/// Runs of separator-ish characters left behind by the substitution.
final _kRuns = RegExp(r'[-\s_]{2,}');

/// Win32 reserved device names — a file called `NUL.pdf` cannot be created even
/// though every character in it is legal.
const _kReserved = <String>{
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
};

/// Longest base name we will hand to a platform share sheet, **in UTF-8 bytes**.
///
/// Bytes, not characters: `NAME_MAX` is 255 *bytes* on ext4/f2fs and APFS, and 96
/// CJK characters is 288 of them — which fails the write, which `printing`
/// swallows, which is the exact silent failure this file exists to prevent.
/// Well under the limit because on some targets it applies to the whole *path*
/// and the temp directory we are writing into is not ours to measure.
const _kMaxBytes = 96;

/// Make [name] safe to use as a file name on macOS, iOS, Android, Windows and
/// Linux, falling back to [fallback] when nothing usable survives.
///
/// This is a **backstop at the point a name reaches the platform**, not a
/// validator for the caller to reason about — every producer here interpolates
/// something a user or a server controls:
///
///  * a document *number*, whose pattern is a company setting, so `INV/2026/0001`
///    is an ordinary European numbering scheme rather than an edge case;
///  * a saved-version timestamp, which is rendered through the company's
///    `date_format_id` and therefore carries `/` on four of the fourteen formats
///    (including the server's default, `dd/MMM/yyyy`) and a `:` on all of them.
///
/// Why it has to be here and cannot be left to `printing`: every one of that
/// package's native share implementations concatenates the name onto a temp
/// directory and **swallows the failure** — macOS/iOS `catch { print(…); return }`,
/// Android `catch (IOException e) { e.printStackTrace(); }`, Windows an
/// unchecked `ofstream` followed by a `ShellExecute` on a path that was never
/// written. So an illegal name is not an error the user sees; it is a Share
/// button that does nothing at all.
String sanitizeFileName(String name, {String fallback = 'document'}) {
  // A label from `tr()` carries invisible bidi isolates in a right-to-left
  // locale; in a file name they are noise at best.
  var out = stripBidiControls(
    name,
  ).replaceAll(_kIllegal, '-').replaceAll(_kRuns, '-');
  // Windows also refuses a trailing dot or space, and a leading dot would make
  // the file hidden on POSIX.
  out = out.replaceAll(RegExp(r'^[.\s-]+|[.\s-]+$'), '');
  if (utf8.encode(out).length > _kMaxBytes) {
    out = _capBytes(out).replaceAll(RegExp(r'[.\s-]+$'), '');
  }
  if (out.isEmpty) return fallback;
  // Compared against the whole base name: `NUL` is reserved, `NUL-2` is not.
  if (_kReserved.contains(out.toLowerCase())) return '$out-file';
  return out;
}

/// [name] cut to [_kMaxBytes] of UTF-8.
///
/// Rune by rune, and measured in bytes: `substring` counts UTF-16 code units,
/// so it both under-counts a CJK name against `NAME_MAX` and can cut a
/// surrogate pair in half — leaving an unpaired surrogate that the platform
/// channel turns into U+FFFD, and that a trailing strip will not remove.
String _capBytes(String name) {
  final kept = StringBuffer();
  var bytes = 0;
  for (final rune in name.runes) {
    final char = String.fromCharCode(rune);
    final width = utf8.encode(char).length;
    if (bytes + width > _kMaxBytes) break;
    kept.write(char);
    bytes += width;
  }
  return kept.toString();
}

/// A file extension worth keeping apart from the base name: `.pdf`, `.xml`.
final _kExtension = RegExp(r'\.[A-Za-z0-9]{1,5}$');

/// Make a file name the **server** chose safe for the platform, changing as
/// little of it as it can; null when nothing usable survives.
///
/// Not [sanitizeFileName], whose separator collapse exists to tidy names this
/// app assembles: run over `Acme Ltd - Invoice - 0042.pdf` it would hand the
/// user `Acme Ltd-Invoice-0042`, a different name from the one the same
/// document has in the email and the client portal. A server name is already
/// what the company chose, so only what a platform refuses goes — the illegal
/// characters, a leading dot or space (and a trailing one where nothing
/// follows it: `Invoice_5..pdf`, which the server sends for invoice `5.`, is a
/// legal name), the bidi controls (which can disguise an extension), a base
/// past [_kMaxBytes], a Win32 device name.
String? sanitizeServerFileName(String name) {
  final clean = stripBidiControls(name).replaceAll(_kIllegal, '-').trim();
  final ext = _kExtension.firstMatch(clean)?.group(0) ?? '';
  final leading = RegExp(r'^[.\s]+');
  final trailing = RegExp(r'[.\s]+$');
  var base = clean
      .substring(0, clean.length - ext.length)
      .replaceAll(leading, '');
  if (utf8.encode(base).length > _kMaxBytes) base = _capBytes(base);
  // A dot or space is refused only at the very end of the name.
  if (ext.isEmpty) base = base.replaceAll(trailing, '');
  if (base.replaceAll(trailing, '').isEmpty) return null;
  // Windows takes the part before the FIRST dot as the device: `NUL.001.pdf`
  // is as reserved as `NUL.pdf`.
  final dot = base.indexOf('.');
  final stem = (dot < 0 ? base : base.substring(0, dot)).trimRight();
  if (_kReserved.contains(stem.toLowerCase())) {
    base = '$stem-file${dot < 0 ? '' : base.substring(dot)}';
  }
  return '$base$ext';
}

/// The file name in an HTTP `Content-Disposition` header, or null.
///
/// RFC 6266: `filename*` (RFC 5987, `charset'language'percent-encoded`) wins
/// over `filename`, which is a token or a quoted string. The server is Laravel
/// on Symfony, which writes the charset in lower case (`utf-8''`) and quotes any
/// name with a space or a `;` — and a legacy name may hold a `;` — so the
/// header is split into parameters on the semicolons *outside* quotes, and a
/// name can never smuggle in a parameter of its own. A malformed escape
/// (`50%.pdf`, or `%FF`, which is not UTF-8) must not fail a download that has
/// already arrived: it falls back to the plain name, or to none.
String? fileNameFromContentDisposition(String? header) {
  if (header == null || header.trim().isEmpty) return null;
  final params = _dispositionParams(header);
  final star = params['filename*'];
  if (star != null) {
    final parts = RegExp(r"^([^']*)'[^']*'(.*)$").firstMatch(star);
    final decoded = _percentDecode(
      parts?.group(2) ?? star,
      latin1: (parts?.group(1) ?? '').trim().toLowerCase() == 'iso-8859-1',
    );
    if (decoded != null && decoded.trim().isNotEmpty) return decoded.trim();
  }
  final plain = params['filename']?.trim();
  return plain == null || plain.isEmpty ? null : plain;
}

/// The `name=value` parameters of a `Content-Disposition` header, names lower
/// case, a quoted value unquoted (`\"` → `"`), the first of a repeated name kept.
/// Split on the semicolons outside quotes; an unterminated quote runs to the end.
Map<String, String> _dispositionParams(String header) {
  final parts = <String>[];
  var current = StringBuffer();
  var quoted = false;
  for (var i = 0; i < header.length; i++) {
    final char = header[i];
    if (quoted && char == r'\' && i + 1 < header.length) {
      current
        ..write(char)
        ..write(header[++i]);
      continue;
    }
    if (char == '"') quoted = !quoted;
    if (char == ';' && !quoted) {
      parts.add(current.toString());
      current = StringBuffer();
      continue;
    }
    current.write(char);
  }
  parts.add(current.toString());

  final params = <String, String>{};
  for (final part in parts) {
    // The disposition type (`attachment`) has no `=`.
    final eq = part.indexOf('=');
    if (eq < 0) continue;
    final name = part.substring(0, eq).trim().toLowerCase();
    var value = part.substring(eq + 1).trim();
    if (value.startsWith('"')) {
      value = value.length > 1 && value.endsWith('"')
          ? value.substring(1, value.length - 1)
          : value.substring(1);
      value = value.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
    }
    params.putIfAbsent(name, () => value);
  }
  return params;
}

final _kHexPair = RegExp(r'^[0-9A-Fa-f]{2}$');

/// An RFC 5987 value's percent escapes decoded as UTF-8 (or Latin-1); null for
/// a malformed escape or bytes that are not the charset.
String? _percentDecode(String encoded, {required bool latin1}) {
  final bytes = <int>[];
  final runes = encoded.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (rune == 0x25) {
      if (i + 2 >= runes.length) return null;
      final pair = String.fromCharCodes(runes.sublist(i + 1, i + 3));
      if (!_kHexPair.hasMatch(pair)) return null;
      bytes.add(int.parse(pair, radix: 16));
      i += 2;
    } else if (rune < 0x80 || (latin1 && rune <= 0xFF)) {
      bytes.add(rune);
    } else if (latin1) {
      return null;
    } else {
      // Not legal in an RFC 5987 value; take it as the character it is.
      bytes.addAll(utf8.encode(String.fromCharCode(rune)));
    }
  }
  try {
    return latin1 ? const Latin1Codec().decode(bytes) : utf8.decode(bytes);
  } on Object {
    return null;
  }
}

/// The name the server gave each response body, keyed by the body itself.
///
/// An `Expando`, so the name travels with the bytes through every
/// `Future<Uint8List>` between `ApiClient` and the screen that saves them
/// without a single signature changing — and goes when they do. A copy of the
/// bytes (`Uint8List.fromList`, `sublist`) is a different object and carries no
/// name; that is the safe direction, since the caller's own name still applies.
final _serverFileNames = Expando<String>('serverFileName');

/// Names the server writes on a response that is not a document's own file —
/// `live_preview`'s and `bulk_print`'s — and that must never replace one.
const _kPlaceholderNames = {'preview.pdf', 'print.pdf'};

/// Remembers the file name in [contentDisposition] for [bytes]; see
/// [serverFileNameOf].
void rememberServerFileName(Uint8List bytes, String? contentDisposition) {
  final name = fileNameFromContentDisposition(contentDisposition);
  if (name == null || _kPlaceholderNames.contains(name.toLowerCase())) return;
  _serverFileNames[bytes] = name;
}

/// The name the server gave [bytes] (made platform-safe by
/// [sanitizeServerFileName]), or null when the response carried none — an
/// older route, `live_preview`, or a fetch that did not ask to keep it.
///
/// It is the name the document has in its email attachment and the client
/// portal — today `Invoice_0042.pdf`, the type usually in the client's
/// language (docs/file-downloads.md). [extension] (`pdf`, `xml`) is appended
/// when the name lacks it: a save with no extension fails on web and opens in
/// nothing anywhere else.
String? serverFileNameOf(Uint8List bytes, {String? extension}) {
  final raw = _serverFileNames[bytes];
  final name = raw == null ? null : sanitizeServerFileName(raw);
  if (name == null || extension == null) return name;
  return name.toLowerCase().endsWith('.${extension.toLowerCase()}')
      ? name
      : '$name.$extension';
}
