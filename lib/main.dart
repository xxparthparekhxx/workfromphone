import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workfromphone/screens/main_screen.dart';
import 'package:workfromphone/theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The Matrix design system is dark-only (DESIGN.md).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.background,
      ),
      child: MaterialApp(
        title: 'WorkFromPhone',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const MainScreen(),
      ),
    );
  }
}
