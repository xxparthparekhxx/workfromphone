import 'package:flutter_test/flutter_test.dart';
import 'package:workfromphone/models/llm_config.dart';
import 'package:workfromphone/services/api_service.dart';

void main() {
  group('LLMConfig secret serialization', () {
    test('toJson excludes secrets by default', () {
      const config = LLMConfig(apiKey: 'sk-secret', backendAccessToken: 'tok');
      final plain = config.toJson();
      expect(plain.containsKey('api_key'), isFalse);
      expect(plain.containsKey('backend_access_token'), isFalse);
      expect(plain['model'], isNotEmpty);
    });

    test('toApiJson includes secrets for backend payloads', () {
      const config = LLMConfig(apiKey: 'sk-secret', backendAccessToken: 'tok');
      final api = config.toApiJson();
      expect(api['api_key'], 'sk-secret');
      expect(api['backend_access_token'], 'tok');
    });
  });

  group('ApiService URL helpers', () {
    test('isCleartextUrl flags http and schemaless input', () {
      expect(ApiService.isCleartextUrl('http://192.168.1.50:8000'), isTrue);
      expect(ApiService.isCleartextUrl('192.168.1.50:8000'), isTrue);
      expect(ApiService.isCleartextUrl('ws://host:8000'), isTrue);
      expect(ApiService.isCleartextUrl('https://example.com'), isFalse);
      expect(ApiService.isCleartextUrl('wss://example.com/ws'), isFalse);
    });

    test('normalizeBackendUrl adds an explicit scheme', () {
      expect(
        ApiService.normalizeBackendUrl('192.168.1.50:8000'),
        'http://192.168.1.50:8000',
      );
      expect(
        ApiService.normalizeBackendUrl('https://example.com/'),
        'https://example.com',
      );
    });

    test('decodeErrorDetail prefers server detail bodies', () {
      expect(
        ApiService.decodeErrorDetail('{"detail":"Rate limit exceeded"}', 429),
        'Rate limit exceeded',
      );
      expect(
        ApiService.decodeErrorDetail('{"error":{"message":"bad key"}}', 401),
        'bad key',
      );
      expect(ApiService.decodeErrorDetail('not json', 500), 'HTTP 500');
    });

    test('ApiException exposes typed flags', () {
      expect(const ApiException('x', statusCode: 401).isUnauthorized, isTrue);
      expect(const ApiException('x', statusCode: 429).isRateLimited, isTrue);
      expect(
        const ApiException('x', statusCode: 413).isPayloadTooLarge,
        isTrue,
      );
      expect(const ApiException('x', statusCode: 200).isUnauthorized, isFalse);
    });
  });

  group('ApiService token scoping', () {
    test('headersFor does not mutate the global token', () {
      ApiService.configureAccessToken(
        'global-token',
        backendUrl: 'http://127.0.0.1:8000',
      );
      final other = Uri.parse('http://192.168.1.50:8000/api/v1/search');
      final scoped = ApiService.headersFor(
        token: 'other-token',
        backendUrl: 'http://192.168.1.50:8000',
        uri: other,
        json: true,
      );
      expect(scoped['Authorization'], 'Bearer other-token');

      // A token scoped to another origin is never attached.
      final foreign = Uri.parse('http://evil.example/api/v1/search');
      final blocked = ApiService.headersFor(
        token: 'other-token',
        backendUrl: 'http://192.168.1.50:8000',
        uri: foreign,
        json: true,
      );
      expect(blocked.containsKey('Authorization'), isFalse);

      // The global token still targets its own origin.
      final own = Uri.parse('http://127.0.0.1:8000/api/v1/health');
      expect(
        ApiService.headers(uri: own)['Authorization'],
        'Bearer global-token',
      );
      ApiService.configureAccessToken('', backendUrl: '');
    });

    test('preview navigation stays on the proxied origin and entry', () {
      const backend = 'http://127.0.0.1:8000';
      expect(
        ApiService.isPreviewNavigationAllowed(
          backendUrl: backend,
          entryId: 'prev_1',
          url: 'http://127.0.0.1:8000/api/v1/preview/proxy/prev_1/index.html',
        ),
        isTrue,
      );
      // Another entry id on the same origin is not allowed.
      expect(
        ApiService.isPreviewNavigationAllowed(
          backendUrl: backend,
          entryId: 'prev_1',
          url: 'http://127.0.0.1:8000/api/v1/preview/proxy/prev_2/',
        ),
        isFalse,
      );
      // Off-origin navigation is never allowed (token exfiltration guard).
      expect(
        ApiService.isPreviewNavigationAllowed(
          backendUrl: backend,
          entryId: 'prev_1',
          url: 'http://evil.example/api/v1/preview/proxy/prev_1/',
        ),
        isFalse,
      );
    });
  });
}
