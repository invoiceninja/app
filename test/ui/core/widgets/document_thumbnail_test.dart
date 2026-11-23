import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/data/models/domain/document.dart';
import 'package:admin/ui/core/widgets/document_thumbnail.dart';
import 'package:admin/ui/core/widgets/rename_document_dialog.dart';

/// invoiceninja/app#206. The server makes no previews, so a thumbnail is the
/// file itself, downloaded with the token and scaled on the device — which is
/// why the cache has limits, and each one has a test here.
void main() {
  Document doc(String id, {String type = 'jpg', int size = 1000}) => Document(
    id: id,
    name: '$id.$type',
    hash: 'h-$id',
    type: type,
    size: size,
  );

  Uint8List thumb(String id) => Uint8List.fromList(id.codeUnits);

  group('supports', () {
    test('a type the app can draw, under the size cap', () {
      expect(DocumentThumbnailCache.supports(doc('a')), isTrue);
      expect(DocumentThumbnailCache.supports(doc('a', type: 'pdf')), isTrue);
      expect(DocumentThumbnailCache.supports(doc('a', type: 'docx')), isFalse);
      expect(DocumentThumbnailCache.supports(doc('a', type: 'heic')), isFalse);
      expect(
        DocumentThumbnailCache.supports(
          doc('a', size: DocumentThumbnailCache.maxBytes + 1),
        ),
        isFalse,
      );
      expect(
        DocumentThumbnailCache.supports(const Document(type: 'jpg')),
        isFalse,
      );
    });
  });

  test('downloads each file once, however many rows ask', () async {
    var fetches = 0;
    final cache = DocumentThumbnailCache(
      fetch: (id) async {
        fetches++;
        return Uint8List(4);
      },
      render: (d, _) async => thumb(d.id),
    );
    final results = await Future.wait([
      cache.load(doc('a')),
      cache.load(doc('a')),
      cache.load(doc('a')),
    ]);
    expect(results, everyElement(thumb('a')));
    expect(await cache.load(doc('a')), thumb('a'));
    expect(cache.cached(doc('a')), thumb('a'));
    expect(fetches, 1);
  });

  test('keyed by content: a rename does not fetch again', () async {
    var fetches = 0;
    final cache = DocumentThumbnailCache(
      fetch: (id) async {
        fetches++;
        return Uint8List(4);
      },
      render: (d, _) async => thumb(d.id),
    );
    await cache.load(doc('a'));
    await cache.load(doc('a').copyWith(name: 'Renamed.jpg', updatedAt: 99));
    expect(fetches, 1);
  });

  test(
    'never more than maxConcurrent downloads at once, and the newest '
    'waiting goes next — the rows on screen, not the ones scrolled past',
    () async {
      final gates = <String, Completer<Uint8List>>{};
      var active = 0;
      var peak = 0;
      final cache = DocumentThumbnailCache(
        maxConcurrent: 2,
        fetch: (id) {
          active++;
          peak = active > peak ? active : peak;
          return (gates[id] = Completer<Uint8List>()).future.whenComplete(
            () => active--,
          );
        },
        render: (d, _) async => thumb(d.id),
      );
      final loads = [
        for (final id in ['a', 'b', 'c', 'd']) cache.load(doc(id)),
      ];
      await pumpEventQueue();
      expect(gates.keys, ['a', 'b'], reason: 'c and d wait their turn');
      gates['a']!.complete(Uint8List(1));
      await pumpEventQueue();
      expect(gates.keys, ['a', 'b', 'd'], reason: 'newest first');
      for (final id in ['b', 'd']) {
        gates[id]!.complete(Uint8List(1));
      }
      await pumpEventQueue();
      gates['c']!.complete(Uint8List(1));
      expect(await Future.wait(loads), [
        for (final id in ['a', 'b', 'c', 'd']) thumb(id),
      ]);
      expect(peak, 2);
    },
  );

  test('a waiting download nobody shows any more is dropped before it '
      'starts — a fast scroll does not download every row it passed', () async {
    final gates = <String, Completer<Uint8List>>{};
    final cache = DocumentThumbnailCache(
      maxConcurrent: 1,
      fetch: (id) => (gates[id] = Completer<Uint8List>()).future,
      render: (d, _) async => thumb(d.id),
    );
    final a = cache.load(doc('a'));
    final b = cache.load(doc('b'));
    await pumpEventQueue();
    cache.release(doc('b')); // scrolled away while waiting
    gates['a']!.complete(Uint8List(1));
    expect(await a, thumb('a'));
    expect(await b, isNull);
    expect(gates.keys, ['a'], reason: 'b was never downloaded');
    // Not a failure: shown again, it is asked for at once.
    final again = cache.load(doc('b'));
    await pumpEventQueue();
    gates['b']!.complete(Uint8List(1));
    expect(await again, thumb('b'));
  });

  test(
    'the queue holds at most maxQueued; the oldest waiting go first',
    () async {
      final gates = <String, Completer<Uint8List>>{};
      final cache = DocumentThumbnailCache(
        maxConcurrent: 1,
        fetch: (id) => (gates[id] = Completer<Uint8List>()).future,
        render: (d, _) async => thumb(d.id),
      );
      final first = cache.load(doc('busy'));
      final waiting = [
        for (var i = 0; i <= DocumentThumbnailCache.maxQueued; i++)
          cache.load(doc('w$i')),
      ];
      await pumpEventQueue();
      expect(await waiting.first, isNull, reason: 'dropped by the newer ones');
      gates['busy']!.complete(Uint8List(1));
      await first;
    },
  );

  test('keeps the most recent maxEntries', () async {
    final cache = DocumentThumbnailCache(
      maxEntries: 2,
      fetch: (id) async => Uint8List(1),
      render: (d, _) async => thumb(d.id),
    );
    await cache.load(doc('a'));
    await cache.load(doc('b'));
    cache.cached(doc('a')); // a is now the most recent
    await cache.load(doc('c'));
    expect(cache.cached(doc('a')), isNotNull);
    expect(cache.cached(doc('b')), isNull);
    expect(cache.cached(doc('c')), isNotNull);
  });

  test('a failure is not asked again for retryAfter — no request storm '
      'from a list scrolled offline', () async {
    var now = DateTime(2026, 11, 23, 12);
    var fetches = 0;
    var fail = true;
    final cache = DocumentThumbnailCache(
      now: () => now,
      fetch: (id) async {
        fetches++;
        if (fail) throw StateError('offline');
        return Uint8List(1);
      },
      render: (d, _) async => thumb(d.id),
    );
    expect(await cache.load(doc('a')), isNull);
    expect(await cache.load(doc('a')), isNull);
    expect(fetches, 1);

    fail = false;
    now = now.add(DocumentThumbnailCache.retryAfter);
    expect(await cache.load(doc('a')), thumb('a'));
    expect(fetches, 2);
  });

  test('an unsupported file is never fetched', () async {
    var fetches = 0;
    final cache = DocumentThumbnailCache(
      fetch: (id) async {
        fetches++;
        return Uint8List(1);
      },
    );
    expect(await cache.load(doc('a', type: 'docx')), isNull);
    expect(fetches, 0);
  });

  test('clear forgets every thumbnail', () async {
    final cache = DocumentThumbnailCache(
      fetch: (id) async => Uint8List(1),
      render: (d, _) async => thumb(d.id),
    );
    await cache.load(doc('a'));
    cache.clear();
    expect(cache.cached(doc('a')), isNull);
  });

  testWidgets('a photo is scaled to its long side, keeping its shape; a '
      'body that is not an image draws nothing', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 400, 200),
        ui.Paint()..color = const Color(0xFF3366CC),
      );
      final image = await recorder.endRecording().toImage(400, 200);
      final png = (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();

      final out = await renderDocumentThumbnail(doc('p', type: 'png'), png);
      final decoded = await decodeImageFromList(out!);
      expect(decoded.width, kDocumentThumbnailPixels);
      expect(decoded.height, kDocumentThumbnailPixels ~/ 2);

      expect(
        await renderDocumentThumbnail(
          doc('x', type: 'pdf'),
          Uint8List.fromList('not a pdf'.codeUnits),
        ),
        isNull,
      );
    });
  });

  group('renameSelectionFor', () {
    test('selects the words, not the extension', () {
      expect(renameSelectionFor('scan.jpg').extentOffset, 4);
      expect(renameSelectionFor('a.b.pdf').extentOffset, 3);
    });

    test('selects everything with no extension, or only one', () {
      expect(renameSelectionFor('Receipt').extentOffset, 7);
      expect(renameSelectionFor('.env').extentOffset, 4);
    });
  });
}
