import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/i18n/i18n.dart';

class AssistantComposer extends StatefulWidget {
  const AssistantComposer({super.key});

  @override
  State<AssistantComposer> createState() => _AssistantComposerState();
}

class _AssistantComposerState extends State<AssistantComposer> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    if (_controller.text.trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            'Il backend condiviso dell’assistente non è ancora esposto in modo sicuro al desktop.',
            'The assistant’s shared backend isn’t safely exposed to the desktop yet.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const radius = 31.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              key: const Key('assistant_glass_bar'),
              height: 62,
              padding: const EdgeInsets.fromLTRB(9, 7, 7, 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xEEFFFFFF), Color(0xDDF5F5F7)],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .94),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 30,
                    offset: Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Color(0x8FFFFFFF),
                    blurRadius: 2,
                    offset: Offset(0, -1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.green.withValues(alpha: .12),
                      border: Border.all(
                        color: AppColors.green.withValues(alpha: .16),
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 20,
                      color: AppColors.green,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _send(),
                      maxLines: 1,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: tr(
                          'Chiedimi qualcosa sulla tua giornata…',
                          'Ask me something about your day…',
                        ),
                        hintStyle: TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w400,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_hasText) ...[
                    const SizedBox(width: AppSpacing.xs),
                    IconButton(
                      onPressed: _send,
                      tooltip: tr('Invia', 'Send'),
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(40),
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    ),
                  ],
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
                              'Input vocale non ancora disponibile.',
                              'Voice input not available yet.',
                            ),
                          ),
                        ),
                      );
                    },
                    tooltip: tr('Input vocale', 'Voice input'),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(40),
                      backgroundColor: const Color(0xCCF2F2F4),
                      foregroundColor: AppColors.green,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: .9),
                      ),
                    ),
                    icon: const Icon(Icons.mic_rounded, size: 21),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
