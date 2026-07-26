import 'package:flutter/material.dart';
import '../models/user_role.dart';
import '../services/orchestrator_service.dart';
import '../services/role_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/status_pill.dart';
import 'home_shell.dart';
import 'knowledge_capture/knowledge_capture_screen.dart';
import 'lessons_learned/lessons_learned_timeline_screen.dart';
import 'technician/chat_screen.dart';
import 'upload_document_screen.dart';

class DevHomeScreen extends StatelessWidget {
  const DevHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AtlasAI — Dev Menu'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const _StatusCard(),
            const SizedBox(height: AppSpacing.lg),

            _MenuTile(
              icon: Icons.chat_bubble_outline,
              title: 'Knowledge Agent Chat',
              subtitle: 'Skip auth — go straight to the technician chat',
              onTap: () {
                // CHANGE: this dev shortcut skips AuthGate entirely, so
                // there's no RoleScope ancestor set up for it the way
                // there is for the real login flow. ChatScreen's AppBar
                // now includes RoleSwitcher, which calls
                // RoleScope.of(context) — without wrapping this route
                // in its own RoleScope, that call has no ancestor to
                // find and throws. This wraps a standalone
                // RoleController seeded to technician around the
                // screen, same as the three dashboard tiles below.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoleScope(
                      controller: RoleController(UserRole.technician),
                      child: const ChatScreen(userRole: 'technician'),
                    ),
                  ),
                );
              },
            ),

            _MenuTile(
              icon: Icons.upload_file,
              title: 'Upload Document',
              subtitle: 'Ingest a PDF into the knowledge base',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UploadDocumentScreen(),
                  ),
                );
              },
            ),

            _MenuTile(
              icon: Icons.timeline_outlined,
              title: 'Lessons Learned Timeline',
              subtitle: 'Day 5 — recurring failure patterns',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const LessonsLearnedTimelineScreen(),
                  ),
                );
              },
            ),

            _MenuTile(
              icon: Icons.record_voice_over_outlined,
              title: 'Knowledge Capture',
              subtitle: 'Day 5 — guided voice interview',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const KnowledgeCaptureScreen(),
                  ),
                );
              },
            ),

            _MenuTile(
              icon: Icons.dashboard_outlined,
              title: 'Engineer Dashboard',
              subtitle: 'Preview Engineer role',
              onTap: () {
                // CHANGE: HomeShell no longer takes a `role` param —
                // it reads the live role from RoleScope instead (see
                // home_shell.dart). This dev shortcut bypasses
                // AuthGate (which is normally what creates the
                // RoleScope), so it needs to create its own
                // standalone one, seeded to the role this tile is
                // meant to preview.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoleScope(
                      controller: RoleController(UserRole.engineer),
                      child: const HomeShell(),
                    ),
                  ),
                );
              },
            ),

            _MenuTile(
              icon: Icons.dashboard_outlined,
              title: 'Manager Dashboard',
              subtitle: 'Preview Plant Manager role',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoleScope(
                      controller: RoleController(UserRole.manager),
                      child: const HomeShell(),
                    ),
                  ),
                );
              },
            ),

            _MenuTile(
              icon: Icons.dashboard_outlined,
              title: 'Auditor Dashboard',
              subtitle: 'Preview Auditor role',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoleScope(
                      controller: RoleController(UserRole.auditor),
                      child: const HomeShell(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) {
    final orchestrator = OrchestratorService();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backend Status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),

            const StatusPill(
              state: StatusPillState.success,
              loadingText: '',
              successText: 'Firebase connected',
              errorText: '',
            ),

            const SizedBox(height: 8),

            FutureBuilder<bool>(
              future: orchestrator.ping(),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const StatusPill(
                    state: StatusPillState.loading,
                    loadingText: 'Pinging backend...',
                    successText: '',
                    errorText: '',
                  );
                }

                final ok = snapshot.data ?? false;

                return StatusPill(
                  state: ok
                      ? StatusPillState.success
                      : StatusPillState.error,
                  loadingText: '',
                  successText: 'Backend reachable',
                  errorText: 'Backend unreachable',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}