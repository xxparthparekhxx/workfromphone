import 'package:flutter/material.dart';

class MaterialFileIconData {
  final IconData icon;
  final Color color;
  final String? badgeText;
  final Color? badgeColor;

  const MaterialFileIconData({
    required this.icon,
    required this.color,
    this.badgeText,
    this.badgeColor,
  });
}

class MaterialIconTheme {
  // Folder Icons (VS Code Material Icon Theme style)
  static MaterialFileIconData getFolderIcon(
    String folderName, {
    bool isOpen = false,
  }) {
    final name = folderName.toLowerCase().trim();

    // Specific folder matching
    if (name == 'src' ||
        name == 'lib' ||
        name == 'app' ||
        name == 'core' ||
        name == 'sources') {
      return MaterialFileIconData(
        icon: isOpen ? Icons.folder_open : Icons.folder,
        color: const Color(0xFF5DADE2), // Code Blue
      );
    }
    if (name == 'test' ||
        name == 'tests' ||
        name == '__tests__' ||
        name == 'spec' ||
        name == 'testing') {
      return MaterialFileIconData(
        icon: isOpen ? Icons.folder_open : Icons.folder,
        color: const Color(0xFF52BE80), // Test Green
      );
    }
    if (name == 'assets' ||
        name == 'images' ||
        name == 'img' ||
        name == 'icons' ||
        name == 'static' ||
        name == 'public') {
      return MaterialFileIconData(
        icon: isOpen ? Icons.folder_open : Icons.folder,
        color: const Color(0xFFAF7AC5), // Asset Purple
      );
    }
    if (name == 'docs' || name == 'doc' || name == 'documentation') {
      return MaterialFileIconData(
        icon: isOpen ? Icons.folder_open : Icons.folder,
        color: const Color(0xFFF5B041), // Docs Amber
      );
    }
    if (name == 'build' ||
        name == 'dist' ||
        name == 'out' ||
        name == 'target' ||
        name == '.dart_tool') {
      return MaterialFileIconData(
        icon: isOpen ? Icons.folder_open : Icons.folder,
        color: const Color(0xFF85929E), // Build Slate
      );
    }
    if (name == '.git' || name == '.github' || name == '.gitlab') {
      return MaterialFileIconData(
        icon: isOpen ? Icons.folder_open : Icons.folder,
        color: const Color(0xFFE74C3C), // Git Red
      );
    }
    if (name == 'node_modules' ||
        name == 'vendor' ||
        name == '.venv' ||
        name == 'venv') {
      return MaterialFileIconData(
        icon: isOpen ? Icons.folder_open : Icons.folder,
        color: const Color(0xFF48C9B0), // Dependencies Teal
      );
    }
    if (name == 'config' ||
        name == 'configs' ||
        name == '.vscode' ||
        name == '.idea' ||
        name == 'settings') {
      return MaterialFileIconData(
        icon: isOpen ? Icons.folder_open : Icons.folder,
        color: const Color(0xFF7F8C8D), // Config Grey
      );
    }
    if (name == 'backend' || name == 'server' || name == 'api') {
      return MaterialFileIconData(
        icon: isOpen ? Icons.folder_open : Icons.folder,
        color: const Color(0xFF5499C7), // Server Blue
      );
    }

    // Default Material Folder
    return MaterialFileIconData(
      icon: isOpen ? Icons.folder_open : Icons.folder,
      color: const Color(0xFFF4D03F), // Material Folder Yellow/Amber
    );
  }

  // File Icons (VS Code Material Icon Theme style)
  static MaterialFileIconData getFileIcon(String fileName) {
    final lower = fileName.toLowerCase().trim();

    // Exact filename matching
    if (lower == 'pubspec.yaml' || lower == 'pubspec.yml') {
      return const MaterialFileIconData(
        icon: Icons.flutter_dash,
        color: Color(0xFF02569B),
        badgeText: 'FL',
        badgeColor: Color(0xFF0175C2),
      );
    }
    if (lower == 'package.json') {
      return const MaterialFileIconData(
        icon: Icons.data_object,
        color: Color(0xFF83CD29), // Node Green
        badgeText: 'JS',
        badgeColor: Color(0xFF83CD29),
      );
    }
    if (lower == 'cargo.toml') {
      return const MaterialFileIconData(
        icon: Icons.settings,
        color: Color(0xFFDEA584), // Rust Brown
        badgeText: 'RS',
        badgeColor: Color(0xFFDEA584),
      );
    }
    if (lower == 'dockerfile' || lower.startsWith('docker-compose')) {
      return const MaterialFileIconData(
        icon: Icons.directions_boat,
        color: Color(0xFF2496ED), // Docker Blue
      );
    }
    if (lower == '.gitignore' ||
        lower == '.gitattributes' ||
        lower == '.gitmodules') {
      return const MaterialFileIconData(
        icon: Icons.fork_right,
        color: Color(0xFFF05032), // Git Orange
      );
    }
    if (lower == 'readme.md' || lower == 'readme' || lower == 'changelog.md') {
      return const MaterialFileIconData(
        icon: Icons.menu_book,
        color: Color(0xFF42A5F5), // Readme Blue
      );
    }
    if (lower == 'license' || lower == 'license.md' || lower == 'license.txt') {
      return const MaterialFileIconData(
        icon: Icons.verified_user_outlined,
        color: Color(0xFFF1C40F), // Gold
      );
    }
    if (lower.endsWith('.lock') ||
        lower == 'pubspec.lock' ||
        lower == 'package-lock.json' ||
        lower == 'poetry.lock' ||
        lower == 'yarn.lock') {
      return const MaterialFileIconData(
        icon: Icons.lock_outline,
        color: Color(0xFF95A5A6), // Lock Slate
      );
    }

    // Extension-based matching
    final ext = lower.contains('.') ? lower.split('.').last : '';

    switch (ext) {
      // Flutter / Dart
      case 'dart':
        return const MaterialFileIconData(
          icon: Icons.flutter_dash,
          color: Color(0xFF0175C2), // Dart Blue
        );

      // Python
      case 'py':
      case 'pyw':
      case 'ipynb':
        return const MaterialFileIconData(
          icon: Icons.terminal,
          color: Color(0xFF3776AB), // Python Blue
          badgeText: 'PY',
          badgeColor: Color(0xFFFFD43B),
        );

      // JavaScript
      case 'js':
      case 'mjs':
      case 'cjs':
        return const MaterialFileIconData(
          icon: Icons.javascript,
          color: Color(0xFFF7DF1E), // JS Yellow
        );

      // TypeScript
      case 'ts':
        return const MaterialFileIconData(
          icon: Icons.code,
          color: Color(0xFF3178C6), // TS Blue
          badgeText: 'TS',
          badgeColor: Color(0xFF3178C6),
        );
      case 'tsx':
      case 'jsx':
        return const MaterialFileIconData(
          icon: Icons.code,
          color: Color(0xFF61DAFB), // React Cyan
          badgeText: '⚛',
          badgeColor: Color(0xFF61DAFB),
        );

      // JSON & Configs
      case 'json':
      case 'json5':
      case 'jsonl':
        return const MaterialFileIconData(
          icon: Icons.data_object,
          color: Color(0xFFF1C40F), // JSON Yellow
        );
      case 'yaml':
      case 'yml':
        return const MaterialFileIconData(
          icon: Icons.tune,
          color: Color(0xFFE74C3C), // YAML Red
        );
      case 'toml':
      case 'ini':
      case 'conf':
      case 'config':
      case 'env':
        return const MaterialFileIconData(
          icon: Icons.settings_outlined,
          color: Color(0xFF95A5A6), // Config Grey
        );

      // Markdown & Documentation
      case 'md':
      case 'markdown':
        return const MaterialFileIconData(
          icon: Icons.article_outlined,
          color: Color(0xFF42A5F5), // Markdown Blue
        );
      case 'txt':
      case 'log':
        return const MaterialFileIconData(
          icon: Icons.description_outlined,
          color: Color(0xFFBDC3C7), // Text Slate
        );
      case 'pdf':
        return const MaterialFileIconData(
          icon: Icons.picture_as_pdf_outlined,
          color: Color(0xFFE74C3C), // PDF Red
        );

      // Web (HTML, CSS)
      case 'html':
      case 'htm':
        return const MaterialFileIconData(
          icon: Icons.html,
          color: Color(0xFFE44D26), // HTML5 Orange
        );
      case 'css':
        return const MaterialFileIconData(
          icon: Icons.css,
          color: Color(0xFF264DE4), // CSS3 Blue
        );
      case 'scss':
      case 'sass':
      case 'less':
        return const MaterialFileIconData(
          icon: Icons.style,
          color: Color(0xFFCF649A), // Sass Pink
        );

      // Rust
      case 'rs':
        return const MaterialFileIconData(
          icon: Icons.memory,
          color: Color(0xFFDEA584), // Rust
          badgeText: 'RS',
          badgeColor: Color(0xFFDEA584),
        );

      // Go
      case 'go':
        return const MaterialFileIconData(
          icon: Icons.code,
          color: Color(0xFF00ADD8), // Go Cyan
          badgeText: 'GO',
          badgeColor: Color(0xFF00ADD8),
        );

      // Java & Kotlin
      case 'java':
        return const MaterialFileIconData(
          icon: Icons.coffee,
          color: Color(0xFFE76F51), // Java Red
        );
      case 'kt':
      case 'kts':
        return const MaterialFileIconData(
          icon: Icons.code,
          color: Color(0xFF7F52FF), // Kotlin Purple
          badgeText: 'KT',
          badgeColor: Color(0xFF7F52FF),
        );

      // C & C++
      case 'c':
      case 'h':
        return const MaterialFileIconData(
          icon: Icons.code,
          color: Color(0xFF555555), // C Grey
          badgeText: 'C',
          badgeColor: Color(0xFF555555),
        );
      case 'cpp':
      case 'hpp':
      case 'cc':
      case 'cxx':
        return const MaterialFileIconData(
          icon: Icons.code,
          color: Color(0xFF00599C), // C++ Blue
          badgeText: 'C++',
          badgeColor: Color(0xFF00599C),
        );

      // Shell
      case 'sh':
      case 'bash':
      case 'zsh':
        return const MaterialFileIconData(
          icon: Icons.terminal,
          color: Color(0xFF4EAA25), // Shell Green
        );

      // Database
      case 'sql':
      case 'sqlite':
      case 'db':
        return const MaterialFileIconData(
          icon: Icons.storage,
          color: Color(0xFFE67E22), // DB Orange
        );

      // Media / Images
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'ico':
        return const MaterialFileIconData(
          icon: Icons.image_outlined,
          color: Color(0xFF26A69A), // Image Teal
        );
      case 'svg':
        return const MaterialFileIconData(
          icon: Icons.polyline,
          color: Color(0xFFFFB300), // SVG Gold
        );

      // Archives
      case 'zip':
      case 'tar':
      case 'gz':
      case 'rar':
      case '7z':
        return const MaterialFileIconData(
          icon: Icons.folder_zip_outlined,
          color: Color(0xFFE67E22), // Archive Orange
        );

      default:
        return const MaterialFileIconData(
          icon: Icons.insert_drive_file_outlined,
          color: Color(0xFF90A4AE), // Default Grey
        );
    }
  }
}
