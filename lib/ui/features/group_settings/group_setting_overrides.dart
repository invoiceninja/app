import 'package:admin/data/models/api/company_settings_api_model.dart';
import 'package:admin/ui/features/settings/views/advanced/templates_reminders/template_options.dart';

/// What a group's Overview lists: every setting the group sets instead of
/// inheriting it from the company — exactly the fields whose override
/// checkbox is ticked when the settings editor is at group scope — each with
/// the label its settings page gives it and a value formatted the way that
/// page shows it.
///
/// `docs/settings-screens.md` § A group's Overview lists exactly the settings
/// its checkboxes tick.

/// How a stored value is turned into words. Most are read off the value's
/// own type (a `bool` is Enabled / Disabled); these are the ones a page
/// renders through a lookup, where printing the stored value would show a raw
/// id or a code.
enum OverrideValueKind {
  /// Shown as stored — a name, an email, a number, a colour.
  plain,

  /// Markup (terms, footers, templates, portal messages): one line of its
  /// text.
  html,

  /// A credential: never shown.
  secret,

  /// Code the portal runs (custom CSS / JS / head): not shown, only "Custom".
  code,
  currency,
  language,
  country,
  timezone,
  dateFormat,
  paymentType,
  design,

  /// A number of days (`payment_terms`, `valid_until`, reminder offsets).
  days,

  /// `endless_reminder_frequency_id` / `reset_counter_frequency_id`.
  frequency,

  /// A coded choice whose code is also a translation key (`always`,
  /// `when_paid`, `after_due_date`, `portrait`, …).
  word,

  /// `show_currency_code`: Code or Symbol.
  currencyFormat,

  /// `task_round_up`: Round Up or Round Down.
  roundDirection,

  /// `payment_email_all_contacts`: All Contacts or Primary Contact.
  emailRecipients,

  /// `email_sending_method`.
  emailProvider,

  /// `page_numbering_alignment`: `C` / `R` / `L`.
  alignment,

  /// `entity_send_time`: an hour of the day, 0–23.
  hour,

  /// A user id (`gmail_sending_user_id`), drawn as the user's name.
  user,

  /// `company_gateway_ids`: the gateways, by name, in order.
  gateways,

  /// A logo URL, a structured blob (`translations`, `pdf_variables`): "Custom".
  custom,
}

/// One setting's place in the settings UI: the label its page draws, the
/// section (a `kSettingsSections` slug) that page lives under, and how its
/// value reads.
class SettingOverrideSpec {
  const SettingOverrideSpec(
    this.labelKey,
    this.section, [
    this.kind = OverrideValueKind.plain,
  ]);

  final String labelKey;
  final String section;
  final OverrideValueKind kind;
}

/// Every setting a settings page binds by `apiKey`, keyed by that wire key,
/// with the label that page gives it — so the Overview names a setting the
/// way the page the user just ticked it on does. Where a page relies on its
/// section for context (four "Footer" fields, "Secret", "Domain"), the label
/// here is the fuller existing key ("Invoice Footer").
///
/// `group_setting_overrides_test` fails when a page binds an `apiKey` that
/// is missing here, so a new field cannot reach the Overview as a guessed
/// label. The email templates, the reminder rules and the number patterns
/// are a family each and are composed in [settingOverrideLabelKeys] instead.
const Map<String, SettingOverrideSpec> kSettingOverrideSpecs = {
  // Company Details
  'name': SettingOverrideSpec('name', 'company_details'),
  'id_number': SettingOverrideSpec('id_number', 'company_details'),
  'vat_number': SettingOverrideSpec('vat_number', 'company_details'),
  'qr_iban': SettingOverrideSpec('qr_iban', 'company_details'),
  'besr_id': SettingOverrideSpec('besr_id', 'company_details'),
  'classification': SettingOverrideSpec(
    'classification',
    'company_details',
    OverrideValueKind.word,
  ),
  'website': SettingOverrideSpec('website', 'company_details'),
  'email': SettingOverrideSpec('email', 'company_details'),
  'phone': SettingOverrideSpec('phone', 'company_details'),
  'address1': SettingOverrideSpec('address1', 'company_details'),
  'address2': SettingOverrideSpec('address2', 'company_details'),
  'city': SettingOverrideSpec('city', 'company_details'),
  'state': SettingOverrideSpec('state', 'company_details'),
  'postal_code': SettingOverrideSpec('postal_code', 'company_details'),
  'country_id': SettingOverrideSpec(
    'country',
    'company_details',
    OverrideValueKind.country,
  ),
  'custom_value1': SettingOverrideSpec('custom_value1', 'company_details'),
  'custom_value2': SettingOverrideSpec('custom_value2', 'company_details'),
  'custom_value3': SettingOverrideSpec('custom_value3', 'company_details'),
  'custom_value4': SettingOverrideSpec('custom_value4', 'company_details'),
  'company_logo': SettingOverrideSpec(
    'company_logo',
    'company_details',
    OverrideValueKind.custom,
  ),
  'invoice_terms': SettingOverrideSpec(
    'invoice_terms',
    'company_details',
    OverrideValueKind.html,
  ),
  'invoice_footer': SettingOverrideSpec(
    'invoice_footer',
    'company_details',
    OverrideValueKind.html,
  ),
  'quote_terms': SettingOverrideSpec(
    'quote_terms',
    'company_details',
    OverrideValueKind.html,
  ),
  'quote_footer': SettingOverrideSpec(
    'quote_footer',
    'company_details',
    OverrideValueKind.html,
  ),
  'credit_terms': SettingOverrideSpec(
    'credit_terms',
    'company_details',
    OverrideValueKind.html,
  ),
  'credit_footer': SettingOverrideSpec(
    'credit_footer',
    'company_details',
    OverrideValueKind.html,
  ),
  'purchase_order_terms': SettingOverrideSpec(
    'purchase_order_terms',
    'company_details',
    OverrideValueKind.html,
  ),
  'purchase_order_footer': SettingOverrideSpec(
    'purchase_order_footer',
    'company_details',
    OverrideValueKind.html,
  ),
  'documents_public_by_default': SettingOverrideSpec(
    'documents_public_by_default',
    'company_details',
  ),

  // Localization
  'currency_id': SettingOverrideSpec(
    'currency',
    'localization',
    OverrideValueKind.currency,
  ),
  'show_currency_code': SettingOverrideSpec(
    'currency_format',
    'localization',
    OverrideValueKind.currencyFormat,
  ),
  'language_id': SettingOverrideSpec(
    'language',
    'localization',
    OverrideValueKind.language,
  ),
  'timezone_id': SettingOverrideSpec(
    'timezone',
    'localization',
    OverrideValueKind.timezone,
  ),
  'date_format_id': SettingOverrideSpec(
    'date_format',
    'localization',
    OverrideValueKind.dateFormat,
  ),
  'military_time': SettingOverrideSpec('military_time', 'localization'),
  'enable_rappen_rounding': SettingOverrideSpec(
    'rappen_rounding',
    'localization',
  ),

  // Payment Settings
  'auto_bill': SettingOverrideSpec(
    'auto_bill_recurring_invoices',
    'online_payments',
    OverrideValueKind.word,
  ),
  'auto_bill_date': SettingOverrideSpec(
    'auto_bill_on',
    'online_payments',
    OverrideValueKind.word,
  ),
  'auto_bill_standard_invoices': SettingOverrideSpec(
    'auto_bill_standard_invoices',
    'online_payments',
  ),
  'use_credits_payment': SettingOverrideSpec(
    'use_available_credits',
    'online_payments',
    OverrideValueKind.word,
  ),
  'use_unapplied_payment': SettingOverrideSpec(
    'use_available_payments',
    'online_payments',
    OverrideValueKind.word,
  ),
  'payment_flow': SettingOverrideSpec(
    'one_page_checkout',
    'online_payments',
    OverrideValueKind.word,
  ),
  'client_initiated_payments': SettingOverrideSpec(
    'client_initiated_payments',
    'online_payments',
  ),
  'client_initiated_payments_minimum': SettingOverrideSpec(
    'minimum_payment_amount',
    'online_payments',
  ),
  'client_portal_allow_under_payment': SettingOverrideSpec(
    'allow_under_payment',
    'online_payments',
  ),
  'client_portal_under_payment_minimum': SettingOverrideSpec(
    'minimum_under_payment_amount',
    'online_payments',
  ),
  'client_portal_allow_over_payment': SettingOverrideSpec(
    'allow_over_payment',
    'online_payments',
  ),
  'unlock_invoice_documents_after_payment': SettingOverrideSpec(
    'unlock_invoice_documents_after_payment',
    'online_payments',
  ),
  'payment_terms': SettingOverrideSpec(
    'invoice_payment_terms',
    'online_payments',
    OverrideValueKind.days,
  ),
  'valid_until': SettingOverrideSpec(
    'quote_valid_until',
    'online_payments',
    OverrideValueKind.days,
  ),
  'payment_type_id': SettingOverrideSpec(
    'default_payment_type',
    'online_payments',
    OverrideValueKind.paymentType,
  ),
  'default_expense_payment_type_id': SettingOverrideSpec(
    'default_expense_payment_type',
    'online_payments',
    OverrideValueKind.paymentType,
  ),
  'client_online_payment_notification': SettingOverrideSpec(
    'online_payment_email',
    'online_payments',
  ),
  'client_manual_payment_notification': SettingOverrideSpec(
    'manual_payment_email',
    'online_payments',
  ),
  'send_email_on_mark_paid': SettingOverrideSpec(
    'mark_paid_payment_email',
    'online_payments',
  ),
  'payment_email_all_contacts': SettingOverrideSpec(
    'send_emails_to',
    'online_payments',
    OverrideValueKind.emailRecipients,
  ),
  'company_gateway_ids': SettingOverrideSpec(
    'company_gateways',
    'online_payments',
    OverrideValueKind.gateways,
  ),

  // Tax Settings
  'inclusive_taxes': SettingOverrideSpec('inclusive_taxes', 'tax_settings'),
  'tax_name1': SettingOverrideSpec('tax_name1', 'tax_settings'),
  'tax_rate1': SettingOverrideSpec('tax_rate1', 'tax_settings'),
  'tax_name2': SettingOverrideSpec('tax_name2', 'tax_settings'),
  'tax_rate2': SettingOverrideSpec('tax_rate2', 'tax_settings'),
  'tax_name3': SettingOverrideSpec('tax_name3', 'tax_settings'),
  'tax_rate3': SettingOverrideSpec('tax_rate3', 'tax_settings'),

  // Task Settings
  'default_task_rate': SettingOverrideSpec(
    'default_task_rate',
    'task_settings',
  ),
  'allow_billable_task_items': SettingOverrideSpec(
    'show_task_billable',
    'task_settings',
  ),
  'show_task_item_description': SettingOverrideSpec(
    'show_task_item_description',
    'task_settings',
  ),
  'enable_client_portal_tasks': SettingOverrideSpec(
    'show_tasks_in_client_portal',
    'task_settings',
  ),
  'show_all_tasks_client_portal': SettingOverrideSpec(
    'tasks_shown_in_portal',
    'task_settings',
    OverrideValueKind.word,
  ),
  'task_round_up': SettingOverrideSpec(
    'round_tasks',
    'task_settings',
    OverrideValueKind.roundDirection,
  ),
  'task_round_to_nearest': SettingOverrideSpec(
    'task_round_to_nearest',
    'task_settings',
  ),

  // Workflow Settings
  'auto_email_invoice': SettingOverrideSpec(
    'auto_email_invoice',
    'workflow_settings',
  ),
  'auto_archive_invoice': SettingOverrideSpec(
    'auto_archive_paid_invoices',
    'workflow_settings',
  ),
  'auto_archive_invoice_cancelled': SettingOverrideSpec(
    'auto_archive_cancelled_invoices',
    'workflow_settings',
  ),
  'lock_invoices': SettingOverrideSpec(
    'lock_invoices',
    'workflow_settings',
    OverrideValueKind.word,
  ),
  'global_tag_inheritance': SettingOverrideSpec(
    'global_tag_inheritance',
    'workflow_settings',
  ),
  'auto_convert_quote': SettingOverrideSpec(
    'auto_convert_quote',
    'workflow_settings',
  ),
  'auto_archive_quote': SettingOverrideSpec(
    'auto_archive_quote',
    'workflow_settings',
  ),

  // Invoice Design
  'invoice_design_id': SettingOverrideSpec(
    'invoice_design',
    'invoice_design',
    OverrideValueKind.design,
  ),
  'quote_design_id': SettingOverrideSpec(
    'quote_design',
    'invoice_design',
    OverrideValueKind.design,
  ),
  'credit_design_id': SettingOverrideSpec(
    'credit_design',
    'invoice_design',
    OverrideValueKind.design,
  ),
  'purchase_order_design_id': SettingOverrideSpec(
    'purchase_order_design',
    'invoice_design',
    OverrideValueKind.design,
  ),
  'statement_design_id': SettingOverrideSpec(
    'statement_design',
    'invoice_design',
    OverrideValueKind.design,
  ),
  'delivery_note_design_id': SettingOverrideSpec(
    'delivery_note_design',
    'invoice_design',
    OverrideValueKind.design,
  ),
  'payment_receipt_design_id': SettingOverrideSpec(
    'payment_receipt_design',
    'invoice_design',
    OverrideValueKind.design,
  ),
  'payment_refund_design_id': SettingOverrideSpec(
    'payment_refund_design',
    'invoice_design',
    OverrideValueKind.design,
  ),
  'page_size': SettingOverrideSpec('page_size', 'invoice_design'),
  'page_layout': SettingOverrideSpec(
    'page_layout',
    'invoice_design',
    OverrideValueKind.word,
  ),
  'font_size': SettingOverrideSpec('font_size', 'invoice_design'),
  'primary_font': SettingOverrideSpec('primary_font', 'invoice_design'),
  'secondary_font': SettingOverrideSpec('secondary_font', 'invoice_design'),
  'primary_color': SettingOverrideSpec('primary_color', 'invoice_design'),
  'secondary_color': SettingOverrideSpec('secondary_color', 'invoice_design'),
  'show_paid_stamp': SettingOverrideSpec('show_paid_stamp', 'invoice_design'),
  'show_shipping_address': SettingOverrideSpec(
    'show_shipping_address',
    'invoice_design',
  ),
  'sync_invoice_quote_columns': SettingOverrideSpec(
    'share_invoice_quote_columns',
    'invoice_design',
  ),
  'hide_empty_columns_on_pdf': SettingOverrideSpec(
    'empty_columns',
    'invoice_design',
  ),
  'page_numbering': SettingOverrideSpec('page_numbering', 'invoice_design'),
  'page_numbering_alignment': SettingOverrideSpec(
    'page_numbering_alignment',
    'invoice_design',
    OverrideValueKind.alignment,
  ),
  'embed_documents': SettingOverrideSpec(
    'invoice_embed_documents',
    'invoice_design',
  ),
  'pdf_variables': SettingOverrideSpec(
    'invoice_fields',
    'invoice_design',
    OverrideValueKind.custom,
  ),

  // Generated Numbers
  'counter_number_applied': SettingOverrideSpec(
    'generate_number',
    'generated_numbers',
    OverrideValueKind.word,
  ),
  'quote_number_applied': SettingOverrideSpec(
    'quote_number',
    'generated_numbers',
    OverrideValueKind.word,
  ),
  'counter_padding': SettingOverrideSpec('number_padding', 'generated_numbers'),
  'recurring_number_prefix': SettingOverrideSpec(
    'recurring_prefix',
    'generated_numbers',
  ),
  'invoice_filename_pattern': SettingOverrideSpec(
    'invoice_filename_pattern',
    'generated_numbers',
  ),
  'quote_filename_pattern': SettingOverrideSpec(
    'quote_filename_pattern',
    'generated_numbers',
  ),
  'credit_filename_pattern': SettingOverrideSpec(
    'credit_filename_pattern',
    'generated_numbers',
  ),
  'purchase_order_filename_pattern': SettingOverrideSpec(
    'purchase_order_filename_pattern',
    'generated_numbers',
  ),
  'filename_slug': SettingOverrideSpec('filename_slug', 'generated_numbers'),
  'shared_invoice_quote_counter': SettingOverrideSpec(
    'shared_invoice_quote_counter',
    'generated_numbers',
  ),
  'shared_invoice_credit_counter': SettingOverrideSpec(
    'shared_invoice_credit_counter',
    'generated_numbers',
  ),
  'reset_counter_frequency_id': SettingOverrideSpec(
    'reset_counter',
    'generated_numbers',
    OverrideValueKind.frequency,
  ),
  'reset_counter_date': SettingOverrideSpec('next_reset', 'generated_numbers'),

  // Client Portal
  'enable_client_portal': SettingOverrideSpec('client_portal', 'client_portal'),
  'enable_client_portal_dashboard': SettingOverrideSpec(
    'client_portal_dashboard',
    'client_portal',
  ),
  'enable_client_profile_update': SettingOverrideSpec(
    'enable_client_profile_update',
    'client_portal',
  ),
  'client_portal_enable_uploads': SettingOverrideSpec(
    'client_document_upload',
    'client_portal',
  ),
  'vendor_portal_enable_uploads': SettingOverrideSpec(
    'vendor_document_upload',
    'client_portal',
  ),
  'accept_client_input_quote_approval': SettingOverrideSpec(
    'accept_purchase_order_number',
    'client_portal',
  ),
  'show_pdfhtml_on_mobile': SettingOverrideSpec(
    'mobile_version',
    'client_portal',
  ),
  'preference_product_notes_for_html_view': SettingOverrideSpec(
    'preference_product_notes_for_html_view',
    'client_portal',
  ),
  'client_can_register': SettingOverrideSpec(
    'client_registration',
    'client_portal',
  ),
  'enable_client_portal_password': SettingOverrideSpec(
    'enable_portal_password',
    'client_portal',
  ),
  'show_accept_invoice_terms': SettingOverrideSpec(
    'show_accept_invoice_terms',
    'client_portal',
  ),
  'show_accept_quote_terms': SettingOverrideSpec(
    'show_accept_quote_terms',
    'client_portal',
  ),
  'require_invoice_signature': SettingOverrideSpec(
    'require_invoice_signature',
    'client_portal',
  ),
  'require_quote_signature': SettingOverrideSpec(
    'require_quote_signature',
    'client_portal',
  ),
  'require_purchase_order_signature': SettingOverrideSpec(
    'require_purchase_order_signature',
    'client_portal',
  ),
  'signature_on_pdf': SettingOverrideSpec('signature_on_pdf', 'client_portal'),
  'client_portal_terms': SettingOverrideSpec(
    'terms_of_service',
    'client_portal',
    OverrideValueKind.html,
  ),
  'client_portal_privacy_policy': SettingOverrideSpec(
    'privacy_policy',
    'client_portal',
    OverrideValueKind.html,
  ),
  'custom_message_dashboard': SettingOverrideSpec(
    'custom_message_dashboard',
    'client_portal',
    OverrideValueKind.html,
  ),
  'custom_message_unpaid_invoice': SettingOverrideSpec(
    'custom_message_unpaid_invoice',
    'client_portal',
    OverrideValueKind.html,
  ),
  'custom_message_paid_invoice': SettingOverrideSpec(
    'custom_message_paid_invoice',
    'client_portal',
    OverrideValueKind.html,
  ),
  'custom_message_unapproved_quote': SettingOverrideSpec(
    'custom_message_unapproved_quote',
    'client_portal',
    OverrideValueKind.html,
  ),
  'portal_custom_head': SettingOverrideSpec(
    'header',
    'client_portal',
    OverrideValueKind.code,
  ),
  'portal_custom_css': SettingOverrideSpec(
    'custom_css',
    'client_portal',
    OverrideValueKind.code,
  ),
  'portal_custom_footer': SettingOverrideSpec(
    'footer',
    'client_portal',
    OverrideValueKind.code,
  ),
  'portal_custom_js': SettingOverrideSpec(
    'custom_javascript',
    'client_portal',
    OverrideValueKind.code,
  ),

  // E-Invoicing
  'enable_e_invoice': SettingOverrideSpec('enable_e_invoice', 'e_invoice'),
  'e_invoice_type': SettingOverrideSpec('e_invoice_type', 'e_invoice'),
  'e_quote_type': SettingOverrideSpec('e_quote_type', 'e_invoice'),
  'merge_e_invoice_to_pdf': SettingOverrideSpec(
    'merge_e_invoice_to_pdf',
    'e_invoice',
  ),
  'france_reporting_enabled': SettingOverrideSpec(
    'france_reporting_enabled',
    'e_invoice',
  ),
  'france_reporting_schedule': SettingOverrideSpec(
    'france_reporting_schedule',
    'e_invoice',
    OverrideValueKind.word,
  ),
  'e_invoice_forward_email': SettingOverrideSpec(
    'e_invoice_forward_email',
    'e_invoice',
  ),
  'e_expense_forward_email': SettingOverrideSpec(
    'e_expense_forward_email',
    'e_invoice',
  ),
  'skip_automatic_email_with_peppol': SettingOverrideSpec(
    'skip_automatic_email_with_peppol',
    'e_invoice',
  ),

  // Email Settings
  'email_sending_method': SettingOverrideSpec(
    'email_provider',
    'email_settings',
    OverrideValueKind.emailProvider,
  ),
  'gmail_sending_user_id': SettingOverrideSpec(
    'send_from_gmail',
    'email_settings',
    OverrideValueKind.user,
  ),
  'custom_sending_email': SettingOverrideSpec('from_email', 'email_settings'),
  'email_from_name': SettingOverrideSpec('from_name', 'email_settings'),
  'reply_to_email': SettingOverrideSpec('reply_to_email', 'email_settings'),
  'reply_to_name': SettingOverrideSpec('reply_to_name', 'email_settings'),
  'bcc_email': SettingOverrideSpec('bcc_email', 'email_settings'),
  'postmark_secret': SettingOverrideSpec(
    'api_token',
    'email_settings',
    OverrideValueKind.secret,
  ),
  'mailgun_secret': SettingOverrideSpec(
    'api_key',
    'email_settings',
    OverrideValueKind.secret,
  ),
  'mailgun_domain': SettingOverrideSpec('mailgun_domain', 'email_settings'),
  'mailgun_endpoint': SettingOverrideSpec('endpoint', 'email_settings'),
  'brevo_secret': SettingOverrideSpec(
    'secret',
    'email_settings',
    OverrideValueKind.secret,
  ),
  'ses_access_key': SettingOverrideSpec(
    'access_key',
    'email_settings',
    OverrideValueKind.secret,
  ),
  'ses_secret_key': SettingOverrideSpec(
    'secret_key',
    'email_settings',
    OverrideValueKind.secret,
  ),
  'ses_region': SettingOverrideSpec('region', 'email_settings'),
  'ses_topic_arn': SettingOverrideSpec('topic_arn', 'email_settings'),
  'ses_from_address': SettingOverrideSpec('from_address', 'email_settings'),
  'email_style': SettingOverrideSpec(
    'email_style',
    'email_settings',
    OverrideValueKind.word,
  ),
  'email_style_custom': SettingOverrideSpec(
    'email_style_custom',
    'email_settings',
    OverrideValueKind.code,
  ),
  'email_alignment': SettingOverrideSpec(
    'email_alignment',
    'email_settings',
    OverrideValueKind.word,
  ),
  'email_signature': SettingOverrideSpec(
    'signature',
    'email_settings',
    OverrideValueKind.html,
  ),
  'show_email_footer': SettingOverrideSpec(
    'show_email_footer',
    'email_settings',
  ),
  'entity_send_time': SettingOverrideSpec(
    'send_time',
    'email_settings',
    OverrideValueKind.hour,
  ),
  'pdf_email_attachment': SettingOverrideSpec('attach_pdf', 'email_settings'),
  'document_email_attachment': SettingOverrideSpec(
    'attach_documents',
    'email_settings',
  ),
  'ubl_email_attachment': SettingOverrideSpec('attach_ubl', 'email_settings'),

  // Templates & Reminders (the per-template keys are composed below)
  'enable_reminder_endless': SettingOverrideSpec(
    'reminder_endless',
    'templates_and_reminders',
  ),
  'endless_reminder_frequency_id': SettingOverrideSpec(
    'reminder_endless',
    'templates_and_reminders',
    OverrideValueKind.frequency,
  ),

  'company_logo_size': SettingOverrideSpec('logo_size', 'invoice_design'),
  'hidden_payment_types': SettingOverrideSpec(
    'payment_type',
    'online_payments',
    OverrideValueKind.paymentType,
  ),
  'reminder_send_time': SettingOverrideSpec(
    'send_time',
    'templates_and_reminders',
  ),
  'purchase_order_public_notes': SettingOverrideSpec(
    'public_notes',
    'company_details',
    OverrideValueKind.html,
  ),
  'portal_design_id': SettingOverrideSpec(
    'design',
    'client_portal',
    OverrideValueKind.custom,
  ),
  'enable_quote_reminder1': SettingOverrideSpec(
    'quote_reminder1',
    'templates_and_reminders',
  ),

  // Several pages edit these through a picker of their own
  'translations': SettingOverrideSpec(
    'custom_labels',
    'company_details',
    OverrideValueKind.custom,
  ),
};

/// The keys a group sets, in the order its Overview lists them — exactly the
/// ones `GroupSettingsDraftViewModel.isOverridden` answers true for, because
/// both read [raw] through the same typed model: a key that model does not
/// know is not a field any page can tick, and a stored `null` is "inherit".
List<String> overriddenSettingKeys(Map<String, dynamic>? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final json = CompanySettingsApi.fromJsonLenient(raw).toJson();
  return [
    for (final e in json.entries)
      if (e.value != null) e.key,
  ];
}

/// The section a setting is listed under — a `kSettingsSections` slug, or
/// `other` when no page binds it.
String settingOverrideSection(String key) {
  final spec = kSettingOverrideSpecs[key];
  if (spec != null) return spec.section;
  if (_templateFamily(key) != null) return 'templates_and_reminders';
  if (_numberFamily(key) != null) return 'generated_numbers';
  return 'other';
}

/// The translation keys that name [key], joined with ` · ` when there are
/// two ("First Reminder · Subject"). Null when nothing names it — the caller
/// then asks the bundle for the key itself and, failing that, words it.
List<String>? settingOverrideLabelKeys(String key) {
  final composed = _kComposedLabels[key];
  if (composed != null) return composed;
  final spec = kSettingOverrideSpecs[key];
  if (spec != null) return [spec.labelKey];
  return _templateFamily(key) ?? _numberFamily(key);
}

/// Specs whose one label would not say which setting it is.
const Map<String, List<String>> _kComposedLabels = {
  'endless_reminder_frequency_id': ['reminder_endless', 'frequency'],
  'enable_quote_reminder1': ['quote_reminder1', 'send_email'],
  'hidden_payment_types': ['hidden', 'payment_type'],
  'purchase_order_public_notes': ['purchase_order', 'public_notes'],
  'portal_design_id': ['client_portal', 'design'],
};

/// How [key]'s value reads.
OverrideValueKind settingOverrideKind(String key) {
  final spec = kSettingOverrideSpecs[key];
  if (spec != null) return spec.kind;
  if (key.startsWith('email_template_') ||
      key.startsWith('email_quote_template_')) {
    return OverrideValueKind.html;
  }
  if (key.startsWith('num_days_reminder') ||
      key.startsWith('quote_num_days_reminder')) {
    return OverrideValueKind.days;
  }
  if (key.startsWith('schedule_reminder') ||
      key.startsWith('quote_schedule_reminder')) {
    return OverrideValueKind.word;
  }
  return OverrideValueKind.plain;
}

/// `email_subject_*`, `email_template_*`, the quote reminder's
/// `email_quote_*_reminder1`, and each reminder rule's switch, days, schedule
/// and late fees: "Template · Field", the template named as the
/// Templates & Reminders picker names it.
List<String>? _templateFamily(String key) {
  String? templateLabel(String id) {
    for (final o in kTemplateOptions) {
      if (o.key == id) return o.labelKey;
    }
    return null;
  }

  final quote = RegExp(r'^email_quote_(subject|template)_reminder1$');
  final qm = quote.firstMatch(key);
  if (qm != null) {
    return ['quote_reminder1', qm.group(1) == 'subject' ? 'subject' : 'body'];
  }
  final email = RegExp(r'^email_(subject|template)_(.+)$').firstMatch(key);
  if (email != null) {
    final label = templateLabel(email.group(2)!);
    if (label == null) return null;
    return [label, email.group(1) == 'subject' ? 'subject' : 'body'];
  }
  const fields = {
    'enable_reminder': 'send_email',
    'num_days_reminder': 'days',
    'schedule_reminder': 'schedule',
    'late_fee_amount': 'late_fee_amount',
    'late_fee_percent': 'late_fee_percent',
  };
  final rule = RegExp(
    r'^(quote_)?(enable_reminder|num_days_reminder|schedule_reminder|'
    r'late_fee_amount|late_fee_percent)(\d|_endless)$',
  ).firstMatch(key);
  if (rule != null) {
    final suffix = rule.group(3)!;
    final id = suffix == '_endless'
        ? 'reminder_endless'
        : '${rule.group(1) ?? ''}reminder$suffix';
    final label = templateLabel(id);
    if (label == null) return null;
    return [label, fields[rule.group(2)]!];
  }
  // The endless reminder's fees put `endless` in the middle.
  final endless = RegExp(
    r'^late_fee_endless_(amount|percent)$',
  ).firstMatch(key);
  if (endless != null) {
    return ['endless_reminder', 'late_fee_${endless.group(1)}'];
  }
  return null;
}

/// `*_number_pattern` / `*_number_counter`: "Entity · Number Pattern", as
/// the Generated Numbers tabs put it.
List<String>? _numberFamily(String key) {
  final m = RegExp(r'^(.+)_number_(pattern|counter)$').firstMatch(key);
  if (m == null) return null;
  final entity = m.group(1)!;
  // The bundle has no singular `ticket`.
  return [entity == 'ticket' ? 'tickets' : entity, 'number_${m.group(2)}'];
}
