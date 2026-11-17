import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/ui/core/widgets/toast_controller.dart';
import 'package:admin/ui/core/widgets/toast_host.dart';

/// `ToastBottomInset` is how a screen publishes a bar pinned to its bottom
/// edge — a checkout's pay button, the billing editors' sticky totals, a
/// list's selection bar, the phone's timer dock. The narrow toast is lifted
/// above the total, and on a wide layout so is the floating timer pill (it
/// sat on the desktop invoice editor's Total before the totals bar
/// published itself).
void main() {
  Widget bar(double h) => SizedBox(height: h);

  testWidgets('stacked bars add up', (tester) async {
    // A billing editor's totals sitting on top of the phone's timer dock: the
    // tallest alone would leave the toast over the upper bar.
    final c = ToastController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            const Spacer(),
            ToastBottomInset(controller: c, child: bar(56)),
            ToastBottomInset(controller: c, child: bar(48)),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(c.bottomInset.value, 56 + 48);

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            const Spacer(),
            ToastBottomInset(controller: c, child: bar(48)),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(c.bottomInset.value, 48);
  });

  testWidgets('a bar that pays the safe inset reports only what is above it', (
    tester,
  ) async {
    // The toast host adds `padding.bottom` itself; a `SafeArea`-padded bar
    // reporting its whole box would lift the toast by the inset twice.
    final c = ToastController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
          child: Column(
            children: [
              const Spacer(),
              ToastBottomInset(
                controller: c,
                paysBottomPadding: true,
                child: SafeArea(top: false, child: bar(60)),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(c.bottomInset.value, 60);
  });

  testWidgets('a bar in a hidden navigation branch reports nothing', (
    tester,
  ) async {
    // The shell keeps every branch's stack mounted under `TickerMode(enabled:
    // false)`; an editor left open on another tab must not lift anything.
    final c = ToastController();
    addTearDown(c.dispose);
    Widget app(bool active) => MaterialApp(
      home: TickerMode(
        enabled: active,
        child: Column(
          children: [
            const Spacer(),
            ToastBottomInset(controller: c, child: bar(52)),
          ],
        ),
      ),
    );
    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(c.bottomInset.value, 0);

    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(c.bottomInset.value, 52);

    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(c.bottomInset.value, 0);
  });
}
