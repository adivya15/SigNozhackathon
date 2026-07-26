import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/capture_service.dart';
import '../../theme/app_theme.dart';

/// Day 5 deliverable: the Knowledge Capture Agent's guided interview,
/// implemented as a step-through voice/text Q&A flow. Questions come
/// from the backend's /capture/questions (equipment-specific scripts),
/// answers are submitted to /capture/submit and indexed same-day.
class KnowledgeCaptureScreen extends StatefulWidget {
  const KnowledgeCaptureScreen({super.key});

  @override
  State<KnowledgeCaptureScreen> createState() => _KnowledgeCaptureScreenState();
}

enum _CaptureStage { setup, loading, interview, submitting, done, error }

class _KnowledgeCaptureScreenState extends State<KnowledgeCaptureScreen> {
  final _captureService = CaptureService();
  final _speech = stt.SpeechToText();
  final _equipmentIdController = TextEditingController();
  final _answerController = TextEditingController();

  _CaptureStage _stage = _CaptureStage.setup;
  List<String> _questions = [];
  final List<Map<String, String>> _answers = [];
  int _currentIndex = 0;
  bool _isListening = false;
  bool _speechAvailable = false;
  String? _errorMessage;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _speech.initialize().then((ok) => setState(() => _speechAvailable = ok));
  }

  Future<void> _startInterview() async {
    setState(() => _stage = _CaptureStage.loading);
    try {
      final equipmentId = _equipmentIdController.text.trim();
      final questions = await _captureService.fetchQuestions(
        equipmentId: equipmentId.isEmpty ? null : equipmentId,
      );
      setState(() {
        _questions = questions;
        _currentIndex = 0;
        _answers.clear();
        _stage = _CaptureStage.interview;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _stage = _CaptureStage.error;
      });
    }
  }

  void _toggleListening() async {
    if (!_speechAvailable) return;
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        setState(() {
          _answerController.text = result.recognizedWords;
          _answerController.selection = TextSelection.fromPosition(
            TextPosition(offset: _answerController.text.length),
          );
        });
      },
    );
  }

  void _nextQuestion() {
    final answer = _answerController.text.trim();
    if (answer.isNotEmpty) {
      _answers.add({'question': _questions[_currentIndex], 'answer': answer});
    }
    _answerController.clear();
    if (_isListening) {
      _speech.stop();
      _isListening = false;
    }

    if (_currentIndex < _questions.length - 1) {
      setState(() => _currentIndex++);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    setState(() => _stage = _CaptureStage.submitting);
    try {
      final equipmentId = _equipmentIdController.text.trim();
      final result = await _captureService.submitAnswers(
        equipmentId: equipmentId.isEmpty ? null : equipmentId,
        technicianId: FirebaseAuth.instance.currentUser?.uid,
        answers: _answers,
      );
      setState(() {
        _result = result;
        _stage = _CaptureStage.done;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _stage = _CaptureStage.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // FIX: explicitly true (Flutter's default already, but stated
      // here per the requirement) so the body actually shrinks when
      // the keyboard opens instead of the content being pushed off
      // and clipped/overflowing behind the keyboard.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Knowledge Capture')),
      // FIX: wrapped the whole body in SafeArea. This screen wasn't
      // wrapped before, so on devices with notches/gesture bars the
      // usable content area was slightly smaller than the layout
      // assumed, contributing to the 1px-scale overflow seen on the
      // setup screen once the keyboard appeared.
      body: SafeArea(
        child: switch (_stage) {
          _CaptureStage.setup => _buildSetup(),
          _CaptureStage.loading => const Center(child: CircularProgressIndicator()),
          _CaptureStage.interview => _buildInterview(),
          _CaptureStage.submitting => const Center(child: CircularProgressIndicator()),
          _CaptureStage.done => _buildDone(),
          _CaptureStage.error => _buildError(),
        },
      ),
    );
  }

  Widget _buildSetup() {
    // FIX: this is the exact overflow shown in the screenshot
    // ("BOTTOM OVERFLOWED BY 1.00 PIXELS" on the Start Interview
    // button). Cause: the Column used
    // mainAxisAlignment: MainAxisAlignment.center directly inside a
    // Padding with no scroll container, so it assumed a fixed
    // available height. When the keyboard opened (from focusing the
    // Equipment ID field) and shrank that available height by even a
    // hair, the Column's content no longer fit and overflowed by a
    // sliver.
    //
    // Fix: same LayoutBuilder + SingleChildScrollView +
    // ConstrainedBox(minHeight) pattern already used elsewhere in
    // this app (see ChatScreen's _EmptyState) — when there's enough
    // room it still centers exactly as before; when the keyboard
    // shrinks the space, it scrolls instead of overflowing. No
    // widgets removed or redesigned, no spacing changed.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.record_voice_over_outlined, size: 48, color: AppColors.primary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Capture what you know',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'A short guided interview — answer by voice or text. '
                  'Nothing here is graded; it just becomes searchable knowledge.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _equipmentIdController,
                  decoration: const InputDecoration(
                    labelText: 'Equipment ID (optional)',
                    hintText: 'e.g. PUMP-04 — tailors the questions',
                    prefixIcon: Icon(Icons.tag, size: 18),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton.icon(
                  onPressed: _startInterview,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Start interview'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInterview() {
    final progress = (_currentIndex + 1) / _questions.length;
    return Column(
      children: [
        LinearProgressIndicator(value: progress, minHeight: 3, color: AppColors.primary),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Question ${_currentIndex + 1} of ${_questions.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _questions[_currentIndex],
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: TextField(
                    controller: _answerController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      hintText: 'Type or tap the mic to answer...',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: _isListening ? AppColors.dangerBg : AppColors.surfaceMuted,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: _speechAvailable ? _toggleListening : null,
                        icon: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: _isListening ? AppColors.danger : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _nextQuestion,
                        child: Text(
                          _currentIndex < _questions.length - 1 ? 'Next question' : 'Finish',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _nextQuestion,
                    child: const Text('Skip this question', style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDone() {
    // FIX: wrapped in SingleChildScrollView for the same reason as
    // _buildSetup — a centered Column with no scroll fallback can
    // overflow on short screens or in landscape. Design/spacing
    // unchanged.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 48),
          const SizedBox(height: AppSpacing.md),
          Text('Knowledge captured', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            '${_answers.length} answer${_answers.length == 1 ? '' : 's'} saved and indexed. '
            'The Knowledge Agent can use this starting now.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: () => setState(() {
              _stage = _CaptureStage.setup;
              _equipmentIdController.clear();
              _result = null;
            }),
            child: const Text('Capture another'),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    // FIX: same SingleChildScrollView safety net as above.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
          const SizedBox(height: AppSpacing.md),
          Text(
            _errorMessage ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: () => setState(() => _stage = _CaptureStage.setup),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}