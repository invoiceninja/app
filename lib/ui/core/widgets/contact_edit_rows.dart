import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/initials_avatar.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';

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
  });

  final List<ContactRowData> contacts;

  /// The open row's fields, for the contact at an index. The row adds its own
  /// header above and its Make primary / Remove buttons below.
  final List<Widget> Function(BuildContext context, int index) fieldsBuilder;

  final ValueChanged<int> onMakePrimary;
  final ValueChanged<int> onDelete;

  @override
  State<ContactEditRows> createState() => _ContactEditRowsState();
}

class _ContactEditRowsState extends State<ContactEditRows> {
  /// The row the user opened, or the primary before they chose. Null once
  /// they have closed the open row themselves.
  String? _openKey;
  bool _chosen = false;

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
            key: ValueKey(contactRowKey(contacts[i].id, i)),
            index: i,
            contact: contacts[i],
            open: _isOpen(i),
            // A lone or empty contact has nothing to fold away.
            onToggle: contacts.length == 1 || contacts[i].isBlank
                ? null
                : () => _toggle(i),
            canDelete: canDelete,
            fieldsBuilder: widget.fieldsBuilder,
            onMakePrimary: () => widget.onMakePrimary(i),
            onDelete: () => widget.onDelete(i),
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
  final List<Widget> Function(BuildContext context, int index) fieldsBuilder;
  final VoidCallback onMakePrimary;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final theme = Theme.of(context);
    final name = [
      contact.firstName.trim(),
      contact.lastName.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
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
                      if (contact.isPrimary) ...[
                        const SizedBox(width: InSpacing.xs),
                        Tooltip(
                          message: context.tr('primary_contact'),
                          child: Icon(
                            Icons.star,
                            size: 16,
                            color: tokens.accent,
                          ),
                        ),
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
            label: title,
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
