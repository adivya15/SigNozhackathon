import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../models/chat_message.dart';
import '../../models/user_role.dart';
import '../../services/orchestrator_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/explainable_ai_panel.dart';
import '../../widgets/account_menu.dart';
import '../../widgets/role_switcher.dart';
import '../upload_document_screen.dart';
import '../lessons_learned/lessons_learned_timeline_screen.dart';
import '../knowledge_capture/knowledge_capture_screen.dart';

/// Knowledge Agent chat — text + voice input. Logic unchanged from
/// Day 3; this pass is purely the professional UI restyle plus the
/// Day 4 AccountMenu (role display + sign out).
class ChatScreen extends StatefulWidget {
  final String userRole;
  const ChatScreen({super.key, this.userRole = 'technician'});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _orchestrator = OrchestratorService();
  final _textController = TextEditingController();
  final _equipmentIdController = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = stt.SpeechToText();

  final List<ChatMessage> _messages = [];
  bool _isSending = false;
  bool _isListening = false;
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        setState(() => _isListening = false);
      },
    );
    setState(() {});
  }

  void _toggleListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice input unavailable on this device/browser.')),
      );
      return;
    }
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        setState(() {
          _textController.text = result.recognizedWords;
          _textController.selection = TextSelection.fromPosition(
            TextPosition(offset: _textController.text.length),
          );
        });
      },
    );
  }

  Future<void> _send() async {
    final query = _textController.text.trim();
    if (query.isEmpty || _isSending) return;

    final equipmentId = _equipmentIdController.text.trim();

    setState(() {
      _messages.add(ChatMessage(text: query, isUser: true));
      _isSending = true;
      _textController.clear();
    });
    _scrollToBottom();

    try {
      final response = await _orchestrator.query(
        query,
        userRole: widget.userRole,
        equipmentId: equipmentId.isEmpty ? null : equipmentId,
      );
      setState(() {
        _messages.add(ChatMessage.fromOrchestratorResponse(response));
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: 'Could not reach the Knowledge Agent: $e',
          isUser: false,
          isError: true,
        ));
      });
    } finally {
      setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // FIX: explicit true so the body (equipment ID field + chat +
      // input bar) actually shrinks when the keyboard opens, matching
      // the other requirement to handle keyboard-driven overflow.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Knowledge Agent'),
        // FIX (corrected): the previous SingleChildScrollView wrap
        // didn't actually fix anything, because AppBar measures
        // `actions` at their natural/unconstrained width before
        // laying out the title — it never hands actions a bounded
        // width to begin with. A SingleChildScrollView only scrolls
        // when its parent constrains it smaller than its content;
        // with no such bound, it just reported its natural width
        // (icons + RoleSwitcher + AccountMenu), which was still wide
        // enough to push the whole AppBar row past the screen edge.
        // The real fix: wrap it in a ConstrainedBox with an explicit
        // maxWidth, so there's now a genuine bound for the scroll
        // view to scroll within instead of overflowing past it.
        actions: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.62),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.upload_file_outlined),
                    tooltip: 'Upload a document',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const UploadDocumentScreen()),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.timeline_outlined),
                    tooltip: 'Lessons Learned Timeline',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LessonsLearnedTimelineScreen()),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.record_voice_over_outlined),
                    tooltip: 'Capture knowledge',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const KnowledgeCaptureScreen()),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: RoleSwitcher(),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 12, left: 4),
                    child: AccountMenu(role: UserRole.technician),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            color: AppColors.surface,
            child: TextField(
              controller: _equipmentIdController,
              style: const TextStyle(fontSize: 13.5),
              decoration: const InputDecoration(
                labelText: 'Equipment ID (optional)',
                hintText: 'e.g. PUMP-04',
                isDense: true,
                prefixIcon: Icon(Icons.tag, size: 18),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              color: AppColors.background,
              child: _messages.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) => _MessageBubble(message: _messages[i]),
                    ),
            ),
          ),
          if (_isSending)
            const LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              decoration: BoxDecoration(
                color: _isListening ? AppColors.dangerBg : AppColors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _toggleListening,
                icon: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: _isListening ? AppColors.danger : AppColors.primary,
                ),
                tooltip: 'Ask by voice',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(fontSize: 14.5),
                decoration: const InputDecoration(
                  hintText: 'Ask AtlasAI — e.g. "What do I check first when Pump 4 vibrates?"',
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: IconButton(
                onPressed: _isSending ? null : _send,
                icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    // FIX: this is the "BOTTOM OVERFLOWED BY 56 PIXELS" seen in the
    // screenshot. Cause: a centered Column with icon + heading +
    // subtitle had no scroll fallback, so when the keyboard opened
    // (from focusing the Equipment ID field above) and shrank the
    // Expanded area this sits in, the content no longer fit.
    //
    // Fix: LayoutBuilder + SingleChildScrollView + ConstrainedBox
    // (minHeight) — when there's enough room it still centers exactly
    // as before; when space is tight, it scrolls instead of
    // overflowing. Same icon, same text, same spacing.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.hub_outlined, size: 40, color: AppColors.primary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Ask the Knowledge Agent', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Type a question or tap the mic. Answers are\ngrounded in your plant\'s ingested documents.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 14.5)),
        ),
      );
    }

    final bgColor = message.isError ? AppColors.dangerBg : AppColors.surface;
    final borderColor = message.isError ? AppColors.danger.withOpacity(0.3) : AppColors.border;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser && !message.isError) ...[
              Row(
                children: [
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.hub_outlined, size: 13, color: Colors.white),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Knowledge Agent',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message.text,
              style: TextStyle(
                fontSize: 14.5,
                color: message.isError ? AppColors.danger : AppColors.textPrimary,
              ),
            ),
            if (!isUser && !message.isError) ...[
              const SizedBox(height: 10),
              ExplainableAiPanel(
                confidence: message.confidence ?? 0.0,
                sources: message.sources,
                reasoning: message.reasoning,
              ),
            ],
          ],
        ),
      ),
    );
  }
}