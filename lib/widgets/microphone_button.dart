import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Microphone button for live audio recording.
/// Handles recording state with visual feedback.
class MicrophoneButton extends StatelessWidget {
  final bool isRecording;
  final bool isAiSpeaking;
  final bool isEnabled;
  final VoidCallback? onPressed;

  const MicrophoneButton({
    super.key,
    required this.isRecording,
    required this.isAiSpeaking,
    required this.isEnabled,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isAiSpeaking)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              '🔊 AI is speaking...',
              style: TextStyle(color: AppColors.aiSpeaking),
            ),
          ),
        Semantics(
          label: isRecording ? "Stop Recording" : "Start Recording",
          button: true,
          child: GestureDetector(
            onTap: isEnabled && !isAiSpeaking ? onPressed : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isRecording ? 100 : 80,
              height: isRecording ? 100 : 80,
              decoration: BoxDecoration(
                color: _getButtonColor(),
                shape: BoxShape.circle,
                boxShadow: isRecording
                    ? [
                        BoxShadow(
                          color: AppColors.recording.withValues(alpha: 0.6),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isRecording ? Icons.stop : Icons.mic,
                color: AppColors.textLight,
                size: 48,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color _getButtonColor() {
    if (isAiSpeaking) return AppColors.textMuted;
    if (isRecording) return AppColors.recording;
    return AppColors.liveActive;
  }
}
