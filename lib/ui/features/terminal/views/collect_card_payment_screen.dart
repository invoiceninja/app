import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/company_gateway.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/dialogs/confirm_action_dialog.dart';
import 'package:admin/ui/core/utils/haptics.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';
import 'package:admin/ui/core/widgets/form_save_scope.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';
import 'package:admin/ui/core/widgets/qr_code_image.dart';
import 'package:admin/ui/features/terminal/how_to_tap.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_icon.dart';
import 'package:admin/ui/features/terminal/terminal_error_text.dart';
import 'package:admin/ui/features/terminal/view_models/collect_card_payment_view_model.dart';
import 'package:admin/ui/features/terminal/widgets/reader_picker_sheet.dart';
import 'package:admin/utils/formatting.dart';

/// "Collect card payment" for one invoice (docs/in-person-payments.md): a
/// full-screen step on the root navigator, never part of the saved route.
Future<void> showCollectCardPaymentScreen(
  BuildContext context, {
  required String companyId,
  required Invoice invoice,
  Client? client,
  String groupCurrencyId = '',
}) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => CollectCardPaymentScreen(
      companyId: companyId,
      invoice: invoice,
      client: client,
      groupCurrencyId: groupCurrencyId,
      // The invoice's action is Apple's button on an iPhone (5.3).
      pressOnOpen: true,
    ),
  ),
);

class CollectCardPaymentScreen extends StatefulWidget {
  const CollectCardPaymentScreen({
    super.key,
    required this.companyId,
    required this.invoice,
    this.client,
    this.groupCurrencyId = '',
    this.pressOnOpen = false,
    @visibleForTesting this.viewModel,
  });

  /// Opened by the invoice's action, which on an iPhone is the Tap to Pay on
  /// iPhone button: opening presses it
  /// (`CollectCardPaymentViewModel.pressOnOpen`).
  final bool pressOnOpen;

  final String companyId;
  final Invoice invoice;

  /// The invoice's client, for its currency and email, when known.
  final Client? client;

  /// The client's group's currency, when the client inherits one.
  final String groupCurrencyId;

  /// Tests drive the screen with their own (faked) view model.
  final CollectCardPaymentViewModel? viewModel;

  @override
  State<CollectCardPaymentScreen> createState() =>
      _CollectCardPaymentScreenState();
}

class _CollectCardPaymentScreenState extends State<CollectCardPaymentScreen> {
  late final Services _services;
  late final CollectCardPaymentViewModel _vm;
  late final VoidCallback _unregisterGuard;
  late final VoidCallback _unlistenReader;
  late final VoidCallback _releaseWarmUp;
  late final AppLifecycleListener _lifecycle;
  late final TextEditingController _amount;
  late final TextEditingController _email;
  Formatter? _formatter;
  Client? _client;
  TerminalDisplayMessage? _readerMessage;

  /// 0–1 while the reader installs an update, else null.
  double? _updateProgress;
  CollectStage? _lastStage;

  /// Apple's terms were accepted during this screen's connect: education
  /// follows, whatever was shown before (App Review 4.2).
  bool _termsAccepted = false;

  /// Education is showing, or was shown, on this screen.
  bool _educated = false;

  @override
  void initState() {
    super.initState();
    _services = context.read<Services>();
    final session = _services.auth.session.value;
    final company = session?.currentCompany;
    _client = widget.client;
    _formatter = _services.formatterIfReady(widget.companyId);
    final precision =
        _formatter?.precisionFor(currencyId: _clientCurrencyId) ?? 2;
    _vm =
        (widget.viewModel ??
              CollectCardPaymentViewModel(
                companyId: widget.companyId,
                invoice: widget.invoice,
                terminal: _services.terminal,
                repository: _services.terminal.repository,
                isAdmin:
                    (company?.isAdmin ?? false) || (company?.isOwner ?? false),
                merchantDisplayName: company?.name ?? '',
                precision: precision,
                clientEmail: _primaryEmail(_client),
                chargeCurrency: _chargeCurrency,
                enableCardPresent: _enableCardPresent,
                pressOnOpen: widget.pressOnOpen,
              ))
          ..addListener(_onChanged)
          ..askLocation = _askLocation
          ..onReady = _onReady;
    _amount = TextEditingController(text: _moneyInput(_vm.amount));
    _email = TextEditingController(text: _vm.clientEmail)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _unlistenReader = _vm.terminal.addEventListener(
      TerminalReaderEvents(
        onDisplayMessage: (m) {
          if (mounted) setState(() => _readerMessage = m);
        },
        onUpdateProgress: (p) {
          if (mounted) setState(() => _updateProgress = p);
        },
        onUpdateFinished: (_) {
          if (mounted) setState(() => _updateProgress = null);
        },
        onDisconnected: _vm.readerDisconnected,
        onTermsAccepted: _onTermsAccepted,
      ),
    );
    // This screen gets the reader ready itself.
    _releaseWarmUp = _vm.terminal.holdWarmUp();
    // Apple's sheet takes the screen: the app goes inactive under it — the
    // end of the press's latency (App Review 5.6).
    _lifecycle = AppLifecycleListener(
      onInactive: () {
        if (_vm.awaitingSheet) _vm.noteSheetShown();
      },
      // Back from Settings, where location may have been allowed.
      onResume: _vm.appResumed,
    );
    // A company switch (a deep link's) waits while a payment is under way:
    // every call that settles it is bound to this company, so after a
    // switch a charged card could never be checked or recorded from here.
    _unregisterGuard = _services.unsavedChangesGuard.register(
      isDirty: () => _vm.bindsCompany,
      source: _vm,
      blockedMessage: (context) => context.tr(
        _vm.inProgress ? 'terminal_finish_first' : 'terminal_close_first',
      ),
    );
    if (_formatter == null) {
      _services.formatterFor(widget.companyId).then((f) {
        if (!mounted) return;
        setState(() => _formatter = f);
        _syncPrecision();
        // The field was filled before the currency's format was known; only
        // that placeholder text is replaced, never something typed.
        if (_vm.stage == CollectStage.configure &&
            _amount.text == _vm.amount.toString()) {
          _amount.text = _moneyInput(_vm.amount);
        }
      });
    }
    unawaited(_vm.start());
  }

  /// The client's currency code, for the gateway that can charge in it;
  /// null when the client isn't known here (the company's currency would
  /// be a guess).
  Future<String?> _chargeCurrency() async {
    if (_client == null) return null;
    final f = await _services.formatterFor(widget.companyId);
    return f.currencyCodeFor(currencyId: _clientCurrencyId);
  }

  static String _primaryEmail(Client? client) {
    final contacts = [...?client?.contacts]
      ..sort((a, b) => (b.isPrimary ? 1 : 0) - (a.isPrimary ? 1 : 0));
    for (final c in contacts) {
      if (c.email.trim().isNotEmpty) return c.email.trim();
    }
    return '';
  }

  /// The currency the card is charged in: the server's answer once it has
  /// quoted, else the client's own, then its group's (the formatter falls
  /// back to the company's). Never just the client's — one inheriting its
  /// group's currency would show every figure in the company's.
  String? get _currencyId {
    final quoted = _vm.quote?.currencyId ?? '';
    return quoted.isNotEmpty ? quoted : _clientCurrencyId;
  }

  String? get _clientCurrencyId {
    final own = _client?.currencyId ?? '';
    if (own.isNotEmpty) return own;
    return widget.groupCurrencyId.isEmpty ? null : widget.groupCurrencyId;
  }

  String _moneyInput(Decimal value) =>
      _formatter?.inputMoney(value, currencyId: _currencyId) ??
      value.toString();

  String _money(Decimal? value) =>
      _formatter?.money(value, currencyId: _currencyId) ?? '${value ?? ''}';

  /// The amount field rounds to the charged currency's decimals, which are
  /// known for sure only once the formatter is ready and the server quoted.
  void _syncPrecision() {
    final f = _formatter;
    if (f == null) return;
    _vm.precision = f.precisionFor(currencyId: _currencyId);
  }

  /// An admin's press with Card present off turns it on, the way the
  /// gateway's own Settings tab does (`setTypeEnabled('32')`), on the
  /// gateway as the server has it now — then waits until it has been saved.
  Future<void> _enableCardPresent(String companyGatewayId) async {
    final gateways = _services.companyGateways;
    final companyId = widget.companyId;
    await gateways.refreshAll(companyId: companyId, full: true);
    final current = await gateways
        .watchByRealId(companyId: companyId, id: companyGatewayId)
        .first
        .timeout(const Duration(seconds: 5));
    if (current == null) throw StateError('gateway not found');
    final fees = Map<String, FeesAndLimits>.from(current.feesAndLimits);
    fees[_cardPresentType] = (fees[_cardPresentType] ?? const FeesAndLimits())
        .copyWith(isEnabled: true);
    await gateways.save(
      companyId: companyId,
      gateway: current.copyWith(feesAndLimits: fees),
    );
    unawaited(_services.sync.drainOnce(companyId: companyId));
    await gateways
        .watchByRealId(companyId: companyId, id: companyGatewayId)
        .firstWhere((g) => g != null && !g.isDirty)
        .timeout(const Duration(seconds: 30));
  }

  /// Gateway type 32, Card present (`kGatewayTypeLabelKey`).
  static const _cardPresentType = '32';

  void _onChanged() {
    if (!mounted) return;
    _syncPrecision();
    final stage = _vm.stage;
    if (stage != _lastStage) {
      _lastStage = stage;
      _readerMessage = null;
      switch (stage) {
        case CollectStage.approved:
          unawaited(InHaptics.success());
        case CollectStage.waiting || CollectStage.declined:
          unawaited(InHaptics.light());
        default:
      }
    }
    setState(() {});
  }

  /// The reader is ready ([CollectCardPaymentViewModel.onReady]): Apple's
  /// education if owed, and whether the payment may go straight on — not
  /// after Apple's terms, nor after the education.
  Future<bool> _onReady() async {
    final shown = await _educate(afterTerms: _termsAccepted);
    return !_termsAccepted && !shown;
  }

  /// Apple's merchant education ("How to Tap"), which App Review requires
  /// after the terms are accepted (4.2) and before the first Tap to Pay on
  /// iPhone collection: after the terms ([afterTerms]) once their sheet has
  /// closed, else once per account when the reader first connects. Marked
  /// shown only when it was (docs/in-person-payments.md). True when it was
  /// shown, or is being shown, here.
  Future<bool> _educate({required bool afterTerms}) async {
    final terminal = _vm.terminal;
    if (!_vm.tapToPayOnIPhone || !mounted) return false;
    if (_educated) return true;
    if (!afterTerms && !terminal.howToTapDue) return false;
    _educated = true;
    // Never over Apple's terms sheet while it is still going away — however
    // soon after it the reader turns ready.
    if (afterTerms) await _untilTermsSheetClosed();
    if (!mounted) return true;
    final shown = await showHowToTap(context);
    if (shown) await terminal.markHowToTapShown();
    return shown;
  }

  /// The app is back in front (the sheet is gone), and a moment more.
  static Future<void> _untilTermsSheetClosed() async {
    for (var i = 0; i < 150; i++) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  /// Apple's terms were accepted: the education follows.
  void _onTermsAccepted() {
    _termsAccepted = true;
    unawaited(_educate(afterTerms: true));
  }

  @override
  void dispose() {
    _unlistenReader();
    _releaseWarmUp();
    _lifecycle.dispose();
    _unregisterGuard();
    _vm
      ..removeListener(_onChanged)
      ..dispose();
    _amount.dispose();
    _email.dispose();
    super.dispose();
  }

  /// Commits the field; true when that changed the amount (then quoted
  /// anew). The field shows the amount as the currency rounds it.
  bool _setAmount() {
    final value = parseDecimal(
      _amount.text,
      useCommaAsDecimalPlace:
          _formatter?.settings.useCommaAsDecimalPlace ?? false,
    );
    if (value == null) return false;
    final changed = _vm.setAmount(value);
    final shown = _moneyInput(_vm.amount);
    if (_amount.text != shown) _amount.text = shown;
    return changed;
  }

  /// A typed amount counts even when the field never lost focus (a tap on
  /// touch doesn't unfocus it): a changed amount is quoted first, and the
  /// next tap collects it.
  Future<void> _collect() async {
    if (_setAmount()) return;
    await _vm.collect();
  }

  /// The Tap to Pay on iPhone button: a typed amount is quoted first and
  /// then taken by the same press (the press waits for the figures).
  Future<void> _pressTapToPay() async {
    _setAmount();
    await _vm.pressTapToPay(askLocation: _askLocation);
  }

  /// The app's own word before iOS asks for location (App Review asks that
  /// a prompt never come out of nowhere): Continue lets iOS ask.
  Future<bool> _askLocation() async {
    // An opening press may ask before the screen's first frame.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('terminal_location_prealert_title')),
        content: Text(
          context.tr('terminal_location_prealert', {
            'name': tapToPayNameFor(context, 'terminal_location_prealert'),
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('cancel')),
          ),
          PrimaryDialogAction(
            label: context.tr('continue'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// The payment to quote to support, with the one rule that matters.
  List<Widget> _reference(BuildContext context) {
    final reference = _vm.paymentReference;
    return [
      SizedBox(height: InSpacing.md(context)),
      Text(
        context.tr('terminal_dont_record_by_hand'),
        textAlign: TextAlign.center,
      ),
      if (reference != null) ...[
        const SizedBox(height: InSpacing.sm),
        CopyableValue(
          value: reference,
          fillWidth: false,
          child: Center(
            child: LtrText(
              context.tr('terminal_reference', {'reference': reference}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    ];
  }

  /// "Cancel it and start again" may stop a payment someone else is taking.
  Future<void> _cancelOpenCollection() async {
    final ok = await showConfirmActionDialog(
      context,
      title: context.tr('terminal_cancel_open'),
      message: context.tr('terminal_cancel_open_warning'),
      destructive: true,
    );
    if (ok && mounted) await _vm.cancelOpenCollection();
  }

  Future<void> _close() async {
    if (_vm.locked) return;
    if (_vm.inProgress) await _vm.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _acknowledgeSurcharge() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('terminal_surcharge_rules_title')),
        content: SingleChildScrollView(
          child: Text(context.tr('terminal_surcharge_rules')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('cancel')),
          ),
          PrimaryDialogAction(
            label: context.tr('terminal_surcharge_accept'),
            // A legal acknowledgement: never Enter's default.
            autofocus: false,
            showEnterHint: false,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok == true) await _vm.acknowledgeSurcharge();
  }

  Future<void> _pickReader() async {
    final reader = await showReaderPickerSheet(
      context,
      readers: _vm.discoverReaders,
    );
    if (reader != null) await _vm.connectReader(reader);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.inTheme;
    return PopScope(
      canPop: !_vm.locked && !_vm.inProgress,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: theme.surface,
        appBar: AppBar(
          title: Text(context.tr('collect_card_payment')),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: context.tr('close'),
            onPressed: _vm.locked ? null : _close,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: EdgeInsets.all(InSpacing.lg(context)),
                children: [
                  if (!_vm.livemode) _TestModeBadge(),
                  ..._body(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) => switch (_vm.stage) {
    CollectStage.configure => _configure(context),
    CollectStage.creating => [
      _Status(text: context.tr('terminal_preparing'), busy: true),
    ],
    CollectStage.openCollection => [
      _Status(text: _problemText(context)),
      const SizedBox(height: InSpacing.xl),
      _Buttons(
        primary: context.tr('terminal_cancel_open'),
        onPrimary: _cancelOpenCollection,
        secondary: context.tr('close'),
        onSecondary: () async => Navigator.of(context).pop(),
      ),
    ],
    CollectStage.waiting => _waiting(context),
    CollectStage.finalizing => [
      _Total(text: _totalText()),
      _Status(text: context.tr('terminal_checking_card'), busy: true),
    ],
    CollectStage.surchargeNotice => [
      _Total(text: _totalText()),
      _Status(
        icon: Icons.credit_card_outlined,
        text: context.tr('terminal_surcharge_notice', {
          'total': _totalText(),
          'surcharge': _money(_vm.finalized?.surcharge),
        }),
      ),
      const SizedBox(height: InSpacing.xl),
      _Buttons(
        primary: context.tr('continue'),
        onPrimary: () async => _vm.continueWithSurcharge(),
        secondary: context.tr('cancel'),
        onSecondary: _vm.cancel,
      ),
    ],
    CollectStage.settling => [
      _Status(text: context.tr('terminal_settling'), busy: true),
    ],
    CollectStage.processing => [
      _Total(text: _totalText()),
      _Status(text: context.tr('terminal_processing'), busy: true),
    ],
    CollectStage.declined => [
      _Total(text: _totalText()),
      _Status(
        // After a reader reconnected here there is no problem left to name.
        text: _vm.problem == null && _vm.readerState == ReaderState.ready
            ? context.tr('terminal_reader_ready', {
                'reader': _vm.reader?.label ?? '',
              })
            : _problemText(context),
        icon: Icons.credit_card_off_outlined,
      ),
      const SizedBox(height: InSpacing.xl),
      // Reconnecting a reader: nothing to try until it is back.
      if (_vm.readerState == ReaderState.connecting)
        _Buttons(
          primary: context.tr('terminal_reader_connecting'),
          onPrimary: null,
          secondary: context.tr('cancel'),
          onSecondary: _close,
        )
      // The reader went away mid-collection: connect one before trying.
      else if (_vm.readerState == ReaderState.needsReader)
        _Buttons(
          primary: context.tr('terminal_connect_reader'),
          onPrimary: _pickReader,
          secondary: context.tr('cancel'),
          onSecondary: _close,
        )
      else
        _Buttons(
          primary: context.tr(switch (_vm.problem?.code) {
            TerminalErrorCode.declined ||
            TerminalErrorCode.cardNotRead ||
            TerminalErrorCode.pinUnavailable => 'terminal_try_another_card',
            _ => 'terminal_try_again',
          }),
          onPrimary: _vm.tryAnotherCard,
          secondary: context.tr('cancel'),
          onSecondary: _close,
        ),
    ],
    CollectStage.approved => _approved(context),
    CollectStage.recording => [
      ..._pending(context, context.tr('terminal_recording')),
      ..._reference(context),
    ],
    CollectStage.checking => [
      ..._pending(context, context.tr('terminal_checking_help')),
      ..._reference(context),
      const SizedBox(height: InSpacing.sm),
      Center(
        child: TextButton(
          onPressed: _vm.cancelUnconfirmed,
          child: Text(context.tr('terminal_cancel_payment')),
        ),
      ),
    ],
    CollectStage.unrecorded => [
      _Status(
        text: context.tr('terminal_unrecorded'),
        icon: Icons.report_outlined,
      ),
      ..._reference(context),
      const SizedBox(height: InSpacing.xl),
      _Buttons(
        primary: context.tr('close'),
        onPrimary: () async => Navigator.of(context).pop(),
      ),
    ],
    CollectStage.cancelled => [
      _Status(
        text: context.tr('terminal_cancelled'),
        icon: Icons.block_outlined,
      ),
      if (_vm.problem != null) ...[
        const SizedBox(height: InSpacing.sm),
        Text(_problemText(context), textAlign: TextAlign.center),
      ],
      const SizedBox(height: InSpacing.xl),
      _Buttons(
        primary: context.tr('close'),
        onPrimary: () async => Navigator.of(context).pop(),
      ),
    ],
  };

  String _problemText(BuildContext context) {
    final problem = _vm.problem;
    return problem == null
        ? ''
        : terminalProblemText(
            problem,
            context.tr,
            name: (key) => tapToPayNameFor(context, key),
            tapToPay: _vm.tapToPayOnIPhone,
          );
  }

  /// The server's latest figure once it has decided one (a lowered or raised
  /// PaymentIntent), else the quote.
  ///
  /// Once the PaymentIntent exists, it is the amount the card is read for:
  /// created at the base amount, and raised only after a credit card is read
  /// — a Bluetooth reader has no screen, so this is the only figure shown.
  String _totalText() {
    final finalized = _vm.finalized;
    if (finalized != null) return _money(finalized.amount);
    final intent = _vm.intent;
    if (intent != null) return _money(intent.amount);
    return _money(_vm.quote?.total ?? _vm.amount);
  }

  List<Widget> _configure(BuildContext context) {
    final quote = _vm.quote;
    final surchargeShown = _vm.applySurcharge && quote != null;
    return [
      Text(
        context.tr('terminal_for_invoice', {'number': widget.invoice.number}),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (widget.invoice.isDraft) ...[
        const SizedBox(height: InSpacing.xs),
        Text(context.tr('terminal_draft_marked_sent')),
      ],
      const SizedBox(height: InSpacing.sm),
      FormSaveScope(
        onSubmit: _setAmount,
        child: Focus(
          onFocusChange: (focused) {
            if (!focused) _setAmount();
          },
          child: TextField(
            controller: _amount,
            decoration: InputDecoration(labelText: context.tr('amount')),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            // No press held, or under way, charges what was there before
            // this edit: a fresh press commits it first.
            onChanged: (_) => _vm.amountEdited(),
            onSubmitted: (_) => _setAmount(),
          ),
        ),
      ),
      if (_vm.surchargeUnavailable) ...[
        const SizedBox(height: InSpacing.sm),
        Text(
          context.tr('terminal_surcharge_unavailable_ttp', {
            'name': tapToPayNameFor(
              context,
              'terminal_surcharge_unavailable_ttp',
            ),
          }),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      if (_vm.surchargeNeedsAcknowledgement) ...[
        const SizedBox(height: InSpacing.sm),
        if (_vm.isAdmin)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _acknowledgeSurcharge,
              child: Text(context.tr('terminal_surcharge_set_up')),
            ),
          )
        else
          Text(context.tr('terminal_surcharge_ask_admin')),
      ],
      if (_vm.surchargeOffered)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _vm.applySurcharge,
          onChanged: _vm.setSurcharge,
          title: Text(_surchargeLabel(context)),
          subtitle: Text(context.tr('terminal_surcharge_credit_only')),
        ),
      if (_vm.surchargeRefusal case final reason?)
        Text(
          context.tr(switch (reason) {
            'region' => 'terminal_surcharge_refused_region',
            'adjust_fee_percent' => 'terminal_surcharge_refused_adjust',
            'over_cap' => 'terminal_surcharge_refused_cap',
            _ => 'terminal_surcharge_refused_invoice',
          }),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      const SizedBox(height: InSpacing.sm),
      if (quote != null)
        Semantics(
          liveRegion: true,
          child: Text(
            surchargeShown && quote.feeGross > Decimal.zero
                ? context.tr('terminal_customer_pays_surcharge', {
                    'total': _money(quote.total),
                    'amount': _money(quote.amount),
                  })
                : context.tr('terminal_customer_pays', {
                    'total': _money(quote.total),
                  }),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        )
      else if (_vm.quoting || _vm.starting)
        const LinearProgressIndicator()
      // Nothing to quote with until the press sets Card present or Stripe
      // up (iPhone).
      else if (_vm.cardPresentOff || _vm.needsStripe)
        const SizedBox.shrink()
      else
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _vm.retry,
            child: Text(context.tr('retry')),
          ),
        ),
      SizedBox(height: InSpacing.md(context)),
      // Its own progress, from the same events (3.9.1).
      if (_vm.tapToPayOnIPhone)
        _TapToPayRow(
          vm: _vm,
          progress: _vm.terminal.setupProgress,
          onRetry: _pressTapToPay,
        )
      else if (_updateProgress != null)
        Semantics(
          liveRegion: true,
          child: Text(
            context.tr(
              isIPhonePlatform()
                  ? 'terminal_reader_updating_ios'
                  : 'terminal_reader_updating',
              {'percent': '${(_updateProgress! * 100).round()}'},
            ),
          ),
        )
      else
        _ReaderRow(vm: _vm, onPickReader: _pickReader),
      if (_vm.problem != null && _vm.readerState != ReaderState.failed) ...[
        const SizedBox(height: InSpacing.sm),
        Text(
          _problemText(context),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: InSpacing.xl),
      if (_vm.tapToPayOnIPhone)
        // Apple's button: its name and symbol, never greyed out, top of the
        // screen's choices (App Review 5.1–5.5). A press does what is
        // missing, then the next one takes the card.
        FilledButton.icon(
          onPressed: _pressTapToPay,
          icon: const TapToPayIcon(size: 22),
          label: Text(tapToPayName(context)),
        )
      else
        FilledButton(
          onPressed: _vm.canCollect ? _collect : null,
          child: Text(
            quote == null
                ? context.tr('collect_card_payment')
                : context.tr('terminal_collect_amount', {
                    'amount': _money(quote.total),
                  }),
          ),
        ),
    ];
  }

  /// "Add credit card surcharge (3%)", or without the figure when the fee
  /// is a fixed amount.
  String _surchargeLabel(BuildContext context) {
    final percent = _vm.gateway?.surcharge.feePercent ?? Decimal.zero;
    if (percent <= Decimal.zero) {
      return context.tr('terminal_add_surcharge_plain');
    }
    final f = _formatter;
    final text = f == null
        ? percent.toString()
        : f.inputAmount(percent.toDouble());
    return context.tr('terminal_add_surcharge', {'percent': text});
  }

  List<Widget> _waiting(BuildContext context) {
    final message = _readerMessage;
    final tapToPay = _vm.reader?.kind == TerminalReaderKind.tapToPay;
    final finalized = _vm.finalized;
    final again = _vm.readAgain && finalized != null;
    final iPhone = _vm.tapToPayOnIPhone;
    return [
      _Total(text: _totalText()),
      _Status(
        // Apple's symbol on iOS, never the Material one (App Review 5.5).
        icon: isIPhonePlatform() ? null : Icons.contactless_outlined,
        leading: iPhone ? const TapToPayIcon(size: 48) : null,
        text: again
            ? (finalized.surcharge > Decimal.zero
                  ? context.tr('terminal_tap_again_surcharge', {
                      'amount': _money(finalized.amount),
                    })
                  : context.tr('terminal_tap_again'))
            : message != null
            ? context.tr(_readerMessageKey(message))
            : context.tr(
                iPhone
                    ? 'terminal_hold_card_iphone'
                    : tapToPay
                    ? 'terminal_hold_card'
                    : 'terminal_present_card',
              ),
      ),
      const SizedBox(height: InSpacing.xl),
      _Buttons(
        primary: context.tr('cancel'),
        onPrimary: _vm.cancel,
        tonal: true,
      ),
    ];
  }

  List<Widget> _approved(BuildContext context) {
    final done = _vm.completion;
    // What the server recorded: after a refunded surcharge, or for another
    // attempt's payment, that is not what this screen quoted.
    final charged = done != null && done.isRecorded
        ? _money(done.applied + done.unapplied)
        : _money(_vm.finalized?.amount ?? _vm.quote?.total);
    final card = [
      if ((done?.brand ?? '').isNotEmpty) done!.brand.toUpperCase(),
      if ((done?.last4 ?? '').isNotEmpty) '•• ${done!.last4}',
    ].join(' ');
    final receiptUrl = done?.receiptUrl ?? '';
    return [
      _Status(
        icon: Icons.check_circle_outline,
        text: context.tr('terminal_approved'),
      ),
      _Total(text: charged),
      if (card.isNotEmpty) Center(child: LtrText(card)),
      if (done?.status == 'unapplied')
        Padding(
          padding: const EdgeInsets.only(top: InSpacing.sm),
          child: Text(
            context.tr('terminal_unapplied', {
              'amount': _money(done!.unapplied),
            }),
            textAlign: TextAlign.center,
          ),
        )
      else if (done?.invoiceBalance != null)
        Padding(
          padding: const EdgeInsets.only(top: InSpacing.sm),
          child: Text(
            context.tr('terminal_remaining_balance', {
              'amount': _money(done!.invoiceBalance),
            }),
            textAlign: TextAlign.center,
          ),
        ),
      const SizedBox(height: InSpacing.xl),
      if (_vm.receiptSent)
        Text(context.tr('terminal_receipt_sent'), textAlign: TextAlign.center)
      else ...[
        TextField(
          controller: _email,
          decoration: InputDecoration(labelText: context.tr('email')),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _sendReceipt(),
        ),
        const SizedBox(height: InSpacing.sm),
        OutlinedButton(
          onPressed: _vm.sendingReceipt ? null : _sendReceipt,
          child: Text(context.tr('terminal_send_receipt')),
        ),
        if (_vm.problem != null) ...[
          const SizedBox(height: InSpacing.sm),
          Text(
            _problemText(context),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_email.text.trim().isEmpty && receiptUrl.isNotEmpty) ...[
          SizedBox(height: InSpacing.md(context)),
          Text(
            context.tr('terminal_scan_receipt'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: InSpacing.sm),
          Center(child: QrCodeImage(data: receiptUrl, size: 180)),
        ],
      ],
      const SizedBox(height: InSpacing.xl),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.tr('done')),
      ),
    ];
  }

  Future<void> _sendReceipt() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    await _vm.sendReceipt(email);
  }

  List<Widget> _pending(BuildContext context, String text) => [
    // Another attempt's payment: this screen's quote isn't its amount.
    if (!_vm.settlingAnother) _Total(text: _totalText()),
    _Status(text: text, icon: Icons.hourglass_top_outlined),
    const SizedBox(height: InSpacing.xl),
    _Buttons(
      primary: context.tr('terminal_check_again'),
      onPrimary: _vm.checkAgain,
      secondary: context.tr('close'),
      onSecondary: () async => Navigator.of(context).pop(),
    ),
  ];
}

class _ReaderRow extends StatelessWidget {
  const _ReaderRow({required this.vm, required this.onPickReader});

  final CollectCardPaymentViewModel vm;
  final Future<void> Function() onPickReader;

  @override
  Widget build(BuildContext context) {
    final tapToPay = vm.readerChoice == TerminalReaderChoice.tapToPay;
    final (String text, Widget? action) = switch (vm.readerState) {
      // Never "Nearby devices on Android" on an iPhone or iPad.
      ReaderState.idle || ReaderState.permissions => (
        context.tr(
          isIPhonePlatform()
              ? 'terminal_permissions_help_ios'
              : 'terminal_permissions_help',
        ),
        null,
      ),
      ReaderState.turningOn => (context.tr('terminal_turning_on'), null),
      ReaderState.blocked => (
        context.tr(terminalErrorKey(TerminalErrorCode.permissionDenied)),
        TextButton(
          onPressed: vm.openSettings,
          child: Text(context.tr('open_settings')),
        ),
      ),
      ReaderState.connecting => (
        tapToPay
            ? context.tr('terminal_tap_to_pay_preparing', {
                'name': tapToPayNameFor(
                  context,
                  'terminal_tap_to_pay_preparing',
                ),
              })
            : context.tr('terminal_reader_connecting'),
        null,
      ),
      ReaderState.needsReader => (
        context.tr('terminal_reader_needed'),
        TextButton(
          onPressed: onPickReader,
          child: Text(context.tr('terminal_connect_reader')),
        ),
      ),
      ReaderState.ready => (
        tapToPay
            ? context.tr('terminal_tap_to_pay_ready')
            : context.tr('terminal_reader_ready', {
                'reader': vm.reader?.label ?? '',
              }),
        null,
      ),
      ReaderState.failed => (
        vm.problem == null
            ? context.tr('terminal_error_unknown')
            : terminalProblemText(
                vm.problem!,
                context.tr,
                name: (key) => tapToPayNameFor(context, key),
              ),
        TextButton(
          onPressed: vm.prepareReader,
          child: Text(context.tr('retry')),
        ),
      ),
    };
    final busy =
        vm.readerState == ReaderState.connecting ||
        vm.readerState == ReaderState.turningOn ||
        vm.readerState == ReaderState.permissions;
    return Row(
      children: [
        Icon(
          vm.readerState == ReaderState.ready
              // Never the Material contactless icon on iOS (App Review 5.5).
              ? (isIPhonePlatform()
                    ? Icons.check_circle_outline
                    : Icons.contactless_outlined)
              : Icons.info_outline,
          size: 20,
        ),
        const SizedBox(width: InSpacing.sm),
        Expanded(child: Text(text)),
        if (busy)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ?action,
      ],
    );
  }
}

/// Where Tap to Pay on iPhone stands, under the figures: nothing until a
/// press asks for something, then what it is doing — "Getting Tap to Pay on
/// iPhone ready…" with the reader's own progress while it configures (App
/// Review 5.7, 3.9.1) — or what stopped it, with Retry.
class _TapToPayRow extends StatelessWidget {
  const _TapToPayRow({
    required this.vm,
    required this.progress,
    required this.onRetry,
  });

  final CollectCardPaymentViewModel vm;
  final ValueListenable<double?> progress;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    String name(String key) => tapToPayNameFor(context, key);
    switch (vm.readerState) {
      case ReaderState.idle || ReaderState.needsReader:
        return const SizedBox.shrink();
      case ReaderState.permissions:
        return Text(
          context.tr('terminal_location_prealert_title'),
          style: Theme.of(context).textTheme.bodyMedium,
        );
      case ReaderState.turningOn:
        return Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('terminal_turning_on')),
              const SizedBox(height: InSpacing.sm),
              const LinearProgressIndicator(),
            ],
          ),
        );
      case ReaderState.connecting:
        return Semantics(
          liveRegion: true,
          child: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('terminal_tap_to_pay_initializing', {
                    'name': name('terminal_tap_to_pay_initializing'),
                  }),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: InSpacing.sm),
                LinearProgressIndicator(value: value),
                if (value != null) ...[
                  const SizedBox(height: InSpacing.xs),
                  LtrText('${(value * 100).round()}%'),
                ],
              ],
            ),
          ),
        );
      case ReaderState.ready:
        return Text(
          context.tr('terminal_tap_to_pay_ready_ios', {
            'name': name('terminal_tap_to_pay_ready_ios'),
          }),
        );
      case ReaderState.blocked:
        return Row(
          children: [
            Expanded(
              child: Text(
                context.tr('terminal_location_blocked_ios', {
                  'name': name('terminal_location_blocked_ios'),
                }),
              ),
            ),
            TextButton(
              onPressed: vm.openSettings,
              child: Text(context.tr('open_settings')),
            ),
          ],
        );
      case ReaderState.failed:
        final problem = vm.problem;
        return Row(
          children: [
            Expanded(
              child: Text(
                problem == null
                    ? context.tr('terminal_error_unknown')
                    : terminalProblemText(
                        problem,
                        context.tr,
                        name: name,
                        tapToPay: true,
                      ),
              ),
            ),
            if (problem?.code == TerminalErrorCode.locationServicesDisabled)
              TextButton(
                onPressed: vm.openSettings,
                child: Text(context.tr('open_settings')),
              )
            else
              TextButton(onPressed: onRetry, child: Text(context.tr('retry'))),
          ],
        );
    }
  }
}

class _TestModeBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: InSpacing.sm),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.inTheme.warningSoft,
          borderRadius: BorderRadius.circular(InRadii.r1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            context.tr('test_mode').toUpperCase(),
            style: TextStyle(
              color: context.inTheme.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}

class _Total extends StatelessWidget {
  const _Total({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: InSpacing.sm),
    child: Center(
      child: LtrText(
        text,
        style: Theme.of(context).textTheme.displaySmall,
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({
    required this.text,
    this.icon,
    this.leading,
    this.busy = false,
  });

  final String text;
  final IconData? icon;

  /// Drawn instead of [icon]: Apple's Tap to Pay on iPhone symbol.
  final Widget? leading;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      children: [
        SizedBox(height: InSpacing.md(context)),
        if (busy)
          const CircularProgressIndicator()
        else if (leading != null)
          leading!
        else if (icon != null)
          Icon(icon, size: 48),
        SizedBox(height: InSpacing.md(context)),
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _Buttons extends StatelessWidget {
  const _Buttons({
    required this.primary,
    required this.onPrimary,
    this.secondary,
    this.onSecondary,
    this.tonal = false,
  });

  final String primary;

  /// Null disables it (a reader reconnecting).
  final Future<void> Function()? onPrimary;
  final String? secondary;
  final Future<void> Function()? onSecondary;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    const size = Size(64, 44);
    final main = tonal
        ? FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: size),
            onPressed: onPrimary,
            child: Text(primary),
          )
        : FilledButton(
            style: FilledButton.styleFrom(minimumSize: size),
            onPressed: onPrimary,
            child: Text(primary),
          );
    final second = secondary;
    if (second == null) return main;
    // Side by side, the way out next to the way on (CLAUDE.md § Design
    // system (v2)).
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: onSecondary,
            child: Text(second),
          ),
        ),
        SizedBox(width: InSpacing.md(context)),
        Expanded(child: main),
      ],
    );
  }
}

/// A Bluetooth reader's prompt, in words.
String _readerMessageKey(TerminalDisplayMessage message) => switch (message) {
  TerminalDisplayMessage.retryCard => 'terminal_reader_retry_card',
  TerminalDisplayMessage.insertCard => 'terminal_reader_insert_card',
  TerminalDisplayMessage.insertOrSwipeCard =>
    'terminal_reader_insert_or_swipe_card',
  TerminalDisplayMessage.swipeCard => 'terminal_reader_swipe_card',
  TerminalDisplayMessage.removeCard => 'terminal_reader_remove_card',
  TerminalDisplayMessage.multipleContactlessCardsDetected =>
    'terminal_reader_multiple_cards',
  TerminalDisplayMessage.tryAnotherReadMethod =>
    'terminal_reader_try_another_read_method',
  TerminalDisplayMessage.tryAnotherCard => 'terminal_reader_try_another_card',
  TerminalDisplayMessage.cardRemovedTooEarly =>
    'terminal_reader_card_removed_too_early',
  TerminalDisplayMessage.checkMobileDevice =>
    'terminal_reader_check_mobile_device',
};
