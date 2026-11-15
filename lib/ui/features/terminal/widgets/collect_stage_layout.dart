import 'dart:math' as math;
import 'dart:ui' show FontFeature, PathMetric;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';
import 'package:admin/ui/core/widgets/toast_host.dart';

// ---------------------------------------------------------------------------
// The in-person payment screens' stage chrome, shared by the collect screen,
// "Pay another way" and the Tap to Pay on iPhone enable screen so they read
// as one product: content in a scroll view, the actions pinned at the bottom
// (one primary, beside its way out), and a hero — a tinted tile, the
// headline, the amount, a supporting line — a little above the middle.
//
// ---------------------------------------------------------------------------

/// What a stage's hero says at a glance.
enum StageTone { neutral, accent, success, warning, danger }

extension StageToneColors on StageTone {
  /// The tone's ink (icon, dot) and its soft fill (tile).
  (Color, Color) colors(InTheme t) => switch (this) {
    StageTone.neutral => (t.ink2, t.draftSoft),
    StageTone.accent => (t.accentInk, t.accentSoft),
    StageTone.success => (t.paid, t.paidSoft),
    StageTone.warning => (t.warning, t.warningSoft),
    StageTone.danger => (t.overdue, t.overdueSoft),
  };
}

/// Figures that don't shift as they change.
const stageFigures = [FontFeature.tabularFigures()];

/// A stage: [children] scroll, centred a little above the middle of what
/// the actions leave, and [actions] stay at the bottom, stacked with the
/// primary last — nearest the thumb. A hairline separates them only while
/// content runs on underneath, and a toast is lifted above them.
class CollectStageLayout extends StatefulWidget {
  const CollectStageLayout({
    super.key,
    required this.children,
    this.actions = const [],
  });

  final List<Widget> children;
  final List<Widget> actions;

  @override
  State<CollectStageLayout> createState() => _CollectStageLayoutState();
}

class _CollectStageLayoutState extends State<CollectStageLayout> {
  /// Content runs on under the pinned actions: a hairline says so.
  bool _more = false;

  bool _onMetrics(ScrollMetricsNotification n) {
    _track(n.metrics);
    return false;
  }

  bool _onScroll(ScrollNotification n) {
    _track(n.metrics);
    return false;
  }

  void _track(ScrollMetrics metrics) {
    final more = metrics.extentAfter > 0.5;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
    const pad = 16.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) =>
                NotificationListener<ScrollMetricsNotification>(
                  onNotification: _onMetrics,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(pad),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.max(0, box.maxHeight - pad * 2),
                        ),
                        child: Align(
                          alignment: const Alignment(0, -0.25),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: widget.children,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ),
        ),
        if (actions.isNotEmpty)
          // A toast is lifted above the pinned actions, never over them: on
          // an iPhone one of them is the Tap to Pay on iPhone button, which
          // nothing may obscure (App Review 5.3; docs/toast-messages.md).
          ToastBottomInset(
            controller: context.read<Services?>()?.toasts,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: _more ? context.inTheme.border : Colors.transparent,
                  ),
                ),
              ),
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  pad,
                  _more ? InSpacing.lg(context) : InSpacing.sm,
                  pad,
                  pad,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(height: InSpacing.sm),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The stage at a glance: a tinted tile holding [icon] (a spinner when
/// [busy], Apple's [symbol] as drawn, a check that draws itself for
/// [StageTone.success]); then [title], [amount], [message] and [footer].
/// The tile arrives once (a fade and a small scale, through [InMotion]) each
/// time the stage changes.
class CollectStageHero extends StatelessWidget {
  const CollectStageHero({
    super.key,
    this.tone = StageTone.neutral,
    this.icon,
    this.symbol,
    this.busy = false,
    this.title,
    this.amount,
    this.message,
    this.caption,
    this.footer,
    this.headingLevel = 2,
  });

  /// 1 where the title is the screen's own (no app bar title above it).
  final int headingLevel;

  final StageTone tone;
  final IconData? icon;

  /// Drawn in the tile instead of [icon], tinted like any icon and
  /// otherwise untouched: Apple's Tap to Pay on iPhone symbol (App Review
  /// 5.5).
  final Widget? symbol;
  final bool busy;
  final String? title;
  final String? amount;
  final String? message;

  /// Which payment this is ("Invoice 0042 · Client"), small, under the
  /// amount.
  final String? caption;

  /// Under the words (a reassurance).
  final Widget? footer;

  static const double tile = 72;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final text = Theme.of(context).textTheme;
    final (ink, soft) = tone.colors(tokens);
    final drawsCheck = tone == StageTone.success && symbol == null && !busy;
    final mark = _HeroMark(
      // A new tone or glyph is a new arrival.
      key: ValueKey((tone, icon, busy, symbol != null)),
      soft: soft,
      ink: ink,
      outlined: tone == StageTone.neutral,
      drawsCheck: drawsCheck,
      child: busy
          ? SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: ink),
            )
          : symbol != null
          ? IconTheme.merge(
              data: IconThemeData(color: ink),
              child: symbol!,
            )
          : drawsCheck
          ? null
          : Icon(icon, size: 36, color: ink),
    );
    final title = this.title ?? '';
    final amount = this.amount ?? '';
    final message = this.message ?? '';
    final caption = this.caption ?? '';
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          const SizedBox(height: 16),
          if (title.isNotEmpty)
            Semantics(
              header: true,
              headingLevel: headingLevel,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          if (amount.isNotEmpty) ...[
            if (title.isNotEmpty) const SizedBox(height: InSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: LtrText(
                amount,
                textAlign: TextAlign.center,
                style: text.displayMedium?.copyWith(
                  fontSize: 48,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.5,
                  height: 1.15,
                ),
              ),
            ),
          ],
          if (caption.isNotEmpty) ...[
            const SizedBox(height: InSpacing.xs),
            LtrText(
              caption,
              keepRtlScript: true,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: tokens.ink3),
            ),
          ],
          if (message.isNotEmpty) ...[
            const SizedBox(height: InSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(
                fontSize: 15,
                color: tokens.ink2,
                height: 1.45,
              ),
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 16), footer!],
        ],
      ),
    );
  }
}

/// The hero's tile: it fades and scales in once, and a success check draws
/// itself after. Never repeats; instant under reduced motion.
class _HeroMark extends StatefulWidget {
  const _HeroMark({
    super.key,
    required this.soft,
    required this.ink,
    required this.outlined,
    required this.drawsCheck,
    this.child,
  });

  final Color soft;
  final Color ink;
  final bool outlined;
  final bool drawsCheck;
  final Widget? child;

  @override
  State<_HeroMark> createState() => _HeroMarkState();
}

class _HeroMarkState extends State<_HeroMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final motion = InMotion.of(context);
    if (!motion.enabled) {
      _c.value = 1;
      return;
    }
    _c
      ..duration = widget.drawsCheck
          ? InMotion.slow + InMotion.base
          : InMotion.slow
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    // The tile arrives over the first stretch; a check draws over the rest.
    final arrive = CurvedAnimation(
      parent: _c,
      curve: Interval(0, widget.drawsCheck ? 0.55 : 1, curve: InMotion.out),
    );
    final draw = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.4, 1, curve: InMotion.move),
    );
    return FadeTransition(
      opacity: arrive,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.86, end: 1).animate(arrive),
        child: Container(
          width: CollectStageHero.tile,
          height: CollectStageHero.tile,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.soft,
            borderRadius: BorderRadius.circular(InRadii.r4),
            // Grey on grey needs an edge, in the dark theme above all.
            border: widget.outlined
                ? Border.all(color: tokens.borderStrong)
                : null,
          ),
          child: widget.drawsCheck
              ? AnimatedBuilder(
                  animation: draw,
                  builder: (context, _) => CustomPaint(
                    size: const Size.square(36),
                    painter: _CheckPainter(draw.value, widget.ink),
                  ),
                )
              : widget.child,
        ),
      ),
    );
  }
}

/// A check mark, drawn up to [progress] of its length.
class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.18, h * 0.54)
      ..lineTo(w * 0.42, h * 0.76)
      ..lineTo(w * 0.84, h * 0.28);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final PathMetric m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}

/// A small coloured dot: where something stands (ready, getting ready,
/// stopped), beside its words.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.tone});

  final StageTone tone;

  @override
  Widget build(BuildContext context) {
    final (ink, soft) = tone.colors(context.inTheme);
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(InRadii.r1),
      ),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: tone == StageTone.neutral ? context.inTheme.ink3 : ink,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// A status dot and its words, on one compact line.
class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.tone,
    required this.text,
    this.trailing,
    this.centered = false,
  });

  final StageTone tone;
  final String text;
  final Widget? trailing;

  /// Centred under a hero; from the start in a row.
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: context.inTheme.ink2, height: 1.4);
    if (centered) {
      // The pair hugs its longest line, so it stays centred however the
      // words wrap.
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: StatusDot(tone: tone),
          ),
          const SizedBox(width: InSpacing.sm),
          Flexible(
            child: Text(
              text,
              style: style,
              textWidthBasis: TextWidthBasis.longestLine,
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: StatusDot(tone: tone),
        ),
        const SizedBox(width: InSpacing.sm),
        Expanded(child: Text(text, style: style)),
        ?trailing,
      ],
    );
  }
}

/// A slim determinate (or not yet) bar with its percentage.
class StageProgress extends StatelessWidget {
  const StageProgress({super.key, required this.value});

  /// 0–1, or null while it can't say.
  final double? value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final value = this.value;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(InRadii.r1),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: tokens.border,
              color: tokens.accent,
            ),
          ),
        ),
        if (value != null) ...[
          const SizedBox(width: InSpacing.sm),
          LtrText(
            '${(value * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.ink2,
              fontWeight: FontWeight.w600,
              fontFeatures: stageFigures,
            ),
          ),
        ],
      ],
    );
  }
}

/// A bordered card of label / value rows (invoice, client, card, …).
class CollectDetails extends StatelessWidget {
  const CollectDetails({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return CollectCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: tokens.border),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// One row of [CollectDetails]: a small muted label at the start, the value
/// (laid out left-to-right, a name keeping its own script) at the end.
class CollectDetailRow extends StatelessWidget {
  const CollectDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.isName = false,
    this.strong = false,
    this.leading,
    this.wrap,
  });

  final String label;
  final String value;

  /// A client's name: right-to-left script keeps its direction.
  final bool isName;

  /// The row a breakdown adds up to.
  final bool strong;

  /// Before the value (a card mark).
  final Widget? leading;

  /// Wraps the value (a copy affordance, say).
  final Widget Function(Widget value)? wrap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final text = Theme.of(context).textTheme;
    final shown = LtrText(
      value,
      textAlign: TextAlign.end,
      keepRtlScript: isName,
      style: text.bodyMedium?.copyWith(
        fontSize: strong ? 16 : 15,
        fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
        color: tokens.ink,
        fontFeatures: stageFigures,
      ),
    );
    final leading = this.leading;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(
                fontSize: 14,
                color: strong ? tokens.ink : tokens.ink3,
                fontWeight: strong ? FontWeight.w600 : null,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            flex: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading,
                  const SizedBox(width: InSpacing.sm),
                ],
                Flexible(child: wrap?.call(shown) ?? shown),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The stages' card surface: a quiet fill and a hairline.
class CollectCard extends StatelessWidget {
  const CollectCard({super.key, required this.child, this.padding, this.tone});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// A tinted card (a caution) instead of the neutral one.
  final StageTone? tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final tint = tone?.colors(tokens).$2;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint ?? tokens.surfaceAlt,
        borderRadius: BorderRadius.circular(InRadii.r3),
        border: Border.all(color: tint ?? tokens.border),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

/// A line that must be read before acting (don't record it by hand), in a
/// tinted card with its icon.
class CollectNote extends StatelessWidget {
  const CollectNote({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.tone = StageTone.neutral,
  });

  final String text;
  final IconData icon;
  final StageTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final (ink, _) = tone.colors(tokens);
    return Semantics(
      liveRegion: true,
      child: CollectCard(
        tone: tone == StageTone.neutral ? null : tone,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: ink),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.ink,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small reassurance under a hero ("The customer wasn't charged."): an
/// icon and a line in a soft, rounded-rectangle tag.
class StageTag extends StatelessWidget {
  const StageTag({
    super.key,
    required this.text,
    this.icon = Icons.verified_user_outlined,
    this.tone = StageTone.neutral,
  });

  final String text;
  final IconData icon;
  final StageTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final (ink, soft) = tone.colors(tokens);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(InRadii.r2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: ink),
            const SizedBox(width: InSpacing.sm),
            Flexible(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tokens.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The other things that can be done from here, as one card of rows (Pay
/// another way, Send decline receipt, Back to the reader): each a whole-row
/// target with its icon, a line of explanation and a chevron.
class StageOptions extends StatelessWidget {
  const StageOptions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Material(
      color: tokens.surfaceAlt,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(InRadii.r3),
        side: BorderSide(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: tokens.border,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One row of [StageOptions].
class StageOption extends StatelessWidget {
  const StageOption({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.accent = false,
    this.chevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// The option that matters most here: its icon sits in the accent.
  final bool accent;

  /// It leads somewhere new (a way back does not).
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final text = Theme.of(context).textTheme;
    final subtitle = this.subtitle;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent ? tokens.accentSoft : tokens.border,
                  borderRadius: BorderRadius.circular(InRadii.r2),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: accent ? tokens.accentInk : tokens.ink2,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.ink,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: text.bodySmall?.copyWith(
                          fontSize: 13,
                          color: tokens.ink3,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (chevron) ...[
                const SizedBox(width: InSpacing.sm),
                Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.chevron_left
                      : Icons.chevron_right,
                  size: 20,
                  color: tokens.ink3,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// How much a pinned action says.
enum StageButtonKind {
  /// The one thing to do next: filled accent.
  primary,

  /// A real alternative: the accent's soft fill.
  secondary,

  /// The way out, beside the primary.
  outlined,
}

/// A pinned action, a size up from a form's buttons — a checkout's.
class StageButton extends StatelessWidget {
  const StageButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = StageButtonKind.primary,
    this.icon,
  });

  final String label;

  /// Null disables it.
  final VoidCallback? onPressed;
  final StageButtonKind kind;
  final Widget? icon;

  /// A floor, never a fixed size: a large text scale grows it.
  static const size = Size(64, 52);

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    final type = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontSize: 16,
      fontWeight: kind == StageButtonKind.outlined
          ? FontWeight.w500
          : FontWeight.w600,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(InRadii.r3),
    );
    final child = Text(label, textAlign: TextAlign.center);
    final icon = this.icon;
    switch (kind) {
      case StageButtonKind.primary || StageButtonKind.secondary:
        final style = kind == StageButtonKind.primary
            ? FilledButton.styleFrom(
                minimumSize: size,
                textStyle: type,
                shape: shape,
                // The accent is the user's to choose: white on a pale one
                // can't be read, so the label takes whichever of white and
                // near-black the accent in force carries.
                foregroundColor: tokens.onAccent,
              )
            : FilledButton.styleFrom(
                minimumSize: size,
                textStyle: type,
                shape: shape,
                backgroundColor: tokens.accentSoft,
                foregroundColor: tokens.accentInk,
              );
        return icon == null
            ? FilledButton(style: style, onPressed: onPressed, child: child)
            : FilledButton.icon(
                style: style,
                onPressed: onPressed,
                icon: icon,
                label: child,
              );
      case StageButtonKind.outlined:
        final style = OutlinedButton.styleFrom(
          minimumSize: size,
          textStyle: type,
          shape: shape,
          side: BorderSide(color: tokens.borderStrong),
        );
        return icon == null
            ? OutlinedButton(style: style, onPressed: onPressed, child: child)
            : OutlinedButton.icon(
                style: style,
                onPressed: onPressed,
                icon: icon,
                label: child,
              );
    }
  }
}

/// The way out beside the way on (CLAUDE.md § Design system (v2)): the way
/// out takes what it needs, the way on the rest.
class StageButtonPair extends StatelessWidget {
  const StageButtonPair({
    super.key,
    required this.secondary,
    required this.primary,
    this.even = false,
  });

  final Widget secondary;
  final Widget primary;

  /// Two equals (Share · Done) rather than a way out and a way on.
  final bool even;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: even ? 1 : 2, child: secondary),
      const SizedBox(width: InSpacing.sm),
      Expanded(flex: even ? 1 : 3, child: primary),
    ],
  );
}

/// A receipt's one tidy row: the email, and Send inside the same line.
class ReceiptEmailRow extends StatelessWidget {
  const ReceiptEmailRow({
    super.key,
    required this.controller,
    required this.onSend,
    this.sending = false,
    this.autofocus = false,
    this.fill,
  });

  final TextEditingController controller;

  /// Null while there is nothing to send to.
  final VoidCallback? onSend;
  final bool sending;
  final bool autofocus;

  /// The field's fill, where it sits on a tinted card.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            decoration: InputDecoration(
              hintText: context.tr('email'),
              filled: fill != null,
              fillColor: fill,
              prefixIcon: Icon(
                Icons.mail_outline,
                size: 20,
                color: tokens.ink3,
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend?.call(),
          ),
        ),
        const SizedBox(width: InSpacing.sm),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(72, 48),
            backgroundColor: tokens.accentSoft,
            foregroundColor: tokens.accentInk,
            disabledBackgroundColor: tokens.draftSoft,
            disabledForegroundColor: tokens.ink3,
          ),
          onPressed: sending ? null : onSend,
          child: Text(context.tr(sending ? 'sending' : 'send')),
        ),
      ],
    );
  }
}
