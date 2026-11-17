import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/env.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/entity_record_column.dart';
import 'package:admin/ui/core/detail/entity_record_page.dart';
import 'package:admin/ui/core/detail/profile_card_width.dart';
import 'package:admin/ui/core/detail/record_timestamps.dart';
import 'package:admin/ui/core/list/entity_list_constants.dart';
import 'package:admin/ui/core/list/list_density_scope.dart';
import 'package:admin/ui/core/utils/phone_actions.dart';
import 'package:admin/ui/core/widgets/back_dismissible_menu_anchor.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';
import 'package:admin/ui/core/widgets/detail_info_row.dart';
import 'package:admin/ui/core/widgets/initials_avatar.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/core/widgets/phone_number_value.dart';
import 'package:admin/ui/core/widgets/status_pill.dart';
import 'package:admin/ui/features/dashboard/widgets/card_shell.dart';

/// One thing a contact row can do. [onTap] null means "not available for this
/// contact" and the action is left out entirely — a contact with no number
/// gets no Call button, greyed or otherwise.
@immutable
class PartyContactAction {
  const PartyContactAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

/// A person at a client or a vendor: who they are, how to reach them, and the
/// one or two things most often done with them.
///
/// Party-agnostic on purpose. `Contact` and `VendorContact` share no
/// supertype, so this takes plain strings and callbacks and each party builds
/// it from its own model.
///
/// **Two lines.** The name line — the name, the quieter Primary label, and
/// whatever [pills] the party adds (a billing document's Sent / Viewed) —
/// then the details: the address and the number in a `Wrap`, so the number
/// drops to its own line where the two do not fit side by side. Never a "·"
/// between them: at a wrap it would dangle at the end of the first line.
/// **The address is never shortened to an ellipsis** — a cut-off address is a
/// wrong one — so where even a line of its own is too narrow it wraps.
///
/// **Actions.** The first two of [actions] that are available become icon
/// buttons, at full touch size on touch; the rest go behind a `⋮`. Order
/// [actions] most-used first; an action that does not apply is skipped, so
/// the same list yields Call + Email on a phone and Email + Copy portal link
/// on a desktop with tap-to-call off.
///
/// **Email is text, not a link.** It copies — on tap with a finger, by the
/// hover icon with a pointer — and writing to it is the Email action. Making
/// the address itself launch a mail client would put two small links two
/// pixels apart (the phone beside it dials), and would take away the one
/// thing a desktop webmail user wants from an address: to copy it.
///
/// **No clock here.** The callee's local time is said once, in the card's
/// header (`ContactLocalTime.header`): every contact of a client shares the
/// client's timezone, and a vendor has none of its own.
///
/// Wrap the whole row in a `PhoneActionsScope` at the call site: the Call and
/// Message actions are computed above this widget, from a preference that can
/// change while the screen is mounted behind `/settings`.
class PartyContactRow extends StatelessWidget {
  const PartyContactRow({
    super.key,
    required this.name,
    required this.email,
    required this.phone,
    required this.actions,
    this.isPrimary = false,
    this.pills = const [],
    this.details = const [],
    this.phoneSubject,
    this.clientId,
    this.logTarget,
    this.avatarSeed,
    this.phoneRegion,
  });

  /// Draws a 32 px `InitialsAvatar` before the contact, seeded on this — the
  /// contact's id. Null draws none: the card decides for all of its rows at
  /// once ([showAvatars]), so one card never mixes the two.
  final String? avatarSeed;

  /// The country [phone] is read in for display (`phoneDisplayRegion`): the
  /// party's, else the company's. Display only — the call, the message and
  /// the copy use [phone] as stored.
  final String? phoneRegion;

  /// Whether the contact rows of a card at [context] get avatars: never on a
  /// phone (`isPhoneRecordLayout`), and elsewhere only where every one of
  /// [emails] still fits beside one ([avatarsFit]).
  ///
  /// The card's width comes from the layout that placed it
  /// (`ProfileCardWidthScope`), or is the rail's, known in advance. A card
  /// that is told neither draws none: it cannot measure itself, because the
  /// same card sits in a row levelled with `IntrinsicHeight`, where a
  /// `LayoutBuilder` may not go.
  static bool showAvatars(
    BuildContext context, {
    required Iterable<String> emails,
  }) {
    if (isPhoneRecordLayout(context)) return false;
    final card =
        ProfileCardWidthScope.of(context) ??
        (RecordColumnScope.isRail(context) ? kRecordRailWidth : null);
    if (card == null) return false;
    // The card's own padding and its 1 px border, each side.
    final width = card - InSpacing.lg(context) * 2 - 2;
    return avatarsFit(context, width: width, emails: emails);
  }

  /// Whether a card [width] wide has room for an avatar on every one of
  /// [emails] without wrapping any of them.
  ///
  /// The avatar costs 44 px of a row whose text is already the narrowest
  /// thing on it, so the card asks this once for all its rows, and draws
  /// avatars on all of them or on none. Measured, not estimated — the font,
  /// the text scale and the locale's glyphs all move the answer.
  static bool avatarsFit(
    BuildContext context, {
    required double width,
    required Iterable<String> emails,
  }) {
    final style = _detailStyle(context);
    // The worst case: two buttons and the `⋮`, after the gap before them.
    final actions = _actionSize() * 3 + InSpacing.sm;
    final room = width - actions - _kAvatarSize - _kAvatarGap;
    if (room <= 0) return false;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    try {
      for (final email in emails) {
        if (email.isEmpty) continue;
        painter
          ..text = TextSpan(text: email, style: style)
          ..layout();
        if (painter.width > room) return false;
      }
    } finally {
      painter.dispose();
    }
    return true;
  }

  /// Empty falls back to [email], then to `no_name_fallback`.
  final String name;
  final String email;
  final String phone;

  /// Most-used first. See the class doc for how they are split.
  final List<PartyContactAction> actions;

  /// Draws [PartyContactPrimaryLabel] beside the name. The caller passes
  /// `contact.isPrimary` **only when the party has two or more contacts worth
  /// showing** — beside a lone contact the word answers nothing.
  final bool isPrimary;

  /// Labels on the name line — Unsubscribed, CC Only, a billing document's
  /// Sent / Viewed. Empty for the ordinary contact.
  final List<Widget> pills;

  /// Extra read-only lines, already "Label: value" — last portal login,
  /// contact custom fields.
  final List<String> details;

  /// Passed to `PhoneNumberValue` — who the confirm prompt names, whose
  /// timezone the out-of-hours check uses, and where a finished call is logged.
  final String? phoneSubject;
  final String? clientId;
  final CallLogTarget? logTarget;

  /// How many of [actions] get their own button.
  static const int _primaryCount = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.inTheme;
    final hasName = name.trim().isNotEmpty;
    final title = hasName
        ? name.trim()
        : (email.isNotEmpty ? email : context.tr('no_name_fallback'));
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      color: tokens.ink,
      fontWeight: FontWeight.w500,
    );
    final subStyle = _detailStyle(context);
    final available = [
      for (final a in actions)
        if (a.onTap != null) a,
    ];
    final primary = available.take(_primaryCount).toList(growable: false);
    final overflow = available.skip(_primaryCount).toList(growable: false);

    // No `maxLines`, no ellipsis: a cut-off address is a wrong one. Too long
    // for its line, it wraps.
    Widget emailLine(TextStyle? style) => CopyableValue(
      value: email,
      // Its own width, so it can share a line with the number; the copy icon
      // floats rather than holding a slot between the two.
      fillWidth: false,
      floatIcon: true,
      child: LtrText(email, style: style),
    );

    final nameLine = Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // The title is the email only when there is no name, and then it is
        // the copyable one.
        if (hasName || email.isEmpty)
          Text(title, style: titleStyle)
        else
          emailLine(titleStyle),
        // A word, where this was a star: a star says nothing to a screen
        // reader and little to anyone who has not learned it.
        if (isPrimary) const PartyContactPrimaryLabel(),
        ...pills,
      ],
    );

    final hasEmailLine = hasName && email.isNotEmpty;
    final facts = [
      if (hasEmailLine) emailLine(subStyle),
      if (phone.isNotEmpty)
        PhoneNumberValue(
          phone: phone,
          style: subStyle,
          subject: phoneSubject,
          clientId: clientId,
          logTarget: logTarget,
          regionIso: phoneRegion,
          // Said once, in the card's header.
          showLocalTime: false,
        ),
    ];

    final seed = avatarSeed;
    final Widget row = Padding(
      // Compact density's 4 px, else 8 — the record's list rows' rule.
      padding: EdgeInsets.symmetric(
        vertical: listRowVerticalPadding(context, normal: InSpacing.sm),
      ),
      child: Row(
        // Centred against the buttons: the two lines are a block beside them.
        children: [
          if (seed != null) ...[
            ExcludeSemantics(
              child: InitialsAvatar(
                seed: seed,
                label: initialsFor(title) ?? '?',
                size: _kAvatarSize,
              ),
            ),
            const SizedBox(width: _kAvatarGap),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                nameLine,
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  // Not a `LayoutBuilder`: this row sits in a card levelled
                  // with `IntrinsicHeight`.
                  Wrap(
                    spacing: InSpacing.lg(context),
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: facts,
                  ),
                ],
                for (final line in details) ...[
                  const SizedBox(height: 2),
                  Text(line, style: subStyle),
                ],
              ],
            ),
          ),
          if (primary.isNotEmpty || overflow.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: InSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final a in primary) _ActionButton(action: a),
                  if (overflow.isNotEmpty) _OverflowButton(actions: overflow),
                ],
              ),
            ),
        ],
      ),
    );
    // A pointer gets a faint wash under the row it is over; a finger has no
    // hover, and a wash left behind by a tap would read as a selection.
    return Env.isTouchPrimary ? row : _HoverWash(child: row);
  }
}

/// The details line's style. `ink2`: these are the contact's actual details,
/// and `ink3` at this size is under the contrast floor on a card.
TextStyle? _detailStyle(BuildContext context) => Theme.of(
  context,
).textTheme.bodySmall?.copyWith(color: context.inTheme.ink2);

const double _kAvatarSize = 32;
const double _kAvatarGap = 12;

/// The row's hover wash: the translucent `ink` the entity lists' rows use
/// (`selectable_list_row.dart`), painted a little past the row's sides so the
/// text does not sit on the wash's edge. Painted, not a `Material`: nothing
/// here is a tap target, and the actions keep their own feedback.
class _HoverWash extends StatefulWidget {
  const _HoverWash({required this.child});

  final Widget child;

  @override
  State<_HoverWash> createState() => _HoverWashState();
}

class _HoverWashState extends State<_HoverWash> {
  bool _hovering = false;

  void _set(bool value) {
    if (_hovering != value) setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return MouseRegion(
      onEnter: (_) => _set(true),
      onExit: (_) => _set(false),
      child: CustomPaint(
        painter: _WashPainter(
          color: _hovering
              ? tokens.ink.withAlpha(light ? 0x0A : 0x14)
              : const Color(0x00000000),
        ),
        child: widget.child,
      ),
    );
  }
}

class _WashPainter extends CustomPainter {
  const _WashPainter({required this.color});

  final Color color;

  /// How far past each side of the row the wash reaches — inside the card's
  /// own padding, which is wider.
  static const double _outset = InSpacing.sm;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final rect = Rect.fromLTRB(-_outset, 0, size.width + _outset, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(InRadii.r2)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_WashPainter oldDelegate) => oldDelegate.color != color;
}

/// The side of a contact action button: the touch floor on touch, the app's
/// compact icon-button size with a pointer.
double _actionSize() => Env.isTouchPrimary ? InSizes.touchTarget : 32;

/// Pinned on both axes. Left to the theme an `IconButton` is floored at the
/// 48 px tap target on touch, which would make three of them wider than the
/// row can spare and taller than the three lines of text beside them.
ButtonStyle _pinned() {
  final size = _actionSize();
  return IconButton.styleFrom(
    fixedSize: Size.square(size),
    minimumSize: Size.zero,
    maximumSize: Size.infinite,
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final PartyContactAction action;

  @override
  Widget build(BuildContext context) => IconButton(
    style: _pinned(),
    tooltip: action.label,
    icon: Icon(action.icon, size: 18),
    onPressed: action.onTap,
  );
}

class _OverflowButton extends StatelessWidget {
  const _OverflowButton({required this.actions});

  final List<PartyContactAction> actions;

  @override
  Widget build(BuildContext context) => BackDismissibleMenuAnchor(
    consumeOutsideTap: true,
    menuChildren: [
      for (final a in actions)
        MenuItemButton(
          leadingIcon: Icon(a.icon, size: 18),
          onPressed: a.onTap,
          child: Text(a.label),
        ),
    ],
    builder: (context, controller, _) => IconButton(
      style: _pinned(),
      tooltip: context.tr('more'),
      icon: const Icon(Icons.more_vert, size: 18),
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
    ),
  );
}

/// A labelled exception under a contact's name. Neutral unless [alert] — an
/// unsubscribed contact is the one that explains an email that never arrived.
class PartyContactPill extends StatelessWidget {
  const PartyContactPill({super.key, required this.label, this.alert = false});

  final String label;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return StatusPill(
      label: label,
      fgColor: alert ? tokens.overdue : tokens.draft,
      bgColor: alert ? tokens.overdueSoft : tokens.draftSoft,
    );
  }
}

/// "Primary", beside the contact a client or vendor's mail goes to first.
///
/// Drawn only where it tells the user something — a party with two or more
/// contacts worth showing; on a lone contact it is noise. Quieter than the
/// status pills beside it: `accentInk` text in a 1 px `border` outline with
/// no fill, a rounded rectangle and never a pill (CLAUDE.md § Design system),
/// and a word where this used to be a star.
class PartyContactPrimaryLabel extends StatelessWidget {
  const PartyContactPrimaryLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Tooltip(
      message: context.tr('primary_contact'),
      child: Semantics(
        label: context.tr('primary_contact'),
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(InRadii.r1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              context.tr('primary'),
              maxLines: 1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: tokens.accentInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The record screen's Contacts card, for a client, a vendor or a billing
/// document's recipients: the title with the header's facts, the rows, and
/// "Show N more" under a hairline.
///
/// **The header** (`DashboardCardShell.trailing`) says, in order: how many
/// contacts there are — the *visible* ones the caller passes as [count], and
/// only from two, since "1" beside one row says nothing — then [localTime]
/// (a client's clock, said once for every contact), then [onAdd]'s "+ Add".
/// [extraTrailing] follows the count: a billing document's shared send state.
/// On a card too narrow for all of it the time goes first, then "+ Add"'s
/// label ([_headerFit]).
///
/// **The footer** is the whole width of the card, 44 px on touch and 36 with
/// a pointer: "Show N more" while [hiddenCount] rows wait, "Show less" once
/// they are out ([expanded]); none when everything fits.
class PartyContactsCard extends StatelessWidget {
  const PartyContactsCard({
    super.key,
    required this.rows,
    required this.count,
    this.localTime,
    this.extraTrailing = const [],
    this.onAdd,
    this.hiddenCount = 0,
    this.expanded = false,
    this.onShowMore,
    this.onShowLess,
  });

  final List<Widget> rows;

  /// How many contacts the party has worth showing — never `contacts.length`,
  /// which counts the blank one the server seeds.
  final int count;
  final Widget? localTime;
  final List<Widget> extraTrailing;

  /// Opens the party's editor on a new contact. Null hides "+ Add" — no edit
  /// permission, a deleted record, or a billing document.
  final VoidCallback? onAdd;

  final int hiddenCount;
  final bool expanded;
  final VoidCallback? onShowMore;
  final VoidCallback? onShowLess;

  /// What of the header's facts fit beside the title: the local time first
  /// to go, then "+ Add"'s label (the button stays, as a 44 px `+` with its
  /// tooltip). Measured with `TextPainter` against the width the layout told
  /// the card (`ProfileCardWidthScope`, or the rail's) — the card sits in a
  /// row levelled with `IntrinsicHeight`, where a `LayoutBuilder` may not go.
  ///
  /// A host that says neither gets the window's width less a phone's 12 px
  /// gutters — what a record column leaves a card on a phone — so a narrow
  /// window still sheds what its card cannot hold. A host that places the
  /// card narrower than that has to say so through the scope.
  ///
  /// [extraTrailing] is not measured: only a billing document passes it, and
  /// a document has neither a clock nor "+ Add" to shed.
  ({bool time, bool addLabel}) _headerFit(
    BuildContext context, {
    required bool touch,
  }) {
    const all = (time: true, addLabel: true);
    final hasTime = localTime != null;
    if (!hasTime && onAdd == null) return all;
    final card =
        ProfileCardWidthScope.of(context) ??
        (RecordColumnScope.isRail(context) ? kRecordRailWidth : null) ??
        MediaQuery.sizeOf(context).width - InSpacing.lg(context) * 2;
    final theme = Theme.of(context);
    final base = DefaultTextStyle.of(context).style;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    double measure(String text, TextStyle? style) {
      painter
        ..text = TextSpan(text: text, style: base.merge(style))
        ..layout();
      return painter.width;
    }

    try {
      // The shell's header row: the 1 px border each side, its start inset,
      // and an end inset that gives up 6 px to a touch-size button's slack.
      final row =
          card -
          2 -
          InSpacing.lg(context) -
          (onAdd != null && touch
              ? InSpacing.lg(context) - 6
              : InSpacing.lg(context));
      final title = measure(
        context.tr('contacts'),
        theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      );
      final countWidth = count >= 2
          ? measure('$count', theme.textTheme.bodySmall)
          : 0.0;
      final time = hasTime
          ? InSpacing.md(context) + ContactLocalTime.headerWidthBound(context)
          : 0.0;
      // `TextButton.icon`: its padding, the 16 px icon, the gap — 8 px,
      // closing to 4 as the text scales to 2x (`_TextButtonWithIconChild`)
      // — and the label; never under its 64 px minimum.
      final labelStyle = _quietButtonText(context);
      final grow =
          (MediaQuery.textScalerOf(context).scale(labelStyle?.fontSize ?? 14) /
                  14)
              .clamp(1.0, 2.0) -
          1;
      final addLabel = onAdd == null
          ? 0.0
          : InSpacing.xs +
                math.max(
                  64.0,
                  InSpacing.sm * 2 +
                      16 +
                      (8 - 4 * grow) +
                      measure(context.tr('add'), labelStyle),
                );
      final room = row - title - countWidth;
      if (time + addLabel <= room) return all;
      return (time: false, addLabel: addLabel <= room);
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final touch = Env.isTouchPrimary;
    // The shell's own body padding, which the footer has to step outside of
    // to run the card's full width: compact on a record screen is tighter.
    final dense =
        ListDensityScope.isCompactOf(context) &&
        RecordColumnScope.contains(context);
    final vertical = dense ? InSpacing.sm : InSpacing.md(context);
    final showFooter =
        (hiddenCount > 0 && onShowMore != null) ||
        (expanded && onShowLess != null);

    final fit = _headerFit(context, touch: touch);
    final addTarget = touch ? InSizes.touchTarget : 32.0;
    final trailing = <Widget>[
      if (count >= 2)
        LtrText(
          '$count',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: tokens.ink2),
        ),
      for (final w in extraTrailing) ...[
        const SizedBox(width: InSpacing.sm),
        w,
      ],
      if (localTime != null && fit.time) ...[
        SizedBox(width: InSpacing.md(context)),
        localTime!,
      ],
      if (onAdd != null) ...[
        const SizedBox(width: InSpacing.xs),
        if (fit.addLabel)
          Tooltip(
            message: context.tr('add_contact'),
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: Text(context.tr('add')),
              style: TextButton.styleFrom(
                foregroundColor: tokens.ink2,
                textStyle: _quietButtonText(context),
                minimumSize: Size(64, addTarget),
                padding: const EdgeInsets.symmetric(horizontal: InSpacing.sm),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          )
        else
          IconButton(
            onPressed: onAdd,
            tooltip: context.tr('add_contact'),
            icon: const Icon(Icons.add, size: 18),
            color: tokens.ink2,
            padding: EdgeInsets.zero,
            // Pinned, with no density and no padded tap target: either would
            // move the square off the size `_headerFit` budgeted for it.
            constraints: BoxConstraints.tightFor(
              width: addTarget,
              height: addTarget,
            ),
            visualDensity: VisualDensity.standard,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    ];

    return DashboardCardShell(
      title: context.tr('contacts'),
      trailing: trailing.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: trailing),
      // A 44 px "+ Add" sits inside the header band rather than adding its
      // height on top of the title's padding.
      trailingSpansBand: onAdd != null && touch,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              InSpacing.lg(context),
              vertical,
              InSpacing.lg(context),
              vertical,
            ),
            child: DetailRowStack(children: rows),
          ),
          if (showFooter) ...[
            Divider(height: 1, thickness: 1, color: tokens.border),
            TextButton.icon(
              onPressed: hiddenCount > 0 ? onShowMore : onShowLess,
              icon: Icon(
                hiddenCount > 0 ? Icons.expand_more : Icons.expand_less,
                size: 16,
              ),
              iconAlignment: IconAlignment.end,
              label: Text(
                hiddenCount > 0
                    ? context.tr('show_n_more', {'count': '$hiddenCount'})
                    : context.tr('show_less'),
              ),
              style: TextButton.styleFrom(
                foregroundColor: tokens.ink2,
                textStyle: _quietButtonText(context),
                minimumSize: Size(64, touch ? InSizes.touchTarget : 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                // The card's bottom corners, so the press and hover fills
                // stay inside its outline.
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(InRadii.r3 - 1),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The header's "+ Add" and the footer's "Show N more": the card's own
/// controls, a step quieter than its title. From the theme, so the face is
/// the app's — a bare `TextStyle` here would drop the font family.
TextStyle? _quietButtonText(BuildContext context) => Theme.of(
  context,
).textTheme.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w500);
