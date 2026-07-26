import 'package:flutter/material.dart';
import 'chat_screen.dart';

/// Day 3: technician's copilot is now the live Knowledge Agent chat,
/// replacing the Day 1 stub. Voice-first Q&A per the plan.
class TechnicianHome extends StatelessWidget {
  const TechnicianHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const ChatScreen(userRole: 'technician');
  }
}