/// The URL of [path] on the server at [baseUrl], keeping [baseUrl]'s own path.
///
/// A self-hosted install can live under a sub-path (`https://host/ninja`).
/// `Uri.parse(baseUrl).resolve('/api/v1/login')` drops that path, because a
/// reference starting with `/` replaces the whole path, so every request went
/// to `https://host/api/v1/login` and a sub-path install could not sign in on
/// any platform. admin-portal appended the route to the full base URL instead
/// (`formatApiUrl`); this does the same, for every request the app builds.
///
/// [path] is a server route (`/api/v1/x`, with or without the leading slash)
/// and may carry its own query (`/api/v1/refresh?first_load=true`), which is
/// kept as written. An absolute [path] (a URL the server handed back) is
/// returned unchanged, as `resolve` did.
Uri apiUri(String baseUrl, String path) {
  final ref = Uri.parse(path);
  if (ref.hasScheme) return ref;
  final base = Uri.parse(baseUrl);
  var basePath = base.path;
  while (basePath.endsWith('/')) {
    basePath = basePath.substring(0, basePath.length - 1);
  }
  final routePath = ref.path.startsWith('/') ? ref.path : '/${ref.path}';
  return Uri(
    scheme: base.scheme,
    userInfo: base.userInfo.isEmpty ? null : base.userInfo,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: '$basePath$routePath',
    query: ref.hasQuery ? ref.query : null,
  );
}

/// The server base URL a redirect of [request] points at, or null when it
/// points anywhere but the same route under another base.
///
/// [request] is an [apiUri] (a base, then `/api/v1/…`); [location] is the
/// response's `Location` header, absolute or relative. A redirect from
/// `http://host/api/v1/login` to `https://host/api/v1/login` gives
/// `https://host`, and one to `https://host/ninja/api/v1/login` gives
/// `https://host/ninja`. One to a home page, a login page, another scheme or
/// an address with credentials in it gives null.
String? baseUrlFromRedirect(Uri request, String? location) {
  final raw = location?.trim() ?? '';
  if (raw.isEmpty) return null;
  final Uri target;
  try {
    target = request.resolve(raw);
  } on FormatException {
    return null;
  }
  final scheme = target.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (target.host.isEmpty || target.userInfo.isNotEmpty) return null;
  final at = request.path.lastIndexOf('/api/v1/');
  if (at < 0) return null;
  final route = request.path.substring(at);
  if (!target.path.endsWith(route)) return null;
  var path = target.path.substring(0, target.path.length - route.length);
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return Uri(
    scheme: scheme,
    host: target.host,
    port: target.hasPort ? target.port : null,
    path: path,
  ).toString();
}
