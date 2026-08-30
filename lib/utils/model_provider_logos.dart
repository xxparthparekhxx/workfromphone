/// Provider logos for OpenRouter model identifiers.
///
/// OpenRouter serves author logos from `/images/icons/`, but the file name
/// cannot be derived from the model id: the extension varies (`.svg`, `.png`)
/// and the capitalisation is per-brand, so `openai` is `OpenAI.svg` while
/// `meta-llama` is `Meta.png`. The names below were resolved against the live
/// endpoint; the models API itself exposes no logo field. Anything not listed
/// falls back to a generated monogram, which is also what happens when a name
/// stops resolving, so an unknown or renamed provider degrades quietly.
library;

import 'package:flutter/material.dart';

const String _iconBase = 'https://openrouter.ai/images/icons';

class _Logo {
  const _Logo(this.file, {this.monochrome = false});

  final String file;

  /// True when the artwork carries no colour of its own and renders as solid
  /// black, which is invisible against a dark background unless it is tinted.
  final bool monochrome;
}

const Map<String, _Logo> _logos = <String, _Logo>{
  'amazon': _Logo('Bedrock.svg'),
  'anthropic': _Logo('Anthropic.svg'),
  'cohere': _Logo('Cohere.png'),
  'deepseek': _Logo('DeepSeek.png'),
  'dots-studio': _Logo('DotsStudio.png'),
  'google': _Logo('GoogleGemini.svg'),
  'ibm-granite': _Logo('IBMGranite.svg', monochrome: true),
  'inception': _Logo('Inception.svg', monochrome: true),
  'kwaipilot': _Logo('Kwaipilot.png'),
  'meta': _Logo('Meta.png'),
  'meta-llama': _Logo('Meta.png'),
  'microsoft': _Logo('Microsoft.svg'),
  'mistralai': _Logo('Mistral.png'),
  'moonshotai': _Logo('MoonshotAI.png'),
  'nex-agi': _Logo('NexAGI.svg', monochrome: true),
  'openai': _Logo('OpenAI.svg', monochrome: true),
  'openrouter': _Logo('openrouter-glyph-light.svg'),
  'perplexity': _Logo('Perplexity.svg'),
  'poolside': _Logo('poolside-logomark-solid-color.svg'),
  'qwen': _Logo('Qwen.png'),
  'tencent': _Logo('Tencent.png'),
  'thedrummer': _Logo('TheDrummer.png'),
};

/// A provider logo resolved from a model id, or null when none is known.
class ModelProviderLogo {
  const ModelProviderLogo({required this.url, required this.monochrome});

  final String url;

  /// Whether the caller should tint the artwork to the current foreground
  /// colour. Full-colour brand marks must never be tinted.
  final bool monochrome;

  bool get isSvg => url.endsWith('.svg');
}

/// The author segment of an OpenRouter model id, e.g. `anthropic` for
/// `anthropic/claude-sonnet-4`.
///
/// A leading `~` marks an OpenRouter routing variant of the same brand and is
/// not part of the author name.
String providerSlug(String modelId) {
  final withoutVariant = modelId.startsWith('~')
      ? modelId.substring(1)
      : modelId;
  final separator = withoutVariant.indexOf('/');
  final slug = separator == -1
      ? withoutVariant
      : withoutVariant.substring(0, separator);
  return slug.trim().toLowerCase();
}

/// The logo for [modelId], or null when the provider has none published.
ModelProviderLogo? providerLogo(String modelId) {
  final logo = _logos[providerSlug(modelId)];
  if (logo == null) return null;
  return ModelProviderLogo(
    url: '$_iconBase/${logo.file}',
    monochrome: logo.monochrome,
  );
}

/// Up to two letters standing in for a provider that publishes no logo.
String providerMonogram(String modelId) {
  final slug = providerSlug(modelId);
  if (slug.isEmpty) return '?';
  final words = slug
      .split(RegExp(r'[-_.]'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.length >= 2) {
    return (words[0][0] + words[1][0]).toUpperCase();
  }
  final word = words.isEmpty ? slug : words.first;
  return word.characters.take(2).toString().toUpperCase();
}

/// A stable accent colour for a provider without a logo.
///
/// Derived from the slug so a given provider always gets the same colour, and
/// kept at a fixed saturation and lightness so every monogram sits legibly on
/// the surface behind it.
Color providerAccent(String modelId, Brightness brightness) {
  final slug = providerSlug(modelId);
  var hash = 0;
  for (final unit in slug.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(
    1,
    (hash % 360).toDouble(),
    0.45,
    brightness == Brightness.dark ? 0.62 : 0.42,
  ).toColor();
}
