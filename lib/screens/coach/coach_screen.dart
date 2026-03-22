import 'package:flutter/material.dart';

import '../learn/learn_screen.dart';
import '../chat/chat_screen.dart';

/// Coach tab — wraps Learn and Chat in a TabBar.
class CoachScreen extends StatelessWidget {
  const CoachScreen({super.key});

  static const _tabs = [
    Tab(text: 'Learn'),
    Tab(text: 'Chat'),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'Coach',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          bottom: TabBar(
            tabs: _tabs,
            indicatorColor: Theme.of(context).colorScheme.primary,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        body: const TabBarView(
          children: [
            LearnScreen(),
            ChatScreen(),
          ],
        ),
      ),
    );
  }
}
