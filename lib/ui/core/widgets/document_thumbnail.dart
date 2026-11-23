import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/document_thumbnails_controller.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/document.dart';
import 'package:admin/ui/core/widgets/document_type_icon.dart';
import 'package:admin/utils/document_preview.dart';
import 'package:admin/utils/pdf_bytes_guard.dart';

/// Small previews of uploaded documents — a photo, or a PDF's first page —
/// drawn on the device (invoiceninja/app#206, docs/document-thumbnails.md).
///
/// The server makes none: `UploadFile::generatePreview` is commented out, so
/// every `preview` it sends is empty. A thumbnail is the file itself, fetched
/// with the API token (`DocumentsApi.download`, never the `url` —
/// docs/document-urls.md) and scaled down here.
///
/// **Memory only, on purpose.** The local database is encrypted; a folder of
/// scaled-down receipts beside it would not be. So a thumbnail costs one
/// download per file per session, which is what the limits below are for:
///
/// * only a type the app can draw (`previewKindForType`), at most [maxBytes];
/// * at most [maxConcurrent] downloads at once, the rest queued in order;
/// * [maxEntries] thumbnails kept (each a ~10–30 KB PNG), least recent out;
/// * a failure is not retried for [retryAfter], so a list scrolled offline
///   does not ask again on every frame.
///
/// One cache per signed-in account ([DocumentThumbnailCache.of]): it empties
/// when the session ends or another account signs in, so one person's files
/// never show under another's.
class DocumentThumbnailCache {
  DocumentThumbnailCache({
    required Future<Uint8List> Function(String id) fetch,
    Future<Uint8List?> Function(Document doc, Uint8List bytes)? render,
    DateTime Function()? now,
    this.maxEntries = 150,
    this.maxConcurrent = 2,
  }) : _fetch = fetch,
       _render = render ?? renderDocumentThumbnail,
       _now = now ?? DateTime.now;

  final Future<Uint8List> Function(String id) _fetch;
  final Future<Uint8List?> Function(Document doc, Uint8List bytes) _render;
  final DateTime Function() _now;
  final int maxEntries;
  final int maxConcurrent;

  /// Larger files are left as their icon: a thumbnail is worth a quick
  /// download, not a 40 MB one.
  static const int maxBytes = 12 * 1024 * 1024;

  static const Duration retryAfter = Duration(minutes: 1);

  /// The cache for the account signed in on [services]; null when there is
  /// none, or [services] can't say (a widget test's fake).
  static DocumentThumbnailCache? of(Services services) {
    try {
      final session = services.auth.session;
      final current = session.value;
      if (current == null) return null;
      final account = '${current.baseUrl}|${current.accountId}';
      final held = _byServices[services];
      if (held != null && held.account == account) return held.cache;
      final api = services.documentsApi;
      final entry = (
        account: account,
        cache: DocumentThumbnailCache(fetch: api.download),
      );
      _byServices[services] = entry;
      if (_listening[services] != true) {
        _listening[services] = true;
        // Once per Services: drop the cache the moment its account is gone.
        void onSession() {
          final s = session.value;
          final live = _byServices[services];
          if (live == null) return;
          if (s == null || '${s.baseUrl}|${s.accountId}' != live.account) {
            live.cache.clear();
            _byServices[services] = null;
          }
        }

        session.addListener(onSession);
      }
      return entry.cache;
    } catch (_) {
      return null;
    }
  }

  static final _listening = Expando<bool>('DocumentThumbnailCache.listening');

  static final _byServices =
      Expando<({String account, DocumentThumbnailCache cache})>(
        'DocumentThumbnailCache',
      );

  /// Whether [doc] can have a thumbnail at all.
  static bool supports(Document doc) =>
      doc.id.isNotEmpty &&
      // An unknown size could be anything: never a blind download.
      doc.size > 0 &&
      doc.size <= maxBytes &&
      previewKindForType(doc.type) != DocumentPreviewKind.none;

  // Keyed by content, not by `updated_at`: a rename touches that and leaves
  // the file as it was.
  static String _key(Document doc) => '${doc.id}|${doc.hash}';

  final LinkedHashMap<String, Uint8List> _ready = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _loading = {};
  final Map<String, DateTime> _failedAt = {};
  int _active = 0;

  /// Downloads waiting for a slot, oldest first; served newest first.
  final List<({String key, Completer<bool> turn})> _waiting = [];

  /// How many widgets want each thumbnail ([load] / [release]). A queued
  /// download nobody wants any more is dropped before it starts — a list
  /// flung past a thousand receipts must not download each one it showed
  /// for a frame, after the screen has gone.
  final Map<String, int> _wanted = {};

  /// Downloads that may wait at once; the oldest goes first when more are
  /// asked for — the rows a fast scroll left behind.
  static const int maxQueued = 24;

  /// The thumbnail, when it is already here — for a first frame that does
  /// not flicker through the icon on every rebuild.
  Uint8List? cached(Document doc) {
    final key = _key(doc);
    final hit = _ready.remove(key);
    if (hit != null) _ready[key] = hit; // most recent last
    return hit;
  }

  /// The thumbnail, fetched and drawn if it isn't here yet; null when [doc]
  /// has none, it failed, it failed less than [retryAfter] ago, or nobody
  /// wanted it any more before its turn came. Every call that got past the
  /// cache is matched by one [release].
  Future<Uint8List?> load(Document doc) {
    if (!supports(doc)) return Future.value();
    final hit = cached(doc);
    if (hit != null) return Future.value(hit);
    final key = _key(doc);
    _wanted[key] = (_wanted[key] ?? 0) + 1;
    final failed = _failedAt[key];
    if (failed != null && _now().difference(failed) < retryAfter) {
      return Future.value();
    }
    // A block body: `=> _loading.remove(key)` hands `whenComplete` the
    // removed future — this one — and it waits on itself forever.
    return _loading[key] ??= _make(doc, key).whenComplete(() {
      _loading.remove(key);
    });
  }

  /// The caller no longer shows [doc] (its row scrolled away or closed).
  void release(Document doc) {
    final key = _key(doc);
    final n = (_wanted[key] ?? 0) - 1;
    if (n > 0) {
      _wanted[key] = n;
    } else {
      _wanted.remove(key);
    }
  }

  bool _isWanted(String key) => (_wanted[key] ?? 0) > 0;

  Future<Uint8List?> _make(Document doc, String key) async {
    if (!await _acquire(key)) return null;
    if (!_isWanted(key)) {
      _release();
      return null;
    }
    try {
      final bytes = await _fetch(doc.id);
      final thumb = bytes.isEmpty ? null : await _render(doc, bytes);
      if (thumb == null) {
        _failedAt[key] = _now();
        return null;
      }
      _failedAt.remove(key);
      _ready[key] = thumb;
      while (_ready.length > maxEntries) {
        _ready.remove(_ready.keys.first);
      }
      return thumb;
    } catch (_) {
      _failedAt[key] = _now();
      return null;
    } finally {
      _release();
    }
  }

  /// A download slot for [key]: true when it is this download's turn (the
  /// slot is handed over, not re-counted), false when it was dropped from
  /// the queue first.
  Future<bool> _acquire(String key) {
    if (_active < maxConcurrent) {
      _active++;
      return Future.value(true);
    }
    final turn = Completer<bool>();
    _waiting.add((key: key, turn: turn));
    while (_waiting.length > maxQueued) {
      _waiting.removeAt(0).turn.complete(false);
    }
    return turn.future;
  }

  void _release() {
    // Newest first: the rows on screen now, not the ones scrolled past.
    while (_waiting.isNotEmpty) {
      final next = _waiting.removeLast();
      if (_isWanted(next.key)) {
        next.turn.complete(true);
        return;
      }
      next.turn.complete(false);
    }
    _active--;
  }

  /// Forget every thumbnail — the account they belong to is gone.
  void clear() {
    _ready.clear();
    _failedAt.clear();
  }
}

/// Long side of a stored thumbnail, in pixels: sharp at 3× for the 48 px row
/// slot, and enough for the rename dialog's larger preview.
const int kDocumentThumbnailPixels = 192;

/// [bytes] of [doc] scaled to a PNG at most [kDocumentThumbnailPixels] on its
/// long side — a photo as itself, a PDF as its first page. Null when nothing
/// can be drawn (a body that only claims to be a PDF, an image the codec
/// refuses).
Future<Uint8List?> renderDocumentThumbnail(Document doc, Uint8List bytes) {
  switch (previewKindForBytes(doc.type, bytes)) {
    case DocumentPreviewKind.image:
      return _scaleImage(bytes);
    case DocumentPreviewKind.pdf:
      return _firstPdfPage(bytes);
    case DocumentPreviewKind.none:
      return Future.value();
  }
}

Future<Uint8List?> _scaleImage(Uint8List bytes) async {
  // Each native object is let go whatever fails after it was made: a corrupt
  // file throws from `encoded` or `instantiateCodec`, and a buffer the size
  // of the file would otherwise leak once a minute while the list is open.
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final wide = descriptor.width >= descriptor.height;
    codec = await descriptor.instantiateCodec(
      // One side only: the codec keeps the aspect ratio. Never upscaled.
      targetWidth: wide && descriptor.width > kDocumentThumbnailPixels
          ? kDocumentThumbnailPixels
          : null,
      targetHeight: !wide && descriptor.height > kDocumentThumbnailPixels
          ? kDocumentThumbnailPixels
          : null,
    );
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Future<Uint8List?> _firstPdfPage(Uint8List bytes) async {
  if (!isRenderablePdf(bytes)) return null;
  // Sized from the long side: A4 is 11.7 in tall (Letter 11), so a portrait
  // page lands at about the cap, and a landscape one too.
  const dpi = kDocumentThumbnailPixels / 11.7;
  await for (final page in Printing.raster(bytes, pages: const [0], dpi: dpi)) {
    return page.toPng();
  }
  return null;
}

/// A document's thumbnail in a square of [size], or its type icon — while
/// it loads, when it has none, and whenever drawing it fails. Never a
/// spinner: a list of files that all spin reads as broken, an icon that
/// turns into a picture reads as done.
class DocumentThumbnail extends StatefulWidget {
  const DocumentThumbnail({
    super.key,
    required this.document,
    this.size = 40,
    this.iconSize = 20,
    this.iconColor,
  });

  final Document document;
  final double size;
  final double iconSize;

  /// The type icon's colour; the theme's `ink2` when null.
  final Color? iconColor;

  @override
  State<DocumentThumbnail> createState() => _DocumentThumbnailState();
}

class _DocumentThumbnailState extends State<DocumentThumbnail> {
  DocumentThumbnailCache? _cache;
  Uint8List? _bytes;
  Document? _requested;
  bool? _requestedEnabled;

  /// The document this widget asked [_cache] to load, until it [_letGo]es.
  Document? _held;

  void _letGo() {
    final held = _held;
    _held = null;
    if (held != null) _cache?.release(held);
  }

  @override
  void dispose() {
    _letGo();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cache = _resolveCache();
    if (!identical(cache, _cache)) {
      _letGo();
      _requested = null;
    }
    _cache = cache;
    _request();
  }

  @override
  void didUpdateWidget(DocumentThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.document;
    final b = widget.document;
    if (a.id != b.id || a.hash != b.hash) _request();
  }

  DocumentThumbnailCache? _resolveCache() {
    try {
      final services = context.read<Services>();
      return DocumentThumbnailCache.of(services);
    } catch (_) {
      return null; // no Services above (a design-system preview, a test)
    }
  }

  void _request() {
    final doc = widget.document;
    // Off: no download at all, not merely no picture. Turned back on, the
    // build that follows the switch asks again (`didChangeDependencies`).
    final enabled = watchDocumentThumbnails(context, listen: false);
    final cache = enabled ? _cache : null;
    if (identical(_requested, doc) && _requestedEnabled == enabled) return;
    _requested = doc;
    _requestedEnabled = enabled;
    _letGo();
    _bytes = cache?.cached(doc);
    if (cache == null || _bytes != null) return;
    if (!DocumentThumbnailCache.supports(doc)) return;
    _held = doc;
    unawaited(
      cache.load(doc).then((bytes) {
        if (!mounted || !identical(_requested, doc) || bytes == null) return;
        setState(() => _bytes = bytes);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final enabled = watchDocumentThumbnails(context);
    final icon = SizedBox.square(
      dimension: widget.size,
      child: Center(
        child: Icon(
          documentTypeIcon(widget.document.type),
          size: widget.iconSize,
          color: widget.iconColor ?? tokens.ink2,
        ),
      ),
    );
    final bytes = enabled ? _bytes : null;
    if (bytes == null) return icon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(InRadii.r1),
      child: Container(
        width: widget.size,
        height: widget.size,
        color: tokens.surfaceAlt,
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => icon,
        ),
      ),
    );
  }
}

/// Whether this device shows document thumbnails ("Show Document Preview"),
/// subscribing [context] unless [listen] is false. On when no
/// [DocumentThumbnailsController] is provided.
bool watchDocumentThumbnails(BuildContext context, {bool listen = true}) {
  final controller = listen
      ? context.watch<DocumentThumbnailsController?>()
      : context.read<DocumentThumbnailsController?>();
  return controller?.value ?? true;
}
