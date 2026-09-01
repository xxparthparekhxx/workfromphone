import 'package:flutter_test/flutter_test.dart';
import 'package:workfromphone/services/api_service.dart';

void main() {
  test('backend token is sent only to its configured origin', () {
    ApiService.configureAccessToken(
      'secret-token',
      backendUrl: 'https://trusted.example.com',
    );

    expect(
      ApiService.headers(uri: Uri.parse('https://trusted.example.com/api')),
      containsPair('Authorization', 'Bearer secret-token'),
    );
    expect(
      ApiService.headers(uri: Uri.parse('https://evil.example.com/api')),
      isNot(contains('Authorization')),
    );
    expect(
      ApiService.headers(
        uri: Uri.parse('https://trusted.example.com:8443/api'),
      ),
      isNot(contains('Authorization')),
    );

    ApiService.configureAccessToken('');
  });

  test('websocket token is sent only to the configured backend origin', () {
    ApiService.configureAccessToken(
      'secret-token',
      backendUrl: 'https://trusted.example.com',
    );

    expect(
      ApiService.webSocketAuthHeaders(
        Uri.parse('wss://trusted.example.com/api/v1/terminal/ws'),
        'secret-token',
      ),
      containsPair('Authorization', 'Bearer secret-token'),
    );
    expect(
      ApiService.webSocketAuthHeaders(
        Uri.parse('wss://evil.example.com/api/v1/terminal/ws'),
        'secret-token',
      ),
      isNot(contains('Authorization')),
    );
    expect(
      ApiService.webSocketAuthHeaders(
        Uri.parse('wss://trusted.example.com:8443/api/v1/terminal/ws'),
        'secret-token',
      ),
      isNot(contains('Authorization')),
    );

    ApiService.configureAccessToken('');
  });

  test('websocket token is withheld once the backend origin changes', () {
    ApiService.configureAccessToken(
      'secret-token',
      backendUrl: 'http://10.0.0.4:8000',
    );
    final staleUri = Uri.parse('ws://10.0.0.4:8000/api/v1/system/ws');
    expect(
      ApiService.webSocketAuthHeaders(staleUri, 'secret-token'),
      containsPair('Authorization', 'Bearer secret-token'),
    );

    // A session left over from the previous backend must not keep sending it.
    ApiService.configureAccessToken(
      'other-token',
      backendUrl: 'http://10.0.0.9:8000',
    );
    expect(
      ApiService.webSocketAuthHeaders(staleUri, 'secret-token'),
      isNot(contains('Authorization')),
    );

    ApiService.configureAccessToken('');
  });

  test('no token is sent when no backend origin is configured', () {
    ApiService.configureAccessToken('secret-token');
    expect(
      ApiService.webSocketAuthHeaders(
        Uri.parse('ws://localhost:8000/api/v1/system/ws'),
        'secret-token',
      ),
      isNot(contains('Authorization')),
    );

    ApiService.configureAccessToken('');
  });

  test('an unusable backend URL never authenticates anything', () {
    // Must not throw: a schemeless URL has no comparable origin.
    ApiService.configureAccessToken('secret-token', backendUrl: 'host:8000');
    expect(
      ApiService.webSocketAuthHeaders(
        Uri.parse('ws://host:8000/api/v1/system/ws'),
        'secret-token',
      ),
      isNot(contains('Authorization')),
    );
    expect(
      ApiService.headers(uri: Uri.parse('http://host:8000/api')),
      isNot(contains('Authorization')),
    );

    ApiService.configureAccessToken('');
  });

  test('preview navigation stays on the backend proxy origin and entry', () {
    expect(
      ApiService.isPreviewNavigationAllowed(
        backendUrl: 'https://trusted.example.com',
        entryId: 'prev_1',
        url: 'https://trusted.example.com/api/v1/preview/proxy/prev_1/app',
      ),
      isTrue,
    );
    expect(
      ApiService.isPreviewNavigationAllowed(
        backendUrl: 'https://trusted.example.com',
        entryId: 'prev_1',
        url: 'https://evil.example.com/api/v1/preview/proxy/prev_1/',
      ),
      isFalse,
    );
    expect(
      ApiService.isPreviewNavigationAllowed(
        backendUrl: 'https://trusted.example.com',
        entryId: 'prev_1',
        url: 'https://trusted.example.com/api/v1/fs/browse',
      ),
      isFalse,
    );
    expect(
      ApiService.isPreviewNavigationAllowed(
        backendUrl: 'https://trusted.example.com',
        entryId: 'prev_1',
        url: 'javascript:alert(1)',
      ),
      isFalse,
    );
  });
}
