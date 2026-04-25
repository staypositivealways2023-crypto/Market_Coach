import 'package:flutter/material.dart';

import '../../features/jarvis_chat/presentation/jarvis_chat_screen.dart';
import '../learn/learn_screen.dart';

/// Coach tab — two sub-tabs:
///   • Learn  – lesson library (LearnScreen embedded without its own AppBar)
///   • Ask    – Jarvis text + voice conversation (JarvisChatScreen)
class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text(
                'Coach',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.menu_book_outlined, size: 18),
                text: 'Learn',
                iconMargin: EdgeInsets.only(bottom: 2),
              ),
              Tab(
                icon: Icon(Icons.chat_bubble_outline_rounded, size: 18),
                text: 'Ask',
                iconMargin: EdgeInsets.only(bottom: 2),
              ),
            ],
            indicatorColor: Color(0xFF06B6D4),
            indicatorWeight: 2,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            dividerColor: Colors.transparent,
          ),
        ),
        body: const TabBarView(
          children: [
            LearnScreen(),
            JarvisChatScreen(showAppBar: false),
          ],
        ),
      ),
    );
  }
}
