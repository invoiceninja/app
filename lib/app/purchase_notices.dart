import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import 'package:admin/app/localized_toast.dart';
import 'package:admin/domain/upgrade/purchase_delivery.dart';
import 'package:admin/ui/core/widgets/toast_controller.dart';

/// Tells the user about a store purchase delivered while no purchase sheet is
/// open — an Ask to Buy approved later, a purchase interrupted on the way to
/// the server, one handed back at launch. The open sheet says it itself.
///
/// It subscribes when the app builds, which can be after the launch sweep has
/// already delivered: [PurchaseDelivery.activity] holds what happened before
/// its first listener and hands it over, so that refusal is told too.
///
/// Only a refusal is told: the hosted service's own words (a test purchase,
/// one already linked to another account) under a localized title. A
/// purchase applied in the background — every renewal is one — says nothing,
/// and one left for a later try is retried on the next launch without a word.
class PurchaseNotices {
  PurchaseNotices({
    required PurchaseDelivery delivery,
    required ToastController toasts,
    required BuildContext? Function() contextOf,
  }) : _delivery = delivery,
       _toasts = toasts,
       _contextOf = contextOf {
    _sub = delivery.activity.listen(_onActivity);
  }

  final PurchaseDelivery _delivery;
  final ToastController _toasts;
  final BuildContext? Function() _contextOf;
  late final StreamSubscription<PurchaseActivity> _sub;
  static final _log = Logger('PurchaseNotices');

  void _onActivity(PurchaseActivity a) {
    if (a.kind != PurchaseActivityKind.rejected || _delivery.sheetOpen) return;
    _show(a, 0);
  }

  /// How many frames a refusal waits for a context to say it in: one held
  /// from the launch sweep can arrive before the first frame has a navigator.
  static const _maxFrameWaits = 10;

  void _show(PurchaseActivity a, int frameWaits) {
    if (_disposed) return;
    if (_contextOf() == null && frameWaits < _maxFrameWaits) {
      final binding = WidgetsBinding.instance;
      binding.addPostFrameCallback((_) => _show(a, frameWaits + 1));
      binding.scheduleFrame();
      return;
    }
    final message = a.message?.trim() ?? '';
    showLocalizedToast(
      toasts: _toasts,
      context: _contextOf(),
      key: 'store_purchase_not_applied',
      detail: message.isEmpty ? null : message,
      kind: LocalizedToastKind.error,
      log: _log,
    );
  }

  bool _disposed = false;

  Future<void> dispose() {
    _disposed = true;
    return _sub.cancel();
  }
}
