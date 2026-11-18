import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/app/services.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/domain/terminal/online_gateways.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/terminal/how_to_tap.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_icon.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_setup.dart';
import 'package:admin/ui/features/terminal/terminal_error_text.dart';
import 'package:admin/ui/features/terminal/view_models/tap_to_pay_enable_view_model.dart';
import 'package:admin/ui/features/terminal/widgets/location_pre_alert.dart';
import 'package:admin/ui/features/terminal/widgets/collect_stage_layout.dart';
import 'package:admin/ui/core/fold_geometry.dart';

/// Opens [TapToPayEnableScreen] over everything: a full-screen step on the
/// root navigator, never part of the saved route (like the collect screen).
Future<void> showTapToPayEnableScreen(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const TapToPayEnableScreen(),
      ),
    );

/// Turning on Tap to Pay on iPhone outside checkout (App Review 3.6, 3.9):
/// from Device Settings, the setup checklist and the end of Stripe's
/// onboarding. It runs the collect button's steps — Card present, location,
/// Apple's terms, the education — then says it's ready. Close is quiet:
/// setup carries on in the controller.
class TapToPayEnableScreen extends StatefulWidget {
  const TapToPayEnableScreen({
    super.key,
    @visibleForTesting this.viewModel,
    @visibleForTesting this.canPayOnline,
  });

  /// Tests answer whether the company's invoices can be paid online.
  final Future<bool?> Function()? canPayOnline;

  /// Tests drive the screen with their own view model.
  final TapToPayEnableViewModel? viewModel;

  @override
  State<TapToPayEnableScreen> createState() => _TapToPayEnableScreenState();
}

class _TapToPayEnableScreenState extends State<TapToPayEnableScreen> {
  late final TapToPayEnableViewModel _vm;
  late final VoidCallback _unlisten;
  late final VoidCallback _releaseWarmUp;
  late final AppLifecycleListener _lifecycle;

  /// Apple's terms were accepted while this screen connected.
  bool _termsAccepted = false;

  @override
  void initState() {
    super.initState();
    final services = context.read<Services>();
    final company = services.auth.session.value?.currentCompany;
    final companyId = services.auth.session.value?.currentCompanyId ?? '';
    _vm =
        (widget.viewModel ??
              TapToPayEnableViewModel(
                companyId: companyId,
                companyName: company?.name ?? '',
                isAdmin:
                    (company?.isAdmin ?? false) || (company?.isOwner ?? false),
                merchantDisplayName: company?.name ?? '',
                terminal: services.terminal,
                enableCardPresent: (id) =>
                    enableCardPresent(services, companyId, id),
              ))
          ..askLocation = _askLocation
          ..onReady = _educate
          ..addListener(_onChanged);
    _unlisten = _vm.terminal.addEventListener(
      TerminalReaderEvents(onTermsAccepted: () => _termsAccepted = true),
    );
    // This screen gets the reader ready itself.
    _releaseWarmUp = _vm.terminal.holdWarmUp();
    _lifecycle = AppLifecycleListener(onResume: _vm.appResumed);
    unawaited(_vm.load());
  }

  void _onChanged() {
    if (!mounted) return;
    if (_vm.stage == TapToPayEnableStage.ready && !_onlineChecked) {
      _onlineChecked = true;
      unawaited(_checkOnline());
    }
    setState(() {});
  }

  /// Apple wants every merchant to have another way to be paid. Once ready,
  /// the company's gateways are read once from Drift: when no online payment
  /// type is on anywhere, the screen says so and points to the settings.
  bool _onlineChecked = false;
  bool _noOnline = false;

  Future<void> _checkOnline() async {
    // A test's own view model has no database behind it.
    final check =
        widget.canPayOnline ?? (widget.viewModel == null ? _readOnline : null);
    if (check == null) return;
    bool? payable;
    try {
      payable = await check();
    } catch (_) {}
    if (mounted && payable == false) setState(() => _noOnline = true);
  }

  Future<bool?> _readOnline() async {
    final services = context.read<Services>();
    final companyId = services.auth.session.value?.currentCompanyId ?? '';
    return canTakeOnlinePayments(
      await services.companyGateways
          .watchPage(companyId: companyId)
          .first
          .timeout(const Duration(seconds: 2)),
    );
  }

  void _openPaymentSettings() {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop();
    router?.go('/settings/company_gateways');
  }

  @override
  void dispose() {
    _unlisten();
    _releaseWarmUp();
    _lifecycle.dispose();
    _vm
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  Future<bool> _askLocation() async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      anchorPoint: foldAnchorPoint(context),
      builder: (_) => const LocationPreAlertDialog(),
    );
    return ok ?? false;
  }

  /// Apple's education once the terms sheet has gone (4.2): after the terms
  /// it waits for the app to be back in front, and a moment more.
  Future<void> _educate() async {
    if (_termsAccepted) {
      for (var i = 0; i < 150; i++) {
        final state = WidgetsBinding.instance.lifecycleState;
        if (state == null || state == AppLifecycleState.resumed) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    if (!mounted) return;
    final terminal = _vm.terminal;
    if (!_termsAccepted && !terminal.howToTapDue) return;
    final shown = await showHowToTap(
      context,
      accountCountry: _vm.accountCountry,
    );
    if (shown) await terminal.markHowToTapShown();
  }

  void _close() => Navigator.of(context).pop();

  void _openInvoices() {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop();
    router?.go('/invoices');
  }

  @override
  Widget build(BuildContext context) {
    final problem = _vm.problem;
    return ValueListenableBuilder<double?>(
      valueListenable: _vm.terminal.setupProgress,
      builder: (context, progress, _) => TapToPayEnableView(
        stage: _vm.stage,
        companyName: _vm.companyName,
        steps: _vm.steps,
        doneSteps: _vm.doneSteps,
        loading: _vm.loading,
        progress: progress,
        problem: problem == null
            ? null
            : terminalProblemText(
                problem,
                context.tr,
                name: (key) => tapToPayNameFor(context, key),
                tapToPay: true,
              ),
        onStart: _vm.start,
        onRetry: _vm.start,
        onDone: _close,
        onOpenInvoices: _openInvoices,
        onOpenPaymentSettings: _noOnline ? _openPaymentSettings : null,
        onOpenSettings: _vm.needsSettings
            ? () => unawaited(_vm.terminal.platform.openSettings())
            : null,
      ),
    );
  }
}

/// What [TapToPayEnableScreen] draws, from plain inputs.
class TapToPayEnableView extends StatelessWidget {
  const TapToPayEnableView({
    super.key,
    required this.stage,
    required this.companyName,
    this.steps = const {},
    this.doneSteps = const {},
    this.progress,
    this.problem,
    this.onStart,
    this.onRetry,
    this.onDone,
    this.onOpenInvoices,
    this.onOpenPaymentSettings,
    this.onOpenSettings,
    this.loading = false,
  });

  /// Only Settings fixes what stopped it: the primary action opens them.
  final VoidCallback? onOpenSettings;

  /// The intro is still finding out which steps are needed.
  final bool loading;

  final TapToPayEnableStage stage;

  /// The company it is being turned on for — the Stripe account's merchant.
  final String companyName;

  /// The steps still to run, in order (an admin with Card present on skips
  /// it; the education always runs).
  final Set<TapToPayEnableStep> steps;
  final Set<TapToPayEnableStep> doneSteps;

  /// 0–1 while the reader configures, null while it can't say.
  final double? progress;

  /// What stopped it, in words ([TapToPayEnableStage.failed]).
  final String? problem;

  final VoidCallback? onStart;
  final VoidCallback? onRetry;
  final VoidCallback? onDone;
  final VoidCallback? onOpenInvoices;

  /// Set when no online payment type is on for the company: Ready adds a
  /// row saying so, which opens the gateway settings.
  final VoidCallback? onOpenPaymentSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Scaffold(
      backgroundColor: tokens.surface,
      appBar: AppBar(
        backgroundColor: tokens.surface,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: context.tr('close'),
          onPressed: onDone,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            // The collect screen's own stage: a hero, what is left to do,
            // and the actions pinned at the bottom.
            child: CollectStageLayout(
              actions: _actions(context),
              children: _body(context),
            ),
          ),
        ),
      ),
    );
  }

  String _name(BuildContext context, String key) =>
      tapToPayNameFor(context, key);

  /// Apple's symbol in the stage's tile, tinted like any icon and never
  /// altered or badged (App Review: the symbol is used as Apple draws it).
  Widget _hero(StageTone tone, {required String title, String? message}) =>
      CollectStageHero(
        tone: tone,
        symbol: const TapToPayIcon(size: 40),
        headingLevel: 1,
        title: title,
        message: message,
      );

  List<Widget> _body(BuildContext context) {
    final tokens = context.inTheme;
    final text = Theme.of(context).textTheme;
    switch (stage) {
      case TapToPayEnableStage.intro:
        return [
          _hero(
            StageTone.accent,
            title: tapToPayName(context),
            message: context.tr('terminal_enable_intro', {
              'name': _name(context, 'terminal_enable_intro'),
              'company': companyName,
            }),
          ),
          const SizedBox(height: InSpacing.xl),
          if (loading)
            const Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (steps.isNotEmpty)
            _Steps(steps: steps, done: doneSteps),
        ];
      case TapToPayEnableStage.preparing:
        return [
          _hero(
            StageTone.accent,
            title: context.tr('terminal_tap_to_pay_initializing', {
              'name': _name(context, 'terminal_tap_to_pay_initializing'),
            }),
          ),
          const SizedBox(height: InSpacing.xl),
          Semantics(
            liveRegion: true,
            child: CollectCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StageProgress(value: progress),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('terminal_enable_first_time'),
                    style: text.bodyMedium?.copyWith(
                      color: tokens.ink2,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('terminal_enable_leave_note'),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(
              fontSize: 13,
              color: tokens.ink3,
              height: 1.4,
            ),
          ),
          // What is left, ticked off as it happens.
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Steps(steps: steps, done: doneSteps),
          ],
        ];
      case TapToPayEnableStage.failed:
        return [
          _hero(StageTone.accent, title: tapToPayName(context)),
          const SizedBox(height: InSpacing.xl),
          CollectNote(
            icon: Icons.error_outline,
            tone: StageTone.danger,
            text: problem ?? context.tr('terminal_error_unknown'),
          ),
          // A first load that failed knows no steps: no empty card.
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Steps(steps: steps, done: doneSteps),
          ],
        ];
      case TapToPayEnableStage.ready:
        return [
          _hero(
            StageTone.success,
            title: context.tr('terminal_enable_ready_title'),
            message: context.tr('terminal_enable_ready_body', {
              'name': _name(context, 'terminal_enable_ready_body'),
            }),
          ),
          if (onOpenPaymentSettings != null) ...[
            const SizedBox(height: InSpacing.xl),
            StageOptions(
              children: [
                StageOption(
                  icon: Icons.info_outline,
                  title: context.tr('terminal_payment_settings'),
                  subtitle: context.tr('terminal_no_online_gateway'),
                  onTap: onOpenPaymentSettings,
                ),
              ],
            ),
          ],
        ];
      case TapToPayEnableStage.askAdmin:
        return [
          _hero(
            StageTone.neutral,
            title: context.tr('terminal_error_terms_not_accepted', {
              'name': _name(context, 'terminal_error_terms_not_accepted'),
            }),
            message: context.tr('terminal_enable_ask_admin_body', {
              'name': _name(context, 'terminal_enable_ask_admin_body'),
              'company': companyName,
            }),
          ),
        ];
    }
  }

  List<Widget> _actions(BuildContext context) {
    switch (stage) {
      case TapToPayEnableStage.intro:
        // Apple 3.5: the clear action that leads to its terms.
        return [
          StageButton(
            onPressed: onStart,
            label: context.tr('terminal_enable_turn_on', {
              'name': _name(context, 'terminal_enable_turn_on'),
            }),
          ),
        ];
      case TapToPayEnableStage.preparing:
        // Closes quietly: setup carries on.
        return [
          StageButton(
            kind: StageButtonKind.outlined,
            onPressed: onDone,
            label: context.tr('close'),
          ),
        ];
      case TapToPayEnableStage.failed:
        return [
          StageButtonPair(
            secondary: StageButton(
              kind: StageButtonKind.outlined,
              onPressed: onDone,
              label: context.tr('close'),
            ),
            primary: StageButton(
              onPressed: onOpenSettings ?? onRetry,
              label: context.tr(
                onOpenSettings != null ? 'open_settings' : 'retry',
              ),
            ),
          ),
        ];
      case TapToPayEnableStage.ready:
        return [
          StageButtonPair(
            secondary: StageButton(
              kind: StageButtonKind.outlined,
              onPressed: onDone,
              label: context.tr('done'),
            ),
            primary: StageButton(
              onPressed: onOpenInvoices,
              label: context.tr('terminal_open_invoices'),
            ),
          ),
        ];
      case TapToPayEnableStage.askAdmin:
        return [StageButton(onPressed: onDone, label: context.tr('done'))];
    }
  }
}

/// The steps still needed, numbered, each ticked once done.
class _Steps extends StatelessWidget {
  const _Steps({required this.steps, required this.done});

  final Set<TapToPayEnableStep> steps;
  final Set<TapToPayEnableStep> done;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final ordered = [
      for (final s in TapToPayEnableStep.values)
        if (steps.contains(s)) s,
    ];
    return CollectCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final (i, step) in ordered.indexed) ...[
            if (i > 0) Divider(height: 1, color: tokens.border),
            _StepRow(
              number: i + 1,
              text: _text(context, step),
              done: done.contains(step),
            ),
          ],
        ],
      ),
    );
  }

  String _text(BuildContext context, TapToPayEnableStep step) {
    final key = switch (step) {
      TapToPayEnableStep.cardPresent => 'terminal_enable_step_card_present',
      TapToPayEnableStep.location => 'terminal_enable_step_location',
      TapToPayEnableStep.terms => 'terminal_enable_step_terms',
      TapToPayEnableStep.learn => 'terminal_enable_step_learn',
    };
    return context.tr(key, {'name': tapToPayNameFor(context, key)});
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.text,
    required this.done,
  });

  final int number;
  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final type = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Semantics(
        checked: done,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? tokens.paidSoft : tokens.accentSoft,
                  borderRadius: BorderRadius.circular(InRadii.r2),
                ),
                child: done
                    ? Icon(Icons.check_rounded, size: 18, color: tokens.paid)
                    : LtrText(
                        '$number',
                        style: type.labelLarge?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tokens.accentInk,
                          fontFeatures: stageFigures,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: type.bodyLarge?.copyWith(
                    fontSize: 15,
                    height: 1.35,
                    color: done ? tokens.ink3 : tokens.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
