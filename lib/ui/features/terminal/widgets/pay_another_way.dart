import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/core/widgets/qr_code_image.dart';
import 'package:admin/ui/features/terminal/view_models/collect_card_payment_view_model.dart'
    show DeclineReceiptState;
import 'package:admin/ui/features/terminal/widgets/collect_stage_layout.dart';

/// "Pay another way" after a decline (App Review 4.8, the regional
/// fallback): the invoice's own payment link as a QR the customer scans to
/// pay online with another card or method, [Share link] [Done], and the way
/// back to the reader. With no link — or no online gateway — it says to
/// record a cash or other payment instead. Drawn from plain inputs: the view
/// model decides when it may show (docs/in-person-payments.md).
class PayAnotherWayView extends StatelessWidget {
  const PayAnotherWayView({
    super.key,
    required this.link,
    required this.backLabel,
    this.subtitle = '',
    this.receipt,
    this.onShare,
    this.onDone,
    this.onBack,
    this.onEnterPayment,
    this.enteringPayment = false,
  });

  /// Enter Payment was pressed and waits for the cancel's answer: busy, and
  /// not to be pressed again.
  final bool enteringPayment;

  /// The client portal's link to this invoice; '' when there is none to
  /// offer. The text names no amount: the portal pays the invoice (balance,
  /// deposit, its own fees), so a figure here could disagree with it.
  final String link;

  /// "Back to Tap to Pay on iPhone", or to the card reader.
  final String backLabel;

  /// Which invoice (and client) this is, under the heading.
  final String subtitle;

  /// The decline receipt, the last of the options.
  final Widget? receipt;

  final VoidCallback? onShare;
  final VoidCallback? onDone;
  final VoidCallback? onBack;
  final VoidCallback? onEnterPayment;

  @override
  Widget build(BuildContext context) {
    if (link.isEmpty) {
      return CollectStageLayout(
        actions: [
          StageButtonPair(
            secondary: StageButton(
              kind: StageButtonKind.outlined,
              label: context.tr('done'),
              onPressed: onDone,
            ),
            primary: StageButton(
              label: context.tr('enter_payment'),
              icon: enteringPayment
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.inTheme.ink3,
                      ),
                    )
                  : null,
              onPressed: enteringPayment ? null : onEnterPayment,
            ),
          ),
        ],
        children: [
          CollectStageHero(
            icon: Icons.payments_outlined,
            title: context.tr('terminal_pay_another_way'),
            caption: subtitle,
            message: context.tr('terminal_no_online_payment'),
          ),
          const SizedBox(height: InSpacing.xl),
          _options(context),
        ],
      );
    }
    final tokens = context.inTheme;
    final text = Theme.of(context).textTheme;
    // The code is the hero: as large as the screen allows, and never so
    // large on a small phone that the instruction leaves the screen.
    final screen = MediaQuery.sizeOf(context);
    final qr = (screen.height < 740 ? 168.0 : 216.0)
        .clamp(120.0, math.max(120.0, screen.width - 140))
        .toDouble();
    return CollectStageLayout(
      actions: [
        StageButtonPair(
          even: true,
          secondary: StageButton(
            kind: StageButtonKind.outlined,
            label: context.tr('terminal_share_link'),
            icon: Icon(Icons.adaptive.share, size: 18),
            onPressed: onShare,
          ),
          primary: StageButton(label: context.tr('done'), onPressed: onDone),
        ),
      ],
      children: [
        Semantics(
          header: true,
          headingLevel: 2,
          child: Text(
            context.tr('terminal_pay_another_way'),
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: InSpacing.xs),
          LtrText(
            subtitle,
            keepRtlScript: true,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: tokens.ink3),
          ),
        ],
        const SizedBox(height: 16),
        CollectCard(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            children: [
              // QrCodeImage draws its own white card, so it scans in either
              // theme.
              QrCodeImage(data: link, size: qr),
              const SizedBox(height: 12),
              Text(
                context.tr('terminal_pay_online_qr'),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  fontSize: 15,
                  color: tokens.ink2,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _options(context),
      ],
    );
  }

  /// The way back to the reader, its caution on the same row, then the
  /// decline receipt: one card of secondary options.
  Widget _options(BuildContext context) => StageOptions(
    children: [
      StageOption(
        icon: Icons.arrow_back,
        chevron: false,
        title: backLabel,
        subtitle: context.tr('terminal_back_to_reader_caution'),
        onTap: onBack,
      ),
      ?receipt,
    ],
  );
}

/// "Send decline receipt" (App Review 5.10): a quiet row of
/// [StageOptions], and the email field only once it is pressed. Where the
/// send stands is the view model's ([state]), so the row reads the same on
/// the declined stage and on "Pay another way".
class DeclineReceiptForm extends StatelessWidget {
  const DeclineReceiptForm({
    super.key,
    required this.state,
    required this.onSend,
    required this.controller,
    required this.open,
    required this.onOpen,
    this.initialEmail = '',
    this.errorText = '',
  });

  final DeclineReceiptState state;
  final ValueChanged<String> onSend;

  /// The screen's: the form is drawn in two places (the declined stage, the
  /// fallback), and what was typed in one is there in the other.
  final TextEditingController controller;

  /// The row was pressed: the field shows.
  final bool open;
  final VoidCallback onOpen;

  /// Shown under the row before it is pressed.
  final String initialEmail;

  /// Why it wasn't sent ([DeclineReceiptState.failed]).
  final String errorText;

  void _send() {
    final email = controller.text.trim();
    if (email.isNotEmpty) onSend(email);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    switch (state) {
      case DeclineReceiptState.sent:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: StatusLine(
            tone: StageTone.success,
            text: context.tr('terminal_decline_receipt_sent'),
          ),
        );
      case DeclineReceiptState.limit:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: StatusLine(
            tone: StageTone.neutral,
            text: context.tr('terminal_receipt_limit'),
          ),
        );
      case DeclineReceiptState.idle ||
          DeclineReceiptState.sending ||
          DeclineReceiptState.failed:
    }
    final sending = state == DeclineReceiptState.sending;
    final failed = state == DeclineReceiptState.failed;
    if (!open && !sending && !failed) {
      return StageOption(
        icon: Icons.receipt_long_outlined,
        title: context.tr('terminal_send_decline_receipt'),
        subtitle: initialEmail,
        onTap: onOpen,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Send follows the field as it is typed in.
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => ReceiptEmailRow(
              controller: controller,
              autofocus: open && !failed,
              sending: sending,
              onSend: controller.text.trim().isEmpty ? null : _send,
              fill: tokens.surface,
            ),
          ),
          if (failed) ...[
            const SizedBox(height: InSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                errorText.isEmpty
                    ? context.tr('terminal_error_unknown')
                    : errorText,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.overdue),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
