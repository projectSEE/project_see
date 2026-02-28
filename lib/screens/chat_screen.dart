import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:geolocator/geolocator.dart';
import '../services/gemini_service.dart';
import '../services/firestore_service.dart';
import '../services/tts_service.dart';
import '../utils/audio_input.dart';
import '../utils/audio_output.dart';
import '../utils/conversation_exporter.dart';
import '../theme/theme.dart';
import '../widgets/widgets.dart';
import '../main.dart';
import '../core/localization/app_localizations.dart';
import '../core/services/language_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final GeminiService _geminiService = GeminiService();
  final FirestoreService _firestoreService = FirestoreService();
  final TTSService _ttsService = TTSService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  // Audio utilities for Live mode
  final AudioInput _audioInput = AudioInput();
  final AudioOutput _audioOutput = AudioOutput();

  // User identification from Firebase Auth
  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';

  // Current conversation topic/session ID
  String _currentTopicId = '';

  // Stores chat messages: {role: 'user'|'model', text: '...', imageBytes: Uint8List?}
  final List<Map<String, dynamic>> _messages = [];

  bool _isLoading = false;

  // Live mode state
  bool _isLiveMode = false;
  bool _isLiveSessionActive = false;
  bool _isRecording = false;
  bool _isAiSpeaking = false; // Track when AI is responding with audio
  StreamSubscription<dynamic>? _responseSubscription;

  // Text-to-Speech toggle
  bool _ttsEnabled = true;

  // Chat history from database
  List<Map<String, dynamic>> _chatHistory = [];

  // Pending image for attach-then-type feature
  XFile? _pendingImage;
  Uint8List? _pendingImageBytes;

  // Search query for filtering history
  String _searchQuery = '';

  final LanguageNotifier _langNotifier = LanguageNotifier();

  @override
  void initState() {
    super.initState();
    _currentTopicId = DateTime.now().millisecondsSinceEpoch.toString();
    _ttsService.initialize();
    _initAudio();
    _initDatabase();
    _langNotifier.addListener(_onLangChanged);
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initDatabase() async {
    // Cleanup old conversations on app start
    await _firestoreService.cleanupOldConversations(_userId);
    // Load chat history
    await _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    try {
      // Load topic previews instead of individual messages
      final topics = await _firestoreService.getTopicPreviews(_userId);
      setState(() {
        _chatHistory = topics;
      });
    } catch (e) {
      debugPrint('Error loading chat history: $e');
    }
  }

  /// Load all messages for a specific topic
  Future<void> _loadTopicMessages(String topicId) async {
    try {
      final grouped = await _firestoreService.getConversationsGroupedByTopic(
        _userId,
      );
      final topicMessages = grouped[topicId] ?? [];

      setState(() {
        _messages.clear();
        for (final msg in topicMessages) {
          _messages.add({
            'role': msg['role'] == 'assistant' ? 'model' : msg['role'],
            'text': msg['content']?.toString() ?? '',
            'imageUrl': msg['imageUrl'], // <--- Add this
          });
        }
        // Switch to this topic for new messages
        _currentTopicId = topicId;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error loading topic messages: $e');
    }
  }

  Future<void> _initAudio() async {
    await _audioInput.init();
    await _audioOutput.init();
  }

  @override
  void dispose() {
    _langNotifier.removeListener(_onLangChanged);
    _disconnectLiveSession();
    _audioInput.dispose();
    _audioOutput.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ========== Normal Mode Methods ==========

  Future<void> _handleSendMessage({String? text}) async {
    final userText = text?.trim() ?? "";

    // If no text and no pending image, do nothing
    if (userText.isEmpty && _pendingImage == null) return;

    // Prepare image bytes
    Uint8List? imageBytes = _pendingImageBytes;
    String? imageMimeType = _pendingImage?.mimeType;
    final messageContent = userText.isEmpty ? "Describe this image" : userText;

    // Add user message to chat with image thumbnail if available
    setState(() {
      _messages.add({
        'role': 'user',
        'text': messageContent,
        'imageBytes': imageBytes,
      });
      _isLoading = true;
      // Clear pending image
      _pendingImage = null;
      _pendingImageBytes = null;
    });
    _scrollToBottom();
    _textController.clear();

    // Save user message to database
    await _firestoreService.saveMessage(
      _userId,
      'user',
      messageContent,
      hasImage: imageBytes != null,
      topicId: _currentTopicId,
      imageBytes: imageBytes,
    );

    try {
      // Get user's location for POI context (optional)
      double? latitude;
      double? longitude;
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        );
        latitude = position.latitude;
        longitude = position.longitude;
      } catch (e) {
        // Location not available, continue without it
        debugPrint('Location not available: $e');
      }

      // Get user settings for personalized behavior
      final databaseContext = await _firestoreService.buildContextForAI(
        _userId, // Assuming _userId is equivalent to user.uid here
        latitude: latitude,
        longitude: longitude,
      );

      final response = await _geminiService.sendMessage(
        messageContent,
        imageBytes: imageBytes,
        imageMimeType: imageMimeType,
        databaseContext: databaseContext,
      );

      // Save assistant response to database
      await _firestoreService.saveMessage(
        _userId,
        'assistant',
        response,
        topicId: _currentTopicId,
      );

      setState(() {
        _messages.add({'role': 'model', 'text': response});
        _isLoading = false;
      });
      _scrollToBottom();
      _speak(response);
    } catch (e) {
      setState(() {
        _messages.add({'role': 'model', 'text': "Error: ${e.toString()}"});
        _isLoading = false;
      });
    }
  }

  Future<void> _speak(String text) async {
    if (!_ttsEnabled) {
      debugPrint('TTS: Text-to-Speech disabled, skipping speech');
      return;
    }

    await _ttsService.speak(text, force: true, preventDuplicates: false);
  }

  /// Delete a message at the given index
  void _deleteMessage(int index) {
    if (index >= 0 && index < _messages.length) {
      setState(() {
        _messages.removeAt(index);
      });
    }
  }

  /// Show image in fullscreen viewer
  void _showImageFullscreen(Uint8List imageBytes) {
    ImageViewerDialog.show(context, imageBytes);
  }

  /// Export conversation as PDF
  Future<void> _shareConversation() async {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No messages to export')));
      return;
    }
    await ConversationExporter.exportAsPdf(_messages);
  }

  /// Filter chat history by search query
  List<Map<String, dynamic>> get _filteredChatHistory {
    if (_searchQuery.isEmpty) return _chatHistory;
    final lowerQuery = _searchQuery.toLowerCase();
    return _chatHistory.where((topic) {
      final firstMessage =
          topic['firstMessage']?.toString().toLowerCase() ?? '';
      return firstMessage.contains(lowerQuery);
    }).toList();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _pendingImage = image;
          _pendingImageBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint("Image pick error: $e");
    }
  }

  void _clearPendingImage() {
    setState(() {
      _pendingImage = null;
      _pendingImageBytes = null;
    });
  }

  // ========== Live Mode Methods ==========

  Future<void> _toggleLiveMode(bool value) async {
    setState(() {
      _isLiveMode = value;
    });

    if (_isLiveMode) {
      await _connectLiveSession();
    } else {
      await _disconnectLiveSession();
    }
  }

  Future<void> _connectLiveSession() async {
    try {
      setState(() {
        _isLoading = true;
      });

      await _geminiService.connectLive();

      // Start listening to responses
      _startListeningToResponses();

      setState(() {
        _isLiveSessionActive = true;
        _isLoading = false;
        _messages.add({
          'role': 'system',
          'text':
              '🎙️ Live session connected. Tap the microphone to start speaking.',
        });
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLiveMode = false;
        _messages.add({
          'role': 'system',
          'text': '❌ Failed to connect live session: $e',
        });
      });
      _scrollToBottom();
    }
  }

  Future<void> _disconnectLiveSession() async {
    await _responseSubscription?.cancel();
    _responseSubscription = null;

    if (_isRecording) {
      await _stopRecording();
    }

    await _geminiService.disconnectLive();
    await _audioOutput.stop();

    if (mounted) {
      setState(() {
        _isLiveSessionActive = false;
        _isAiSpeaking = false;
        if (_isLiveMode) {
          _messages.add({
            'role': 'system',
            'text': '🔌 Live session disconnected.',
          });
        }
      });
      _scrollToBottom();
    }
  }

  void _startListeningToResponses() {
    final responseStream = _geminiService.liveResponses;
    if (responseStream == null) return;

    _responseSubscription = responseStream.listen(
      (LiveServerResponse response) async {
        await _handleLiveResponse(response);
      },
      onError: (error) {
        setState(() {
          _messages.add({
            'role': 'system',
            'text': '❌ Error in live session: $error',
          });
        });
        _scrollToBottom();
      },
    );
  }

  Future<void> _handleLiveResponse(LiveServerResponse response) async {
    final message = response.message;

    if (message is LiveServerContent) {
      final parts = message.modelTurn?.parts;
      if (parts != null) {
        for (final part in parts) {
          if (part is InlineDataPart && part.mimeType.startsWith('audio')) {
            // Stop recording when AI starts speaking to prevent feedback loop
            if (_isRecording) {
              await _stopRecording();
            }

            // Mark AI as speaking and play the audio response
            setState(() {
              _isAiSpeaking = true;
            });
            await _audioOutput.addAudioStream(part.bytes);
          } else if (part is TextPart) {
            // Display text response if any
            setState(() {
              _messages.add({'role': 'model', 'text': part.text});
            });
            _scrollToBottom();
          }
        }
      }

      // Handle turn complete - AI finished speaking
      if (message.turnComplete == true) {
        setState(() {
          _isAiSpeaking = false;
        });
      }

      // Note: Transcription features require firebase_ai 3.x+
      // If using newer version, uncomment the transcription handling below
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!_isLiveSessionActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live session not connected')),
      );
      return;
    }

    // Don't start recording if AI is still speaking
    if (_isAiSpeaking) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wait for AI to finish speaking')),
      );
      return;
    }

    setState(() {
      _isRecording = true;
    });

    try {
      await _audioOutput.playStream();
      final inputStream = await _audioInput.startRecordingStream();

      if (inputStream != null) {
        await for (final data in inputStream) {
          // Stop if no longer recording or AI starts speaking
          if (!_isRecording || _isAiSpeaking) break;
          await _geminiService.sendAudioRealtime(data);
        }
      }
    } catch (e) {
      debugPrint("Recording error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Recording error: $e')));
      }
    }
  }

  Future<void> _stopRecording() async {
    await _audioInput.stopRecording();
    setState(() {
      _isRecording = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations(_langNotifier.languageCode);
    return Scaffold(
      appBar: AppBar(
        leading: Semantics(
          label: strings.get('back'),
          button: true,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, size: 28),
            tooltip: strings.get('back'),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          // Text-to-Speech Toggle
          Semantics(
            label: strings.get('toggleTts'),
            button: true,
            child: IconButton(
              icon: Icon(
                _ttsEnabled ? Icons.volume_up : Icons.volume_off,
                color:
                    _ttsEnabled
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              tooltip: strings.get('toggleTts'),
              onPressed: () async {
                setState(() {
                  _ttsEnabled = !_ttsEnabled;
                });
                // Stop speaking if TTS was just disabled
                if (!_ttsEnabled) {
                  await _ttsService.stop();
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _ttsEnabled
                          ? strings.get('ttsEnabled')
                          : strings.get('ttsStopped'),
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
          // Live Mode Toggle
          Row(
            children: [
              Text(
                _isLiveMode
                    ? strings.get('liveMode')
                    : strings.get('normalMode'),
                style: TextStyle(
                  color: _isLiveMode ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Switch(
                value: _isLiveMode,
                onChanged: _isLoading ? null : _toggleLiveMode,
                activeColor: Colors.white,
                inactiveThumbColor: Colors.white70,
              ),
            ],
          ),
          if (_isLiveSessionActive)
            Container(
              margin: const EdgeInsets.only(right: 8),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color:
                    _isAiSpeaking ? AppColors.aiSpeaking : AppColors.liveActive,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isAiSpeaking
                            ? AppColors.aiSpeaking
                            : AppColors.liveActive)
                        .withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                color: Theme.of(context).colorScheme.surface,
                child: Row(
                  children: [
                    Icon(
                      Icons.settings,
                      color: Theme.of(context).colorScheme.onSurface,
                      size: 28,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      strings.get('settingsAndHistory'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),

              // Text-to-Speech Toggle
              SwitchListTile(
                title: Text(
                  strings.get('ttsLabel'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  _ttsEnabled
                      ? strings.get('ttsEnabledDesc')
                      : strings.get('ttsSilentMode'),
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                value: _ttsEnabled,
                onChanged: (value) {
                  setState(() {
                    _ttsEnabled = value;
                  });
                },
                activeColor: Theme.of(context).colorScheme.onSurface,
                secondary: Icon(
                  _ttsEnabled ? Icons.volume_up : Icons.volume_off,
                  color:
                      _ttsEnabled
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),

              // Dark Mode Toggle (Immediate Effect)
              SwitchListTile(
                title: Text(
                  strings.get('darkMode'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  ThemeNotifier().isDarkMode
                      ? strings.get('darkThemeActive')
                      : strings.get('lightThemeActive'),
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                value: ThemeNotifier().isDarkMode,
                onChanged: (value) {
                  ThemeNotifier().setDarkMode(value);
                  setState(() {}); // Refresh UI
                },
                activeColor: Theme.of(context).colorScheme.onSurface,
                secondary: Icon(
                  ThemeNotifier().isDarkMode
                      ? Icons.dark_mode
                      : Icons.light_mode,
                  color:
                      ThemeNotifier().isDarkMode
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),

              const Divider(),

              // Share Conversation Button
              ListTile(
                leading: Icon(
                  Icons.share,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                title: Text(
                  strings.get('shareConversation'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  strings.get('exportAsText'),
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _shareConversation();
                },
              ),

              const Divider(),

              // Chat History Header
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      strings.get('chatHistory'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      onPressed: _loadChatHistory,
                      tooltip: strings.get('refresh'),
                    ),
                  ],
                ),
              ),

              // Search Bar
              ChatSearchBar(
                onSearch: (query) {
                  setState(() {
                    _searchQuery = query;
                  });
                },
              ),
              // Chat History List (Grouped by Topic)
              Expanded(
                child:
                    _filteredChatHistory.isEmpty
                        ? Center(
                          child: Text(
                            _searchQuery.isEmpty
                                ? strings.get('noConversations')
                                : strings.get('noMatchingConversations'),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                        : ListView.builder(
                          itemCount: _filteredChatHistory.length,
                          itemBuilder: (context, index) {
                            final topic = _filteredChatHistory[index];
                            final topicId = topic['topicId']?.toString() ?? '';
                            final messageCount = topic['messageCount'] ?? 0;
                            final firstMessage =
                                topic['firstMessage']?.toString() ??
                                strings.get('newConversation');
                            final timestamp = topic['timestamp'];

                            // Format timestamp
                            String timeStr = '';
                            if (timestamp is num) {
                              final date = DateTime.fromMillisecondsSinceEpoch(
                                timestamp.toInt(),
                              );
                              final now = DateTime.now();
                              final isToday =
                                  date.year == now.year &&
                                  date.month == now.month &&
                                  date.day == now.day;
                              if (isToday) {
                                timeStr =
                                    '${strings.get('today')} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
                              } else {
                                timeStr =
                                    '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
                              }
                            }

                            // Create a preview title from first message
                            String title =
                                firstMessage.length > 40
                                    ? '${firstMessage.substring(0, 40)}...'
                                    : firstMessage;

                            return Card(
                              color: Theme.of(context).colorScheme.surface,
                              margin: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xs,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusMd,
                                ),
                                side:
                                    ThemeNotifier().isDarkMode
                                        ? const BorderSide(
                                          color: Colors.white,
                                          width: 1.5,
                                        )
                                        : BorderSide.none,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.1),
                                  child: Icon(
                                    Icons.chat_bubble_outline,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  title,
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    fontSize: 14,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '$messageCount ${strings.get('messages')} • $timeStr',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right,
                                  color: AppColors.textSecondary,
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  _loadTopicMessages(topicId);
                                },
                              ),
                            );
                          },
                        ),
              ),

              // Clear History Button
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _messages.clear();
                    });
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  label: Text(
                    strings.get('clearCurrentChat'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    side: BorderSide(
                      color:
                          ThemeNotifier().isDarkMode
                              ? Colors.white
                              : Colors.black,
                      width: 2.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final imageBytes = msg['imageBytes'] as Uint8List?;
                final imageUrl = msg['imageUrl'] as String?;
                return InteractiveMessageBubble(
                  role: msg['role'] ?? 'model',
                  text: msg['text'] ?? '',
                  imageBytes: imageBytes,
                  imageUrl: imageUrl,
                  onTapReadAloud: () => _speak(msg['text'] ?? ''),
                  onDelete: () => _deleteMessage(index),
                  onImageTap:
                      imageBytes != null
                          ? () => _showImageFullscreen(imageBytes)
                          : null,
                );
              },
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: LinearProgressIndicator(color: Colors.white),
            ),

          // Pending image preview
          if (_pendingImage != null && _pendingImageBytes != null)
            PendingImagePreview(
              imageBytes: _pendingImageBytes!,
              onClear: _clearPendingImage,
            ),

          // Input Area
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
            child:
                _isLiveMode
                    ? Center(
                      child: MicrophoneButton(
                        isRecording: _isRecording,
                        isAiSpeaking: _isAiSpeaking,
                        isEnabled: _isLiveSessionActive,
                        onPressed: _toggleRecording,
                      ),
                    )
                    : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _textController,
                          style: AppTextStyles.bodyMedium,
                          decoration: InputDecoration(
                            hintText:
                                _pendingImage != null
                                    ? strings.get('addMessageAboutImage')
                                    : strings.get('typeMessage'),
                          ),
                          onSubmitted: (val) => _handleSendMessage(text: val),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Builder(
                              builder:
                                  (context) => IconButton(
                                    icon: Icon(
                                      Icons.menu,
                                      color:
                                          Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                      size: 32,
                                    ),
                                    onPressed:
                                        () => Scaffold.of(context).openDrawer(),
                                    tooltip: strings.get('settingsAndHistory'),
                                    style: IconButton.styleFrom(
                                      padding: const EdgeInsets.all(
                                        AppSpacing.sm,
                                      ),
                                    ),
                                  ),
                            ),
                            Semantics(
                              label: strings.get('chooseFromGallery'),
                              button: true,
                              child: IconButton(
                                icon: Icon(
                                  Icons.photo_library,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  size: 36,
                                ),
                                onPressed:
                                    () => _pickImage(ImageSource.gallery),
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                ),
                              ),
                            ),
                            Semantics(
                              label: strings.get('takePicture'),
                              button: true,
                              child: IconButton(
                                icon: Icon(
                                  Icons.camera_alt,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  size: 36,
                                ),
                                onPressed: () => _pickImage(ImageSource.camera),
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Semantics(
                              label: strings.get('sendMessage'),
                              button: true,
                              child: IconButton(
                                icon: Icon(
                                  Icons.send,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  size: 36,
                                ),
                                onPressed:
                                    () => _handleSendMessage(
                                      text: _textController.text,
                                    ),
                                style: IconButton.styleFrom(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }
}
