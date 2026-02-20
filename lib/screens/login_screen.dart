import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;

  // Show verification card instead of the login form
  bool _showVerificationCard = false;
  String _verificationEmail = '';

  @override
  void initState() {
    super.initState();
    // If main.dart sent us here because user is signed in but not verified,
    // show the verification card immediately
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      _showVerificationCard = true;
      _verificationEmail = user.email ?? '';
    }
  }

  // ─── Email / Password ────────────────────────────

  Future<void> _submitEmailPassword() async {
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
      if (_isLogin) {
        // ── Login ──
        final cred = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Block unverified users
        if (cred.user != null && !cred.user!.emailVerified) {
          // Don't sign out — userChanges() in main.dart will show LoginScreen
          setState(() {
            _verificationEmail = email;
            _showVerificationCard = true;
          });
          return;
        }
        // If verified → userChanges() in main.dart navigates to HomeScreen
      } else {
        // ── Register ──
        final cred = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Send verification email
        await cred.user?.sendEmailVerification();

        // Show success snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification email sent! Check your inbox.'),
              duration: Duration(seconds: 4),
            ),
          );
        }

        // Don't sign out — main.dart sees unverified user → shows LoginScreen
        // Show the verification card
        setState(() {
          _verificationEmail = email;
          _showVerificationCard = true;
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

  // ─── Resend verification ─────────────────────────

  Future<void> _resendVerificationEmail() async {
    setState(() => _isLoading = true);
    try {
      // User is still signed in, just resend
      await _auth.currentUser?.sendEmailVerification();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email resent! Check your inbox.')),
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

  // ─── Check if user has verified ──────────────────

  Future<void> _checkVerification() async {
    setState(() => _isLoading = true);
    try {
      // Reload the current user to get fresh emailVerified status
      await _auth.currentUser?.reload();

      // After reload(), userChanges() stream in main.dart will fire.
      // If emailVerified is now true, main.dart will show HomeScreen.
      // If still false, we're still here.
      final user = _auth.currentUser;
      if (user == null || !user.emailVerified) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email not verified yet. Please check your inbox and click the link.'),
            ),
          );
        }
      }
      // If verified, userChanges() will automatically navigate away
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
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
      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize();
      final GoogleSignInAccount googleUser = await googleSignIn.authenticate();

      final idToken = googleUser.authentication.idToken;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Google Sign-In failed');
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Password Reset ──────────────────────────────

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email to reset your password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset link sent! Check your email.')),
        );
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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ─── Build ───────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showVerificationCard
            ? 'Verify Your Email'
            : (_isLogin ? 'Login' : 'Register')),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: _showVerificationCard
              ? _buildVerificationCard()
              : _buildLoginForm(),
        ),
      ),
    );
  }

  // ─── Verification Card ───────────────────────────

  Widget _buildVerificationCard() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.mark_email_unread_outlined,
              size: 80, color: Colors.blue.shade600),
        ),
        const SizedBox(height: 32),
        const Text(
          'Check Your Email',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Text(
          'We sent a verification link to\n$_verificationEmail\n\nPlease click the link in the email to verify your account.',
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
              ElevatedButton.icon(
                onPressed: _checkVerification,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("I've Verified My Email",
                    style: TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _resendVerificationEmail,
                icon: const Icon(Icons.email_outlined),
                label: const Text('Resend Verification Email',
                    style: TextStyle(fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  await _auth.signOut();
                  setState(() {
                    _showVerificationCard = false;
                    _isLogin = true;
                    _errorMessage = null;
                  });
                },
                child: const Text('Back to Login',
                    style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
      ],
    );
  }

  // ─── Login / Register Form ───────────────────────

  Widget _buildLoginForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_outline, size: 80, color: Colors.blueAccent),
        const SizedBox(height: 32),
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12.0),
            margin: const EdgeInsets.only(bottom: 16.0),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade800),
              textAlign: TextAlign.center,
            ),
          ),
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email),
          ),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock),
          ),
          obscureText: true,
          autocorrect: false,
        ),
        const SizedBox(height: 24),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: _submitEmailPassword,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  _isLogin ? 'Sign In' : 'Sign Up',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _errorMessage = null;
                  });
                },
                child: Text(
                  _isLogin
                      ? 'Don\'t have an account? Register here'
                      : 'Already have an account? Sign in here',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if (_isLogin)
                TextButton(
                  onPressed: _resetPassword,
                  child: const Text(
                    'Forgot Password? Reset Here',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text('OR'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _signInWithGoogle,
                icon: const Icon(Icons.g_mobiledata, size: 36),
                label: const Text(
                  'Continue with Google',
                  style: TextStyle(fontSize: 18),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
