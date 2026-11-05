import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:smooth_app/auth/bearer_request.dart';
import 'package:smooth_app/auth/keycloak_config.dart';
import 'package:smooth_app/auth/keycloak_session.dart';

/// Installs the bearer-token hook in front of every `dart:io` HTTP client.
///
/// The Open Food Facts Dart package has no bearer-token parameter on product
/// writes. It still sends `user_id` in the body. This client adds
/// `Authorization: Bearer` on those calls, after refreshing a token that is
/// about to expire. The header is set before the body is written, which is
/// when `dart:io` flushes the request headers.
class BearerHttpOverrides extends HttpOverrides {
  BearerHttpOverrides(this._fallback);

  final HttpOverrides? _fallback;

  static void install() {
    if (HttpOverrides.current is BearerHttpOverrides) {
      return;
    }
    HttpOverrides.global = BearerHttpOverrides(HttpOverrides.current);
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final HttpClient inner =
        _fallback?.createHttpClient(context) ?? super.createHttpClient(context);
    return _BearerHttpClient(inner);
  }
}

class _BearerHttpClient implements HttpClient {
  _BearerHttpClient(this._inner);

  final HttpClient _inner;

  Future<HttpClientRequest> _wrap(Future<HttpClientRequest> future) async {
    final HttpClientRequest request = await future;
    return _BearerRequest(request, request.uri);
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _wrap(_inner.openUrl(method, url));

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _wrap(_inner.open(method, host, port, path));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _wrap(_inner.get(host, port, path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _wrap(_inner.getUrl(url));

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _wrap(_inner.post(host, port, path));

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _wrap(_inner.postUrl(url));

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _wrap(_inner.put(host, port, path));

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _wrap(_inner.putUrl(url));

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _wrap(_inner.delete(host, port, path));

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _wrap(_inner.deleteUrl(url));

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _wrap(_inner.patch(host, port, path));

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _wrap(_inner.patchUrl(url));

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _wrap(_inner.head(host, port, path));

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _wrap(_inner.headUrl(url));

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  bool get autoUncompress => _inner.autoUncompress;

  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration get idleTimeout => _inner.idleTimeout;

  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  String? get userAgent => _inner.userAgent;

  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _inner.badCertificateCallback = callback;

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);
}

class _BearerRequest implements HttpClientRequest {
  _BearerRequest(this._inner, this._requestUri);

  final HttpClientRequest _inner;
  final Uri _requestUri;
  final BytesBuilder _body = BytesBuilder(copy: false);
  bool _sent = false;

  Future<void> _sendBody() async {
    if (_sent) {
      return;
    }
    _sent = true;
    final List<int> bytes = _body.takeBytes();
    // The refresh call itself is a POST to Keycloak. It must not wait on
    // another refresh, or the two requests deadlock.
    if (!KeycloakConfig.isKeycloakHost(_requestUri)) {
      final KeycloakSession session = KeycloakSession.instance;
      final String? userId = session.userId;
      final String? contentType = _inner.headers.contentType?.mimeType;
      final String? existingAuthorization = _inner.headers.value(
        HttpHeaders.authorizationHeader,
      );
      if (userId != null &&
          requestUsesSignedInSession(
            uri: _requestUri,
            contentType: contentType,
            body: bytes,
            userId: userId,
            authorizationHeader: existingAuthorization,
          )) {
        final String? authorization = bearerAuthorizationHeader(
          uri: _requestUri,
          contentType: contentType,
          body: bytes,
          userId: userId,
          accessToken: await session.freshAccessToken(),
          authorizationHeader: existingAuthorization,
        );
        if (authorization != null) {
          _inner.headers.set(HttpHeaders.authorizationHeader, authorization);
        }
      }
    }
    if (bytes.isNotEmpty) {
      _inner.add(bytes);
    }
  }

  @override
  void add(List<int> data) => _body.add(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(_body.add);

  @override
  void write(Object? object) => _body.add(encoding.encode('${object ?? ''}'));

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> flush() async {
    await _sendBody();
    await _inner.flush();
  }

  @override
  Future<HttpClientResponse> close() async {
    await _sendBody();
    return _inner.close();
  }

  @override
  Encoding get encoding => _inner.encoding;

  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  bool get bufferOutput => _inner.bufferOutput;

  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;

  @override
  int get contentLength => _inner.contentLength;

  @override
  set contentLength(int value) => _inner.contentLength = value;

  @override
  bool get followRedirects => _inner.followRedirects;

  @override
  set followRedirects(bool value) => _inner.followRedirects = value;

  @override
  int get maxRedirects => _inner.maxRedirects;

  @override
  set maxRedirects(int value) => _inner.maxRedirects = value;

  @override
  bool get persistentConnection => _inner.persistentConnection;

  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  Future<HttpClientResponse> get done => _inner.done;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  @override
  String get method => _inner.method;

  @override
  Uri get uri => _inner.uri;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      _inner.abort(exception, stackTrace);
}
