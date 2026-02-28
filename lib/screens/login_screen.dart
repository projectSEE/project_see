import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/firestore_service.dart';
import '../core/localization/app_localizations.dart';
import '../core/services/language_provider.dart';

class LoginScreen extends StatefulWidget {
  final bool isNewGoogleUser;
  final User? googleUser;

  const LoginScreen({super.key, this.isNewGoogleUser = false, this.googleUser});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  final LanguageNotifier _langNotifier = LanguageNotifier();

  // ─── Controllers ─────────────────────────────────
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();

  // ─── State ───────────────────────────────────────
  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // Page states: 'login', 'register', 'verification', 'resetPassword', 'googleRegister'
  String _currentPage = 'login';
  String _verificationEmail = '';
  bool _resetEmailSent = false;

  @override
  void initState() {
    super.initState();
    _langNotifier.addListener(_onLangChanged);

    // Initialize Google Sign-In once at startup
    _initGoogleSignIn();

    // If this is a new Google user, go straight to Google registration
    if (widget.isNewGoogleUser && widget.googleUser != null) {
      _currentPage = 'googleRegister';
      // Pre-fill name and email from Google account
      _fullNameController.text = widget.googleUser!.displayName ?? '';
      _emailController.text = widget.googleUser!.email ?? '';
    } else {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        _currentPage = 'verification';
        _verificationEmail = user.email ?? '';
      }
    }
  }

  // ─── Google Sign-In Initialization ───────────────

  // Web client ID from google-services.json (client_type: 3)
  static const String _webClientId =
      '777852765437-v0nv168rtu25i0q2ope14iufd3991bus.apps.googleusercontent.com';

  bool _googleSignInInitialized = false;

  Future<void> _initGoogleSignIn() async {
    try {
      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(serverClientId: _webClientId);
      _googleSignInInitialized = true;
      debugPrint('✅ Google Sign-In initialized successfully');
    } catch (e) {
      debugPrint('❌ Google Sign-In initialization failed: $e');
    }
  }

  void _onLangChanged() {
    if (mounted) setState(() {});
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

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    if (!RegExp(r'^[\w\.\-]+@[\w\.\-]+\.\w{2,}$').hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Password must be at least 6 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Include at least 1 uppercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Include at least 1 number';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != _passwordController.text) return 'Passwords do not match';
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

  String? _validateEmergencyPhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Emergency contact phone is required';
    }
    final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(cleaned)) {
      return 'Enter a valid phone number (8-15 digits)';
    }
    return null;
  }

  // ─── Register Flow ───────────────────────────────

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Create Firebase Auth account
      final cred = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 2. Update display name
      await cred.user?.updateDisplayName(_fullNameController.text.trim());

      // 3. Save profile to Firestore (keyed by Firebase UID)
      await _firestoreService
          .updateUserProfile(cred.user!.uid, <String, dynamic>{
            'fullName': _fullNameController.text.trim(),
            'email': _emailController.text.trim(),
            'phone': _phoneController.text.trim(),
            'emergencyContactName': _emergencyNameController.text.trim(),
            'emergencyContactPhone': _emergencyPhoneController.text.trim(),
            'uid': cred.user!.uid,
            'createdAt': DateTime.now().toIso8601String(),
          });

      // 4. Send verification email
      await cred.user?.sendEmailVerification();

      // 5. Show verification card
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification email sent! Check your inbox.'),
            duration: Duration(seconds: 4),
          ),
        );
        setState(() {
          _verificationEmail = _emailController.text.trim();
          _currentPage = 'verification';
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Registration failed');
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Login Flow ──────────────────────────────────

  Future<void> _submitLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter email and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (cred.user != null && !cred.user!.emailVerified) {
        setState(() {
          _verificationEmail = email;
          _currentPage = 'verification';
        });
        return;
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Authentication failed');
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Resend & Check Verification ─────────────────

  Future<void> _resendVerificationEmail() async {
    setState(() => _isLoading = true);
    try {
      await _auth.currentUser?.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification email resent! Check your inbox.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resend: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkVerification() async {
    setState(() => _isLoading = true);
    try {
      await _auth.currentUser?.reload();
      final user = _auth.currentUser;
      if (user == null || !user.emailVerified) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Email not verified yet. Check your inbox and click the link.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Google Sign-In ──────────────────────────────

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Ensure initialization is complete
      if (!_googleSignInInitialized) {
        debugPrint('⏳ Google Sign-In not yet initialized, initializing now...');
        await _initGoogleSignIn();
      }

      debugPrint('🔐 Starting Google Sign-In authenticate()...');
      final googleSignIn = GoogleSignIn.instance;
      final GoogleSignInAccount? googleUser = await googleSignIn.authenticate();

      if (googleUser == null) {
        debugPrint('⚠️ Google Sign-In returned null (user cancelled)');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      debugPrint('✅ Google account selected: ${googleUser.email}');
      debugPrint('🔑 Getting ID token...');

      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        debugPrint(
          '❌ ID token is null! Check SHA-1 fingerprint in Firebase Console.',
        );
        if (mounted) {
          setState(
            () =>
                _errorMessage =
                    'Google Sign-In failed: Could not get authentication token. '
                    'Please ensure your SHA-1 fingerprint is registered in Firebase Console.',
          );
        }
        return;
      }

      debugPrint('✅ Got ID token, signing in with Firebase...');
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      final userCred = await _auth.signInWithCredential(credential);
      debugPrint('✅ Firebase Sign-In successful: ${userCred.user?.email}');
    } on GoogleSignInException catch (e) {
      debugPrint('❌ GoogleSignInException: code=${e.code}, message=$e');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        debugPrint('ℹ️ Google Sign-In cancelled by user');
        // Don't show error for user cancellation
      } else {
        setState(() => _errorMessage = 'Google Sign-In failed: ${e.code}');
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('❌ FirebaseAuthException: ${e.code} - ${e.message}');
      setState(() => _errorMessage = e.message ?? 'Google Sign-In failed');
    } catch (e, stackTrace) {
      debugPrint('❌ Unexpected error during Google Sign-In: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() => _errorMessage = 'Google Sign-In failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Google Registration (Complete Profile) ──────

  Future<void> _submitGoogleRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = _auth.currentUser;
      if (user == null) {
        setState(() => _errorMessage = 'No user signed in. Please try again.');
        return;
      }

      final fullName = _fullNameController.text.trim();

      // Update display name if different
      if (user.displayName != fullName) {
        await user.updateDisplayName(fullName);
      }

      // Save profile to Firestore
      await _firestoreService.updateUserProfile(fullName, {
        'fullName': fullName,
        'email': user.email ?? _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'emergencyContactName': _emergencyNameController.text.trim(),
        'emergencyContactPhone': _emergencyPhoneController.text.trim(),
        'uid': user.uid,
        'provider': 'google',
        'createdAt': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ Google user profile saved successfully');

      // Force auth state refresh so main.dart re-checks profile
      if (mounted) {
        await user.reload();
        // Trigger userChanges() stream by reloading
        await user.getIdToken(true);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Registration failed');
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Password Reset ──────────────────────────────

  Future<void> _sendResetEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email address.');
      return;
    }
    final emailError = _validateEmail(email);
    if (emailError != null) {
      setState(() => _errorMessage = emailError);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        setState(() => _resetEmailSent = true);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Failed to send reset email');
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Dispose ─────────────────────────────────────

  @override
  void dispose() {
    _langNotifier.removeListener(_onLangChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations(_langNotifier.languageCode);
    String title;
    switch (_currentPage) {
      case 'register':
        title = strings.get('createAccount');
        break;
      case 'googleRegister':
        title = 'Complete Your Profile';
        break;
      case 'verification':
        title = strings.get('verifyEmail');
        break;
      case 'resetPassword':
        title = strings.get('resetPasswordTitle');
        break;
      default:
        title = strings.get('login');
    }

    final showBackButton =
        _currentPage == 'register' || _currentPage == 'resetPassword';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        leading:
            showBackButton
                ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed:
                      () => setState(() {
                        _currentPage = 'login';
                        _isLogin = true;
                        _errorMessage = null;
                        _resetEmailSent = false;
                      }),
                )
                : null,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: _buildCurrentPage(),
        ),
      ),
    );
  }

  Widget _buildCurrentPage() {
    final strings = AppLocalizations(_langNotifier.languageCode);
    switch (_currentPage) {
      case 'register':
        return _buildRegistrationForm(strings);
      case 'googleRegister':
        return _buildGoogleRegistrationForm();
      case 'verification':
        return _buildVerificationCard(strings);
      case 'resetPassword':
        return _buildResetPasswordPage(strings);
      default:
        return _buildLoginForm(strings);
    }
  }

  // ─── Login Form ──────────────────────────────────

  Widget _buildLoginForm(AppLocalizations strings) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_outline, size: 80, color: Colors.blueAccent),
        const SizedBox(height: 32),
        if (_errorMessage != null) _buildErrorBanner(),
        TextField(
          controller: _emailController,
          decoration: InputDecoration(
            labelText: strings.get('email'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.email),
          ),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: strings.get('password'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              tooltip: 'Toggle password visibility',
              onPressed:
                  () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          obscureText: _obscurePassword,
          autocorrect: false,
        ),
        const SizedBox(height: 24),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                label: strings.get('signIn'),
                child: ElevatedButton(
                  onPressed: _submitLogin,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    strings.get('signIn'),
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed:
                    () => setState(() {
                      _currentPage = 'register';
                      _errorMessage = null;
                    }),
                child: Text(
                  strings.get('dontHaveAccountRegister'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              TextButton(
                onPressed:
                    () => setState(() {
                      _currentPage = 'resetPassword';
                      _errorMessage = null;
                      _resetEmailSent = false;
                    }),
                child: Text(
                  strings.get('forgotPasswordResetHere'),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(strings.get('or')),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: strings.get('continueWithGoogle'),
                child: OutlinedButton.icon(
                  onPressed: _signInWithGoogle,
                  icon: const Icon(Icons.g_mobiledata, size: 36),
                  label: Text(
                    strings.get('continueWithGoogle'),
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ─── Registration Form ───────────────────────────

  Widget _buildRegistrationForm(AppLocalizations strings) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          const Icon(
            Icons.person_add_outlined,
            size: 60,
            color: Colors.blueAccent,
          ),
          const SizedBox(height: 16),
          Text(
            strings.get('createYourAccount'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            strings.get('fillInDetails'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),

          if (_errorMessage != null) _buildErrorBanner(),

          // ── Personal Info Section ──
          _buildSectionHeader(strings.get('personalInfo'), Icons.person),
          const SizedBox(height: 12),

          // Full Name
          TextFormField(
            controller: _fullNameController,
            validator: _validateFullName,
            decoration: InputDecoration(
              labelText: strings.get('fullNameRequired'),
              hintText: strings.get('nameHint'),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
            textCapitalization: TextCapitalization.words,
            autocorrect: false,
          ),
          const SizedBox(height: 16),

          // Email
          TextFormField(
            controller: _emailController,
            validator: _validateEmail,
            decoration: InputDecoration(
              labelText: strings.get('emailRequired'),
              hintText: strings.get('emailHint'),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          const SizedBox(height: 16),

          // Phone
          TextFormField(
            controller: _phoneController,
            validator: _validatePhone,
            decoration: InputDecoration(
              labelText: strings.get('phoneRequired'),
              hintText: strings.get('phoneHint'),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.phone_outlined),
            ),
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\+\-\s\(\)]')),
            ],
          ),
          const SizedBox(height: 24),

          // ── Password Section ──
          _buildSectionHeader(strings.get('setPassword'), Icons.lock_outline),
          const SizedBox(height: 12),

          // Password
          TextFormField(
            controller: _passwordController,
            validator: _validatePassword,
            decoration: InputDecoration(
              labelText: strings.get('passwordRequired'),
              hintText: strings.get('passwordHint'),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: 'Toggle password visibility',
                onPressed:
                    () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
            autocorrect: false,
          ),
          const SizedBox(height: 16),

          // Confirm Password
          TextFormField(
            controller: _confirmPasswordController,
            validator: _validateConfirmPassword,
            decoration: InputDecoration(
              labelText: strings.get('confirmPasswordRequired'),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_reset),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: 'Toggle password visibility',
                onPressed:
                    () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            obscureText: _obscureConfirm,
            autocorrect: false,
          ),
          const SizedBox(height: 24),

          // ── Emergency Contact Section ──
          _buildSectionHeader(
            strings.get('emergencyContact'),
            Icons.emergency_outlined,
          ),
          const SizedBox(height: 4),
          Text(
            strings.get('emergencyContactDesc'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),

          // Emergency Contact Name
          TextFormField(
            controller: _emergencyNameController,
            validator: _validateEmergencyName,
            decoration: InputDecoration(
              labelText: strings.get('emergencyContactNameRequired'),
              hintText: strings.get('nameHint'),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.contact_emergency_outlined),
            ),
            textCapitalization: TextCapitalization.words,
            autocorrect: false,
          ),
          const SizedBox(height: 16),

          // Emergency Contact Phone
          TextFormField(
            controller: _emergencyPhoneController,
            validator: _validateEmergencyPhone,
            decoration: InputDecoration(
              labelText: strings.get('emergencyContactPhoneRequired'),
              hintText: strings.get('emergencyPhoneHint'),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.phone_callback_outlined),
            ),
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\+\-\s\(\)]')),
            ],
          ),
          const SizedBox(height: 32),

          // ── Submit Button ──
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            Semantics(
              button: true,
              label: strings.get('createAccount'),
              child: ElevatedButton(
                onPressed: _submitRegistration,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  strings.get('createAccount'),
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),

          const SizedBox(height: 16),
          TextButton(
            onPressed:
                () => setState(() {
                  _currentPage = 'login';
                  _isLogin = true;
                  _errorMessage = null;
                }),
            child: Text(
              strings.get('alreadyHaveAccountSignIn'),
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Verification Card ───────────────────────────

  Widget _buildVerificationCard(AppLocalizations strings) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.mark_email_unread_outlined,
            size: 80,
            color: Colors.blue.shade600,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          strings.get('checkYourEmail'),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          '${strings.get('verificationLinkSent')}\n$_verificationEmail\n\n${strings.get('clickLinkToVerify')}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 32),
        if (_isLoading)
          const CircularProgressIndicator()
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                label: strings.get('iveVerifiedMyEmail'),
                child: ElevatedButton.icon(
                  onPressed: _checkVerification,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    strings.get('iveVerifiedMyEmail'),
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                button: true,
                label: strings.get('resendVerificationEmail'),
                child: OutlinedButton.icon(
                  onPressed: _resendVerificationEmail,
                  icon: const Icon(Icons.email_outlined),
                  label: Text(
                    strings.get('resendVerificationEmail'),
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  await _auth.signOut();
                  setState(() {
                    _currentPage = 'login';
                    _errorMessage = null;
                  });
                },
                child: Text(
                  strings.get('backToLogin'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ─── Reset Password Page ──────────────────────────

  Widget _buildResetPasswordPage(AppLocalizations strings) {
    // After the reset email is sent, show a confirmation card
    if (_resetEmailSent) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mark_email_read_outlined,
              size: 80,
              color: Colors.orange.shade600,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            strings.get('resetLinkSent'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            '${strings.get('weSentResetLink')}\n${_emailController.text.trim()}\n\n${strings.get('resetLinkSentDesc')}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 32),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                label: strings.get('backToLogin'),
                child: ElevatedButton.icon(
                  onPressed:
                      () => setState(() {
                        _currentPage = 'login';
                        _resetEmailSent = false;
                        _errorMessage = null;
                        _passwordController.clear();
                      }),
                  icon: const Icon(Icons.login),
                  label: Text(
                    strings.get('backToLogin'),
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _resetEmailSent = false);
                },
                icon: const Icon(Icons.refresh),
                label: Text(
                  strings.get('tryDifferentEmail'),
                  style: const TextStyle(fontSize: 16),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Email input form
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.lock_reset, size: 80, color: Colors.blue.shade600),
        ),
        const SizedBox(height: 32),
        Text(
          strings.get('forgotYourPassword'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          strings.get('forgotYourPasswordDesc'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        if (_errorMessage != null) _buildErrorBanner(),
        TextField(
          controller: _emailController,
          decoration: InputDecoration(
            labelText: strings.get('emailAddress'),
            hintText: strings.get('emailHint'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
        ),
        const SizedBox(height: 24),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else
          Semantics(
            button: true,
            label: strings.get('sendResetLink'),
            child: ElevatedButton(
              onPressed: _sendResetEmail,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              child: Text(
                strings.get('sendResetLink'),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Google Registration Form ───────────────────

  Widget _buildGoogleRegistrationForm() {
    final user = widget.googleUser ?? _auth.currentUser;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          const Icon(
            Icons.person_add_outlined,
            size: 60,
            color: Colors.blueAccent,
          ),
          const SizedBox(height: 16),
          const Text(
            'Complete Your Profile',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome, ${user?.displayName ?? 'there'}! Please fill in a few more details to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),

          if (_errorMessage != null) _buildErrorBanner(),

          // ── Google account info (read-only) ──
          _buildSectionHeader('Google Account', Icons.account_circle),
          const SizedBox(height: 12),

          // Full Name (pre-filled, editable)
          TextFormField(
            controller: _fullNameController,
            validator: _validateFullName,
            decoration: const InputDecoration(
              labelText: 'Full Name *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            textCapitalization: TextCapitalization.words,
            autocorrect: false,
          ),
          const SizedBox(height: 16),

          // Email (read-only from Google)
          TextFormField(
            controller: _emailController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Email Address',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.email_outlined),
              filled: true,
              fillColor: Colors.grey.shade100,
            ),
          ),
          const SizedBox(height: 24),

          // ── Contact Info Section ──
          _buildSectionHeader('Contact Information', Icons.phone),
          const SizedBox(height: 12),

          // Phone
          TextFormField(
            controller: _phoneController,
            validator: _validatePhone,
            decoration: const InputDecoration(
              labelText: 'Phone Number *',
              hintText: 'e.g. +60123456789',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\+\-\s\(\)]')),
            ],
          ),
          const SizedBox(height: 24),

          // ── Emergency Contact Section ──
          _buildSectionHeader('Emergency Contact', Icons.emergency_outlined),
          const SizedBox(height: 4),
          Text(
            'This person will be contacted in case of emergencies detected by the app.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),

          // Emergency Contact Name
          TextFormField(
            controller: _emergencyNameController,
            validator: _validateEmergencyName,
            decoration: const InputDecoration(
              labelText: 'Emergency Contact Name *',
              hintText: 'e.g. Jane Doe',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.contact_emergency_outlined),
            ),
            textCapitalization: TextCapitalization.words,
            autocorrect: false,
          ),
          const SizedBox(height: 16),

          // Emergency Contact Phone
          TextFormField(
            controller: _emergencyPhoneController,
            validator: _validateEmergencyPhone,
            decoration: const InputDecoration(
              labelText: 'Emergency Contact Phone *',
              hintText: 'e.g. +60198765432',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone_callback_outlined),
            ),
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\+\-\s\(\)]')),
            ],
          ),
          const SizedBox(height: 32),

          // ── Submit Button ──
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            ElevatedButton(
              onPressed: _submitGoogleRegistration,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Complete Registration',
                style: TextStyle(fontSize: 18),
              ),
            ),

          const SizedBox(height: 16),
          TextButton(
            onPressed: () async {
              await _auth.signOut();
              if (mounted) {
                setState(() {
                  _currentPage = 'login';
                  _errorMessage = null;
                });
              }
            },
            child: const Text(
              'Sign out and go back',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blueAccent),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.blueAccent,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12.0),
      margin: const EdgeInsets.only(bottom: 16.0),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }
}
