/// Serve the built Flutter app and local API on one LAN port for phone tests.
/// Use fictional stories only: this local preview has no user authentication.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dartvm.exe scripts/serve_iphone_preview.dart <LAN-IP>',
    );
    exitCode = 2;
    return;
  }
  final host = args.single;
  final build = Directory.fromUri(
    Platform.script.resolve('../mobile/build/web/'),
  );
  if (!File.fromUri(build.uri.resolve('index.html')).existsSync()) {
    stderr.writeln('Build the Flutter web app before starting this preview.');
    exitCode = 2;
    return;
  }

  final backend = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  final server = await HttpServer.bind(InternetAddress(host), 8080);
  stdout.writeln('FinPilot preview: http://$host:8080');
  await for (final request in server) {
    unawaited(_handle(request, build, backend));
  }
}

Future<void> _handle(
  HttpRequest request,
  Directory build,
  HttpClient backend,
) async {
  request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  try {
    if (request.uri.path.startsWith('/api/v1/')) {
      await _proxy(request, backend);
    } else if (request.method == 'GET' || request.method == 'HEAD') {
      await _static(request, build);
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  } catch (_) {
    try {
      request.response.statusCode = HttpStatus.badGateway;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'detail': 'The local preview is unavailable. Please try again.',
        }),
      );
    } catch (_) {
      // A response already in progress cannot be replaced.
    }
    try {
      await request.response.close();
    } catch (_) {
      // The client may have disconnected.
    }
  }
}

Future<void> _proxy(HttpRequest request, HttpClient backend) async {
  if (!{'GET', 'POST', 'PATCH'}.contains(request.method)) {
    request.response.statusCode = HttpStatus.methodNotAllowed;
    await request.response.close();
    return;
  }
  final chunks = <int>[];
  await for (final chunk in request) {
    chunks.addAll(chunk);
    if (chunks.length > 1000000) {
      request.response.statusCode = HttpStatus.requestEntityTooLarge;
      await request.response.close();
      return;
    }
  }
  final target = Uri.parse('http://127.0.0.1:8000${request.uri}');
  final outbound = await backend.openUrl(request.method, target);
  outbound.headers.contentType = ContentType.json;
  if (chunks.isNotEmpty) outbound.add(chunks);
  final incoming = await outbound.close().timeout(const Duration(seconds: 70));
  request.response.statusCode = incoming.statusCode;
  request.response.headers.contentType =
      incoming.headers.contentType ?? ContentType.json;
  await request.response.addStream(
    incoming.timeout(const Duration(seconds: 70)),
  );
  await request.response.close();
}

Future<void> _static(HttpRequest request, Directory build) async {
  final segments = request.uri.pathSegments;
  if (segments.any(
    (part) =>
        part == '..' ||
        part.contains('/') ||
        part.contains('\\') ||
        part.contains(':'),
  )) {
    request.response.statusCode = HttpStatus.badRequest;
    await request.response.close();
    return;
  }
  final relative = segments
      .where((part) => part.isNotEmpty)
      .join(Platform.pathSeparator);
  var file = File('${build.path}${Platform.pathSeparator}$relative');
  if (!file.existsSync() &&
      !relative.split(Platform.pathSeparator).last.contains('.')) {
    file = File.fromUri(build.uri.resolve('index.html'));
  }
  if (!file.existsSync()) {
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
    return;
  }
  request.response.headers.contentType = _contentType(file.path);
  request.response.headers.contentLength = await file.length();
  if (request.method == 'GET') {
    await request.response.addStream(file.openRead());
  }
  await request.response.close();
}

ContentType _contentType(String path) {
  if (path.endsWith('.html')) return ContentType.html;
  if (path.endsWith('.js')) return ContentType('text', 'javascript');
  if (path.endsWith('.css')) return ContentType('text', 'css');
  if (path.endsWith('.json')) return ContentType.json;
  if (path.endsWith('.svg')) return ContentType('image', 'svg+xml');
  if (path.endsWith('.png')) return ContentType('image', 'png');
  if (path.endsWith('.wasm')) return ContentType('application', 'wasm');
  return ContentType.binary;
}
