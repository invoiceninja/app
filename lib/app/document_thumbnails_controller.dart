import 'package:admin/data/prefs/device_pref.dart';
import 'package:admin/data/prefs/device_pref_keys.dart';
import 'package:admin/data/prefs/device_prefs_store.dart';

/// Owns the "Show Document Preview" preference
/// (`DevicePrefKeys.documentThumbnails`, device-local): whether a document
/// list draws each photo or PDF as a thumbnail (invoiceninja/app#206,
/// docs/document-thumbnails.md).
///
/// Defaults to **on**, unlike React's opt-in `show_document_preview`: a
/// thumbnail is what tells one receipt from the next, and the cache keeps the
/// cost to one capped download per file per session. Off for someone on a
/// metered connection, which is why it is per device.
///
/// Read through its root provider with `watchDocumentThumbnails(context)`.
class DocumentThumbnailsController extends DevicePref<bool> {
  DocumentThumbnailsController({required DevicePrefsStore prefs})
    : super(prefs, DevicePrefKeys.documentThumbnails, fallback: true);
}
