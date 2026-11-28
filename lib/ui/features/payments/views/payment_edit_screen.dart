import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:admin/app/services.dart';
import 'package:admin/data/models/domain/payment.dart';
import 'package:admin/domain/payment_types.dart';
import 'package:admin/l10n/localization.dart';
import 'package:admin/ui/core/detail/entity_detail_actions_row.dart';
import 'package:admin/ui/core/edit/after_save_create_action.dart';
import 'package:admin/ui/core/edit/carry_edit_entities.dart';
import 'package:admin/ui/core/edit/entity_edit_screen_scaffold.dart';
import 'package:admin/ui/features/payments/seed_payment_create_defaults.dart';
import 'package:admin/ui/features/payments/view_models/payment_edit_view_model.dart';
import 'package:admin/ui/features/payments/widgets/edit/payment_edit_layout.dart';
import 'package:admin/ui/features/invoices/widgets/invoice_actions.dart';
import 'package:admin/ui/core/widgets/notify.dart';
import 'package:admin/ui/features/payments/widgets/payment_actions.dart';

class PaymentEditScreen extends StatelessWidget {
  const PaymentEditScreen({this.existingId, this.cloneFrom, super.key});

  final String? existingId;

  /// Edit-mode override draft (parallels InvoiceEditScreen). Null for a normal
  /// edit (uses the fetched record) and for create (which reads the staged
  /// draft via `Services.takeCreateDraft`).
  final Payment? cloneFrom;

  @override
  Widget build(BuildContext context) {
    return EntityEditScreenScaffold<Payment, PaymentEditViewModel>(
      existingId: existingId,
      entityTypeName: 'payment',
      fetchExisting: (ctx, services, companyId, id) =>
          services.payments.watch(companyId: companyId, id: id).first,
      buildVm: (ctx, services, companyId, existing) {
        // Capture `ctx` once so validation messages thrown from `performSave`
        // can be translated without dragging BuildContext through the VM
        // method signatures. Safe because the scaffold owns the ctx for
        // the VM's lifetime.
        // Create-mode seed staged on `Services` (route extra:/query is dropped
        // cross-branch + on screen reuse); the keyed `/new` route recreates the
        // screen on each stage so buildVm re-reads it. `cloneFrom` is the
        // edit-mode override. Sources (client/invoice/credit) stage a payment
        // draft (clientId + any paymentables) before navigating.
        final clone =
            cloneFrom ??
            (existing == null
                ? services.takeCreateDraft<Payment>('/payments')
                : null);
        final vm = PaymentEditViewModel(
          repo: services.payments,
          companyId: companyId,
          existing: existing,
          cloneFrom: clone,
          translate: ctx.tr,
          useCommaAsDecimalPlace:
              services
                  .formatterIfReady(companyId)
                  ?.settings
                  .useCommaAsDecimalPlace ??
              false,
          sync: services.sync,
          connectivity: services.connectivity,
        );
        // The client's own Default Payment Type, else its last payment's
        // type, else the group's / company's (docs/payment-types.md).
        seedPaymentCreateDefaults(
          settings: services.settings,
          companyId: companyId,
          vm: vm,
          client: PaymentClientLookups(
            clientOverride: (clientId) async => defaultPaymentTypeId(
              (await services.clients
                      .watch(companyId: companyId, id: clientId)
                      .first)
                  ?.settings,
            ),
            lastPaymentType: (clientId) =>
                services.payments.lastManualTypeForClient(
                  companyId: companyId,
                  clientId: clientId,
                ),
            refreshLastPayment: (clientId) =>
                services.payments.refreshLatestForClient(
                  companyId: companyId,
                  clientId: clientId,
                ),
            // A type the company hides is passed over for the default.
            hiddenTypeIds: () async => parseHiddenPaymentTypes(
              (await services.company.get(
                companyId,
              ))?.settings.hiddenPaymentTypes,
            ),
          ),
        );
        // The Email receipt switch starts where the settings cascade's
        // `client_manual_payment_notification` says.
        seedPaymentReceiptDefault(
          settings: services.settings,
          companyId: companyId,
          vm: vm,
        );
        // Manual Overpayments decides whether money may be left unapplied.
        if (vm.isCreate) {
          services.company.get(companyId).then((c) {
            if (c != null && !vm.isDisposed) {
              vm.enableApplyingPayments = c.enableApplyingPayments;
            }
          }).ignore();
        }
        return vm;
      },
      titleWhileLoading: (ctx) =>
          existingId == null ? ctx.tr('new_payment') : ctx.tr('edit'),
      titleBuilder: (ctx, vm) => vm.isCreate
          ? ctx.tr('new_payment')
          : (vm.draft.number.isNotEmpty
                ? '${ctx.tr('edit')} · #${vm.draft.number}'
                : ctx.tr('edit')),
      bodyBuilder: (ctx, vm) => PaymentEditLayout(vm: vm),
      // Paying an invoice where a card payment this device took may have
      // been charged could count the money twice: a new payment, or an
      // existing one newly applied to it.
      confirmSave: (ctx, vm) {
        final before = {
          for (final p in vm.original?.paymentables ?? const <Paymentable>[])
            p.invoiceId,
        };
        final invoiceIds = [
          for (final p in vm.draft.paymentables)
            if (p.invoiceId.isNotEmpty && !before.contains(p.invoiceId))
              p.invoiceId,
        ];
        if (invoiceIds.isEmpty) return Future.value(true);
        final services = ctx.read<Services>();
        return InvoiceActions.cardPaymentsSettled(
          ctx,
          services,
          services.auth.session.value!.currentCompanyId,
          invoiceIds,
        );
      },
      resetToEmpty: (vm) => vm.resetToEmpty(),
      entityIdOf: (p) => p.id,
      actionsBuilder: (ctx, vm, onTap, saveButton) =>
          EntityOverflowActionBar<PaymentAction>(
            leading: saveButton,
            items: PaymentActions.editScreenItemsFor(
              ctx,
              vm.draft,
              (a) => onTap(a),
              isCreate: vm.isCreate,
            ),
          ),
      onAfterSaveAction: (ctx, saved, a) {
        final services = ctx.read<Services>();
        return PaymentActions.dispatch(
          ctx,
          services,
          services.auth.session.value!.currentCompanyId,
          saved,
          a as PaymentAction,
        );
      },
      // Create-mode: resolve the tmp id to the real one so Refund keeps its
      // navigation instead of the detail redirect.
      onAfterSaveActionOnCreate: (ctx, saved, a) async {
        final services = ctx.read<Services>();
        final companyId = services.auth.session.value!.currentCompanyId;
        // Enter Payment opens the next payment's editor offline too, where
        // the id is still `tmp_` and the generic path would send the user
        // to this payment's record over it. Taking over navigation also
        // skips the scaffold's toast, so the save is confirmed here, in the
        // scaffold's own words for an action's save: "Saved", which is true
        // offline too, where "created" would not be.
        if (a == PaymentAction.newPayment) {
          Notify.success(ctx, ctx.tr('saved'));
          await PaymentActions.dispatch(
            ctx,
            services,
            companyId,
            saved,
            PaymentAction.newPayment,
          );
          return true;
        }
        return dispatchAfterSaveOnCreate<Payment, PaymentAction>(
          ctx,
          saved: saved,
          idOf: (p) => p.id,
          withId: (p, id) => p.copyWith(id: id),
          resolveId: services.payments.resolveId,
          action: a as PaymentAction,
          navigatesOnCreate: PaymentActions.navigatesOnCreate,
          dispatch: (c, resolved, act) =>
              PaymentActions.dispatch(c, services, companyId, resolved, act),
        );
      },
      basePath: '/payments',
      // An edit typed while a new record's create was out rides to the
      // record's editor, over the server's copy (docs/after-saving.md).
      carryEdit: carryPaymentEdit,
    );
  }
}
