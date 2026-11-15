import 'package:flutter/foundation.dart';

/// The dashboard's "Start getting paid" checklist, as pure facts → rows
/// (docs/first-run-welcome.md). Ordered for the first sent invoice: the
/// business is set up already (the wizard did it, so the bar starts with
/// progress), then the logo, then sending — clients are created inline from
/// the invoice, so they are not a prerequisite.
///
/// [tapToPay] is optional and last, after every required step: offered only
/// to someone who can finish it (an iPhone that can take Tap to Pay on iPhone,
/// in an iPhone country), and never counted — the card is complete without it
/// (docs/in-person-payments.md).
enum SetupChecklistItem { business, logo, invoice, payments, clients, tapToPay }

/// Where the logo stands. An upload queued in the outbox counts as done — the
/// user did it, and the row must not read "not done" while it is offline.
enum LogoUploadState { none, uploading, failed }

enum ChecklistRowState { done, uploading, failed, todo }

@immutable
class SetupChecklistFacts {
  const SetupChecklistFacts({
    this.hasLogo = false,
    this.logoUpload = LogoUploadState.none,
    this.sentInvoice = false,
    this.hasGateway = false,
    this.hasClient = false,
    this.tapToPay,
  });

  final bool hasLogo;
  final LogoUploadState logoUpload;

  /// An invoice past draft exists.
  final bool sentInvoice;
  final bool hasGateway;
  final bool hasClient;

  /// Tap to Pay on iPhone: null when not offered here, else whether it's set
  /// up.
  final bool? tapToPay;

  @override
  bool operator ==(Object other) =>
      other is SetupChecklistFacts &&
      other.hasLogo == hasLogo &&
      other.logoUpload == logoUpload &&
      other.sentInvoice == sentInvoice &&
      other.hasGateway == hasGateway &&
      other.hasClient == hasClient &&
      other.tapToPay == tapToPay;

  @override
  int get hashCode => Object.hash(
    hasLogo,
    logoUpload,
    sentInvoice,
    hasGateway,
    hasClient,
    tapToPay,
  );
}

@immutable
class SetupChecklistRow {
  const SetupChecklistRow(this.item, this.state);

  final SetupChecklistItem item;
  final ChecklistRowState state;

  /// Counts toward progress: done, or an upload on its way.
  bool get isComplete =>
      state == ChecklistRowState.done || state == ChecklistRowState.uploading;

  /// Counts toward the progress and "all done" — every step but the
  /// optional Tap to Pay on iPhone one.
  bool get counts => item != SetupChecklistItem.tapToPay;

  String get id => item.name;
}

List<SetupChecklistRow> setupChecklistRows(SetupChecklistFacts f) {
  ChecklistRowState flag(bool done) =>
      done ? ChecklistRowState.done : ChecklistRowState.todo;
  final logo = f.hasLogo
      ? ChecklistRowState.done
      : switch (f.logoUpload) {
          LogoUploadState.uploading => ChecklistRowState.uploading,
          LogoUploadState.failed => ChecklistRowState.failed,
          LogoUploadState.none => ChecklistRowState.todo,
        };
  return [
    const SetupChecklistRow(
      SetupChecklistItem.business,
      ChecklistRowState.done,
    ),
    SetupChecklistRow(SetupChecklistItem.logo, logo),
    SetupChecklistRow(SetupChecklistItem.invoice, flag(f.sentInvoice)),
    SetupChecklistRow(SetupChecklistItem.payments, flag(f.hasGateway)),
    SetupChecklistRow(SetupChecklistItem.clients, flag(f.hasClient)),
    if (f.tapToPay case final tapToPay?)
      SetupChecklistRow(SetupChecklistItem.tapToPay, flag(tapToPay)),
  ];
}

/// The one row that gets the filled button: the first not yet complete. A
/// failed upload is not complete, so Retry leads. The optional Tap to Pay on
/// iPhone row never leads.
SetupChecklistItem? nextChecklistItem(List<SetupChecklistRow> rows) =>
    rows.where((r) => r.counts && !r.isComplete).firstOrNull?.item;

int completedCount(List<SetupChecklistRow> rows) =>
    rows.where((r) => r.counts && r.isComplete).length;

/// The steps that count toward progress.
int countedTotal(List<SetupChecklistRow> rows) =>
    rows.where((r) => r.counts).length;

/// Item ids that count as done, as the card remembers them between visits.
Set<String> doneIds(List<SetupChecklistRow> rows) => {
  for (final r in rows)
    if (r.isComplete) r.id,
};
