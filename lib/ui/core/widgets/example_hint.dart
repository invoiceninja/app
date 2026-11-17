import 'package:material_ui/material_ui.dart';

import 'package:admin/l10n/localization.dart';

/// [example] worded as an example — "e.g. 31 Jan 2000" — for the placeholder
/// of an empty field whose worked example would otherwise look like a value.
///
/// A bare example in hint grey reads as data: design reviews took a blank due
/// date's `31/Jan/2000` for a date already set (and overdue), and a blank
/// estimate's `1h 30m` for a real estimate. Every worked-example placeholder —
/// `InDateField`, `InTimeField`, the task duration fields — goes through this
/// one helper and its one key (`example_value_hint`), so they cannot drift.
String exampleHint(BuildContext context, String example) =>
    context.tr('example_value_hint', {'value': example});

/// The worked example a duration field shows — a shape `parseDuration`
/// accepts — for [exampleHint].
const String kDurationExample = '1h 30m';
