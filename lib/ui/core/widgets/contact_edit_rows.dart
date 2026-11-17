import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/domain/contact_email_mode.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/edit/add_contact_request.dart';
import 'package:admin/ui/core/widgets/field_label.dart';
import 'package:admin/ui/core/widgets/initials_avatar.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/core/widgets/notify.dart';

/// What the edit screens' contact list needs to know about one contact. A
/// client's `Contact` and a vendor's `VendorContact` are separate models with
/// the same fields; this is the part of them a row reads.
class ContactRowData {
  const ContactRowData({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.isPrimary,
    required this.isBlank,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final bool isPrimary;

  /// Nothing typed into it yet (one just added).
  final bool isBlank;
}

/// Stable key per contact row so an editor's text controllers follow the
/// contact across sibling add / remove. Real ids are stable; a brand-new
/// contact (id `''`) falls back to `'new_<index>'`, which is fine because new
/// rows are only ever appended at the end.
String contactRowKey(String id, int index) => id.isNotEmpty ? id : 'new_$index';

/// The contacts of a client or vendor edit screen as rows that open one at a
/// time. Three contacts' worth of fields used to run to two screens and push
/// Notes off the bottom; a closed row says who it is (initials, name, address)
/// in one line.
///
/// What is never hidden: a lone contact, a contact with nothing in it yet, and
/// the primary until the user opens another.
class ContactEditRows extends StatefulWidget {
  const ContactEditRows({
    super.key,
    required this.contacts,
    required this.fieldsBuilder,
    required this.onMakePrimary,
    required this.onDelete,
    this.reveal,
    this.onRevealed,
  });

  final List<ContactRowData> contacts;

  /// Scroll this row into view once it is laid out — on mount, and whenever
  /// a new [ContactReveal] arrives.
  final ContactReveal? reveal;

  /// Called once [reveal]'s row has been scrolled to, so its owner can clear
  /// it. A reveal still set when the rows mount again — the client edit
  /// layout moves the card between its one- and two-column trees on a resize
  /// — would otherwise pull the form back to that contact.
  final VoidCallback? onRevealed;

  /// The open row's fields, for the contact at an index. The row adds its own
  /// header above and its Make primary / Remove buttons below.
  final List<Widget> Function(BuildContext context, int index) fieldsBuilder;

  final ValueChanged<int> onMakePrimary;

  /// Removes the contact at an index and returns what puts it back, for the
  /// toast's Undo (null: nothing was removed). Remove asks nothing first —
  /// the Undo is the way back — and is never offered on the only contact.
  final VoidCallback? Function(int index) onDelete;

  @override
  State<ContactEditRows> createState() => _ContactEditRowsState();
}

class _ContactEditRowsState extends State<ContactEditRows> {
  /// The row the user opened, or the primary before they chose. Null once
  /// they have closed the open row themselves.
  String? _openKey;
  bool _chosen = false;

  /// One key per row, so [ContactEditRows.reveal] can find the row's context.
  /// Global rather than the `ValueKey` they replace, with the same identity —
  /// a row's key follows its contact either way.
  final Map<String, GlobalKey> _rowKeys = {};

  @override
  void initState() {
    super.initState();
    if (widget.reveal != null) _revealAfterLayout();
  }

  @override
  void didUpdateWidget(covariant ContactEditRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reveal != null && !identical(widget.reveal, oldWidget.reveal)) {
      _revealAfterLayout();
    }
  }

  void _revealAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final index = widget.reveal?.index;
      final contacts = widget.contacts;
      if (!mounted || index == null || index < 0 || index >= contacts.length) {
        return;
      }
      final target =
          _rowKeys[contactRowKey(contacts[index].id, index)]?.currentContext;
      if (target == null) return;
      unawaited(
        Scrollable.ensureVisible(
          target,
          // Near the top, so the open row's fields read down from it.
          alignment: 0.1,
          duration: InMotion.of(target)(InMotion.base),
          curve: InMotion.move,
        ),
      );
      widget.onRevealed?.call();
    });
  }

  bool _isOpen(int i) {
    final contacts = widget.contacts;
    final contact = contacts[i];
    if (contacts.length == 1 || contact.isBlank) return true;
    if (_chosen) return _openKey == contactRowKey(contact.id, i);
    final primary = contacts.indexWhere((c) => c.isPrimary);
    return i == (primary < 0 ? 0 : primary);
  }

  void _toggle(int i) {
    final key = contactRowKey(widget.contacts[i].id, i);
    setState(() {
      _openKey = _isOpen(i) ? null : key;
      _chosen = true;
    });
  }

  void _delete(BuildContext context, int i) {
    final contact = widget.contacts[i];
    final name = _nameOf(contact);
    final label = name.isNotEmpty
        ? name
        : contact.email.trim().isNotEmpty
        ? contact.email.trim()
        : context.tr('contact');
    final message = context.tr('removed_contact_name', {'name': label});
    final undoLabel = context.tr('undo');
    final undo = widget.onDelete(i);
    if (undo == null) return;
    Notify.info(context, message, action: NotifyAction(undoLabel, undo));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final contacts = widget.contacts;
    final canDelete = contacts.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < contacts.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: tokens.border),
          _ContactRow(
            key: _rowKeys.putIfAbsent(
              contactRowKey(contacts[i].id, i),
              GlobalKey.new,
            ),
            index: i,
            contact: contacts[i],
            open: _isOpen(i),
            // A lone or empty contact has nothing to fold away.
            onToggle: contacts.length == 1 || contacts[i].isBlank
                ? null
                : () => _toggle(i),
            canDelete: canDelete,
            // One contact is necessarily the primary; the label only tells
            // two or more apart.
            showPrimaryLabel: contacts.length > 1,
            fieldsBuilder: widget.fieldsBuilder,
            onMakePrimary: () => widget.onMakePrimary(i),
            onDelete: () => _delete(context, i),
          ),
        ],
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    super.key,
    required this.index,
    required this.contact,
    required this.open,
    required this.onToggle,
    required this.canDelete,
    required this.showPrimaryLabel,
    required this.fieldsBuilder,
    required this.onMakePrimary,
    required this.onDelete,
  });

  final int index;
  final ContactRowData contact;

  /// Whether the fields show. A closed row is its header line alone.
  final bool open;

  /// Opens or closes the row; null where it cannot be closed.
  final VoidCallback? onToggle;
  final bool canDelete;
  final bool showPrimaryLabel;
  final List<Widget> Function(BuildContext context, int index) fieldsBuilder;
  final VoidCallback onMakePrimary;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final name = _nameOf(contact);
    final title = name.isNotEmpty
        ? name
        : contact.isPrimary
        ? context.tr('primary_contact')
        : context.tr('contact_with_index', {'index': '${index + 1}'});
    final subtitle = [
      contact.email.trim(),
      contact.phone.trim(),
    ].where((part) => part.isNotEmpty).join('  ·  ');
    final header = ConstrainedBox(
      // A row's floor, not its height: two lines at a large text size grow it.
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: InSpacing.sm),
        child: Row(
          children: [
            InitialsAvatar(
              seed: contactRowKey(contact.id, index),
              label: initialsFor(title) ?? '',
            ),
            const SizedBox(width: InSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (contact.isPrimary && showPrimaryLabel) ...[
                        const SizedBox(width: InSpacing.sm),
                        const PrimaryContactLabel(),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty)
                    LtrText(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.ink3,
                      ),
                    ),
                ],
              ),
            ),
            if (onToggle != null)
              Icon(
                open ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: tokens.ink3,
              ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onToggle == null)
          header
        else
          Semantics(
            button: true,
            expanded: open,
            label: contact.isPrimary && showPrimaryLabel
                ? '$title, ${context.tr('primary')}'
                : title,
            onTap: onToggle,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(InRadii.r1),
              child: ExcludeSemantics(child: header),
            ),
          ),
        if (open) ...[
          const SizedBox(height: InSpacing.xs),
          ...fieldsBuilder(context, index),
          // What the header's star and cross used to do, said in words, and
          // out of the way of a row that is only being read.
          if ((!contact.isPrimary) || canDelete)
            Wrap(
              spacing: InSpacing.sm,
              children: [
                if (!contact.isPrimary)
                  TextButton.icon(
                    onPressed: onMakePrimary,
                    icon: const Icon(Icons.star_border, size: 18),
                    label: Text(context.tr('make_primary')),
                  ),
                if (canDelete)
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(context.tr('remove_contact')),
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.overdue,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: InSpacing.sm),
        ],
      ],
    );
  }
}

/// "First Last", trimmed, or `''`.
String _nameOf(ContactRowData contact) => [
  contact.firstName.trim(),
  contact.lastName.trim(),
].where((part) => part.isNotEmpty).join(' ');

/// The word "Primary" in a small rounded rectangle beside the primary
/// contact's name — words, not the star that read as a favourite. Never a
/// pill (CLAUDE.md § Design system).
class PrimaryContactLabel extends StatelessWidget {
  const PrimaryContactLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        borderRadius: BorderRadius.circular(InRadii.r1),
      ),
      child: Text(
        context.tr('primary'),
        maxLines: 1,
        style: TextStyle(
          color: tokens.accentInk,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// How a contact gets a document's email, as one choice of three — To, CC,
/// None — where there were two switches ("Add to invoices", "CC only") that
/// could be set against each other (`ContactEmailMode`).
///
/// CC is disabled on the primary contact: the server never stores the
/// primary as CC-only.
class ContactEmailModeField extends StatelessWidget {
  const ContactEmailModeField({
    super.key,
    required this.value,
    required this.isPrimary,
    required this.onChanged,
  });

  final ContactEmailMode value;
  final bool isPrimary;
  final ValueChanged<ContactEmailMode> onChanged;

  static String _labelKey(ContactEmailMode mode) => switch (mode) {
    ContactEmailMode.to => 'to',
    ContactEmailMode.cc => 'cc',
    ContactEmailMode.none => 'none',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final label = context.tr('email');
    Widget option(ContactEmailMode mode) {
      final enabled = !(mode == ContactEmailMode.cc && isPrimary);
      final text = context.tr(_labelKey(mode));
      final tile = MergeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(InRadii.r1),
          onTap: enabled ? () => onChanged(mode) : null,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: InSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Radio<ContactEmailMode>(value: mode, enabled: enabled),
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: enabled ? tokens.ink : tokens.ink3,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (enabled) return tile;
      return Tooltip(
        message: context.tr('primary_contact_not_cc'),
        child: tile,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kFieldVerticalGap),
      child: Semantics(
        container: true,
        label: label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Text(label, style: LabeledField.textStyle(context)),
            ),
            RadioGroup<ContactEmailMode>(
              groupValue: value,
              onChanged: (mode) {
                if (mode != null) onChanged(mode);
              },
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final mode in ContactEmailMode.values) option(mode),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
