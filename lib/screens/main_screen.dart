import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/screens/chat/general_chat_screen.dart';
import 'package:workfromphone/screens/projects/projects_screen.dart';
import 'package:workfromphone/screens/settings/settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const ProjectsScreen(),
          GeneralChatScreen(isActive: _currentIndex == 1),
          SettingsScreen(isActive: _currentIndex == 2),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(CupertinoIcons.folder),
            selectedIcon: Icon(CupertinoIcons.folder_fill),
            label: 'Projects',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.sparkles),
            selectedIcon: Icon(CupertinoIcons.sparkles),
            label: 'Assistant',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.settings),
            selectedIcon: Icon(CupertinoIcons.settings_solid),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
