import 'package:flutter/material.dart';
import '../core/localization/app_localizations.dart';
import '../core/services/language_provider.dart';
import '../main.dart';
import '../utils/accessibility_settings.dart';

/// Settings screen with WCAG-accessible controls.
/// Language, Theme, Text Size, TTS Speed, Haptic Feedback.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LanguageNotifier _langNotifier = LanguageNotifier();
  final ThemeNotifier _themeNotifier = ThemeNotifier();

  double _fontScale = 1.0;
  double _ttsSpeed = 0.5;
  bool _hapticEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _langNotifier.addListener(_onChanged);
    _themeNotifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    _langNotifier.removeListener(_onChanged);
    _themeNotifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    final scale = await AccessibilitySettings.getFontScale();
    final rate = await AccessibilitySettings.getTtsSpeechRate();
    final haptic = await AccessibilitySettings.isHapticFeedbackEnabled();
    if (mounted) {
      setState(() {
        _fontScale = scale;
        _ttsSpeed = rate;
        _hapticEnabled = haptic;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations(_langNotifier.languageCode);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.get('settingsTitle')),
        centerTitle: true,
        leading: Semantics(
          label: strings.get('back'),
          button: true,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, size: 28),
            tooltip: strings.get('back'),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Language ──
          _buildSectionHeader(strings.get('language'), Icons.language, theme),
          const SizedBox(height: 12),
          ...LanguageNotifier.supportedLanguages.entries.map((entry) {
            final isSelected = _langNotifier.languageCode == entry.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                label:
                    '${entry.value} language option${isSelected ? ", selected" : ""}',
                button: true,
                child: Material(
                  color:
                      isSelected
                          ? theme.colorScheme.primary.withOpacity(0.15)
                          : theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color:
                          isSelected
                              ? theme.colorScheme.primary
                              : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _langNotifier.setLanguage(entry.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color:
                                isSelected
                                    ? theme.colorScheme.primary
                                    : Colors.grey,
                            size: 28,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight:
                                  isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 28),

          // ── Theme ──
          _buildSectionHeader(strings.get('colorTheme'), Icons.palette, theme),
          const SizedBox(height: 12),
          _buildThemeOption(
            strings.get('lightMode'),
            Icons.light_mode,
            ThemeMode.light,
            theme,
          ),
          const SizedBox(height: 8),
          _buildThemeOption(
            strings.get('darkMode'),
            Icons.dark_mode,
            ThemeMode.dark,
            theme,
          ),

          const SizedBox(height: 28),

          // ── Text Size ──
          _buildSectionHeader(
            strings.get('textSize'),
            Icons.text_fields,
            theme,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('A', style: TextStyle(fontSize: 14)),
              Expanded(
                child: Semantics(
                  label:
                      '${strings.get('textSize')} ${strings.get('scale')}: ${_fontScale.toStringAsFixed(1)}',
                  slider: true,
                  child: Slider(
                    value: _fontScale,
                    min: 0.8,
                    max: 2.0,
                    divisions: 12,
                    label: '${_fontScale.toStringAsFixed(1)}x',
                    onChanged: (val) async {
                      setState(() => _fontScale = val);
                      await AccessibilitySettings.setFontScale(val);
                      await TextScaleNotifier().setScale(val); // Rebuild app
                    },
                  ),
                ),
              ),
              const Text(
                'A',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Text(
            '${strings.get('scale')}: ${_fontScale.toStringAsFixed(1)}x',
            style: TextStyle(fontSize: 16 * _fontScale),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 28),

          // ── TTS Speed ──
          _buildSectionHeader(
            strings.get('ttsSpeed'),
            Icons.record_voice_over,
            theme,
          ),
          const SizedBox(height: 12),
          Semantics(
            label: '${strings.get('ttsSpeed')}: ${(_ttsSpeed * 100).toInt()}%',
            slider: true,
            child: Slider(
              value: _ttsSpeed,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              label: '${(_ttsSpeed * 100).toInt()}%',
              onChanged: (val) async {
                setState(() => _ttsSpeed = val);
                await AccessibilitySettings.setTtsSpeechRate(val);
                await AccessibilitySettings.applyTtsSettings();
              },
            ),
          ),
          Text(
            '${strings.get('speed')}: ${(_ttsSpeed * 100).toInt()}%',
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 28),

          // ── Haptic Feedback ──
          Semantics(
            label:
                '${strings.get('hapticFeedback')}: ${_hapticEnabled ? strings.get('enabled') : strings.get('disabled')}',
            child: SwitchListTile(
              title: Text(
                strings.get('hapticFeedback'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                _hapticEnabled
                    ? strings.get('enabled')
                    : strings.get('disabled'),
              ),
              value: _hapticEnabled,
              onChanged: (val) async {
                setState(() => _hapticEnabled = val);
                await AccessibilitySettings.setHapticFeedbackEnabled(val);
              },
              secondary: Icon(
                _hapticEnabled ? Icons.vibration : Icons.do_not_touch,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── Reset ──
          SizedBox(
            width: double.infinity,
            height: 56,
            child: Semantics(
              label: strings.get('resetDefaults'),
              button: true,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await AccessibilitySettings.resetToDefaults();
                  await _langNotifier.setLanguage('en');
                  _themeNotifier.setDarkMode(false);
                  await TextScaleNotifier().setScale(1.0); // Reset scale
                  await _loadSettings();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(strings.get('resetConfirm'))),
                    );
                  }
                },
                icon: const Icon(Icons.restore, size: 28),
                label: Text(
                  strings.get('resetDefaults'),
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 28, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildThemeOption(
    String label,
    IconData icon,
    ThemeMode mode,
    ThemeData theme,
  ) {
    final isSelected = _themeNotifier.themeMode == mode;
    return Semantics(
      label: '$label theme option${isSelected ? ", selected" : ""}',
      button: true,
      child: Material(
        color:
            isSelected
                ? theme.colorScheme.primary.withOpacity(0.15)
                : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color:
                isSelected ? theme.colorScheme.primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _themeNotifier.setDarkMode(mode == ThemeMode.dark),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: isSelected ? theme.colorScheme.primary : Colors.grey,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
