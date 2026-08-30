import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import 'package:workfromphone/utils/model_provider_logos.dart';

/// Fetches provider logos once per URL and keeps the bytes for the session.
///
/// The bytes are validated before any decoder sees them. Handing an error page
/// to `flutter_svg` makes it throw `Invalid SVG data` from inside its parser,
/// which surfaces as an uncaught async error rather than reaching a widget's
/// `errorBuilder`, so a captive portal or a moved asset would take the app
/// down instead of falling back. Validating here keeps every failure — offline,
/// non-200, wrong type, non-SVG body — on the same quiet path: a null result,
/// which the caller renders as a monogram.
class ModelLogoCache {
  ModelLogoCache._();

  static final Map<String, Future<Uint8List?>> _requests =
      <String, Future<Uint8List?>>{};

  /// Replaces the HTTP client used to fetch logos. For tests.
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  @visibleForTesting
  static void reset() => _requests.clear();

  static Future<Uint8List?> load(ModelProviderLogo logo) {
    return _requests.putIfAbsent(logo.url, () => _fetch(logo));
  }

  static Future<Uint8List?> _fetch(ModelProviderLogo logo) async {
    final client = clientFactory();
    try {
      final response = await client
          .get(Uri.parse(logo.url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (!contentType.startsWith('image/')) return null;

      final bytes = response.bodyBytes;
      if (bytes.isEmpty) return null;
      if (logo.isSvg && !_looksLikeSvg(bytes)) return null;
      return bytes;
    } catch (_) {
      // Offline, DNS failure, timeout, malformed URL: all fall back.
      return null;
    } finally {
      client.close();
    }
  }

  /// Whether [bytes] open like an SVG document rather than, say, the HTML of
  /// an error page served with an image content type.
  static bool _looksLikeSvg(Uint8List bytes) {
    final head = String.fromCharCodes(bytes.take(512)).trimLeft().toLowerCase();
    return head.startsWith('<svg') ||
        (head.startsWith('<?xml') && head.contains('<svg'));
  }
}

/// The provider logo for a model, falling back to a monogram.
///
/// The monogram is shown while the logo loads and kept if it never arrives, so
/// providers with no published logo and providers that simply failed to load
/// look the same and the list stays visually uniform.
class ModelProviderAvatar extends StatefulWidget {
  const ModelProviderAvatar({super.key, required this.modelId, this.size = 28});

  final String modelId;
  final double size;

  @override
  State<ModelProviderAvatar> createState() => _ModelProviderAvatarState();
}

class _ModelProviderAvatarState extends State<ModelProviderAvatar> {
  ModelProviderLogo? _logo;
  Future<Uint8List?>? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ModelProviderAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelId != widget.modelId) _resolve();
  }

  void _resolve() {
    final logo = providerLogo(widget.modelId);
    _logo = logo;
    _bytes = logo == null ? null : ModelLogoCache.load(logo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monogram = _Monogram(modelId: widget.modelId, size: widget.size);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.size * 0.28),
        child: Container(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          padding: EdgeInsets.all(widget.size * 0.14),
          child: _bytes == null
              ? monogram
              : FutureBuilder<Uint8List?>(
                  future: _bytes,
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes == null) return monogram;
                    return _image(context, bytes, monogram);
                  },
                ),
        ),
      ),
    );
  }

  Widget _image(BuildContext context, Uint8List bytes, Widget monogram) {
    final theme = Theme.of(context);
    final logo = _logo!;

    if (!logo.isSvg) {
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => monogram,
      );
    }

    return SvgPicture.memory(
      bytes,
      fit: BoxFit.contain,
      // Only artwork carrying no colour of its own is tinted: a black-only
      // mark is invisible on a dark background, while tinting a brand's real
      // colours would flatten them into a silhouette.
      colorFilter: logo.monochrome
          ? ColorFilter.mode(theme.colorScheme.onSurface, BlendMode.srcIn)
          : null,
      placeholderBuilder: (context) => monogram,
      errorBuilder: (context, error, stackTrace) => monogram,
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.modelId, required this.size});

  final String modelId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          providerMonogram(modelId),
          style: TextStyle(
            color: providerAccent(modelId, theme.brightness),
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1,
          ),
        ),
      ),
    );
  }
}
