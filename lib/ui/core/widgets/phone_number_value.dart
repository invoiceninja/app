import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/value/timezone.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/utils/phone_actions.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';
import 'package:admin/ui/core/widgets/detail_info_row.dart';
import 'package:admin/ui/core/widgets/link_text.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/utils/phone_display.dart';

/// Compact button style shared by the contact-row actions (Call / Message /
/// View portal / Copy link) on the client and vendor detail cards.
///
/// Deliberately 32 rather than the 44 touch floor: these sit in a `Wrap` of
/// four, and growing them would leave the new Call / Message buttons towering
/// over the portal ones they sit beside.
final ButtonStyle contactActionButtonStyle = TextButton.styleFrom(
  minimumSize: const Size(0, 32),
  padding: const EdgeInsets.symmetric(horizontal: 8),
  visualDensity: VisualDensity.compact,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// Whether tapping a phone number should dial it, for this device and this
/// number. False for an undialable string ("call the office"), so a caller can
/// fall back to plain text instead of offering a dead tap.
///
/// **Read this under a listener, never bare.** See [PhoneActionsScope].
bool canDialPhone(BuildContext context, String phone) =>
    context.read<Services>().phoneActions.value.tapToCall &&
    telUri(phone) != null;

/// Rebuilds [builder] whenever the device's phone-action preferences change.
///
/// Load-bearing rather than decorative: a client detail screen sits mounted
/// behind the `/settings/**` route while the user flips "Tap to call", so a
/// plain build-time read would leave that screen rendering numbers with the
/// old styling until something unrelated rebuilt it.
class PhoneActionsScope extends StatelessWidget {
  const PhoneActionsScope({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: context.read<Services>().phoneActions,
    builder: (context, _) => builder(context),
  );
}

/// A [DetailInfoRow] whose value dials when tapped.
///
/// Degrades to exactly the pre-#109 behaviour — plain copyable text — when the
/// preference is off or the number isn't dialable, so a call site needs no
/// branching of its own. Callers still have to skip the row for an empty
/// number themselves: `DetailRowStack` inserts a divider per non-null child,
/// so returning a shrunk widget would leave a stray hairline.
class PhoneDetailRow extends StatelessWidget {
  const PhoneDetailRow({
    super.key,
    required this.label,
    required this.phone,
    this.subject,
    this.clientId,
    this.logTarget,
  });

  final String label;
  final String phone;

  /// Who is being called, for the confirmation prompt.
  final String? subject;

  /// Resolves the per-client timezone override for the out-of-hours warning.
  final String? clientId;

  /// Record a completed call can be logged against (invoiceninja/flutter#120).
  /// Null = don't offer to log — a team member's own number, say, which has no
  /// activity feed of its own.
  final CallLogTarget? logTarget;

  @override
  Widget build(BuildContext context) => PhoneActionsScope(
    builder: (context) {
      final dialable = canDialPhone(context, phone);
      return DetailInfoRow(
        label: label,
        value: phone,
        onTap: dialable
            ? () => callPhoneNumber(
                context,
                phone,
                subject: subject,
                clientId: clientId,
                logTarget: logTarget,
              )
            : null,
        // The suffix is a sibling of the value, not part of it, so `copyText`
        // stays the bare number.
        trailing: ContactLocalTime(clientId: clientId),
        semanticsLabel: dialable ? '${context.tr('call')} $phone' : null,
        // No tooltip on touch: there is no hover, and the long-press it would
        // otherwise fire on is already taken by copy.
        tooltip: dialable && !Env.isTouchPrimary ? context.tr('call') : null,
      );
    },
  );
}

/// The ISO 3166 code a phone number is read against for display
/// ([formatPhoneForDisplay]): the party's country when [countryId] names
/// one, else the company's. Null when neither is known — a number with no
/// `+` is then shown as typed.
String? phoneDisplayRegion(BuildContext context, {String countryId = ''}) {
  final services = context.read<Services>();
  var id = countryId;
  if (id.isEmpty) {
    final companyId = services.auth.currentCompanyId;
    if (companyId == null) return null;
    id = services.formatterIfReady(companyId)?.settings.countryId ?? '';
  }
  if (id.isEmpty) return null;
  final iso = services.statics.country(id)?.iso2 ?? '';
  return iso.isEmpty ? null : iso;
}

/// A phone number inside a contact card: dials on tap when enabled, still
/// copyable either way, with the callee's local time beside it when that
/// differs from this device's ([showLocalTime]).
///
/// **Shown reformatted, used as stored.** The text on screen is
/// [formatPhoneForDisplay] of [phone] against [regionIso]; the dial, the
/// message and the copy all take [phone] itself.
class PhoneNumberValue extends StatelessWidget {
  const PhoneNumberValue({
    super.key,
    required this.phone,
    this.style,
    this.subject,
    this.clientId,
    this.logTarget,
    this.regionIso,
    this.showLocalTime = true,
  });

  final String phone;
  final TextStyle? style;
  final String? subject;
  final String? clientId;

  /// The country a number with no `+` is read in, for display — the party's
  /// (`phoneDisplayRegion`). Null reads it in the company's.
  final String? regionIso;

  /// The callee's clock after the number. Off in the record screen's
  /// Contacts cards, which say it once in their header instead — every
  /// contact of a client shares the client's timezone.
  final bool showLocalTime;

  /// Record a completed call can be logged against (invoiceninja/flutter#120).
  /// Null = don't offer to log — a team member's own number, say, which has no
  /// activity feed of its own.
  final CallLogTarget? logTarget;

  @override
  Widget build(BuildContext context) => PhoneActionsScope(
    builder: (context) {
      final tokens = context.inTheme;
      final dialable = canDialPhone(context, phone);
      final shown = formatPhoneForDisplay(
        phone,
        regionIso: regionIso ?? phoneDisplayRegion(context),
      );
      // Hoisted so the `Semantics` below can re-declare the same action: its
      // `excludeSemantics` drops the child's own tap node along with the text.
      void dial() => callPhoneNumber(
        context,
        phone,
        subject: subject,
        clientId: clientId,
        logTarget: logTarget,
      );
      Widget display = dialable
          // The documented link treatment, the same as `DetailInfoRow`'s:
          // `accentInk` (the user's `accent` can fall under the contrast
          // floor), and an underline at rest only where there is no hover.
          // A client's own number and its contacts' numbers sit on one
          // screen and used to be two different blues.
          ? LinkText(
              label: shown,
              style: style,
              color: tokens.accentInk,
              underlineAtRest: linkNeedsAtRestCue,
              onTap: dial,
            )
          : LtrText(shown, style: style);
      if (dialable) {
        // `LinkText` emits no semantics of its own and takes no tooltip, so a
        // screen reader would otherwise announce a bare number with no hint
        // that it is actionable.
        display = Semantics(
          button: true,
          label: '${context.tr('call')} $shown',
          // Re-declared because `excludeSemantics` below drops the
          // descendant's own `SemanticsAction.tap` along with its text node,
          // leaving a button nothing could activate.
          onTap: dial,
          // Without this the child `Text` merges its own node in and the
          // number is announced twice ("Call +1 415…, +1 415…").
          excludeSemantics: true,
          child: Env.isTouchPrimary
              ? display
              : Tooltip(message: context.tr('call'), child: display),
        );
      }
      return CopyableValue(
        value: phone,
        // Tap is taken by the call, so copy moves to long-press — the same
        // trade `DetailInfoRow` makes for a launchable website.
        enableTapToCopy: !dialable,
        enableLongPressToCopy: dialable,
        fillWidth: false,
        child: showLocalTime
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(child: display),
                  ContactLocalTime(clientId: clientId),
                ],
              )
            : display,
      );
    },
  );
}

/// The `[ Call ] [ Message ]` pair for a contact row's action `Wrap`.
///
/// Empty when the number can't be dialled or the preference is off, so the
/// caller can spread it and let the `Wrap` collapse.
List<Widget> phoneActionButtons(
  BuildContext context,
  String phone, {
  String? subject,
  String? clientId,
  CallLogTarget? logTarget,
}) {
  if (!canDialPhone(context, phone)) return const [];
  return [
    TextButton.icon(
      style: contactActionButtonStyle,
      icon: const Icon(Icons.call_outlined, size: 14),
      label: Text(context.tr('call')),
      onPressed: () => callPhoneNumber(
        context,
        phone,
        subject: subject,
        clientId: clientId,
        logTarget: logTarget,
      ),
    ),
    TextButton.icon(
      style: contactActionButtonStyle,
      icon: const Icon(Icons.sms_outlined, size: 14),
      label: Text(context.tr('send_sms')),
      onPressed: () => messagePhoneNumber(context, phone),
    ),
  ];
}

/// A dimmed "11:47 PM" beside a phone number — **only** when the callee's zone
/// is not this device's.
///
/// The point is to catch the bad call before the tap rather than after it, and
/// the "only when it differs" rule is what keeps it from being noise: an
/// account whose clients are all domestic never sees it. Renders
/// `SizedBox.shrink()` in every other case (no timezone configured, no
/// company, offsets equal), so it costs nothing where it has nothing to say.
///
/// The zone is resolved asynchronously and this renders nothing until it lands
/// — deliberately not seeded from `SettingsRepository`'s synchronous
/// first-frame mirror, which exists so the invoice lock banner can size ~44px
/// of chrome on frame 1 and is allowed to be stale (`peek_is_seed_only_test`
/// pins its reach). Nothing moves when a trailing suffix appears a frame late,
/// so there is nothing here to buy with a stale answer.
///
/// A one-minute ticker keeps a screen left open from displaying a stale clock;
/// the check inside [callPhoneNumber] is recomputed at tap time regardless, so
/// this is presentation only.
///
/// [ContactLocalTime.header] is the Contacts card's form: "5:38 AM local",
/// said once for the whole card, with the timezone in a pointer tooltip and
/// in what a screen reader hears (`contact_local_time`).
class ContactLocalTime extends StatefulWidget {
  const ContactLocalTime({super.key, this.clientId}) : header = false;

  /// The Contacts card header's form — see the class doc.
  const ContactLocalTime.header({super.key, this.clientId}) : header = true;

  final String? clientId;
  final bool header;

  /// The widest [ContactLocalTime.header] can draw at [context], whatever
  /// the hour — so a card deciding whether the clock fits decides once, not
  /// again every minute as "9:59" turns into "10:00".
  ///
  /// Every hour is tried, in the clock the company reads, against the
  /// widest minute the font can draw: its widest tens digit (0–5), then its
  /// widest units digit.
  static double headerWidthBound(BuildContext context) {
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(_style(context, header: true));
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    double measure(String text) {
      painter
        ..text = TextSpan(text: text, style: style)
        ..layout();
      return painter.width;
    }

    String widest(int upTo) {
      var digit = 0;
      var width = 0.0;
      for (var d = 0; d <= upTo; d++) {
        final w = measure('$d');
        if (w > width) (width, digit) = (w, d);
      }
      return '$digit';
    }

    try {
      final minute = int.parse('${widest(5)}${widest(9)}');
      final military = _military(context);
      var bound = 0.0;
      for (var hour = 0; hour < 24; hour++) {
        final time = formatTimeOfDay(hour, minute, military: military);
        final w = measure(context.tr('local_time_short', {'time': time}));
        if (w > bound) bound = w;
      }
      return bound;
    } finally {
      painter.dispose();
    }
  }

  /// The company's 24-hour clock setting; 12-hour until its formatter is up.
  static bool _military(BuildContext context) {
    final services = context.read<Services>();
    final companyId = services.auth.currentCompanyId;
    return (companyId == null
            ? null
            : services
                  .formatterIfReady(companyId)
                  ?.settings
                  .enableMilitaryTime) ??
        false;
  }

  static TextStyle? _style(BuildContext context, {required bool header}) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
        color: context.inTheme.ink3,
        fontSize: header ? 12 : 11.5,
      );

  @override
  State<ContactLocalTime> createState() => _ContactLocalTimeState();
}

class _ContactLocalTimeState extends State<ContactLocalTime> {
  Timezone? _zone;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  @override
  void didUpdateWidget(covariant ContactLocalTime old) {
    super.didUpdateWidget(old);
    // Not reachable through today's routes — the detail subtree is keyed by
    // record id (`router.dart`), and every row in one contacts card shares a
    // client — but a stale clock for the *previous* contact is a silent lie,
    // and re-resolving is one Drift read.
    if (old.clientId != widget.clientId) unawaited(_resolve());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// The minute ticker only runs while there is a clock on screen. A contacts
  /// card renders one of these per contact and most of them show nothing, so
  /// arming unconditionally would leave a domestic account paying for a
  /// wake-up per contact per minute to rebuild empty boxes.
  void _syncTicker() {
    if (_shouldRender) {
      _ticker ??= Timer.periodic(
        const Duration(minutes: 1),
        (_) => setState(() {}),
      );
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Same offset as this device ⇒ the phone number's clock is the one the user
  /// is already reading off their own screen. Nothing to add.
  ///
  /// Both sides must be DST-aware or this inverts: `DateTime.timeZoneOffset`
  /// is, while the server's `Timezone.utcOffset` is standard-time only, so
  /// comparing against the raw constant told a New York user that their New
  /// York client was in a different zone for eight months a year — and then
  /// showed them a clock an hour behind. [contactClock] resolves the IANA name
  /// for both halves.
  bool get _shouldRender {
    final zone = _zone;
    return zone != null &&
        contactClock(zone).offset != DateTime.now().timeZoneOffset;
  }

  Future<void> _resolve() async {
    final services = context.read<Services>();
    final companyId = services.auth.currentCompanyId;
    if (companyId == null) return;
    final zone = await resolveContactTimezone(
      services: services,
      companyId: companyId,
      clientId: widget.clientId,
    );
    if (!mounted || zone?.id == _zone?.id) return;
    setState(() => _zone = zone);
    _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldRender) return const SizedBox.shrink();
    final zone = _zone!;
    final local = contactClock(zone).local;
    final time = formatTimeOfDay(
      local.hour,
      local.minute,
      military: ContactLocalTime._military(context),
    );
    final style = ContactLocalTime._style(context, header: widget.header);
    if (widget.header) {
      final zoneName = zone.name.isEmpty ? zone.location : zone.name;
      Widget text = Text(
        context.tr('local_time_short', {'time': time}),
        style: style,
        maxLines: 1,
      );
      // No tooltip on touch: there is no hover to show it.
      if (!Env.isTouchPrimary) {
        text = Tooltip(message: zoneName, child: text);
      }
      return Semantics(
        label: context.tr('contact_local_time', {
          'time': time,
          'timezone': zoneName,
        }),
        excludeSemantics: true,
        child: text,
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: InSpacing.sm),
      child: Text(time, style: style),
    );
  }
}
