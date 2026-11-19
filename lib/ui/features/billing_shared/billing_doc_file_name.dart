/// A billing document's file name in the shape the server gives it when the
/// company set no file-name pattern — `BaseModel::numberFormatter()`: the
/// document type, `_`, the number, whitespace runs as `_` — so a file this app
/// names itself matches the one the same document has in its email and the
/// client portal (`Invoice_0042`, `Purchase_Order_0042`).
///
/// [typeLabel] is the translated type (`context.tr(type.singularLabelKey)`).
/// The server writes it in the client's language and this is the app's; the
/// fallback only runs when the response carried no name (docs/file-downloads.md).
/// Not sanitized: pass the result through `sanitizeFileName`.
String billingDocFileBase(String typeLabel, String number) =>
    '${typeLabel.trim()}_$number'.replaceAll(RegExp(r'\s+'), '_');
