import 'package:flutter/material.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../services/orchestrator_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/explainable_ai_panel.dart';
import '../../widgets/role_switcher.dart';
import '../actions/action_result_screen.dart';
import '../equipment/equipment_timeline_screen.dart';

/// Maintenance Engineer copilot — runs the backend Maintenance Agent
/// against a chosen equipment ID (retrieval over maintenance/incident
/// records, enriched with Knowledge Graph context), and offers RCA
/// report generation via the Action Engine. Replaces the Day 1 stub
/// ("coming Day 5+").
///
/// Mirrors the same request/response pattern already used by
/// AuditorHome for the Compliance Agent: pass `agents:
/// ['maintenance_agent']` explicitly so the orchestrator runs only
/// that agent for this screen, rather than whatever its default
/// keyword-based routing would otherwise pick.
class EngineerHome extends StatefulWidget {
  const EngineerHome({super.key});

  @override
  State<EngineerHome> createState() => _EngineerHomeState();
}

class _EngineerHomeState extends State<EngineerHome> {
  final _orchestrator = OrchestratorService();
  final _equipmentController = TextEditingController();
  final _queryController = TextEditingController();

  bool _checking = false;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void dispose() {
    _equipmentController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _runMaintenanceCheck() async {
    final equipmentId = _equipmentController.text.trim();
    if (equipmentId.isEmpty) return;

    final userQuery = _queryController.text.trim().isNotEmpty
        ? _queryController.text.trim()
        : 'What is the maintenance history for $equipmentId?';

    setState(() {
      _checking = true;
      _error = null;
      _result = null;
    });

    try {
      final response = await _orchestrator.query(
        userQuery,
        userRole: 'engineer',
        equipmentId: equipmentId,
        agents: const ['maintenance_agent'],
      );

      print('===== EngineerHome: response received =====');
      print(response);

      final results = (response['results'] as List?) ?? [];
      print('===== EngineerHome: agents in response =====');
      print(results.map((r) => r['agent']).toList());

      final maintenanceResult = results.firstWhere(
        (r) => r['agent'] == 'maintenance_agent',
        orElse: () => null,
      );

      setState(() => _result = maintenanceResult as Map<String, dynamic>?);
      if (_result == null) {
        setState(() => _error = 'Maintenance Agent did not return a result for this query.');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // FIX: explicit true so this screen's TextFields resize
      // correctly when the keyboard opens instead of the fixed
      // bottom content being pushed/clipped.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Maintenance Engineer'),
        // FIX (corrected): the previous SingleChildScrollView wrap
        // didn't actually fix anything, because AppBar measures
        // `actions` at their natural/unconstrained width before
        // laying out the title — it never hands actions a bounded
        // width to begin with. A SingleChildScrollView only scrolls
        // when its parent constrains it smaller than its content;
        // with no such bound, it just reported its natural width
        // (RoleBadge + RoleSwitcher + logout), which was still wide
        // enough to push the whole AppBar row past the screen edge —
        // exactly the overflow seen in the screenshot. The real fix:
        // wrap it in a ConstrainedBox with an explicit maxWidth, so
        // there's now a genuine bound for the scroll view to scroll
        // within instead of overflowing past it.
        actions: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.62),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: RoleBadge(role: UserRole.engineer),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: RoleSwitcher(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sign out',
                    onPressed: () => AuthService().signOut(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Maintenance History Lookup', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _equipmentController,
              decoration: const InputDecoration(
                labelText: 'Equipment ID',
                hintText: 'e.g. PUMP-04',
                prefixIcon: Icon(Icons.tag),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _queryController,
              decoration: const InputDecoration(
                labelText: 'Question (optional)',
                hintText: 'e.g. What fixed the last vibration issue?',
                prefixIcon: Icon(Icons.help_outline),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // Responsive button layout — matches the fix already
            // applied to AuditorHome, so this screen doesn't overflow
            // on narrow (320-480dp) devices either.
            LayoutBuilder(
              builder: (context, constraints) {
                final checkHistoryButton = FilledButton.icon(
                  onPressed: _checking ? null : _runMaintenanceCheck,
                  icon: _checking
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.history_outlined, size: 18),
                  label: const Text('Check History'),
                );

                final rcaReportButton = OutlinedButton.icon(
                  onPressed: _equipmentController.text.trim().isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ActionResultScreen(
                                actionType: 'rca_report',
                                equipmentId: _equipmentController.text.trim(),
                                userRole: 'engineer',
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.troubleshoot_outlined, size: 18),
                  label: const Text('Generate RCA'),
                );

                const wideBreakpoint = 360.0;

                if (constraints.maxWidth >= wideBreakpoint) {
                  return Row(
                    children: [
                      Expanded(child: checkHistoryButton),
                      const SizedBox(width: 8),
                      Expanded(child: rcaReportButton),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    checkHistoryButton,
                    const SizedBox(height: 8),
                    rcaReportButton,
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Generate Documents', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            // Exposes the Action Engine's maintenance_checklist,
            // inspection_schedule, and preventive_maintenance
            // generation for this equipment. Wrap uses the same
            // "grow, don't overflow" approach as the button rows
            // elsewhere in the app, so these three buttons wrap onto
            // additional lines on narrow phones instead of
            // overflowing.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _equipmentController.text.trim().isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ActionResultScreen(
                                actionType: 'maintenance_checklist',
                                equipmentId: _equipmentController.text.trim(),
                                userRole: 'engineer',
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.checklist_outlined, size: 18),
                  label: const Text('Maintenance Checklist'),
                ),
                OutlinedButton.icon(
                  onPressed: _equipmentController.text.trim().isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ActionResultScreen(
                                actionType: 'inspection_schedule',
                                equipmentId: _equipmentController.text.trim(),
                                userRole: 'engineer',
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.event_note_outlined, size: 18),
                  label: const Text('Inspection Schedule'),
                ),
                OutlinedButton.icon(
                  onPressed: _equipmentController.text.trim().isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ActionResultScreen(
                                actionType: 'preventive_maintenance',
                                equipmentId: _equipmentController.text.trim(),
                                userRole: 'engineer',
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.build_circle_outlined, size: 18),
                  label: const Text('Preventive Maintenance'),
                ),
                OutlinedButton.icon(
                  onPressed: _equipmentController.text.trim().isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EquipmentTimelineScreen(
                                equipmentId: _equipmentController.text.trim(),
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.timeline_outlined, size: 18),
                  label: const Text('Timeline & Health'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            if (_result != null) ...[
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  _result!['answer'] as String? ?? '',
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              ExplainableAiPanel(
                confidence: (_result!['confidence'] as num?)?.toDouble() ?? 0.0,
                sources: List<String>.from(_result!['sources'] ?? const []),
                reasoning: _result!['reasoning'] as String?,
              ),
            ],
          ],
        ),
      ),
    );
  }
}