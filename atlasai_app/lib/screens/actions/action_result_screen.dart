import 'package:flutter/material.dart';
import '../../services/action_engine_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/explainable_ai_panel.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Day 6: shows one generated action (RCA report, maintenance
/// checklist, inspection schedule, or audit report). Fetches on open
/// rather than taking the content as a constructor param, so it's a
/// simple push-and-forget navigation from wherever it's triggered.
class ActionResultScreen extends StatefulWidget {
  final String actionType;
  final String? equipmentId;
  final String? query;
  final String userRole;

  const ActionResultScreen({
    super.key,
    required this.actionType,
    this.equipmentId,
    this.query,
    this.userRole = 'technician',
  });

  @override
  State<ActionResultScreen> createState() => _ActionResultScreenState();
}

class _ActionResultScreenState extends State<ActionResultScreen> {
  final _service = ActionEngineService();
  Map<String, dynamic>? _result;
  String? _error;
  bool _loading = true;

  static const _titles = {
    'rca_report': 'Root Cause Analysis Report',
    'maintenance_checklist': 'Maintenance Checklist',
    'inspection_schedule': 'Inspection Schedule',
    'preventive_maintenance': 'Preventive Maintenance Plan',
    'audit_report': 'Audit Report',
  };

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.generate(
        actionType: widget.actionType,
        query: widget.query,
        equipmentId: widget.equipmentId,
        userRole: widget.userRole,
      );
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[widget.actionType] ?? 'Generated Action'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _generate)
              : _buildResult(),
    );
  }

  Widget _buildResult() {
    final content = _result?['content'] as String? ?? '';
    final sources = List<String>.from(_result?['sources'] ?? const []);
    final confidence = (_result?['confidence'] as num?)?.toDouble() ?? 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.equipmentId != null) ...[
            Text(
              'Equipment: ${widget.equipmentId}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: MarkdownBody(
              data: content,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 14, height: 1.5),
                strong: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ExplainableAiPanel(confidence: confidence, sources: sources),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}