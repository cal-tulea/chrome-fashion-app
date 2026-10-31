import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/security.dart';
import '../../core/theme.dart';
import '../../services/analytics_service.dart';
import '../../services/google_auth_service.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading       = false;
  bool _googleLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // Fast client-side guards before hitting the network
    if (!SecurityUtils.isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await AnalyticsService.logLogin('email');
    } on FirebaseAuthException catch (e) {
      setState(() => _error = SecurityUtils.friendlyAuthError(e.code));
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() { _googleLoading = true; _error = null; });
    try {
      final cred = await GoogleAuthService.signIn();
      if (cred != null) {
        await AnalyticsService.logLogin('google');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Google sign-in failed. Try again.');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _googleLoading;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),

                  // ── Wordmark ──────────────────────────────────────────────
                  Text(
                    'Chromé',
                    style: GoogleFonts.cormorantGaramond(
                      fontSize: 42,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Dress for your palette.',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),

                  const SizedBox(height: 56),

                  Text(
                    'Welcome back',
                    style: GoogleFonts.cormorantGaramond(
                      fontSize: 30,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to continue',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Email / password fields ───────────────────────────────
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => busy ? null : _login(),
                    style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: GoogleFonts.dmSans(color: AppColors.error, fontSize: 13),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── Sign in button ────────────────────────────────────────
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: busy ? null : _login,
                      child: _loading
                          ? const _Spinner()
                          : Text(
                              'SIGN IN',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                                color: AppColors.background,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Divider ───────────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(child: Divider(color: AppColors.textSecondary.withValues(alpha: 0.3))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: AppColors.textSecondary.withValues(alpha: 0.3))),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Google Sign-In ────────────────────────────────────────
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : _googleSignIn,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppColors.textSecondary.withValues(alpha: 0.35),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _googleLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Image.asset(
                              'assets/icons/google_logo.png',
                              width: 20,
                              height: 20,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.g_mobiledata,
                                size: 22,
                                color: Colors.white70,
                              ),
                            ),
                      label: Text(
                        'Continue with Google',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Sign up link ──────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'New here? ',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      GestureDetector(
                        onTap: busy
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const SignupScreen(),
                                  ),
                                ),
                        child: Text(
                          'Create account',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ],
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

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
      );
}
