/// The originating IP an activity row may show, or `''` when it has none
/// worth showing.
///
/// The server stamps the request IP on every activity (`Ninja::eventVars`,
/// `app/Utils/Ninja.php`), and a background job — a queued email, a reminder,
/// a recurring send, an auto-bill — has no request, so `request()->ip()` is
/// the loopback address. Shown, it reads as "someone at 127.0.0.1 did this"
/// on most of the feed, and it says nothing the user can act on. A loopback
/// address (IPv4 `127.0.0.0/8`, IPv6 `::1` in either spelling, or the
/// IPv4-mapped `::ffff:127.x`) is therefore dropped; every other value is
/// returned trimmed.
String displayableActivityIp(String? raw) {
  final ip = (raw ?? '').trim();
  return isLoopbackIp(ip) ? '' : ip;
}

/// Whether [ip] is a loopback address — see [displayableActivityIp].
bool isLoopbackIp(String ip) {
  var v = ip.trim().toLowerCase();
  if (v.isEmpty) return false;
  // `[::1]` as some proxies bracket it.
  if (v.startsWith('[') && v.endsWith(']')) v = v.substring(1, v.length - 1);
  if (v.startsWith('::ffff:')) v = v.substring(7);
  if (v.startsWith('127.')) return true;
  if (v == '::1') return true;
  // The uncompressed IPv6 loopback: every group zero but a final 1.
  final groups = v.split(':');
  if (groups.length == 8 &&
      groups.last.replaceFirst(RegExp('^0+'), '') == '1' &&
      groups.take(7).every((g) => RegExp(r'^0+$').hasMatch(g))) {
    return true;
  }
  return false;
}
