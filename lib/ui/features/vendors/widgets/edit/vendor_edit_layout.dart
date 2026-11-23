import 'package:material_ui/material_ui.dart';

import 'package:admin/ui/core/adaptive.dart';
import 'package:admin/ui/core/widgets/centered_form_column.dart';
import 'package:admin/ui/core/widgets/form_field_pair.dart';
import 'package:admin/ui/features/vendors/view_models/vendor_edit_view_model.dart';
import 'package:admin/ui/features/vendors/widgets/edit/vendor_edit_address_section.dart';
import 'package:admin/ui/features/vendors/widgets/edit/vendor_edit_contacts_section.dart';
import 'package:admin/ui/features/vendors/widgets/edit/vendor_edit_details_section.dart';
import 'package:admin/ui/features/vendors/widgets/edit/vendor_edit_notes_section.dart';
import 'package:admin/ui/features/vendors/widgets/edit/vendor_edit_settings_section.dart';
import 'package:admin/ui/core/edit/create_form_documents.dart';

/// Lays out the edit-screen cards (Details, Address, Settings, Contacts,
/// Notes) using the same v2 mockup pattern as `ClientEditLayout`:
///
/// - ≥1000 px: two columns. Left (`Expanded`) holds Details + Address +
///   Settings; right (`_sidebarWidth` 360 px) holds Contacts + Notes.
/// - <1000 px: single centered column (≤820 px) with all cards stacked.
class VendorEditLayout extends StatelessWidget {
  const VendorEditLayout({super.key, required this.vm});

  final VendorEditViewModel vm;

  static const double _sidebarWidth = 360;

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
              VendorEditDetailsSection(vm: vm),
              const SizedBox(height: kFormCardGap),
              VendorEditAddressSection(vm: vm),
              const SizedBox(height: kFormCardGap),
              VendorEditSettingsSection(vm: vm),
            ],
          ),
        ),
        const SizedBox(width: kFormCardGap),
        SizedBox(
          width: _sidebarWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VendorEditContactsSection(vm: vm),
              const SizedBox(height: kFormCardGap),
              VendorEditNotesSection(vm: vm),
              if (vm.showsDocuments) ...[
                const SizedBox(height: kFormCardGap),
                FormDocumentsCard(vm: vm),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _narrow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VendorEditDetailsSection(vm: vm),
        const SizedBox(height: kFormCardGap),
        VendorEditAddressSection(vm: vm),
        const SizedBox(height: kFormCardGap),
        VendorEditSettingsSection(vm: vm),
        const SizedBox(height: kFormCardGap),
        VendorEditContactsSection(vm: vm),
        const SizedBox(height: kFormCardGap),
        VendorEditNotesSection(vm: vm),
        if (vm.showsDocuments) ...[
          const SizedBox(height: kFormCardGap),
          FormDocumentsCard(vm: vm),
        ],
      ],
    );
  }
}
