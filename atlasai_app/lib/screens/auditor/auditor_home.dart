import 'package:flutter/material.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../services/orchestrator_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/explainable_ai_panel.dart';
import '../../widgets/role_switcher.dart';
import '../actions/action_result_screen.dart';

/// Day 6: Compliance Status view — runs the real backend Compliance
/// Agent (Day 6: rule-based deviation checking, no longer a stub)
/// against a chosen equipment ID, and offers full Audit Report
/// generation via the Action Engine. Replaces the Day 1 stub.
class AuditorHome extends StatefulWidget {
  const AuditorHome({super.key});

  @override
  State<AuditorHome> createState() => _AuditorHomeState();
}

class _AuditorHomeState extends State<AuditorHome> {
  final _orchestrator = OrchestratorService();
  final _equipmentController = TextEditingController();

  bool _checking = false;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void dispose() {
    _equipmentController.dispose();
    super.dispose();
  }

  Future<void> _runComplianceCheck() async {
    final equipmentId = _equipmentController.text.trim();
    if (equipmentId.isEmpty) return;

    setState(() {
      _checking = true;
      _error = null;
      _result = null;
    });

    try {
      final response = await _orchestrator.query(
        'Is $equipmentId compliant with its maintenance interval?',
        userRole: 'auditor',
        equipmentId: equipmentId,
        agents: ['compliance_agent'],
      );

      print('===== AuditorHome: response received =====');
      print(response);

      final results = (response['results'] as List?) ?? [];

      print('===== AuditorHome: agents in response =====');
      print(results.map((r) => r['agent']).toList());

      final complianceResult = results.firstWhere(
        (r) => r['agent'] == 'compliance_agent',
        orElse: () => null,
      );

      setState(() => _result = complianceResult as Map<String, dynamic>?);
      if (_result == null) {
        setState(() => _error = 'Compliance Agent did not return a result for this query.');
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
      appBar: AppBar(
        title: const Text('Compliance & Audit'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: RoleBadge(role: UserRole.auditor),
          ),
          // NEW: lets the user switch to Technician/Engineer/Manager
          // without signing out.
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Run Compliance Check', style: Theme.of(context).textTheme.titleMedium),
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
            LayoutBuilder(
              builder: (context, constraints) {
                final checkComplianceButton = FilledButton.icon(
                  onPressed: _checking ? null : _runComplianceCheck,
                  icon: _checking
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Check Compliance'),
                );

                final fullAuditReportButton = OutlinedButton.icon(
                  onPressed: _equipmentController.text.trim().isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ActionResultScreen(
                                actionType: 'audit_report',
                                equipmentId: _equipmentController.text.trim(),
                                userRole: 'auditor',
                              ),
                            ),
                          ),
                  icon: const Icon(Icons.summarize_outlined, size: 18),
                  label: const Text('Full Audit Report'),
                );

                const wideBreakpoint = 360.0;

                if (constraints.maxWidth >= wideBreakpoint) {
                  return Row(
                    children: [
                      Expanded(child: checkComplianceButton),
                      const SizedBox(width: 8),
                      Expanded(child: fullAuditReportButton),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    checkComplianceButton,
                    const SizedBox(height: 8),
                    fullAuditReportButton,
                  ],
                );
              },
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