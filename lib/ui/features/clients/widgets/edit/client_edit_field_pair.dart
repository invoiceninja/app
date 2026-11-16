// The pair widget is shared by every edit form now; it lives in
// `lib/ui/core/widgets/form_field_pair.dart`. These names stay so the forms
// that imported them keep compiling.
export 'package:admin/ui/core/widgets/form_field_pair.dart'
    show FormFieldPair, kAddressPairWidth, kSidebarPairWidth;

import 'package:admin/ui/core/widgets/form_field_pair.dart';

/// The shared [FormFieldPair], under the name the client form gave it.
typedef ClientEditFieldPair = FormFieldPair;
