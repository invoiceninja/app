import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/company.dart';
import 'package:admin/data/models/domain/company_custom_fields.dart';
import 'package:admin/data/models/value/date.dart';
import 'package:admin/domain/email_template_variables.dart';
import 'package:admin/domain/file_name_pattern.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/back_dismissible_menu_anchor.dart';
import 'package:admin/ui/core/widgets/example_hint.dart';
import 'package:admin/ui/core/widgets/field_action_button.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/core/widgets/template_variables/template_variable_chip.dart';
import 'package:admin/ui/features/settings/view_models/settings_draft_view_model.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/settings/widgets/overridable_switch_field.dart';
import 'package:admin/ui/features/settings/widgets/overridable_text_field.dart';
import 'package:admin/ui/features/settings/widgets/settings_field_bindings.dart';
import 'package:admin/ui/features/settings/widgets/settings_form_shell.dart';
import 'package:admin/utils/bidi.dart';

/// Searchable label keys rendered by the File Names tab.
const kGeneratedNumbersFileNamesSearchKeys = <String>[
  'invoice_filename_pattern',
  'quote_filename_pattern',
  'credit_filename_pattern',
  'purchase_order_filename_pattern',
  'filename_slug',
];

/// One file name field: its setting, the variables it offers, and the
/// document type its example names (with the English word, for a language
/// whose script the example can't show — see [_sampleValues]).
typedef _FileNameField = ({
  String apiKey,
  TemplateVariableScope scope,
  String typeKey,
  String typeEnglish,
});

const _kInvoiceField = (
  apiKey: 'invoice_filename_pattern',
  scope: TemplateVariableScope.invoiceFileName,
  typeKey: 'invoice',
  typeEnglish: 'Invoice',
);
const _kQuoteField = (
  apiKey: 'quote_filename_pattern',
  scope: TemplateVariableScope.quoteFileName,
  typeKey: 'quote',
  typeEnglish: 'Quote',
);
const _kCreditField = (
  apiKey: 'credit_filename_pattern',
  scope: TemplateVariableScope.creditFileName,
  typeKey: 'credit',
  typeEnglish: 'Credit',
);
const _kPurchaseOrderField = (
  apiKey: 'purchase_order_filename_pattern',
  scope: TemplateVariableScope.purchaseOrderFileName,
  typeKey: 'purchase_order',
  typeEnglish: 'Purchase Order',
);

/// The sample document number every example uses.
const _kSampleNumber = '0042';

final _kLatin = RegExp('[A-Za-z0-9]');

/// Generated Numbers → File Names: the name of the PDF (and e-invoice) a
/// client or vendor receives, per document type, from the email-template
/// variables (invoiceninja/invoiceninja discussion #12610). Shown only when
/// the server supports it (`fileNamePatternsSupported`).
///
/// Each field is the email-template field (`OverridableTextField` with a
/// file name [TemplateVariableScope]): chips at rest, Insert variable, the
/// override box. Under it, an "e.g." example built by [fileNameExample] from
/// sample values — the name a real download gets comes from the server.
class GeneratedNumbersFileNamesBody extends StatelessWidget {
  const GeneratedNumbersFileNamesBody({
    super.key,
    required this.company,
    required this.showInvoices,
    required this.showQuotes,
    required this.showCredits,
    required this.showPurchaseOrders,
  });

  final Company company;
  final bool showInvoices;
  final bool showQuotes;
  final bool showCredits;
  final bool showPurchaseOrders;

  @override
  Widget build(BuildContext context) {
    final host = context.watch<SettingsDraftHost>();
    final fields = <_FileNameField>[
      if (showInvoices) _kInvoiceField,
      if (showQuotes) _kQuoteField,
      if (showCredits) _kCreditField,
      // A purchase order's settings are the company's alone: vendors have no
      // client or group settings to override them.
      if (showPurchaseOrders && !host.isCascadeScope) _kPurchaseOrderField,
    ];
    if (fields.isEmpty) return const SizedBox.shrink();
    final slug = host.settings.filenameSlug ?? false;
    // Once per build: every field, the switch and the presets read these.
    final samples = {for (final f in fields) f: _sampleValues(context, f)};
    String? example(_FileNameField field, String pattern, {bool? slugged}) =>
        fileNameExample(pattern, samples[field]!, slug: slugged ?? slug);

    // The switch's example: the first field with a usable pattern. With none,
    // there is nothing for it to change — the server simplifies only custom
    // names — and the subtitle says so.
    String? slugExample;
    for (final field in fields) {
      final pattern = settingsBindingOf(field.apiKey).read(host.settings);
      if (pattern == null || pattern.isEmpty) continue;
      slugExample = example(field, pattern, slugged: true);
      if (slugExample != null) break;
    }

    return SettingsFormShell(
      sections: [
        FormSection(
          title: context.tr('file_names'),
          description: context.tr('file_names_help'),
          trailing: _PresetsMenu(
            fields: fields,
            exampleFor: (pattern) {
              final field = fields.first;
              final p = field == _kPurchaseOrderField
                  ? fileNamePatternForPurchaseOrder(pattern)
                  : pattern;
              return (
                example: example(field, p) ?? p,
                labels: _patternLabels(context, p, field.scope),
              );
            },
            defaultExample: _defaultName(context, fields.first),
          ),
          children: [
            for (final field in fields)
              _FileNameFieldTile(
                key: ValueKey(field.apiKey),
                field: field,
                exampleFor: (pattern) => example(field, pattern),
                defaultName: _defaultName(context, field),
              ),
            OverridableSwitchField(
              label: context.tr(kFileNameSlugKey),
              apiKey: kFileNameSlugKey,
              subtitle: slugExample == null
                  ? context.tr('filename_slug_unset_help')
                  : context.tr('filename_slug_help', {
                      'value': ltrIsolate(slugExample),
                    }),
            ),
          ],
        ),
      ],
    );
  }

  /// The type as a file name shows it: translated, or in English when the
  /// translation has no Latin letters — the server transliterates those, which
  /// this example can't.
  String _typeLabel(BuildContext context, _FileNameField field) {
    final label = context.tr(field.typeKey);
    return _kLatin.hasMatch(label) ? label : field.typeEnglish;
  }

  /// The server's own name for a document when the pattern is blank
  /// (`numberFormatter()`): the type, `_`, the number.
  String _defaultName(BuildContext context, _FileNameField field) =>
      // lint: allow-raw-file-name an example shown on screen, never written
      '${_typeLabel(context, field).trim().replaceAll(RegExp(r'\s+'), '_')}'
      '_$_kSampleNumber.pdf';

  /// Example values for [field]'s variables: the company's own name and
  /// custom field labels, the rest made up.
  Map<String, String> _sampleValues(
    BuildContext context,
    _FileNameField field,
  ) {
    final today = Date.today();
    String custom(String key, int i) {
      final label = company.customFieldLabel('$key$i');
      return label.isEmpty ? 'Custom $i' : label;
    }

    final companyName = company.settings.name ?? '';
    final values = {
      r'$number': _kSampleNumber,
      r'$entity': _typeLabel(context, field),
      // The server writes dates Y-m-d in a file name — a value, not a
      // displayed date.
      r'$date': today.toIso(),
      r'$due_date': today.addDays(30).toIso(),
      r'$po_number': 'PO-17',
      r'$client.name': 'Acme Ltd',
      r'$client.number': '0007',
      r'$client.id_number': 'ID-7',
      for (final i in [1, 2, 3, 4]) '\$client.custom$i': custom('client', i),
      r'$contact.first_name': 'Jane',
      r'$contact.last_name': 'Doe',
      r'$company.name': _kLatin.hasMatch(companyName)
          ? companyName
          : 'Widgets Inc',
      r'$vendor.name': 'Supplies Co',
      r'$vendor.number': '0003',
      r'$vendor.id_number': 'ID-3',
      for (final i in [1, 2, 3, 4]) '\$vendor.custom$i': custom('vendor', i),
    };
    // Only this document's variables, as the server has them: a purchase order
    // has no client, an invoice no vendor.
    values.removeWhere(
      (key, _) => !isTemplateVariableInScope(key, field.scope),
    );
    return values;
  }

  /// [pattern] with each variable as its chip label — "Client Name - Document
  /// Type - Invoice Number" — for the Presets menu.
  static String _patternLabels(
    BuildContext context,
    String pattern,
    TemplateVariableScope scope,
  ) {
    final out = StringBuffer();
    var cursor = 0;
    for (final m in findTemplateVariables(pattern, scope)) {
      out.write(pattern.substring(cursor, m.start));
      final lookup = lookupTemplateVariable(m.token, scope);
      out.write(
        lookup == null
            ? m.token
            : templateVariableLabel(context, lookup.variable),
      );
      cursor = m.end;
    }
    out.write(pattern.substring(cursor));
    return out.toString();
  }
}

class _FileNameFieldTile extends StatefulWidget {
  const _FileNameFieldTile({
    super.key,
    required this.field,
    required this.exampleFor,
    required this.defaultName,
  });

  final _FileNameField field;
  final String? Function(String pattern) exampleFor;
  final String defaultName;

  @override
  State<_FileNameFieldTile> createState() => _FileNameFieldTileState();
}

class _FileNameFieldTileState extends State<_FileNameFieldTile> {
  /// The missing-number error waits until the field is left: while typing,
  /// "Acme - " is a pattern on its way to having one.
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final host = context.watch<SettingsDraftHost>();
    final field = widget.field;
    final pattern = settingsBindingOf(field.apiKey).read(host.settings) ?? '';
    final number = lookupTemplateVariable(r'$number', field.scope)!;
    final missingNumber = !_editing && fileNamePatternMissingNumber(pattern);
    final example = pattern.isEmpty
        // Blank is the server's default name — at company scope; at group /
        // client scope it inherits, which the override box says.
        ? (host.isCascadeScope ? null : widget.defaultName)
        : widget.exampleFor(pattern);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _editing = focused),
      child: OverridableTextField(
        label: context.tr(field.apiKey),
        apiKey: field.apiKey,
        templateVariables: field.scope,
        autocorrect: false,
        hintText: host.isCascadeScope ? null : context.tr('default'),
        // A file name is a value: isolated, so a date-led one keeps its order
        // in a right-to-left sentence.
        helperText: example == null
            ? null
            : exampleHint(context, ltrIsolate(example)),
        errorText: missingNumber
            ? context.tr('file_name_number_required', {
                'variable': templateVariableLabel(context, number.variable),
              })
            : null,
      ),
    );
  }
}

/// One menu for the whole card: set every field to a preset (each shown as
/// the file name it gives, with its variables under it), or copy the invoice
/// pattern to the others.
class _PresetsMenu extends StatelessWidget {
  const _PresetsMenu({
    required this.fields,
    required this.exampleFor,
    required this.defaultExample,
  });

  final List<_FileNameField> fields;
  final ({String example, String labels}) Function(String pattern) exampleFor;
  final String defaultExample;

  void _apply(SettingsDraftHost host, String pattern) {
    host.updateSettings((settings) {
      var s = settings;
      for (final field in fields) {
        final value = pattern.isNotEmpty && field == _kPurchaseOrderField
            ? fileNamePatternForPurchaseOrder(pattern)
            : pattern;
        s = settingsBindingOf(field.apiKey).write(s, value);
      }
      return s;
    });
  }

  @override
  Widget build(BuildContext context) {
    final host = context.watch<SettingsDraftHost>();
    final t = context.inTheme;
    final invoicePattern = host.settings.invoiceFilenamePattern ?? '';
    final canCopyInvoice =
        fields.length > 1 &&
        fields.contains(_kInvoiceField) &&
        invoicePattern.isNotEmpty &&
        !fileNamePatternMissingNumber(invoicePattern);

    Widget item(String example, String? labels) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LtrText(example),
        if (labels != null)
          Text(labels, style: TextStyle(fontSize: 12, color: t.ink2)),
      ],
    );

    return BackDismissibleMenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
          child: Text(
            context.tr('set_all_file_names_to'),
            style: TextStyle(fontSize: 12, color: t.ink2),
          ),
        ),
        // Default is the company's blank; at group / client scope blank is
        // "inherit", which the override box already says.
        if (!host.isCascadeScope)
          MenuItemButton(
            onPressed: () => _apply(host, ''),
            child: item(defaultExample, context.tr('default')),
          ),
        for (final preset in kFileNamePresets)
          MenuItemButton(
            onPressed: () => _apply(host, preset),
            child: () {
              final shown = exampleFor(preset);
              return item(shown.example, shown.labels);
            }(),
          ),
        if (canCopyInvoice) ...[
          const Divider(height: 1),
          MenuItemButton(
            onPressed: () => _apply(host, invoicePattern),
            child: Text(context.tr('use_invoice_file_name_for_all')),
          ),
        ],
      ],
      builder: (context, controller, _) => FieldActionButton(
        icon: Icons.expand_more,
        label: context.tr('presets'),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
