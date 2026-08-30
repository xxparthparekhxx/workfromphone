import 'package:flutter/material.dart';
import 'package:workfromphone/utils/material_icon_theme.dart';

class MaterialFileIcon extends StatelessWidget {
  final String name;
  final bool isDir;
  final bool isOpen;
  final double size;

  const MaterialFileIcon({
    super.key,
    required this.name,
    this.isDir = false,
    this.isOpen = false,
    this.size = 22.0,
  });

  @override
  Widget build(BuildContext context) {
    final iconData = isDir
        ? MaterialIconTheme.getFolderIcon(name, isOpen: isOpen)
        : MaterialIconTheme.getFileIcon(name);

    if (iconData.badgeText == null) {
      return Icon(iconData.icon, size: size, color: iconData.color);
    }

    return SizedBox(
      width: size + 4,
      height: size + 4,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(iconData.icon, size: size, color: iconData.color),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 2.5,
                vertical: 0.5,
              ),
              decoration: BoxDecoration(
                color: iconData.badgeColor ?? iconData.color,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.black, width: 0.5),
              ),
              child: Text(
                iconData.badgeText!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 7.5,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
