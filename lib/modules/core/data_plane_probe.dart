import 'dart:async';
import 'dart:io'
    show
        HttpClient,
        HttpException,
        HttpHeaders,
        HttpStatus,
        SocketException,
        TlsException;

/// Proves an HTTP request completes through the active tunnel.
///
/// A handshake only establishes the VPN session; it says nothing about
/// whether the relay forwards the packets afterwards. This probe returns true
/// only when [url] produced a 200 response and at least one body byte within
/// [deadline]. Every failure mode — refused, timed out, TLS error, empty body
/// — is `false`, because the caller treats false as "this tunnel carried
/// nothing" and needs no distinction between the causes.
class DataPlaneProbe {
  DataPlaneProbe._();

  static Future<bool> once(String url, Duration deadline) async {
    final client = HttpClient()..connectionTimeout = deadline;
    final done = Completer<bool>();
    final timer = Timer(deadline, () {
      client.close(force: true);
      if (!done.isCompleted) done.complete(false);
    });
    unawaited(() async {
      var received = 0;
      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        final response = await request.close();
        if (response.statusCode == HttpStatus.ok) {
          await for (final chunk in response) {
            received += chunk.length;
            if (received > 0) break;
          }
        } else {
          await response.drain<void>();
        }
      } on SocketException {
        // No route through the tunnel.
      } on TlsException {
        // A middlebox or a stale tunnel answered instead of the host.
      } on HttpException {
        // The peer closed mid-response; bytes received so far still count.
      } catch (_) {
        // Treat unknown failures as a miss rather than aborting the caller.
      } finally {
        timer.cancel();
        client.close(force: true);
        if (!done.isCompleted) done.complete(received > 0);
      }
    }());
    return done.future;
  }

  /// Tries [urls] in order and succeeds when one carries a byte.
  ///
  /// Sequential on purpose: the first endpoint is an IP literal that needs no
  /// DNS and succeeds on almost every working tunnel, so a healthy session
  /// pays one handshake. The next endpoint is only contacted when the first
  /// failed, which keeps a blocked provider from causing a false drop while
  /// still catching a genuinely dead data plane.
  static Future<bool> fallback(List<String> urls, Duration deadline) async {
    for (final url in urls) {
      if (await once(url, deadline)) return true;
    }
    return false;
  }
}
