/// Invoice Ninja's own billing portal: `ninja_portal_url`, the white-label
/// checkout and the PEPPOL credit packs all live on this host. A leaf, so the
/// checkout links and the store build's purchase-page check
/// (`isExternalPurchaseUri`) name one host.
const String kInvoiceNinjaBillingHost = 'invoiceninja.invoicing.co';

/// [kInvoiceNinjaBillingHost] as an origin, for building its checkout links.
const String kInvoiceNinjaBillingOrigin = 'https://$kInvoiceNinjaBillingHost';
