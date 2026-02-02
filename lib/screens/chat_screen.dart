import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:geolocator/geolocator.dart';
import '../services/gemini_service.dart';
import '../services/database_service.dart';
import '../utils/audio_input.dart';
import '../utils/audio_output.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final GeminiService _geminiService = GeminiService();
  final DatabaseService _databaseService = DatabaseService();
  final FlutterTts _flutterTts = FlutterTts();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  // Audio utilities for Live mode
  final AudioInput _audioInput = AudioInput();
  final AudioOutput _audioOutput = AudioOutput();
  
  // User identification (in production, use Firebase Auth)
  final String _userId = 'demo_user';

  // Stores chat messages: {role: 'user'|'model', text: '...', imageBytes: Uint8List?}
  final List<Map<String, dynamic>> _messages = [];
  
  bool _isLoading = false;
  bool _ttsReady = false;
  
  // Live mode state
  bool _isLiveMode = false;
  bool _isLiveSessionActive = false;
  bool _isRecording = false;
  bool _isAiSpeaking = false; // Track when AI is responding with audio
  StreamSubscription<dynamic>? _responseSubscription;

  // Transcription toggle
  bool _transcriptionEnabled = true;
  
  // Chat history from database
  List<Map<String, dynamic>> _chatHistory = [];

  // Pending image for attach-then-type feature
  XFile? _pendingImage;
  Uint8List? _pendingImageBytes;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initAudio();
    _initDatabase();
  }
  
  Future<void> _initDatabase() async {
    // Cleanup old conversations on app start
    await _databaseService.cleanupOldConversations(_userId);
    // Load chat history
    await _loadChatHistory();
  }
  
  Future<void> _loadChatHistory() async {
    try {
      final history = await _databaseService.getRecentConversations(_userId);
      setState(() {
        _chatHistory = history;
      });
    } catch (e) {
      debugPrint('Error loading chat history: $e');
    }
  }

  Future<void> _initTts() async {
    await _flutterTts.awaitSpeakCompletion(true);
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setPitch(1.0);
    _ttsReady = true;
  }

  Future<void> _initAudio() async {
    await _audioInput.init();
    await _audioOutput.init();
  }

  @override
  void dispose() {
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
    await _databaseService.saveMessage(
      _userId, 
      'user', 
      messageContent, 
      hasImage: imageBytes != null,
    );

    try {
      // Get user's location for POI context (optional)
      double? latitude;
      double? longitude;
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        );
        latitude = position.latitude;
        longitude = position.longitude;
      } catch (e) {
        // Location not available, continue without it
        debugPrint('Location not available: $e');
      }
      
      // Build context from database
      final databaseContext = await _databaseService.buildContextForAI(
        _userId,
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
      await _databaseService.saveMessage(_userId, 'assistant', response);
      
      setState(() {
        _messages.add({
          'role': 'model',
          'text': response,
        });
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
    if (!_ttsReady) {
      debugPrint("TTS not ready yet, skipping speak.");
      return;
    }
    await _flutterTts.speak(text);
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
          'text': '🎙️ Live session connected. Tap the microphone to start speaking.',
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
              _messages.add({
                'role': 'model',
                'text': part.text,
              });
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

      // Handle transcriptions if available
      if (message.inputTranscription?.text != null) {
        setState(() {
          _messages.add({
            'role': 'user',
            'text': '🎤 ${message.inputTranscription!.text}',
          });
        });
        _scrollToBottom();
      }

      if (message.outputTranscription?.text != null) {
        setState(() {
          _messages.add({
            'role': 'model',
            'text': message.outputTranscription!.text!,
          });
        });
        _scrollToBottom();
      }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording error: $e')),
        );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Visual Assistant"),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Settings & History',
          ),
        ),
        actions: [
          // Transcription Toggle
          IconButton(
            icon: Icon(
              _transcriptionEnabled ? Icons.subtitles : Icons.subtitles_off,
              color: _transcriptionEnabled ? Colors.greenAccent : Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _transcriptionEnabled = !_transcriptionEnabled;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_transcriptionEnabled 
                      ? 'Transcription enabled' 
                      : 'Transcription disabled'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            tooltip: 'Toggle Transcription',
          ),
          // Live Mode Toggle
          Row(
            children: [
              Text(
                _isLiveMode ? 'Live' : 'Normal',
                style: TextStyle(
                  color: _isLiveMode ? Colors.greenAccent : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Switch(
                value: _isLiveMode,
                onChanged: _isLoading ? null : _toggleLiveMode,
                activeColor: Colors.greenAccent,
                inactiveThumbColor: Colors.grey,
              ),
            ],
          ),
          if (_isLiveSessionActive)
            Container(
              margin: const EdgeInsets.only(right: 8),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _isAiSpeaking ? Colors.orangeAccent : Colors.greenAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_isAiSpeaking ? Colors.orangeAccent : Colors.greenAccent).withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: Colors.grey.shade900,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.black,
                child: const Row(
                  children: [
                    Icon(Icons.settings, color: Colors.yellowAccent, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Settings & History',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Transcription Toggle
              SwitchListTile(
                title: const Text('Transcription', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  _transcriptionEnabled ? 'Show text transcripts' : 'Audio only',
                  style: const TextStyle(color: Colors.white70),
                ),
                value: _transcriptionEnabled,
                onChanged: (value) {
                  setState(() {
                    _transcriptionEnabled = value;
                  });
                },
                activeColor: Colors.greenAccent,
                secondary: Icon(
                  _transcriptionEnabled ? Icons.subtitles : Icons.subtitles_off,
                  color: _transcriptionEnabled ? Colors.greenAccent : Colors.grey,
                ),
              ),
              
              const Divider(color: Colors.grey),
              
              // Chat History Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Chat History (3 days)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.yellowAccent,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      onPressed: _loadChatHistory,
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
              ),
              
              // Chat History List
              Expanded(
                child: _chatHistory.isEmpty
                    ? const Center(
                        child: Text(
                          'No chat history yet',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _chatHistory.length,
                        itemBuilder: (context, index) {
                          final msg = _chatHistory[index];
                          final role = msg['role']?.toString() ?? 'unknown';
                          final content = msg['content']?.toString() ?? '';
                          final timestamp = msg['timestamp'];
                          final isUser = role == 'user';
                          
                          // Format timestamp
                          String timeStr = '';
                          if (timestamp is num) {
                            final date = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt());
                            timeStr = '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
                          }
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isUser ? Colors.cyanAccent : Colors.yellowAccent,
                              radius: 16,
                              child: Icon(
                                isUser ? Icons.person : Icons.smart_toy,
                                size: 18,
                                color: Colors.black,
                              ),
                            ),
                            title: Text(
                              content.length > 50 ? '${content.substring(0, 50)}...' : content,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                            subtitle: Text(
                              timeStr,
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            onTap: () {
                              // Load this message into chat
                              setState(() {
                                _messages.add({
                                  'role': role,
                                  'text': content,
                                });
                              });
                              Navigator.pop(context);
                              _scrollToBottom();
                            },
                          );
                        },
                      ),
              ),
              
              // Clear History Button
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _messages.clear();
                    });
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear Current Chat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.3),
                    foregroundColor: Colors.redAccent,
                    minimumSize: const Size(double.infinity, 48),
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
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final role = msg['role'];
                final isUser = role == 'user';
                final isSystem = role == 'system';
                final Uint8List? imageBytes = msg['imageBytes'];
                
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(16),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    decoration: BoxDecoration(
                      color: isSystem 
                          ? Colors.blueGrey.shade800 
                          : (isUser ? const Color(0xFF333333) : const Color(0xFF111111)),
                      border: Border.all(
                        color: isSystem 
                            ? Colors.blueAccent 
                            : (isUser ? Colors.white : Colors.yellowAccent),
                        width: 2
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           // Show actual image thumbnail if available
                           if (imageBytes != null)
                               Padding(
                                   padding: const EdgeInsets.only(bottom: 8.0),
                                   child: ClipRRect(
                                     borderRadius: BorderRadius.circular(8),
                                     child: Image.memory(
                                       imageBytes,
                                       width: 200,
                                       height: 200,
                                       fit: BoxFit.cover,
                                     ),
                                   ),
                               ),
                           if (msg['text'] != null && msg['text'].isNotEmpty)
                             Text(
                               msg['text'],
                               style: TextStyle(
                                 fontSize: isSystem ? 16 : 20,
                                 fontStyle: isSystem ? FontStyle.italic : FontStyle.normal,
                               ),
                             ),
                        ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(color: Colors.yellowAccent),
            ),
          
          // Pending image preview
          if (_pendingImage != null && _pendingImageBytes != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey.shade900,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _pendingImageBytes!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Image attached. Type a message or tap send.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                    onPressed: _clearPendingImage,
                  ),
                ],
              ),
            ),
          
          // Input Area
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.black,
              border: Border(top: BorderSide(color: Colors.yellowAccent, width: 2)),
            ),
            child: Row(
              children: [
                if (_isLiveMode) ...[
                  // Live Mode: Large microphone button
                  Expanded(
                    child: Center(
                      child: Column(
                        children: [
                          if (_isAiSpeaking)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                '🔊 AI is speaking...',
                                style: TextStyle(color: Colors.orangeAccent),
                              ),
                            ),
                          Semantics(
                            label: _isRecording ? "Stop Recording" : "Start Recording",
                            button: true,
                            child: GestureDetector(
                              onTap: _isLiveSessionActive && !_isAiSpeaking ? _toggleRecording : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: _isRecording ? 100 : 80,
                                height: _isRecording ? 100 : 80,
                                decoration: BoxDecoration(
                                  color: _isAiSpeaking 
                                      ? Colors.grey 
                                      : (_isRecording ? Colors.redAccent : Colors.greenAccent),
                                  shape: BoxShape.circle,
                                  boxShadow: _isRecording ? [
                                    BoxShadow(
                                      color: Colors.redAccent.withValues(alpha: 0.6),
                                      blurRadius: 20,
                                      spreadRadius: 4,
                                    ),
                                  ] : [],
                                ),
                                child: Icon(
                                  _isRecording ? Icons.stop : Icons.mic,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // Normal Mode: Camera, Gallery, Text, Send buttons
                  Semantics(
                      label: "Take Picture",
                      button: true,
                      child: IconButton(
                          icon: const Icon(Icons.camera_alt, color: Colors.cyanAccent, size: 40),
                          onPressed: () => _pickImage(ImageSource.camera),
                          style: IconButton.styleFrom(
                              padding: const EdgeInsets.all(12),
                          ),
                      ),
                  ),
                  Semantics(
                      label: "Choose from Gallery",
                      button: true,
                      child: IconButton(
                          icon: const Icon(Icons.photo_library, color: Colors.cyanAccent, size: 40),
                          onPressed: () => _pickImage(ImageSource.gallery),
                      ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                          hintText: _pendingImage != null 
                              ? "Add a message about the image..." 
                              : "Type message...",
                          filled: true,
                          fillColor: const Color(0xFF222222),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onSubmitted: (val) => _handleSendMessage(text: val),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Semantics(
                      label: "Send Message",
                      button: true,
                      child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.yellowAccent, size: 40),
                          onPressed: () => _handleSendMessage(text: _textController.text),
                      ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
