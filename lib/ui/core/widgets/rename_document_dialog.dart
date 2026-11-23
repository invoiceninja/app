import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/document.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/fold_geometry.dart';
import 'package:admin/ui/core/widgets/document_thumbnail.dart';
import 'package:admin/ui/core/widgets/field_label.dart';
import 'package:admin/ui/core/widgets/form_save_scope.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';

/// Ask for a document's new name (invoiceninja/app#206). Resolves to the
/// trimmed name, or null when cancelled, left blank, or left unchanged.
///
/// Shows the file's thumbnail above the field, so the file being named is
/// the one on screen — the reporter's "recognise the correct file". The
/// name opens with everything before the extension selected: the usual
/// rename is the words, not the type. The extension stays editable, and
/// dropping it is harmless — a download puts it back from the file's type
/// (`documentFileName`).
Future<String?> showRenameDocumentDialog(
  BuildContext context,
  Document doc,
) async {
  final name = await showDialog<String>(
    context: context,
    anchorPoint: foldAnchorPoint(context),
    builder: (_) => _RenameDocumentDialog(doc: doc),
  );
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty || trimmed == doc.name ? null : trimmed;
}

/// The selection a rename opens with: the name up to its extension, or all
/// of it when it has none (or is only an extension, like `.env`).
TextSelection renameSelectionFor(String name) {
  final dot = name.lastIndexOf('.');
  return TextSelection(
    baseOffset: 0,
    extentOffset: dot > 0 ? dot : name.length,
  );
}

class _RenameDocumentDialog extends StatefulWidget {
  const _RenameDocumentDialog({required this.doc});

  final Document doc;

  @override
  State<_RenameDocumentDialog> createState() => _RenameDocumentDialogState();
}

class _RenameDocumentDialogState extends State<_RenameDocumentDialog> {
  late final _controller = TextEditingController.fromValue(
    TextEditingValue(
      text: widget.doc.name,
      selection: renameSelectionFor(widget.doc.name),
    ),
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _canSave {
    final name = _controller.text.trim();
    return name.isNotEmpty && name != widget.doc.name;
  }

  void _submit() {
    if (!_canSave) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return AlertDialog(
      title: Text(context.tr('rename')),
      content: FormSaveScope(
        onSubmit: _submit,
        enabled: _canSave,
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (DocumentThumbnailCache.supports(widget.doc)) ...[
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: tokens.border),
                      borderRadius: BorderRadius.circular(InRadii.r2),
                    ),
                    padding: const EdgeInsets.all(InSpacing.xs),
                    child: DocumentThumbnail(
                      document: widget.doc,
                      size: 120,
                      iconSize: 40,
                    ),
                  ),
                ),
                SizedBox(height: InSpacing.lg(context)),
              ],
              LabeledField(
                label: context.tr('name'),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(labelText: context.tr('name')),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel')),
        ),
        PrimaryDialogAction(
          label: context.tr('save'),
          // The field owns focus and Enter; the button starts disabled (the
          // name is unchanged), so no Enter hint either.
          autofocus: false,
          showEnterHint: false,
          onPressed: _canSave ? _submit : null,
        ),
      ],
    );
  }
}
