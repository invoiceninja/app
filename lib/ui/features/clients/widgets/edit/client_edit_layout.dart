import 'package:material_ui/material_ui.dart';

import 'package:admin/app/design_tokens.dart';
import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/widgets/centered_form_column.dart';
import 'package:admin/ui/core/widgets/form_field_pair.dart';
import 'package:admin/ui/features/clients/view_models/client_edit_view_model.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_edit_address_section.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_edit_contacts_section.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_edit_details_section.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_edit_notes_section.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_edit_settings_section.dart';
import 'package:admin/ui/features/clients/widgets/edit/client_edit_shipping_address_section.dart';
import 'package:admin/ui/core/edit/create_form_documents.dart';

/// Lays out the four edit-screen cards (Details, Address, Notes, Contacts)
/// using the v2 mockup pattern: `1fr` main column + fixed-width side column
/// on wide widths.
///
/// - ≥1000 px: two columns. Left (`Expanded`) holds Details + the two
///   addresses (side by side from `_addressPairWidth`) + Settings; right
///   (`_sidebarWidth` 360 px) holds Contacts + Notes.
/// - <1000 px: single centered column (≤820 px) with all cards stacked.
class ClientEditLayout extends StatelessWidget {
  const ClientEditLayout({super.key, required this.vm});

  final ClientEditViewModel vm;

  static const double _sidebarWidth = 360;

  /// The main column's width from which the two address cards share a row.
  static const double _addressPairWidth = 720;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol =
            constraints.maxWidth >= Breakpoints.entityFormMultiColumn;
        return SingleChildScrollView(
          padding: EdgeInsets.all(formPagePadding(context)),
          child: twoCol
              ? _wide(context)
              : CenteredFormColumn(child: _narrow(context)),
        );
      },
    );
  }

  Widget _wide(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClientEditDetailsSection(vm: vm),
              const SizedBox(height: kFormCardGap),
              _addresses(context),
              const SizedBox(height: kFormCardGap),
              ClientEditSettingsSection(vm: vm),
            ],
          ),
        ),
        const SizedBox(width: kFormCardGap),
        SizedBox(
          width: _sidebarWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClientEditContactsSection(vm: vm),
              const SizedBox(height: kFormCardGap),
              ClientEditNotesSection(vm: vm),
              if (vm.offersDocuments) ...[
                const SizedBox(height: kFormCardGap),
                CreateFormDocumentsCard(vm: vm),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Billing and shipping are the same six fields, so where the main column
  /// can hold two cards they sit side by side: one screen of scrolling less,
  /// and the two addresses can be compared. Below that they stack as before.
  Widget _addresses(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = InSpacing.md(context);
        if (constraints.maxWidth < _addressPairWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClientEditAddressSection(vm: vm),
              SizedBox(height: gap),
              ClientEditShippingAddressSection(vm: vm),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClientEditAddressSection(vm: vm, besideShipping: true),
            ),
            SizedBox(width: gap),
            Expanded(child: ClientEditShippingAddressSection(vm: vm)),
          ],
        );
      },
    );
  }

  Widget _narrow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClientEditDetailsSection(vm: vm),
        const SizedBox(height: kFormCardGap),
        ClientEditAddressSection(vm: vm),
        const SizedBox(height: kFormCardGap),
        ClientEditShippingAddressSection(vm: vm),
        const SizedBox(height: kFormCardGap),
        ClientEditContactsSection(vm: vm),
        const SizedBox(height: kFormCardGap),
        ClientEditSettingsSection(vm: vm),
        const SizedBox(height: kFormCardGap),
        ClientEditNotesSection(vm: vm),
        if (vm.offersDocuments) ...[
          const SizedBox(height: kFormCardGap),
          CreateFormDocumentsCard(vm: vm),
        ],
      ],
    );
  }
}
