import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '../services/tts_service.dart';
import '../core/localization/app_localizations.dart';
import '../core/services/language_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestoreService = FirestoreService();
  final TTSService _ttsService = TTSService();
  final LanguageNotifier _langNotifier = LanguageNotifier();
  final _formKey = GlobalKey<FormState>();

  // ─── Controllers ─────────────────────────────────
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _langNotifier.addListener(_onLangChanged);
    _ttsService.initialize();
    _loadProfileData();
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProfileData() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _errorMessage = 'User not logged in';
        _isLoading = false;
      });
      return;
    }

    try {
      final profileData = await _firestoreService.getUserProfile(user.uid);
      if (profileData != null) {
        _fullNameController.text = profileData['fullName'] ?? '';
        _phoneController.text = profileData['phone'] ?? '';
        _emergencyNameController.text =
            profileData['emergencyContactName'] ?? '';
        _emergencyPhoneController.text =
            profileData['emergencyContactPhone'] ?? '';
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to load profile: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Validators ──────────────────────────────────
  String? _validateFullName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Full name is required';
    if (value.trim().length < 2) return 'Name must be at least 2 characters';
    if (!RegExp(r"^[a-zA-Z\s\-']+$").hasMatch(value.trim())) {
      return 'Name can only contain letters, spaces, hyphens';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(cleaned)) {
      return 'Enter a valid phone number (8-15 digits)';
    }
    return null;
  }

  String? _validateEmergencyName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Emergency contact name is required';
    }
    if (value.trim().length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  // ─── Save Action ─────────────────────────────────
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final strings = AppLocalizations(_langNotifier.languageCode);
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Update auth display name
      await user.updateDisplayName(_fullNameController.text.trim());

      // 2. Save profile to Firestore using UID
      final data = <String, dynamic>{
        'fullName': _fullNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'emergencyContactName': _emergencyNameController.text.trim(),
        'emergencyContactPhone': _emergencyPhoneController.text.trim(),
        'uid': user.uid,
        'email': user.email,
        'lastUpdated': DateTime.now().toIso8601String(),
      };

      await _firestoreService.updateUserProfile(user.uid, data);

      await _ttsService.speakUrgent(strings.get('profileUpdated'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(strings.get('profileUpdated')),
            backgroundColor: Colors.black,
          ),
        );
      }
    } catch (e) {
      await _ttsService.speakUrgent(strings.get('updateFailed'));
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    final strings = AppLocalizations(_langNotifier.languageCode);
    await _ttsService.speakUrgent(strings.get('signingOut'));
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _langNotifier.removeListener(_onLangChanged);
    _fullNameController.dispose();
    _phoneController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations(_langNotifier.languageCode);
    final title = strings.get('profileTitle');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.account_circle,
                        size: 80,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(height: 24),

                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: const Color(0xFFE0E0E0),
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // ── Personal Info Section ──
                      _buildSectionHeader(
                        strings.get('personalInfo'),
                        Icons.person,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _fullNameController,
                        validator: _validateFullName,
                        decoration: InputDecoration(
                          labelText: strings.get('fullNameRequired'),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.badge_outlined),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _phoneController,
                        validator: _validatePhone,
                        decoration: InputDecoration(
                          labelText: strings.get('phoneRequired'),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.phone_outlined),
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\+\-\s\(\)]'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ── Emergency Contact Section ──
                      _buildSectionHeader(
                        strings.get('emergencyContact'),
                        Icons.emergency_outlined,
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _emergencyNameController,
                        validator: _validateEmergencyName,
                        decoration: InputDecoration(
                          labelText: strings.get(
                            'emergencyContactNameRequired',
                          ),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(
                            Icons.contact_emergency_outlined,
                          ),
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _emergencyPhoneController,
                        validator: _validatePhone,
                        decoration: InputDecoration(
                          labelText: strings.get(
                            'emergencyContactPhoneRequired',
                          ),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.phone_callback_outlined),
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[\d\+\-\s\(\)]'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // ── Save Button ──
                      Semantics(
                        button: true,
                        label: strings.get('updateProfile'),
                        child: ElevatedButton(
                          onPressed: _saveProfile,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor:
                                Theme.of(context).colorScheme.primary,
                            foregroundColor:
                                Theme.of(context).colorScheme.onPrimary,
                          ),
                          child: Text(
                            strings.get('updateProfile'),
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),

                      // ── Sign Out Button ──
                      Semantics(
                        button: true,
                        label: strings.get('signOut'),
                        child: OutlinedButton.icon(
                          onPressed: _signOut,
                          icon: Icon(
                            Icons.logout,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          label: Text(
                            strings.get('signOut'),
                            style: TextStyle(
                              fontSize: 18,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
