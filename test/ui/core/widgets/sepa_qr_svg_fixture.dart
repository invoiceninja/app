/// `$sepa_qr_code_raw` as the server substitutes it into an email body: the
/// `EpcQrGenerator` wrapper around BaconQrCode's SVG, XML prolog and all
/// (`app/Helpers/Epc/EpcQrGenerator.php`), with the QR path cut short.
const kSepaQrSvg =
    "<svg viewBox='0 0 200 200' width='200' height='200' x='0' y='0' "
    "xmlns='http://www.w3.org/2000/svg'>\n"
    "          <rect x='0' y='0' width='100%' height='100%' fill='#ffffff' />"
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="200" '
    'height="200" viewBox="0 0 200 200"><rect x="0" y="0" width="200" '
    'height="200" fill="#ffffff"/><g transform="scale(4.878)">'
    '<g transform="translate(4,4)"><path fill-rule="evenodd" '
    'd="M8 0L8 1L11 1L11 2L10 2L10 3L9 3L9 5L10 5L10 7L9 7L9 6L8 6Z'
    'M0 0L0 7L7 7L7 0ZM1 1L1 6L6 6L6 1Z" fill="#000000"/></g></g></svg>\n'
    '</svg>';
