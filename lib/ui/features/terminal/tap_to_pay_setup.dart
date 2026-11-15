import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/app/services.dart';
import 'package:admin/app/terminal_controller.dart';
import 'package:admin/data/models/domain/company_gateway.dart';

/// The steps of turning Tap to Pay on iPhone on that the collect screen's
/// button and the enable screen share (docs/in-person-payments.md): each
/// asks the user at most what is still missing, and never prompts out of
/// nowhere.

/// What asking for location came to.
enum LocationAccess {
  granted,

  /// The app's own explanation, or iOS's prompt, was turned down: ask again
  /// on the next press.
  declined,

  /// iOS won't ask again: only Settings.
  blocked,

  /// Location Services are off for the whole device: only Settings, Privacy
  /// & Security.
  servicesOff,
}

/// Location for Tap to Pay on iPhone: a check that shows nothing first, then
/// — only when it was never asked — the app's own explanation
/// ([askLocation], true to go on), then iOS's prompt. [onAsking] runs as the
/// explanation opens; [stillWanted] is asked before each prompt, so a press
/// that something newer replaced never prompts.
Future<LocationAccess> requestTapToPayLocation(
  TerminalController terminal, {
  required Future<bool> Function() askLocation,
  VoidCallback? onAsking,
  bool Function()? stillWanted,
}) async {
  final device = await terminal.refreshDevice();
  if (!device.locationServicesEnabled) return LocationAccess.servicesOff;
  var permission = await terminal.platform.permissionStatus(
    TerminalReaderKind.tapToPay,
  );
  if (permission == TerminalPermission.denied) {
    // Never asked yet: the app explains first, then iOS asks.
    if (stillWanted?.call() == false) return LocationAccess.declined;
    onAsking?.call();
    if (!await askLocation()) return LocationAccess.declined;
    if (stillWanted?.call() == false) return LocationAccess.declined;
    permission = await terminal.platform.requestPermissions(
      TerminalReaderKind.tapToPay,
    );
  }
  return switch (permission) {
    TerminalPermission.granted => LocationAccess.granted,
    TerminalPermission.blocked => LocationAccess.blocked,
    TerminalPermission.denied => LocationAccess.declined,
  };
}

/// Gateway type 32, Card present (`kGatewayTypeLabelKey`).
const kCardPresentGatewayType = '32';

/// An admin turns Card present on for a Stripe gateway, the way the
/// gateway's own Settings tab does (`setTypeEnabled('32')`), on the gateway
/// as the server has it now — then waits until it has been saved.
Future<void> enableCardPresent(
  Services services,
  String companyId,
  String companyGatewayId,
) async {
  final gateways = services.companyGateways;
  await gateways.refreshAll(companyId: companyId, full: true);
  final current = await gateways
      .watchByRealId(companyId: companyId, id: companyGatewayId)
      .first
      .timeout(const Duration(seconds: 5));
  if (current == null) throw StateError('gateway not found');
  final fees = Map<String, FeesAndLimits>.from(current.feesAndLimits);
  fees[kCardPresentGatewayType] =
      (fees[kCardPresentGatewayType] ?? const FeesAndLimits()).copyWith(
        isEnabled: true,
      );
  await gateways.save(
    companyId: companyId,
    gateway: current.copyWith(feesAndLimits: fees),
  );
  unawaited(services.sync.drainOnce(companyId: companyId));
  await gateways
      .watchByRealId(companyId: companyId, id: companyGatewayId)
      .firstWhere((g) => g != null && !g.isDirty)
      .timeout(const Duration(seconds: 30));
}
