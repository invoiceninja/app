import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/app/env.dart';
import 'package:admin/app/services.dart';
import 'package:admin/app/terminal_controller.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/data/services/terminal_server_error.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/features/settings/widgets/form_section.dart';
import 'package:admin/ui/features/settings/widgets/setting_row.dart';
import 'package:admin/ui/features/terminal/how_to_tap.dart';
import 'package:admin/ui/features/settings/widgets/tap_to_pay_tile.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_icon.dart';
import 'package:admin/ui/features/terminal/terminal_error_text.dart';
import 'package:admin/ui/features/terminal/views/tap_to_pay_enable_screen.dart';
import 'package:admin/ui/features/terminal/widgets/reader_picker_sheet.dart';

/// Search keys for the settings sidebar search, colocated with the card (see
/// `search_catalog_consistency_test`).
///
/// On iOS the Tap to Pay row is titled with Apple's name
/// ([kTapToPayOnIPhoneKey]), so search offers that label there and "Tap to
/// Pay" everywhere else.
const kCardReaderSearchKeys = <String>[
  'card_readers',
  'tap_to_pay',
  kTapToPayOnIPhoneKey,
  'bluetooth_card_reader',
];

/// Whether [CardReaderSection] can render in this build: the store build of
/// the mobile app. It draws only once the server has answered too
/// ([cardReaderSectionAnswered]).
bool cardReaderSectionShown() =>
    kCardPresentEnabled && Env.isMobile && StripeTerminal.isAvailable;

/// Whether [CardReaderSection] draws now — and so whether settings search
/// offers its keys: this build can, and the server has answered
/// `terminal/config` for the active company. A server without card payments
/// (404), one that can't be reached, and a user who can't create payments get
/// no section at all, rather than a card about a feature their server doesn't
/// have; it appears by itself once the server answers
/// (`TerminalController.unsupportedConfigRetry`).
bool cardReaderSectionAnswered(Services services) {
  // First, so a build without the feature never touches the controller.
  if (!cardReaderSectionShown()) return false;
  final companyId = services.auth.session.value?.currentCompanyId;
  return companyId != null && services.terminal.configFor(companyId) != null;
}

/// Whether the Tap to Pay row renders. On iOS only once this build is
/// known to carry Apple's entitlement: before general availability (today's
/// App Store build) nothing may name Tap to Pay on iPhone, so the row — its
/// name, symbol and "isn't available" — is not drawn at all.
bool tapToPayRowShown([TerminalDeviceSupport? device]) {
  if (!isIPhonePlatform()) return true;
  final known = device ?? TerminalController.lastKnownDevice;
  return known != null &&
      known.tapToPayBlocker != TerminalErrorCode.entitlementMissing;
}

/// Device Settings → Phone: what this phone can take cards with
/// (docs/in-person-payments.md) — Tap to Pay, or why not; the Bluetooth card
/// reader, connected or not; and where the feature is turned on. Connecting a
/// reader here is how a phone without Tap to Pay starts offering "Collect
/// card payment" on invoices.
class CardReaderSection extends StatefulWidget {
  const CardReaderSection({super.key});

  @override
  State<CardReaderSection> createState() => _CardReaderSectionState();
}

class _CardReaderSectionState extends State<CardReaderSection> {
  late final Services _services;
  late final String? _companyId;
  bool _busy = false;

  TerminalController get _terminal => _services.terminal;

  @override
  void initState() {
    super.initState();
    _services = context.read<Services>();
    _companyId = _services.auth.session.value?.currentCompanyId;
    if (cardReaderSectionShown() && _companyId != null) {
      _terminal.ensureConfig(_companyId);
    }
  }

  Future<void> _connect() async {
    final companyId = _companyId;
    final config = companyId == null ? null : _terminal.configFor(companyId);
    final gateway = config?.usableGateway;
    if (companyId == null || gateway == null) {
      Notify.warning(context, context.tr('terminal_server_not_enabled'));
      return;
    }
    final company = _services.auth.session.value?.currentCompany;
    final isAdmin = (company?.isAdmin ?? false) || (company?.isOwner ?? false);
    var location = gateway.locations.firstOrNull;
    if (location == null && !isAdmin) {
      Notify.warning(context, context.tr('terminal_ask_admin_location'));
      return;
    }
    setState(() => _busy = true);
    // No warm-up takes the reader while one is chosen here, and one that
    // already holds it for Tap to Pay lets go first: the SDK connects one
    // reader at a time.
    final releaseWarmUp = _terminal.holdWarmUp();
    try {
      await _terminal.releaseTapToPay();
      if (!mounted) return;
      // The gateway's first reader: an admin creates its Stripe Location
      // from the company address, as the collect screen does.
      location ??= await _terminal.repository.createLocation(
        companyId,
        companyGatewayId: gateway.companyGatewayId,
      );
      if (!mounted) return;
      unawaited(_terminal.refreshConfig(companyId));
      final permission = await _terminal.platform.requestPermissions(
        TerminalReaderKind.bluetooth,
      );
      if (!mounted) return;
      if (permission != TerminalPermission.granted) {
        Notify.warning(
          context,
          context.tr(terminalErrorKey(TerminalErrorCode.permissionDenied)),
        );
        if (permission == TerminalPermission.blocked) {
          await _terminal.platform.openSettings();
        }
        return;
      }
      await _terminal.prepare(
        companyId: companyId,
        gateway: gateway,
        location: location,
      );
      if (!mounted) return;
      final reader = await showReaderPickerSheet(
        context,
        readers: () => _terminal.discoverBluetooth(gateway),
      );
      if (reader == null) return;
      await _terminal.connectBluetooth(
        reader,
        location: location,
        merchantDisplayName:
            _services.auth.session.value?.currentCompany?.name ?? '',
      );
    } on TerminalError catch (e) {
      if (mounted) {
        Notify.error(
          context,
          context.tr(terminalErrorKey(e.code), {
            'name': tapToPayNameFor(context, terminalErrorKey(e.code)),
          }),
        );
      }
    } on TerminalServerError catch (e) {
      if (mounted) {
        Notify.error(
          context,
          context.tr(
            terminalServerErrorKey(e.code) ?? 'terminal_error_unknown',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Notify.error(context, context.tr('terminal_error_unknown'), error: e);
      }
    } finally {
      releaseWarmUp();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Where Tap to Pay on iPhone stands here, from the controller's live
  /// facts: asking, an iOS to update, getting ready, ready (connected, or
  /// set up on this account before), only an admin can go on, or Turn on.
  TapToPayTileState _tileState(TerminalDeviceSupport device) {
    final companyId = _companyId;
    if (companyId == null) return TapToPayTileState.checking;
    if (device.osUpdateRequired) return TapToPayTileState.updateIos;
    if (_terminal.tapToPayConnecting) return TapToPayTileState.preparing;
    // This company's state, never the per-user announcement.
    if (_terminal.tapToPayReadyFor(companyId)) return TapToPayTileState.ready;
    if (_terminal.configState(companyId) == TerminalConfigState.loading) {
      return TapToPayTileState.checking;
    }
    final company = _services.auth.session.value?.currentCompany;
    final isAdmin = (company?.isAdmin ?? false) || (company?.isOwner ?? false);
    final config = _terminal.configFor(companyId);
    final cardPresentOn =
        config?.gateways.any(
          (g) =>
              g.cardPaymentsActive &&
              kTapToPayIPhoneCountries.contains(g.accountCountry),
        ) ??
        false;
    if (!isAdmin &&
        (_terminal.tapToPayLinkedFor(companyId) == false || !cardPresentOn)) {
      return TapToPayTileState.askAdmin;
    }
    return TapToPayTileState.notSetUp;
  }

  /// The Stripe account's country, for the education's PIN paragraph.
  String _accountCountry() {
    final companyId = _companyId;
    if (companyId == null) return '';
    final config = _terminal.configFor(companyId);
    return config?.usableGateway?.accountCountry ??
        config?.setupGateways.firstOrNull?.accountCountry ??
        '';
  }

  /// What the server said for this company, when it isn't "ready".
  String? _stateKey() {
    final companyId = _companyId;
    if (companyId == null) return null;
    return switch (_terminal.configState(companyId)) {
      TerminalConfigState.noPermission => 'terminal_state_no_permission',
      TerminalConfigState.serverTooOld => 'terminal_state_server_too_old',
      TerminalConfigState.unreachable => 'terminal_state_unreachable',
      TerminalConfigState.switchedOff => 'terminal_server_disabled',
      TerminalConfigState.notEnabled => 'terminal_server_not_enabled',
      TerminalConfigState.accountInactive => 'terminal_state_account_inactive',
      TerminalConfigState.planRequired => 'terminal_server_plan_required',
      TerminalConfigState.unavailable ||
      TerminalConfigState.loading ||
      TerminalConfigState.ready => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!cardReaderSectionShown()) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _terminal,
      builder: (context, _) {
        // Nothing until the server answers: an older server's card is not
        // drawn, and this rebuilds into the section when it does.
        if (!cardReaderSectionAnswered(_services)) {
          return const SizedBox.shrink();
        }
        final device = _terminal.device;
        final reader = _terminal.reader;
        final bluetoothReader =
            reader != null && reader.kind == TerminalReaderKind.bluetooth;
        final tapToPay = device?.tapToPay ?? false;
        // On an iPhone: Apple's name and symbol, never the Material
        // contactless icon (App Review 5.4, 5.5) — and nothing at all before
        // the build may take it.
        final iPhone = isIPhonePlatform();
        final rowShown = tapToPayRowShown(device);
        String subtitleKey() {
          if (iPhone && tapToPay && (device?.osUpdateRequired ?? false)) {
            return 'terminal_update_ios';
          }
          if (tapToPay) {
            return iPhone
                ? 'terminal_tap_to_pay_available_ios'
                : 'terminal_tap_to_pay_ready';
          }
          return switch (device?.tapToPayBlocker) {
            TerminalErrorCode.unsupportedOs => terminalErrorKey(
              TerminalErrorCode.unsupportedOs,
            ),
            _ =>
              iPhone
                  ? 'terminal_tap_to_pay_unavailable_ios'
                  : 'terminal_tap_to_pay_unavailable',
          };
        }

        final subtitle = subtitleKey();
        final setupHelp = iPhone && rowShown && tapToPay
            ? 'terminal_setup_help_ios'
            : 'terminal_setup_help';
        return FormSection(
          title: context.tr('card_readers'),
          description: context.tr('card_readers_help'),
          spacing: 0,
          children: [
            // On an iPhone that can: where Tap to Pay on iPhone stands, and
            // the way to turn it on outside checkout (App Review 3.6, 4.3).
            if (rowShown && iPhone && tapToPay)
              ValueListenableBuilder<double?>(
                valueListenable: _terminal.setupProgress,
                builder: (context, progress, _) => TapToPayTile(
                  state: _tileState(device!),
                  progress: progress,
                  // Only someone who can finish it (the plan, a Stripe
                  // gateway); anyone else reads the status, and the server's
                  // reason below.
                  onTurnOn:
                      _companyId != null &&
                          _terminal.canSetUpTapToPayOnIPhone(_companyId)
                      ? () => unawaited(showTapToPayEnableScreen(context))
                      : null,
                  onHowToUse: () => unawaited(
                    showHowToTap(context, accountCountry: _accountCountry()),
                  ),
                ),
              )
            else if (rowShown)
              SettingRow(
                icon: iPhone
                    ? const TapToPayIcon()
                    : const Icon(Icons.contactless_outlined),
                // The words a settings search hit for it reveals.
                title: iPhone
                    ? context.tr('tap_to_pay_on_iphone')
                    : context.tr('tap_to_pay'),
                subtitle: context.tr(subtitle, {
                  'name': tapToPayNameFor(context, subtitle),
                }),
                stackWhenNarrow: false,
                // Apple wants its "How to Tap" reachable after the first time.
                control:
                    tapToPay &&
                        !kIsWeb &&
                        defaultTargetPlatform == TargetPlatform.iOS
                    ? TextButton(
                        onPressed: () => showHowToTap(context),
                        child: Text(context.tr('terminal_how_to_tap_short')),
                      )
                    : null,
              ),
            if (kCardPresentBluetooth)
              SettingRow(
                icon: const Icon(Icons.point_of_sale_outlined),
                title: context.tr('bluetooth_card_reader'),
                subtitle: bluetoothReader
                    ? reader.label
                    : context.tr('terminal_no_reader'),
                stackWhenNarrow: false,
                control: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : bluetoothReader
                    ? TextButton(
                        onPressed: _terminal.disconnect,
                        child: Text(context.tr('disconnect')),
                      )
                    : TextButton(
                        onPressed: _connect,
                        child: Text(context.tr('terminal_connect_reader')),
                      ),
              ),
            if (_stateKey() case final key?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(context.tr(key)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.tr(setupHelp, {
                  'name': tapToPayNameFor(context, setupHelp),
                }),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }
}
