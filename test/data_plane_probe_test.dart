import 'dart:io';

import 'package:bulbvpn/modules/core/data_plane_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // No TestWidgetsFlutterBinding here: it replaces HttpClient with a 400
  // stub, and these tests need a real loopback server to prove the probe
  // semantics.

  Future<HttpServer> serve(
    Future<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      handler(request).catchError((_) {});
    });
    return server;
  }

  test('a 200 with a body proves the path', () async {
    final server = await serve((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('ip=203.0.113.5\n');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final ok = await DataPlaneProbe.once(
      'http://127.0.0.1:${server.port}/trace',
      const Duration(seconds: 2),
    );
    expect(ok, isTrue);
  });

  test('an error status is not evidence of a working data plane', () async {
    final server = await serve((request) async {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('down');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final ok = await DataPlaneProbe.once(
      'http://127.0.0.1:${server.port}/trace',
      const Duration(seconds: 2),
    );
    expect(ok, isFalse);
  });

  test('a server that never answers is a miss inside the deadline', () async {
    final held = <HttpRequest>[];
    final server = await serve((request) async {
      // Accept the request but never complete the response, the same shape
      // as a tunnel that black-holes every packet after the handshake.
      held.add(request);
    });
    addTearDown(() => server.close(force: true));

    final watch = Stopwatch()..start();
    final ok = await DataPlaneProbe.once(
      'http://127.0.0.1:${server.port}/trace',
      const Duration(milliseconds: 300),
    );
    expect(ok, isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('a refused connection is a miss', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();

    final ok = await DataPlaneProbe.once(
      'http://127.0.0.1:$port/trace',
      const Duration(milliseconds: 500),
    );
    expect(ok, isFalse);
  });

  test('fallback skips a dead endpoint and accepts a live one', () async {
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = dead.port;
    await dead.close();
    final live = await serve((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('loc=NL\n');
      await request.response.close();
    });
    addTearDown(() => live.close(force: true));

    final ok = await DataPlaneProbe.fallback(
      [
        'http://127.0.0.1:$deadPort/trace',
        'http://127.0.0.1:${live.port}/trace',
      ],
      const Duration(seconds: 2),
    );
    expect(ok, isTrue);
  });

  test('fallback fails when every endpoint fails', () async {
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = dead.port;
    await dead.close();

    final ok = await DataPlaneProbe.fallback(
      [
        'http://127.0.0.1:$deadPort/a',
        'http://127.0.0.1:$deadPort/b',
      ],
      const Duration(milliseconds: 500),
    );
    expect(ok, isFalse);
  });
}
