import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/client.dart';
import 'package:admin/data/models/domain/invoice.dart';
import 'package:admin/data/services/terminal_server_error.dart';
import 'package:admin/domain/terminal/online_gateways.dart';
import 'package:admin/domain/terminal/terminal_eligibility.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/detail/copy_entity_link.dart';
import 'package:admin/ui/core/dialogs/confirm_action_dialog.dart';
import 'package:admin/ui/core/utils/haptics.dart';
import 'package:admin/ui/core/widgets/copyable_value.dart';
import 'package:admin/ui/core/widgets/form_save_scope.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/core/widgets/primary_dialog_action.dart';
import 'package:admin/ui/core/widgets/qr_code_image.dart';
import 'package:admin/ui/features/terminal/how_to_tap.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_icon.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_setup.dart';
import 'package:admin/ui/features/terminal/terminal_error_text.dart';
import 'package:admin/ui/features/terminal/view_models/collect_card_payment_view_model.dart';
import 'package:admin/ui/features/terminal/widgets/collect_stage_layout.dart';
import 'package:admin/ui/features/terminal/widgets/location_pre_alert.dart';
import 'package:admin/ui/features/terminal/widgets/pay_another_way.dart';
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
  EnterPaymentByHand? enterPayment,
}) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => CollectCardPaymentScreen(
      companyId: companyId,
      invoice: invoice,
      client: client,
      groupCurrencyId: groupCurrencyId,
      enterPayment: enterPayment,
      // The invoice's action is Apple's button on an iPhone (5.3).
      pressOnOpen: true,
    ),
  ),
);

/// The invoice's own Enter Payment, for "Pay another way" on an invoice
/// that can't be paid online: called once this screen has closed, with the
/// context under it and the invoice as it stands.
typedef EnterPaymentByHand =
    Future<void> Function(BuildContext context, Invoice invoice);

class CollectCardPaymentScreen extends StatefulWidget {
  const CollectCardPaymentScreen({
    super.key,
    required this.companyId,
    required this.invoice,
    this.client,
    this.groupCurrencyId = '',
    this.pressOnOpen = false,
    this.enterPayment,
    @visibleForTesting this.viewModel,
  });

  /// Opens the payment editor for this invoice (the invoice's Enter Payment
  /// action). Without one the fallback's Enter Payment is disabled.
  final EnterPaymentByHand? enterPayment;

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
                refetchInvoice: _refetchInvoice,
                pressOnOpen: widget.pressOnOpen,
              ))
          ..addListener(_onChanged)
          ..askLocation = _askLocation
          ..onReady = _onReady;
    _amount = TextEditingController(text: _moneyInput(_vm.amount));
    _shownAmount = _vm.amount;
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

  /// An admin's press with Card present off turns it on
  /// (`enableCardPresent`).
  Future<void> _enableCardPresent(String companyGatewayId) =>
      enableCardPresent(_services, widget.companyId, companyGatewayId);

  /// The amount the field was last made to show.
  Decimal? _shownAmount;

  void _onChanged() {
    if (!mounted) return;
    _syncPrecision();
    // The amount changed outside the field (an invoice that changed while
    // the customer paid another way): the field shows what will be taken.
    if (_vm.amount != _shownAmount) {
      _shownAmount = _vm.amount;
      final shown = _moneyInput(_vm.amount);
      if (_vm.stage == CollectStage.configure && _amount.text != shown) {
        _amount.text = shown;
      }
    }
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
    final shown = await showHowToTap(
      context,
      accountCountry: _vm.gateway?.accountCountry ?? '',
    );
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
    _declineEmail.dispose();
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
      builder: (_) => const LocationPreAlertDialog(),
    );
    return ok ?? false;
  }

  /// The invoice as the server has it now: fetched into Drift, then read
  /// from it — for a collection started again after "Pay another way".
  Future<Invoice?> _refetchInvoice() async {
    await _services.terminal.repository.refreshInvoice(
      widget.companyId,
      _vm.invoice.id,
    );
    return _services.invoices
        .watch(companyId: widget.companyId, id: _vm.invoice.id)
        .first
        .timeout(const Duration(seconds: 2));
  }

  /// Whether the portal could take the payment (`canTakeOnlinePayments`),
  /// read from Drift once as "Pay another way" opens: bundled on login and
  /// `/refresh`, so no request; a one-shot read, not a live watch, so the
  /// screen holds no Drift stream. Null when it couldn't be read, which
  /// counts as able: the portal says so itself if it can't take a payment.
  bool? _payableOnline;

  /// "Pay another way": the customer pays the invoice online instead
  /// (App Review 4.8). The view model decides whether it may show.
  Future<void> _openPayAnotherWay() async {
    bool? payable;
    try {
      payable = canTakeOnlinePayments(
        await _services.companyGateways
            .watchPage(companyId: widget.companyId)
            .first
            .timeout(const Duration(seconds: 2)),
      );
    } catch (_) {}
    if (!mounted) return;
    _payableOnline = payable;
    _vm.payAnotherWay();
  }

  /// The invoice's own payment link (the client portal), or '' when there
  /// is none to offer: no invitation link, or every online payment type is
  /// switched off (the Stripe gateway taking cards in person only).
  String get _paymentLink {
    if (_payableOnline == false) return '';
    return _vm.invoice.invitations
            .map((i) => i.link)
            .where((l) => l.isNotEmpty)
            .firstOrNull ??
        '';
  }

  Future<void> _shareLink(String link, String label) async {
    if (link.isEmpty) return;
    await shareOrCopyLink(context, link, label: label);
  }

  /// Enter Payment, where the invoice can't be paid online: once the
  /// fallback's cancel has found no charge, this screen closes and the
  /// invoice's own Enter Payment takes over (its checks included).
  Future<void> _enterPayment() async {
    final enter = widget.enterPayment;
    // One press, one payment editor: a second while the first waits on the
    // cancel would open it twice, and pop a route too many.
    if (enter == null || _enteringPayment) return;
    final navigator = Navigator.of(context);
    setState(() => _enteringPayment = true);
    final bool settled;
    try {
      settled = await _vm.settledWithoutCharge();
    } finally {
      if (mounted) setState(() => _enteringPayment = false);
    }
    if (!mounted) return;
    if (!settled) {
      // A charge turned up (its answer has the screen), or nobody knows yet
      // whether the cancel went through: no payment by hand over that.
      if (_vm.stage == CollectStage.cancelled) {
        Notify.warning(context, context.tr('terminal_cancel_unconfirmed'));
      }
      return;
    }
    // Still held: the screen is leaving, and no press may run it again.
    _enteringPayment = true;
    final invoice = _vm.invoice;
    navigator.pop();
    final under = navigator.context;
    if (under.mounted) await enter(under, invoice);
  }

  /// Enter Payment is waiting on the cancel, or has handed over.
  bool _enteringPayment = false;

  /// The decline receipt's email and whether its field is open: kept here,
  /// so what was typed on the declined stage is still there on the fallback.
  late final TextEditingController _declineEmail = TextEditingController(
    text: _vm.clientEmail,
  );
  bool _declineOpen = false;

  /// "Send decline receipt", on the declined stage and on the fallback.
  Widget? _declineReceipt(BuildContext context) {
    if (!_vm.declineReceiptAvailable) return null;
    final problem = _vm.declineReceiptProblem;
    return DeclineReceiptForm(
      controller: _declineEmail,
      open: _declineOpen,
      onOpen: () => setState(() => _declineOpen = true),
      initialEmail: _vm.clientEmail,
      state: _vm.declineReceipt,
      errorText: problem == null
          ? ''
          : terminalProblemText(
              problem,
              context.tr,
              name: (key) => tapToPayNameFor(context, key),
              tapToPay: _vm.tapToPayOnIPhone,
            ),
      onSend: _vm.sendDeclineReceipt,
    );
  }

  Widget _payAnotherWayBody(BuildContext context) {
    final tapToPay =
        _vm.tapToPayOnIPhone ||
        _vm.readerChoice == TerminalReaderChoice.tapToPay;
    final link = _paymentLink;
    return PayAnotherWayView(
      link: link,
      subtitle: _invoiceContext(context),
      backLabel: tapToPay
          ? context.tr('terminal_back_to_tap', {
              'name': tapToPayNameFor(context, 'terminal_back_to_tap'),
            })
          : context.tr('terminal_back_to_card_reader'),
      receipt: _declineReceipt(context),
      onShare: () => _shareLink(link, context.tr('payment_link')),
      onDone: _close,
      onBack: _vm.backToReader,
      onEnterPayment: widget.enterPayment == null ? null : _enterPayment,
      enteringPayment: _enteringPayment,
    );
  }

  /// Pay another way, and the decline receipt when a charge was declined:
  /// the rows under a declined card, or a cancelled payment.
  List<Widget> _fallbackOptions(BuildContext context) => [
    const SizedBox(height: InSpacing.xl),
    StageOptions(
      children: [
        StageOption(
          accent: true,
          icon: Icons.qr_code_2,
          title: context.tr('terminal_pay_another_way'),
          subtitle: context.tr('terminal_pay_another_way_hint'),
          onTap: _openPayAnotherWay,
        ),
        ?_declineReceipt(context),
      ],
    ),
  ];

  /// The client's name, when known here.
  String get _clientName => _client?.displayName ?? '';

  /// "Invoice 0042 · Client".
  String _invoiceContext(BuildContext context) => [
    if (_vm.invoice.number.isNotEmpty)
      context.tr('terminal_for_invoice', {'number': _vm.invoice.number}),
    if (_clientName.isNotEmpty) _clientName,
  ].join(' · ');

  /// The rows every outcome starts its details with: which invoice, whose.
  List<Widget> _invoiceRows(BuildContext context) => [
    if (_vm.invoice.number.isNotEmpty)
      CollectDetailRow(label: context.tr('invoice'), value: _vm.invoice.number),
    if (_clientName.isNotEmpty)
      CollectDetailRow(
        label: context.tr('client'),
        value: _clientName,
        isName: true,
      ),
  ];

  /// The payment to quote to support (copyable), when there is one.
  List<Widget> _referenceRows(BuildContext context) {
    final reference = _vm.paymentReference;
    if (reference == null) return const [];
    return [
      CollectDetailRow(
        label: context.tr('reference'),
        value: reference,
        wrap: (value) =>
            CopyableValue(value: reference, fillWidth: false, child: value),
      ),
    ];
  }

  /// The details card, or nothing when there are no rows.
  List<Widget> _details(BuildContext context, List<Widget> rows) => [
    if (rows.isNotEmpty) ...[
      const SizedBox(height: InSpacing.xl),
      CollectDetails(rows: rows),
    ],
  ];

  /// The one rule that matters once a card may have been charged.
  Widget _dontRecordByHand(BuildContext context) => CollectNote(
    text: context.tr('terminal_dont_record_by_hand'),
    tone: StageTone.warning,
  );

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
          backgroundColor: theme.surface,
          titleSpacing: 0,
          title: Text(
            context.tr('collect_card_payment'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: context.tr('close'),
            onPressed: _vm.locked ? null : _close,
          ),
          actions: [
            if (!_vm.livemode)
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 8, end: 16),
                child: Center(child: _TestModeBadge()),
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _body(context),
            ),
          ),
        ),
      ),
    );
  }

  /// A stage that is only waiting on something: its spinner and words.
  Widget _busy(String title, {String? amount, String? message}) =>
      CollectStageLayout(
        children: [
          CollectStageHero(
            tone: StageTone.accent,
            busy: true,
            title: title,
            amount: amount,
            message: message,
          ),
        ],
      );

  /// The screen's single way out of a finished stage.
  StageButton _closeButton(
    BuildContext context, {
    StageButtonKind kind = StageButtonKind.primary,
  }) => StageButton(
    kind: kind,
    label: context.tr('close'),
    onPressed: () => Navigator.of(context).pop(),
  );

  Widget _body(BuildContext context) {
    // Back from "Pay another way": the invoice, then the figures, again.
    if (_vm.restarting) return _busy(context.tr('terminal_preparing'));
    // Only ever over declined or cancelled (the view model's rule).
    if (_vm.payingAnotherWay) return _payAnotherWayBody(context);
    return _stageBody(context);
  }

  Widget _stageBody(BuildContext context) => switch (_vm.stage) {
    CollectStage.configure => _configure(context),
    CollectStage.creating => _busy(context.tr('terminal_preparing')),
    CollectStage.openCollection => CollectStageLayout(
      actions: [
        StageButtonPair(
          secondary: _closeButton(context, kind: StageButtonKind.outlined),
          primary: StageButton(
            label: context.tr('terminal_cancel_open'),
            onPressed: _cancelOpenCollection,
          ),
        ),
      ],
      children: [
        CollectStageHero(
          tone: StageTone.warning,
          icon: Icons.sync_problem_outlined,
          message: _problemText(context),
        ),
        ..._details(context, _invoiceRows(context)),
      ],
    ),
    CollectStage.waiting => _waiting(context),
    CollectStage.finalizing => _busy(
      context.tr('terminal_checking_card'),
      amount: _totalText(),
    ),
    CollectStage.surchargeNotice => CollectStageLayout(
      actions: [
        StageButtonPair(
          secondary: StageButton(
            kind: StageButtonKind.outlined,
            label: context.tr('cancel'),
            onPressed: _vm.cancel,
          ),
          primary: StageButton(
            label: context.tr('continue'),
            onPressed: () async => _vm.continueWithSurcharge(),
          ),
        ),
      ],
      children: [
        CollectStageHero(
          tone: StageTone.accent,
          icon: Icons.credit_card_outlined,
          amount: _totalText(),
          message: context.tr('terminal_surcharge_notice', {
            'total': _totalText(),
            'surcharge': _money(_vm.finalized?.surcharge),
          }),
        ),
      ],
    ),
    CollectStage.settling => _busy(context.tr('terminal_settling')),
    CollectStage.processing => _busy(
      context.tr('terminal_processing'),
      amount: _totalText(),
    ),
    CollectStage.declined => _declined(context),
    CollectStage.approved => _approved(context),
    CollectStage.recording => _pending(
      context,
      context.tr('terminal_recording'),
    ),
    CollectStage.checking => _pending(
      context,
      context.tr('terminal_checking_help'),
      extra: Center(
        child: TextButton(
          onPressed: _vm.cancelUnconfirmed,
          child: Text(context.tr('terminal_cancel_payment')),
        ),
      ),
    ),
    // Charged: never a fallback or a decline receipt here — the card was
    // taken, and only support can settle it.
    CollectStage.unrecorded => CollectStageLayout(
      actions: [_closeButton(context)],
      children: [
        CollectStageHero(
          tone: StageTone.warning,
          icon: Icons.report_outlined,
          title: context.tr('terminal_unrecorded_title'),
          amount: _vm.finalized == null ? null : _totalText(),
          message: context.tr('terminal_unrecorded'),
        ),
        ..._details(context, [
          ..._invoiceRows(context),
          ..._referenceRows(context),
        ]),
        const SizedBox(height: 16),
        _dontRecordByHand(context),
      ],
    ),
    CollectStage.cancelled => CollectStageLayout(
      actions: [_closeButton(context)],
      children: [
        CollectStageHero(
          icon: Icons.block_outlined,
          title: context.tr('terminal_cancelled'),
          message: _vm.problem == null ? null : _problemText(context),
        ),
        ..._details(context, _invoiceRows(context)),
        // Not charged: the customer can still pay another way — unless the
        // invoice turned out to be paid already.
        if (_vm.problem?.serverCode != TerminalServerError.alreadyPaid)
          ..._fallbackOptions(context),
      ],
    ),
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

  /// What is owed on the invoice: its deposit while one is due, else its
  /// balance (a draft's amount).
  String _dueLine(BuildContext context) {
    final invoice = _vm.invoice;
    final deposit =
        invoice.partial > Decimal.zero &&
        invoice.partial < invoice.balanceOrAmount;
    return '${context.tr(deposit ? 'partial_due' : 'balance_due')} '
        '${_money(deposit ? invoice.partial : invoice.balanceOrAmount)}';
  }

  /// The checkout: the amount is the hero — large, centred, edited where it
  /// stands — with which invoice above it, what the customer pays and where
  /// the reader stands below, and the one button pinned at the bottom.
  Widget _configure(BuildContext context) {
    final quote = _vm.quote;
    final surcharged =
        _vm.applySurcharge && quote != null && quote.feeGross > Decimal.zero;
    final text = Theme.of(context).textTheme;
    final tokens = context.inTheme;
    final quiet = text.bodySmall?.copyWith(
      fontSize: 13,
      color: tokens.ink3,
      height: 1.4,
    );
    final underline = UnderlineInputBorder(
      borderSide: BorderSide(color: tokens.borderStrong, width: 1.5),
    );
    // Tap to Pay on iPhone says nothing until a press asks for something.
    final Widget? status = _vm.tapToPayOnIPhone
        ? (_vm.readerState == ReaderState.idle ||
                  _vm.readerState == ReaderState.needsReader
              ? null
              // Its own progress, from the same events (3.9.1).
              : _TapToPayRow(
                  vm: _vm,
                  progress: _vm.terminal.setupProgress,
                  onRetry: _pressTapToPay,
                ))
        : _updateProgress != null
        ? Semantics(
            liveRegion: true,
            child: _StatusCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StatusLine(
                    tone: StageTone.accent,
                    text: context.tr(
                      isIPhonePlatform()
                          ? 'terminal_reader_updating_ios'
                          : 'terminal_reader_updating',
                      {'percent': '${(_updateProgress! * 100).round()}'},
                    ),
                  ),
                  const SizedBox(height: InSpacing.sm),
                  StageProgress(value: _updateProgress),
                ],
              ),
            ),
          )
        : _ReaderRow(vm: _vm, onPickReader: _pickReader);
    return CollectStageLayout(
      actions: [
        if (_vm.tapToPayOnIPhone)
          // Apple's button: its name and symbol, never greyed out, pinned
          // where it is on screen whatever the form holds — the screen's
          // first choice (App Review 5.1–5.5). A press does what is missing,
          // then the next one takes the card.
          StageButton(
            onPressed: _pressTapToPay,
            icon: const TapToPayIcon(size: 24),
            label: tapToPayName(context),
          )
        else
          StageButton(
            onPressed: _vm.canCollect ? _collect : null,
            label: quote == null
                ? context.tr('collect_card_payment')
                : context.tr('terminal_collect_amount', {
                    'amount': _money(quote.total),
                  }),
          ),
      ],
      children: [
        LtrText(
          _invoiceContext(context),
          keepRtlScript: true,
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: tokens.ink,
          ),
        ),
        const SizedBox(height: 2),
        LtrText(_dueLine(context), textAlign: TextAlign.center, style: quiet),
        const SizedBox(height: InSpacing.xl),
        Text(
          context.tr('amount').toUpperCase(),
          textAlign: TextAlign.center,
          style: text.labelSmall?.copyWith(
            color: tokens.ink3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 168),
            child: IntrinsicWidth(
              child: FormSaveScope(
                onSubmit: _setAmount,
                child: Focus(
                  onFocusChange: (focused) {
                    if (!focused) _setAmount();
                  },
                  child: Semantics(
                    label: context.tr('amount'),
                    child: TextField(
                      controller: _amount,
                      textAlign: TextAlign.center,
                      // A figure reads left-to-right in every language.
                      textDirection: TextDirection.ltr,
                      cursorColor: tokens.accent,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        border: underline,
                        enabledBorder: underline,
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: tokens.accent,
                            width: 2,
                          ),
                        ),
                      ),
                      style: text.displayMedium?.copyWith(
                        fontSize: 48,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.5,
                        height: 1.15,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      // No press held, or under way, charges what was there
                      // before this edit: a fresh press commits it first.
                      onChanged: (_) => _vm.amountEdited(),
                      onSubmitted: (_) => _setAmount(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // What the customer pays: one quiet line while it is the amount
        // above, a breakdown once a surcharge makes it differ.
        if (quote != null)
          Semantics(
            liveRegion: true,
            child: Text(
              surcharged
                  ? context.tr('terminal_customer_pays_surcharge', {
                      'total': _money(quote.total),
                      'amount': _money(quote.amount),
                    })
                  : context.tr('terminal_customer_pays', {
                      'total': _money(quote.total),
                    }),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                fontSize: 15,
                color: tokens.ink2,
              ),
            ),
          )
        else if (_vm.quoting || _vm.starting)
          const Center(
            child: SizedBox(
              width: 120,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          )
        // Nothing to quote with until the press sets Card present or Stripe
        // up (iPhone).
        else if (!(_vm.cardPresentOff || _vm.needsStripe))
          Center(
            child: TextButton(
              onPressed: _vm.retry,
              child: Text(context.tr('retry')),
            ),
          ),
        if (_vm.invoiceChanged || _vm.invoiceUnchecked) ...[
          const SizedBox(height: 12),
          CollectNote(
            tone: StageTone.warning,
            text: context.tr(
              _vm.invoiceChanged
                  ? 'terminal_invoice_changed'
                  : 'terminal_invoice_unchecked',
            ),
          ),
        ],
        if (_vm.invoice.isDraft) ...[
          const SizedBox(height: InSpacing.sm),
          Text(
            context.tr('terminal_draft_marked_sent'),
            textAlign: TextAlign.center,
            style: quiet,
          ),
        ],
        if (_vm.surchargeUnavailable) ...[
          const SizedBox(height: InSpacing.sm),
          Text(
            context.tr('terminal_surcharge_unavailable_ttp', {
              'name': tapToPayNameFor(
                context,
                'terminal_surcharge_unavailable_ttp',
              ),
            }),
            textAlign: TextAlign.center,
            style: quiet,
          ),
        ],
        if (surcharged) ...[
          const SizedBox(height: 16),
          CollectDetails(
            rows: [
              CollectDetailRow(
                label: context.tr('amount'),
                value: _money(quote.amount),
              ),
              CollectDetailRow(
                label: context.tr('surcharge'),
                value: _money(quote.feeGross),
              ),
              CollectDetailRow(
                label: context.tr('total'),
                value: _money(quote.total),
                strong: true,
              ),
            ],
          ),
        ],
        if (_vm.surchargeNeedsAcknowledgement) ...[
          const SizedBox(height: InSpacing.sm),
          if (_vm.isAdmin)
            Center(
              child: TextButton(
                onPressed: _acknowledgeSurcharge,
                child: Text(context.tr('terminal_surcharge_set_up')),
              ),
            )
          else
            Text(
              context.tr('terminal_surcharge_ask_admin'),
              textAlign: TextAlign.center,
              style: quiet,
            ),
        ],
        if (_vm.surchargeOffered) ...[
          const SizedBox(height: 16),
          Material(
            color: tokens.surfaceAlt,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(InRadii.r3),
              side: BorderSide(color: tokens.border),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsetsDirectional.only(
                start: 16,
                end: 8,
              ),
              value: _vm.applySurcharge,
              onChanged: _vm.setSurcharge,
              title: Text(_surchargeLabel(context)),
              subtitle: Text(context.tr('terminal_surcharge_credit_only')),
            ),
          ),
        ],
        if (_vm.surchargeRefusal case final reason?) ...[
          const SizedBox(height: InSpacing.sm),
          Text(
            context.tr(switch (reason) {
              'region' => 'terminal_surcharge_refused_region',
              'adjust_fee_percent' => 'terminal_surcharge_refused_adjust',
              'over_cap' => 'terminal_surcharge_refused_cap',
              _ => 'terminal_surcharge_refused_invoice',
            }),
            textAlign: TextAlign.center,
            style: quiet,
          ),
        ],
        if (status != null) ...[const SizedBox(height: InSpacing.xl), status],
        if (_vm.problem != null && _vm.readerState != ReaderState.failed) ...[
          const SizedBox(height: 16),
          CollectNote(
            tone: StageTone.danger,
            icon: Icons.error_outline,
            text: _problemText(context),
          ),
        ],
      ],
    );
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

  Widget _waiting(BuildContext context) {
    final message = _readerMessage;
    final tapToPay = _vm.reader?.kind == TerminalReaderKind.tapToPay;
    final finalized = _vm.finalized;
    final again = _vm.readAgain && finalized != null;
    final iPhone = _vm.tapToPayOnIPhone;
    return CollectStageLayout(
      actions: [
        StageButton(
          kind: StageButtonKind.outlined,
          label: context.tr('cancel'),
          onPressed: _vm.cancel,
        ),
      ],
      children: [
        CollectStageHero(
          tone: StageTone.accent,
          // Apple's symbol on iOS, as drawn; never the Material contactless
          // icon there (App Review 5.5).
          symbol: iPhone ? const TapToPayIcon(size: 40) : null,
          icon: isIPhonePlatform()
              ? Icons.credit_card_outlined
              : Icons.contactless_outlined,
          title: again
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
          amount: _totalText(),
        ),
      ],
    );
  }

  /// After a decline: a calm outcome — the customer wasn't charged — then
  /// another card (primary, beside the way out), and the other ways on as
  /// rows no one has to hunt for: pay another way, a decline receipt.
  Widget _declined(BuildContext context) {
    final connecting = _vm.readerState == ReaderState.connecting;
    final cancel = StageButton(
      kind: StageButtonKind.outlined,
      label: context.tr('cancel'),
      // Stays on Cancelled, which says the card wasn't charged and
      // still offers the other ways on; its own Close leaves.
      onPressed: _vm.cancel,
    );
    final primary = connecting
        // Reconnecting a reader: nothing to try until it is back.
        ? StageButton(
            label: context.tr('terminal_reader_connecting'),
            onPressed: null,
          )
        // The reader went away mid-collection: connect one before trying.
        : _vm.readerState == ReaderState.needsReader
        ? StageButton(
            label: context.tr('terminal_connect_reader'),
            onPressed: _pickReader,
          )
        : StageButton(
            label: context.tr(switch (_vm.problem?.code) {
              TerminalErrorCode.declined ||
              TerminalErrorCode.cardNotRead ||
              TerminalErrorCode.pinUnavailable => 'terminal_try_another_card',
              _ => 'terminal_try_again',
            }),
            onPressed: _vm.tryAnotherCard,
          );
    return CollectStageLayout(
      actions: [StageButtonPair(secondary: cancel, primary: primary)],
      children: [
        CollectStageHero(
          tone: StageTone.danger,
          icon: Icons.credit_card_off_outlined,
          title: context.tr('terminal_declined_title'),
          amount: _totalText(),
          caption: _invoiceContext(context),
          // After a reader reconnected here there is no problem left to name.
          message: _vm.problem == null && _vm.readerState == ReaderState.ready
              ? context.tr('terminal_reader_ready', {
                  'reader': _vm.reader?.label ?? '',
                })
              : _problemText(context),
          footer: StageTag(
            tone: StageTone.success,
            text: context.tr('terminal_not_charged'),
          ),
        ),
        // The fallback and the decline receipt, for every reader (App Review
        // 4.8, 5.10).
        if (!connecting) ..._fallbackOptions(context),
      ],
    );
  }

  Widget _approved(BuildContext context) {
    final done = _vm.completion;
    final text = Theme.of(context).textTheme;
    final tokens = context.inTheme;
    // What the server recorded: after a refunded surcharge, or for another
    // attempt's payment, that is not what this screen quoted.
    final charged = done != null && done.isRecorded
        ? _money(done.applied + done.unapplied)
        : _money(_vm.finalized?.amount ?? _vm.quote?.total);
    final card = cardLabel(done?.brand ?? '', done?.last4 ?? '');
    final receiptUrl = done?.receiptUrl ?? '';
    final finish = StageButton(
      label: context.tr('done'),
      onPressed: () => Navigator.of(context).pop(),
    );
    return CollectStageLayout(
      actions: [
        // The receipt's link through the share sheet (App Review 5.10's
        // "Activity views"), beside Done.
        if (receiptUrl.isNotEmpty)
          StageButtonPair(
            even: true,
            secondary: StageButton(
              kind: StageButtonKind.outlined,
              label: context.tr('terminal_share_receipt'),
              icon: Icon(Icons.adaptive.share, size: 18),
              onPressed: () => _shareLink(receiptUrl, context.tr('receipt')),
            ),
            primary: finish,
          )
        else
          finish,
      ],
      children: [
        CollectStageHero(
          tone: StageTone.success,
          icon: Icons.check_rounded,
          title: context.tr('terminal_approved'),
          amount: charged,
          message: done?.status == 'unapplied'
              ? context.tr('terminal_unapplied', {
                  'amount': _money(done!.unapplied),
                })
              : done?.invoiceBalance != null
              ? context.tr('terminal_remaining_balance', {
                  'amount': _money(done!.invoiceBalance),
                })
              : null,
        ),
        ..._details(context, [
          ..._invoiceRows(context),
          if (card.isNotEmpty)
            CollectDetailRow(
              label: context.tr('terminal_card'),
              value: card,
              leading: Icon(
                Icons.credit_card_outlined,
                size: 18,
                color: tokens.ink3,
              ),
            ),
        ]),
        const SizedBox(height: InSpacing.xl),
        // The receipt: one row — the email and Send — never a form.
        if (_vm.receiptSent)
          Center(
            child: StatusLine(
              centered: true,
              tone: StageTone.success,
              text: context.tr('terminal_receipt_sent'),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
            child: Text(
              context.tr('terminal_send_receipt'),
              style: text.bodyMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tokens.ink2,
              ),
            ),
          ),
          ReceiptEmailRow(
            controller: _email,
            sending: _vm.sendingReceipt,
            onSend: _email.text.trim().isEmpty ? null : _sendReceipt,
          ),
          if (_vm.problem != null) ...[
            const SizedBox(height: InSpacing.sm),
            Text(
              _problemText(context),
              style: TextStyle(color: tokens.overdue),
            ),
          ],
          if (_email.text.trim().isEmpty && receiptUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              context.tr('terminal_scan_receipt'),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: tokens.ink2),
            ),
            const SizedBox(height: InSpacing.sm),
            Center(child: QrCodeImage(data: receiptUrl, size: 160)),
          ],
        ],
      ],
    );
  }

  Future<void> _sendReceipt() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    await _vm.sendReceipt(email);
  }

  /// Charged, or maybe: the figure, what is happening, the payment to quote
  /// to support, and Check again.
  Widget _pending(BuildContext context, String text, {Widget? extra}) {
    // Another attempt's payment: this screen's quote isn't its amount.
    final amount = _vm.settlingAnother ? null : _totalText();
    return CollectStageLayout(
      actions: [
        StageButtonPair(
          secondary: _closeButton(context, kind: StageButtonKind.outlined),
          primary: StageButton(
            label: context.tr('terminal_check_again'),
            onPressed: _vm.checkAgain,
          ),
        ),
      ],
      children: [
        CollectStageHero(
          tone: StageTone.warning,
          icon: Icons.hourglass_top_outlined,
          amount: amount,
          message: text,
        ),
        ..._details(context, [
          ..._invoiceRows(context),
          ..._referenceRows(context),
        ]),
        const SizedBox(height: 16),
        _dontRecordByHand(context),
        if (extra != null) ...[const SizedBox(height: InSpacing.sm), extra],
      ],
    );
  }
}

/// A status inside the checkout: a quiet card, so a row with an action or
/// a progress bar has edges.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CollectCard(padding: const EdgeInsets.all(12), child: child);
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
    final tone = switch (vm.readerState) {
      ReaderState.ready => StageTone.success,
      ReaderState.failed => StageTone.danger,
      ReaderState.blocked => StageTone.warning,
      ReaderState.needsReader || ReaderState.idle => StageTone.neutral,
      _ => StageTone.accent,
    };
    // Ready is one quiet line under the figures; anything with something to
    // do or to wait for gets a row with edges.
    if (vm.readerState == ReaderState.ready) {
      return Center(
        child: StatusLine(centered: true, tone: tone, text: text),
      );
    }
    return _StatusCard(
      child: StatusLine(
        tone: tone,
        text: text,
        trailing: busy
            ? const Padding(
                padding: EdgeInsetsDirectional.only(start: 8),
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : action,
      ),
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
        return Center(
          child: StatusLine(
            centered: true,
            tone: StageTone.accent,
            text: context.tr('terminal_location_prealert_title'),
          ),
        );
      case ReaderState.turningOn:
        return Semantics(
          liveRegion: true,
          child: _StatusCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatusLine(
                  tone: StageTone.accent,
                  text: context.tr('terminal_turning_on'),
                ),
                const SizedBox(height: InSpacing.sm),
                const StageProgress(value: null),
              ],
            ),
          ),
        );
      case ReaderState.connecting:
        return Semantics(
          liveRegion: true,
          child: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, _) => _StatusCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StatusLine(
                    tone: StageTone.accent,
                    text: context.tr('terminal_tap_to_pay_initializing', {
                      'name': name('terminal_tap_to_pay_initializing'),
                    }),
                  ),
                  const SizedBox(height: InSpacing.sm),
                  StageProgress(value: value),
                ],
              ),
            ),
          ),
        );
      case ReaderState.ready:
        return Center(
          child: StatusLine(
            centered: true,
            tone: StageTone.success,
            text: context.tr('terminal_tap_to_pay_ready_ios', {
              'name': name('terminal_tap_to_pay_ready_ios'),
            }),
          ),
        );
      case ReaderState.blocked:
        return _StatusCard(
          child: StatusLine(
            tone: StageTone.warning,
            text: context.tr('terminal_location_blocked_ios', {
              'name': name('terminal_location_blocked_ios'),
            }),
            trailing: TextButton(
              onPressed: vm.openSettings,
              child: Text(context.tr('open_settings')),
            ),
          ),
        );
      case ReaderState.failed:
        final problem = vm.problem;
        return _StatusCard(
          child: StatusLine(
            tone: StageTone.danger,
            text: problem == null
                ? context.tr('terminal_error_unknown')
                : terminalProblemText(
                    problem,
                    context.tr,
                    name: name,
                    tapToPay: true,
                  ),
            trailing:
                problem?.code == TerminalErrorCode.locationServicesDisabled
                ? TextButton(
                    onPressed: vm.openSettings,
                    child: Text(context.tr('open_settings')),
                  )
                : TextButton(
                    onPressed: onRetry,
                    child: Text(context.tr('retry')),
                  ),
          ),
        );
    }
  }
}

/// Test mode, as a small tag at the end of the app bar: always there, never
/// louder than the payment.
class _TestModeBadge extends StatelessWidget {
  const _TestModeBadge();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.inTheme.warningSoft,
      borderRadius: BorderRadius.circular(InRadii.r1),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(
        context.tr('test_mode').toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: context.inTheme.warning,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    ),
  );
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
