import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/data/models/domain/billing/billing_doc_fields.dart';
import 'package:admin/app/shortcut_hint_controller.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/detail_find_navigator.dart';
import 'package:admin/ui/core/detail/detail_tab_indices.dart';
import 'package:admin/ui/core/detail/entity_detail_actions_row.dart';
import 'package:admin/ui/core/detail/entity_detail_tabs.dart';
import 'package:admin/ui/core/detail/entity_quick_actions.dart';
import 'package:admin/ui/core/detail/record_screen_controller.dart';
import 'package:admin/ui/core/sync/require_synced.dart';
import 'package:admin/ui/core/utils/platform_modifier.dart';
import 'package:admin/ui/core/widgets/shortcut_hint_scope.dart';
import 'package:admin/ui/core/widgets/party_money_cell.dart';
import 'package:admin/ui/features/billing_shared/billing_doc_type.dart';
import 'package:admin/ui/features/billing_shared/detail/billing_doc_record_header.dart';
import 'package:admin/ui/features/billing_shared/line_item_find.dart';
import 'package:admin/utils/formatting.dart';
import 'package:admin/ui/core/widgets/ltr_value.dart';

/// The width from which a billing document shows its PDF beside the record.
/// Below it the PDF is a screen of its own (`/<documents>/:id/pdf`).
const double kBillingDocPdfSplitMinWidth = 900;

/// The body of a billing document's record screen: the record page —
/// identity, quick actions, standing, comments and profile above a pinned tab
/// strip — and, on a wide window, the document's PDF beside it.
///
/// The five screens each carried this split as a copy, around a plain
/// `SingleChildScrollView`. Two things change with it being here:
///
///  * **The scroll half is an `EntityRecordPage`**, so the strip pins once it
///    reaches the top and the half gets pull-to-refresh. That page works
///    inside the split unchanged — it only needs to be handed the strip and
///    the active body, which is what [tabs]' `layout` argument is for: the
///    tabs widget owns the `TabController`, so it wraps the page and hands the
///    two back to be placed.
///  * **The tree has one shape at every width** — a `Row` whose second and
///    third children come and go. Returning the page bare below the split
///    width moved it in the tree the moment a window was dragged across
///    900 px, which remounted it: back to the top, every tab's state gone.
///
/// The PDF half is 6/11 of the width, so at the 900 px floor the record gets
/// about 410 px — the same as the slide-over pane — and never reaches the
/// 1000 px at which `EntityRecordColumn` puts the standing card beside the
/// header until the window is ~2200 px wide. That is intended: a document's
/// record column is a narrow stack almost everywhere, and is designed as one.
class BillingDocRecordBody extends StatefulWidget {
  const BillingDocRecordBody({
    super.key,
    required this.record,
    required this.top,
    required this.tabs,
    required this.pdfPane,
  });

  /// The five documents' tab order: Comments, Activity, Overview, then each
  /// screen's own. Pinned by `comments_surface_wiring_test`.
  static const int activityTabIndex = 1;
  static const int overviewTabIndex = 2;

  final RecordScreenController record;

  /// Everything above the tabs — an `EntityRecordColumn`. Told whether the
  /// PDF pane is showing, which decides whether a View PDF tile is worth its
  /// slot.
  final Widget Function(BuildContext context, bool hasPdfPane) top;

  /// The screen's `EntityDetailTabs`, built by the host (the two leading tabs
  /// are pinned to the host file by `comments_surface_wiring_test`). Pass
  /// `layout` straight to `EntityDetailTabs.layoutBuilder`, `landingTab` to
  /// its `initialIndex`, and wire `onReveal` to `record.page.revealTabs`.
  ///
  /// `landingTab` is the tab a freshly opened document lands on, decided the
  /// first time the body lays out and never again — resizing across the PDF
  /// split must not change the tab under the user. Beside the PDF pane the
  /// document itself is on screen, so Overview (its lines and totals) would
  /// repeat it and Activity — sent, viewed, paid — leads instead; without the
  /// pane Overview is the document. A tab remembered for this entity's pane
  /// still wins (`EntityDetailTabs._restoredIndex`).
  final Widget Function(
    BuildContext context,
    bool hasPdfPane,
    EntityDetailTabsLayoutBuilder layout,
    int landingTab,
  )
  tabs;

  /// Built only while the split is showing.
  final WidgetBuilder pdfPane;

  @override
  State<BillingDocRecordBody> createState() => _BillingDocRecordBodyState();
}

class _BillingDocRecordBodyState extends State<BillingDocRecordBody> {
  /// See [BillingDocRecordBody.tabs]. Set by the first layout.
  int? _landingTab;

  /// Find in line items (`docs/find-in-line-items.md`): the Overview tab's
  /// table highlights, the bar pinned under the strip drives it.
  final LineItemFindController _find = LineItemFindController();

  /// The scaffold's ⌘F / Ctrl+F channel, bound to [_openFind].
  DetailFindNavigator? _findNavigator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigator = DetailFindNavigatorScope.maybeOf(context);
    if (identical(navigator, _findNavigator)) return;
    _findNavigator?.unbind(_openFind);
    _findNavigator = navigator?..bind(_openFind);
  }

  @override
  void dispose() {
    _findNavigator?.unbind(_openFind);
    _find.dispose();
    super.dispose();
  }

  /// ⌘F: the line items are on the Overview tab, so go there (and bring the
  /// strip, with the bar under it, into view), then open the bar.
  void _openFind() {
    widget.record.selectTab.selectId(DetailTabIds.overview);
    _find.open();
  }

  @override
  Widget build(BuildContext context) {
    return ShortcutHintScope(
      hints: [
        ShortcutHint(
          keys: [platformModifierLabel(), 'F'],
          labelKey: 'find_in_items',
        ),
      ],
      child: LineItemFindScope(controller: _find, child: _layout(context)),
    );
  }

  Widget _layout(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= kBillingDocPdfSplitMinWidth;
        final landingTab = _landingTab ??= split
            ? BillingDocRecordBody.activityTabIndex
            : BillingDocRecordBody.overviewTabIndex;
        return widget.tabs(
          context,
          split,
          (context, strip, body) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: widget.record.buildPage(
                  // The find bar pins with the strip, so it stays on screen
                  // while the page scrolls from one hit to the next.
                  strip: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // One shape open or closed, so opening the bar never
                      // remounts the strip.
                      strip,
                      ListenableBuilder(
                        listenable: _find,
                        builder: (context, _) => _find.isOpen
                            ? LineItemFindBar(controller: _find)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  body: body,
                  top: widget.top(context, split),
                ),
              ),
              if (split) ...[
                VerticalDivider(width: 1, color: context.inTheme.border),
                Expanded(flex: 6, child: widget.pdfPane(context)),
              ],
            ],
          ),
          landingTab,
        );
      },
    );
  }
}

/// What a tap on a row of the History tab does: the version it names opens in
/// the PDF pane when there is one, and on a screen of its own when there is
/// not (`docs/document-version-history.md` § Wide swaps the pane; narrow
/// routes). A null id is the live document.
///
/// An unsynced document has no PDF route to open — the guard says so rather
/// than navigating to a screen that would fail.
void Function(String? activityId) billingDocVersionOpener(
  BuildContext context, {
  required BillingDocType type,
  required String docId,
  required bool hasPdfPane,
  required ValueNotifier<String?> selection,
}) => (String? activityId) {
  if (hasPdfPane) {
    selection.value = activityId;
  } else {
    openBillingDocPdf(
      context,
      type: type,
      docId: docId,
      activityId: activityId,
    );
  }
};

/// Open the document's `/pdf` screen on [activityId]'s version (null: the
/// live document), as its delivery note when [deliveryNote] — which only the
/// live document has. Guarded like [billingDocVersionOpener].
void openBillingDocPdf(
  BuildContext context, {
  required BillingDocType type,
  required String docId,
  String? activityId,
  bool deliveryNote = false,
}) {
  if (!requireSynced(context, docId)) return;
  final query = <String, String>{
    if (activityId != null) 'activity_id': activityId,
    if (activityId == null && deliveryNote) 'delivery_note': 'true',
  };
  context.go(
    Uri(
      path: '${type.routePath}/$docId/pdf',
      queryParameters: query.isEmpty ? null : query,
    ).toString(),
  );
}

/// A billing document's number and the one figure that matters, for the fixed
/// bar once the header has scrolled away — so the Activity feed of a long-
/// lived invoice still says which invoice it is.
class BillingDocCompactTitle extends StatelessWidget {
  const BillingDocCompactTitle({
    super.key,
    required this.type,
    required this.doc,
    required this.figure,
    this.formatter,
  });

  final BillingDocType type;
  final BillingDocFields doc;

  /// What is still owed on an invoice, what is left on a credit, the amount
  /// of anything else.
  final Decimal figure;
  final Formatter? formatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.inTheme;
    final subject = billingDocSubject(doc);
    final vendorParty = type.party == BillingDocParty.vendor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // The header's own fallback: a document with no number yet is
          // named for what it is, not left as a blank line.
          subject.isEmpty ? context.tr(type.singularLabelKey) : subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            color: tokens.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        PartyCurrencyBuilder(
          clientId: vendorParty ? null : doc.clientId,
          vendorId: vendorParty ? doc.vendorId : null,
          builder: (context, currencyId) => LtrText(
            formatter?.money(figure, clientCurrencyId: currencyId) ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: tokens.ink2)
                .merge(moneyTextStyle()),
          ),
        ),
      ],
    );
  }
}

/// Assembles a billing document's quick-action tiles from the action items it
/// already has — the shared half of each `<Document>Actions.quickItemsFor`.
///
/// A tile is a second *render* of an item, so everything that decides whether
/// the action can run stays where it is: an item its `itemsFor` left out (no
/// permission, module off) or disabled (wrong status) yields no tile, and the
/// next in the host's ranking takes the slot.
///
/// Returns nothing at all for a deleted document, which is read-only, and for
/// one not yet synced, where every tile would answer "sync first" — the state
/// banner says each of those once.
class BillingDocQuickActions<A> {
  BillingDocQuickActions({
    required this.doc,
    required List<EntityActionItem<A>> items,
  }) : _items = items;

  final BillingDocFields doc;
  final List<EntityActionItem<A>> _items;

  bool get _inert => doc.isDeleted || doc.id.startsWith('tmp_');

  /// The tile for [kind], or null when the document does not have that action
  /// right now. [applies] is the host's "worth a tile for this record" rule,
  /// on top of the item's own `enabled`.
  /// [onScreen]: what it opens is already showing — see
  /// `EntityQuickAction.onScreen`.
  EntityQuickAction<A>? pick(
    A kind,
    String shortLabel, {
    bool applies = true,
    bool onScreen = false,
  }) {
    if (_inert) return null;
    final item = findActionItem<A>(_items, kind);
    if (item == null) return null;
    return EntityQuickAction<A>(
      item: item,
      shortLabel: shortLabel,
      applies: applies,
      onScreen: onScreen,
    );
  }
}
