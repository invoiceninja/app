import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
// The format rules' model types are not exported, and the national prefix a
// national number is written with ("020", "(02)") is only in them — the
// library's own national format leaves it off ("20 7946 0958").
// ignore: implementation_imports
import 'package:phone_numbers_parser/src/metadata/models/phone_metadata_formats.dart';

/// How a stored phone number is **shown** — never what is dialled, texted or
/// copied, which stay the stored text (`telUri` / `cleanPhoneNumber`).
///
/// Reformatted only when the number parses to a valid one with no doubt
/// about which: written nationally when it is in [regionIso]'s country (the
/// party's, else the company's), internationally otherwise. Everything else
/// comes back verbatim — a parse failure, an invalid number, an extension
/// ("x 22", "ext. 4", a `,` pause), letters ("call the office"), and a
/// number with no `+` when there is no region to read it against.
/// → `docs/tap-to-call.md` § A phone number is reformatted for display only.
String formatPhoneForDisplay(String stored, {String? regionIso}) {
  final text = stored.trim();
  if (text.isEmpty) return stored;
  // Only digits and the punctuation people write numbers with. A letter, a
  // `#`, `*`, `,` or `;` is an extension, a pause or prose: the user's text
  // says something a reformat would lose.
  if (!_plainNumber.hasMatch(text)) return stored;
  final region = _isoCode(regionIso);
  final international = text.startsWith('+');
  // A national number is a guess without a country to read it in.
  if (!international && region == null) return stored;
  final PhoneNumber number;
  try {
    number = PhoneNumber.parse(text, callerCountry: region);
  } catch (_) {
    return stored;
  }
  if (number.nsn.isEmpty || !number.isValid()) return stored;
  if (number.isoCode == region) {
    return _national(number) ?? stored;
  }
  final nsn = number.formatNsn(format: NsnFormat.international);
  return '+${number.countryCode} $nsn';
}

final RegExp _plainNumber = RegExp(r'^\+?[0-9\s().\-/]+$');

IsoCode? _isoCode(String? iso) {
  final code = iso?.trim().toUpperCase() ?? '';
  if (code.isEmpty) return null;
  for (final c in IsoCode.values) {
    if (c.name == code) return c;
  }
  return null;
}

/// [number] as it is written at home — with its national prefix where the
/// country writes one (`020 7946 0958`, `(02) 9876 5432`), which the
/// library's national format leaves off. Null when the rule cannot be applied
/// cleanly, so the caller shows the stored text rather than a guess.
String? _national(PhoneNumber number) {
  final formatted = number.formatNsn();
  final rule = _formatRule(
    number.isoCode,
    number.nsn,
  )?.nationalPrefixFormattingRule;
  if (rule == null || rule.isEmpty) return formatted;
  final prefix = metadataByIsoCode[number.isoCode]?.nationalPrefix ?? '';
  if (rule.contains(r'$NP') && prefix.isEmpty) return null;
  final first = RegExp(r'^\d+').firstMatch(formatted)?.group(0);
  if (first == null) return null;
  final group = rule.replaceAll(r'$NP', prefix).replaceAll(r'$FG', first);
  return '$group${formatted.substring(first.length)}';
}

/// The format rule the library picks for [nsn] — the same choice
/// `PhoneNumberFormatter` makes (a lone rule, else the first whose last
/// leading-digits pattern and whole pattern both match).
PhoneMetadataFormat? _formatRule(IsoCode iso, String nsn) {
  PhoneMetadataFormatDefinition? def = metadataFormatsByIsoCode[iso];
  // A country can borrow another's rules (Guernsey uses the UK's); a cycle
  // is not expected, but a bounded walk cannot hang a build.
  for (var i = 0; i < 4 && def is PhoneMetadataFormatReferenceDefinition; i++) {
    def = metadataFormatsByIsoCode[def.referenceIsoCode];
  }
  if (def is! PhoneMetadataFormatListDefinition) return null;
  final rules = def.formats;
  if (rules.isEmpty) return null;
  if (rules.length == 1) return rules.single;
  for (final r in rules) {
    final leading = r.leadingDigits.isEmpty
        ? true
        : RegExp(r.leadingDigits.last).matchAsPrefix(nsn) != null;
    if (leading && RegExp('^(?:${r.pattern})\$').hasMatch(nsn)) return r;
  }
  return null;
}
