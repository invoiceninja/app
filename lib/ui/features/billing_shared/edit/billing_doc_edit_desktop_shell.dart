import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/app/services.dart';
import 'package:admin/ui/core/widgets/toast_host.dart';

/// Desktop multi-column layout for the five billing-doc edit screens
/// (invoice / quote / credit / purchase_order / recurring_invoice).
///
/// Layout from top to bottom:
/// 1. The details: three cards across the top — the party and its
///    contacts, the dates, the number and discount
///    (`BillingDocEditLayout`'s `_DetailsPanelDesktop`).
/// 2. Items section: the host's `LineItemEditor` (full-width, inline
///    edit table on desktop).
/// 3. Bottom row: a tabbed notes/terms/footer/eInvoice card on the
///    left + the totals breakdown card on the right.
/// 4. A full-width PDF preview pane spanning the whole content width,
///    below the bottom row (mirrors React / admin-portal).
/// 5. Sticky totals strip pinned at the bottom.
///
/// The host builds every piece, so per-document differences (vendor vs
/// client picker, the recurring schedule, …) never reach the shell.
class BillingDocEditDesktopShell extends StatelessWidget {
  const BillingDocEditDesktopShell({
    super.key,
    required this.details,
    required this.itemsSection,
    required this.notesTabsCard,
    required this.totalsCard,
    required this.pdfPane,
    required this.stickyTotals,
    this.findBar,
  });

  /// Find in line items' bar, pinned over the scrolling page so it stays on
  /// screen while the page scrolls from one matching line to the next. Mounted
  /// whether or not the bar shows (it draws nothing while closed), so opening
  /// it never remounts the page.
  final Widget? findBar;

  final Widget details;
  final Widget itemsSection;
  final Widget notesTabsCard;

  /// Full subtotal/tax/discount/total breakdown card, shown at the top
  /// of the bottom-right column (mirrors the old admin-portal layout).
  final Widget totalsCard;

  final Widget pdfPane;

  /// Slim single-line "Total" bar pinned at the very bottom.
  final Widget stickyTotals;

  /// Working height of the left notes/terms/footer editor card. Still well
  /// short of the 460–580 pane this replaced: the Settings / e-Invoice
  /// sub-tabs sit in a `SingleChildScrollView` and the markdown editors
  /// scroll internally, so nothing here is unreachable.
  ///
  /// It was `(h * 0.16).clamp(120, 150)` — sized on that same "scrolls
  /// internally" reasoning at a time when a read-mode markdown editor
  /// *couldn't* actually be scrolled (invoiceninja/flutter#107), which made a
  /// 120 px window over Terms a peephole with no way out. Raised now that the
  /// scrolling works.
  static double notesPaneHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return (h * 0.22).clamp(180.0, 260.0);
  }

  /// Height of the full-width PDF preview pane at the bottom of the
  /// desktop edit page. Large like the reference apps but not a literal
  /// full viewport — the page already scrolls and `PdfPreview` scrolls
  /// internally, so an over-tall pane just adds dead over-scroll. The A4
  /// page width is capped at 800 in `billing_doc_pdf_view.dart` anyway.
  static double fullWidthPdfHeight(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return (h * 0.78).clamp(560.0, 900.0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.inTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?findBar,
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(InSpacing.lg(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                SizedBox(height: InSpacing.md(context)),
                itemsSection,
                SizedBox(height: InSpacing.lg(context)),
                // Bottom row: notes-tabs card (left) + totals breakdown
                // (right). No IntrinsicHeight/stretch — the PDF preview
                // is now a full-width pane below, so there's nothing tall
                // on the right to align to; stretching the short,
                // borderless totals card would just paint a dead gap of
                // page background beside the tall notes card. `.start`
                // lets totals sit at its natural height; the notes card
                // drives the row height as before.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: notesTabsCard),
                    SizedBox(width: InSpacing.lg(context)),
                    Expanded(flex: 2, child: totalsCard),
                  ],
                ),
                SizedBox(height: InSpacing.lg(context)),
                // Full-width PDF preview pane (mirrors React /
                // admin-portal: form on top, preview full-width below).
                // It auto-refreshes as the draft changes, so there's no
                // stale-preview banner.
                pdfPane,
              ],
            ),
          ),
        ),
        Divider(height: 1, color: tokens.border),
        // Published as a bottom bar, so the shell lifts the floating timer
        // pill (and a bottom toast) above it rather than over the Total.
        ToastBottomInset(
          controller: context.read<Services?>()?.toasts,
          child: stickyTotals,
        ),
      ],
    );
  }
}
