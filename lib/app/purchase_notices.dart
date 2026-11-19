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

  Future<void> dispose() => _sub.cancel();
}
