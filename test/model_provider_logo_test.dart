import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:workfromphone/utils/model_provider_logos.dart';
import 'package:workfromphone/widgets/model_provider_avatar.dart';

/// A minimal but genuinely parseable SVG, so the decoder is exercised for real.
const _svgBody =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<rect width="10" height="10" fill="#123456"/></svg>';

http.Client _client(http.Response Function(http.Request request) handler) {
  return MockClient((request) async => handler(request));
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(ModelLogoCache.reset);
  tearDown(() {
    ModelLogoCache.reset();
    ModelLogoCache.clientFactory = http.Client.new;
  });

  group('providerSlug', () {
    test('takes the author segment of a model id', () {
      expect(providerSlug('anthropic/claude-sonnet-4'), 'anthropic');
      expect(providerSlug('meta-llama/llama-3.3-70b-instruct'), 'meta-llama');
      expect(providerSlug('openai/gpt-4o:extended'), 'openai');
    });

    test('ignores the ~ routing-variant marker', () {
      expect(providerSlug('~openai/gpt-4o'), 'openai');
      expect(
        providerLogo('~openai/gpt-4o')?.url,
        providerLogo('openai/x')?.url,
      );
    });

    test('handles an id with no author segment', () {
      expect(providerSlug('gpt-4o'), 'gpt-4o');
      expect(providerSlug(''), '');
    });
  });

  group('providerLogo', () {
    test('resolves known providers to an OpenRouter icon URL', () {
      expect(
        providerLogo('openai/gpt-4o')?.url,
        'https://openrouter.ai/images/icons/OpenAI.svg',
      );
      // The file name does not follow from the slug: meta-llama is Meta.png.
      expect(
        providerLogo('meta-llama/llama-3.3-70b')?.url,
        'https://openrouter.ai/images/icons/Meta.png',
      );
    });

    test('marks only colourless artwork as monochrome', () {
      // OpenAI's mark has no fill and renders black; Anthropic ships its own
      // colours and must never be tinted.
      expect(providerLogo('openai/gpt-4o')?.monochrome, isTrue);
      expect(providerLogo('anthropic/claude-sonnet-4')?.monochrome, isFalse);
      expect(providerLogo('google/gemini-2.5-pro')?.monochrome, isFalse);
    });

    test('reports the artwork format', () {
      expect(providerLogo('openai/gpt-4o')?.isSvg, isTrue);
      expect(providerLogo('qwen/qwen3')?.isSvg, isFalse);
    });

    test('returns null for a provider with no published logo', () {
      expect(providerLogo('sao10k/some-model'), isNull);
      expect(providerLogo('a-brand-new-lab/model-1'), isNull);
    });
  });

  group('providerMonogram', () {
    test('uses initials of a hyphenated author', () {
      expect(providerMonogram('meta-llama/llama-3'), 'ML');
      expect(providerMonogram('aion-labs/aion-1'), 'AL');
    });

    test('uses the first two letters of a single-word author', () {
      expect(providerMonogram('nvidia/nemotron'), 'NV');
      expect(providerMonogram('x/y'), 'X');
    });

    test('never returns empty', () {
      expect(providerMonogram(''), '?');
    });
  });

  test('providerAccent is stable per provider and varies between them', () {
    final a = providerAccent('nvidia/nemotron', Brightness.dark);
    final b = providerAccent('nvidia/other-model', Brightness.dark);
    final c = providerAccent('sao10k/model', Brightness.dark);
    expect(a, b);
    expect(a, isNot(c));
  });

  group('ModelProviderAvatar', () {
    testWidgets('renders a monogram for a provider with no logo', (
      tester,
    ) async {
      var requested = false;
      ModelLogoCache.clientFactory = () => _client((request) {
        requested = true;
        return http.Response('', 404);
      });

      await _pump(tester, const ModelProviderAvatar(modelId: 'sao10k/model'));

      expect(find.text('SA'), findsOneWidget);
      expect(requested, isFalse, reason: 'no logo means no network call');
    });

    testWidgets('renders the fetched SVG logo', (tester) async {
      ModelLogoCache.clientFactory = () => _client(
        (request) => http.Response(
          _svgBody,
          200,
          headers: {'content-type': 'image/svg+xml'},
        ),
      );

      await _pump(tester, const ModelProviderAvatar(modelId: 'openai/gpt-4o'));

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('OP'), findsNothing);
    });

    testWidgets('tints a monochrome logo but leaves a colour one alone', (
      tester,
    ) async {
      ModelLogoCache.clientFactory = () => _client(
        (request) => http.Response(
          _svgBody,
          200,
          headers: {'content-type': 'image/svg+xml'},
        ),
      );

      await _pump(tester, const ModelProviderAvatar(modelId: 'openai/gpt-4o'));
      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
        isNotNull,
      );

      ModelLogoCache.reset();
      await _pump(
        tester,
        const ModelProviderAvatar(modelId: 'anthropic/claude-sonnet-4'),
      );
      expect(
        tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
        isNull,
      );
    });

    testWidgets('falls back to a monogram when the fetch fails', (
      tester,
    ) async {
      ModelLogoCache.clientFactory = () =>
          _client((request) => http.Response('nope', 500));

      await _pump(tester, const ModelProviderAvatar(modelId: 'openai/gpt-4o'));

      expect(find.text('OP'), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('rejects an error page served as an image', (tester) async {
      // The case that makes flutter_svg throw from inside its parser, where an
      // errorBuilder cannot catch it.
      ModelLogoCache.clientFactory = () => _client(
        (request) => http.Response(
          '<!doctype html><html><body>404</body></html>',
          200,
          headers: {'content-type': 'image/svg+xml'},
        ),
      );

      await _pump(tester, const ModelProviderAvatar(modelId: 'openai/gpt-4o'));

      expect(tester.takeException(), isNull);
      expect(find.text('OP'), findsOneWidget);
    });

    testWidgets('rejects a non-image response', (tester) async {
      ModelLogoCache.clientFactory = () => _client(
        (request) => http.Response(
          _svgBody,
          200,
          headers: {'content-type': 'text/html'},
        ),
      );

      await _pump(tester, const ModelProviderAvatar(modelId: 'openai/gpt-4o'));

      expect(find.text('OP'), findsOneWidget);
    });

    testWidgets('survives the network being unreachable', (tester) async {
      ModelLogoCache.clientFactory = () => _client((request) {
        throw const SocketExceptionStub();
      });

      await _pump(tester, const ModelProviderAvatar(modelId: 'openai/gpt-4o'));

      expect(tester.takeException(), isNull);
      expect(find.text('OP'), findsOneWidget);
    });

    testWidgets('fetches each logo once across many list items', (
      tester,
    ) async {
      var calls = 0;
      ModelLogoCache.clientFactory = () => _client((request) {
        calls++;
        return http.Response(
          _svgBody,
          200,
          headers: {'content-type': 'image/svg+xml'},
        );
      });

      await _pump(
        tester,
        const SizedBox(
          height: 200,
          width: 100,
          child: Column(
            children: [
              ModelProviderAvatar(modelId: 'openai/gpt-4o'),
              ModelProviderAvatar(modelId: 'openai/gpt-4o-mini'),
              ModelProviderAvatar(modelId: 'openai/o3'),
            ],
          ),
        ),
      );

      expect(calls, 1, reason: 'one URL should mean one request');
    });
  });
}

/// Stands in for a connection failure without importing dart:io.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
