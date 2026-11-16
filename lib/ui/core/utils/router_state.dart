import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// The [GoRouterState] for [context], and the only way this app asks for one
/// (`test/lint/no_raw_go_router_state_of_test.dart`).
///
/// **Why not `GoRouterState.of(context)`:** on go_router 18 it never returns
/// for a widget under a route whose page the router has already dropped, when
/// that route sits in a nested navigator — which is every record screen here
/// (docs/upstream-workarounds.md entry 25). It walks up through navigators
/// looking for a page it knows, but `Navigator.maybeOf` answers a navigator's
/// own context with that same navigator, so the walk stands still, forever,
/// on the UI thread. A page is dropped the moment the URL moves on, while its
/// route lingers for the exit transition; any widget inside it that asks for
/// the first time then freezes the app. Leaving a client did exactly that:
/// the embedded Invoices list in the client's tabs was built for the first
/// time on the way out.
///
/// So this asks go_router only where it is certain to answer at once: under
/// an active route that is a [Page]. Everywhere else — a route on its way
/// out, a dialog or menu pushed onto a nested navigator — it answers with the
/// router's current state, which is where the app now is.
///
/// Throws a [GoError] when there is no router above [context], as
/// `GoRouterState.of` does.
GoRouterState routerStateOf(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route != null && route.isActive && route.settings is Page<Object?>) {
    return GoRouterState.of(context);
  }
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    throw GoError('There is no GoRouter above the current context.');
  }
  return router.state;
}
