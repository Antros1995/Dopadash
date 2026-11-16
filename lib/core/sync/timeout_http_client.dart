import 'dart:async';
import 'package:http/http.dart' as http;

/// Bounds headers and response-body waits so a lost connection cannot hold
/// token refreshes or controller queues open indefinitely.
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient(this.inner, {this.timeout = const Duration(seconds: 30)});
  final http.Client inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request).timeout(timeout);
    return http.StreamedResponse(
      response.stream.timeout(
        timeout,
        onTimeout: (sink) {
          sink.addError(TimeoutException('Response body timed out', timeout));
          sink.close();
        },
      ),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => inner.close();
}
