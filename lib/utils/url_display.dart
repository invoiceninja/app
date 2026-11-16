/// [url] as a person reads it: no `http://` or `https://`, no `www.`, no
/// trailing slash. For display only; open and copy the URL itself.
String displayUrl(String url) {
  var s = url.trim();
  s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  return s;
}
