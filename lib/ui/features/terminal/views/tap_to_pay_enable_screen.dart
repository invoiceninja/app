import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:store_services/store_services.dart';

import 'package:admin/app/services.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/l10n/tap_to_pay_names.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/features/terminal/how_to_tap.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_icon.dart';
import 'package:admin/ui/features/terminal/tap_to_pay_setup.dart';
import 'package:admin/ui/features/terminal/terminal_error_text.dart';
import 'package:admin/ui/features/terminal/view_models/tap_to_pay_enable_view_model.dart';
import 'package:admin/ui/features/terminal/widgets/location_pre_alert.dart';

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
  const TapToPayEnableScreen({super.key, @visibleForTesting this.viewModel});

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
    if (mounted) setState(() {});
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: InSpacing.lg(context),
                      vertical: InSpacing.sm,
                    ),
                    children: [
                      _Hero(stage: stage),
                      const SizedBox(height: InSpacing.xl),
                      ..._body(context),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    InSpacing.lg(context),
                    InSpacing.sm,
                    InSpacing.lg(context),
                    InSpacing.lg(context),
                  ),
                  child: _actions(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _name(BuildContext context, String key) =>
      tapToPayNameFor(context, key);

  List<Widget> _body(BuildContext context) {
    final tokens = context.inTheme;
    final title = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: tokens.ink,
    );
    final body = TextStyle(fontSize: 15, height: 1.45, color: tokens.ink2);
    final note = TextStyle(fontSize: 13, height: 1.4, color: tokens.ink3);
    Widget heading(String text) => Semantics(
      header: true,
      headingLevel: 1,
      child: Text(text, textAlign: TextAlign.center, style: title),
    );
    switch (stage) {
      case TapToPayEnableStage.intro:
        return [
          heading(tapToPayName(context)),
          const SizedBox(height: InSpacing.sm),
          Text(
            context.tr('terminal_enable_intro', {
              'name': _name(context, 'terminal_enable_intro'),
              'company': companyName,
            }),
            textAlign: TextAlign.center,
            style: body,
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
          heading(
            context.tr('terminal_tap_to_pay_initializing', {
              'name': _name(context, 'terminal_tap_to_pay_initializing'),
            }),
          ),
          const SizedBox(height: InSpacing.xl),
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(InRadii.r1),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: tokens.border,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(height: InSpacing.sm),
                if (progress != null)
                  Center(
                    child: LtrText(
                      '${(progress! * 100).round()}%',
                      style: TextStyle(fontSize: 13, color: tokens.ink3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: InSpacing.xl),
          Text(
            context.tr('terminal_enable_first_time'),
            textAlign: TextAlign.center,
            style: body,
          ),
          const SizedBox(height: InSpacing.sm),
          Text(
            context.tr('terminal_enable_leave_note'),
            textAlign: TextAlign.center,
            style: note,
          ),
        ];
      case TapToPayEnableStage.failed:
        return [
          heading(tapToPayName(context)),
          const SizedBox(height: InSpacing.xl),
          _Notice(
            icon: Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
            background: tokens.overdueSoft,
            text: problem ?? context.tr('terminal_error_unknown'),
          ),
          // A first load that failed knows no steps: no empty card.
          if (steps.isNotEmpty) ...[
            SizedBox(height: InSpacing.md(context)),
            _Steps(steps: steps, done: doneSteps),
          ],
        ];
      case TapToPayEnableStage.ready:
        return [
          heading(context.tr('terminal_enable_ready_title')),
          const SizedBox(height: InSpacing.sm),
          Text(
            context.tr('terminal_enable_ready_body', {
              'name': _name(context, 'terminal_enable_ready_body'),
            }),
            textAlign: TextAlign.center,
            style: body,
          ),
        ];
      case TapToPayEnableStage.askAdmin:
        return [
          heading(
            context.tr('terminal_error_terms_not_accepted', {
              'name': _name(context, 'terminal_error_terms_not_accepted'),
            }),
          ),
          const SizedBox(height: InSpacing.sm),
          Text(
            context.tr('terminal_enable_ask_admin_body', {
              'name': _name(context, 'terminal_enable_ask_admin_body'),
              'company': companyName,
            }),
            textAlign: TextAlign.center,
            style: body,
          ),
        ];
    }
  }

  Widget _actions(BuildContext context) {
    const size = Size(64, 44);
    switch (stage) {
      case TapToPayEnableStage.intro:
        // Apple 3.5: the clear action that leads to its terms.
        return FilledButton(
          style: FilledButton.styleFrom(minimumSize: size),
          onPressed: onStart,
          child: Text(
            context.tr('terminal_enable_turn_on', {
              'name': _name(context, 'terminal_enable_turn_on'),
            }),
          ),
        );
      case TapToPayEnableStage.preparing:
        // Closes quietly: setup carries on.
        return OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: onDone,
          child: Text(context.tr('close')),
        );
      case TapToPayEnableStage.failed:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(64, 44),
                ),
                onPressed: onDone,
                child: Text(context.tr('close')),
              ),
            ),
            SizedBox(width: InSpacing.md(context)),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: size),
                onPressed: onOpenSettings ?? onRetry,
                child: Text(
                  context.tr(
                    onOpenSettings != null ? 'open_settings' : 'retry',
                  ),
                ),
              ),
            ),
          ],
        );
      case TapToPayEnableStage.ready:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(64, 44),
                ),
                onPressed: onDone,
                child: Text(context.tr('done')),
              ),
            ),
            SizedBox(width: InSpacing.md(context)),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: size),
                onPressed: onOpenInvoices,
                child: Text(context.tr('terminal_open_invoices')),
              ),
            ),
          ],
        );
      case TapToPayEnableStage.askAdmin:
        return FilledButton(
          style: FilledButton.styleFrom(minimumSize: size),
          onPressed: onDone,
          child: Text(context.tr('done')),
        );
    }
  }
}

/// Apple's symbol in a soft tile, never altered or badged (App Review:
/// the symbol is used as Apple draws it) — green once it's ready.
class _Hero extends StatelessWidget {
  const _Hero({required this.stage});

  final TapToPayEnableStage stage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final ready = stage == TapToPayEnableStage.ready;
    return Center(
      child: Container(
        width: 112,
        height: 112,
        decoration: BoxDecoration(
          color: ready ? tokens.paidSoft : tokens.accentSoft,
          borderRadius: BorderRadius.circular(InRadii.r3 * 2),
        ),
        alignment: Alignment.center,
        child: TapToPayIcon(
          size: 64,
          color: ready ? tokens.paid : tokens.accent,
        ),
      ),
    );
  }
}

/// The steps, numbered, each ticked once done.
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(InRadii.r3),
        border: Border.all(color: tokens.border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: InSpacing.lg(context),
          vertical: InSpacing.sm,
        ),
        child: Column(
          children: [
            for (final (i, step) in ordered.indexed)
              _StepRow(
                number: i + 1,
                text: _text(context, step),
                done: done.contains(step),
              ),
          ],
        ),
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
    return MergeSemantics(
      child: Semantics(
        checked: done,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: InSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? tokens.paid : tokens.surfaceAlt,
                  borderRadius: BorderRadius.circular(InRadii.r1),
                  border: done ? null : Border.all(color: tokens.border),
                ),
                child: done
                    ? Icon(Icons.check, size: 18, color: tokens.surface)
                    : LtrText(
                        '$number',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tokens.ink2,
                        ),
                      ),
              ),
              SizedBox(width: InSpacing.md(context)),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 15,
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

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.background,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(InRadii.r2),
      ),
      child: Padding(
        padding: EdgeInsets.all(InSpacing.md(context)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: InSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: context.inTheme.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
