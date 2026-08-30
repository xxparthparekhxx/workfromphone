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
}
