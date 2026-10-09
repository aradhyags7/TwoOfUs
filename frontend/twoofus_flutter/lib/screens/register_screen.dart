import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../widgets/design_system/design_system.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  String? _errorMessage;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (isError) {
      setState(() => _errorMessage = message);
      AppFeedback.showError(context, message);
    } else {
      AppFeedback.showSuccess(context, message);
    }
  }

  Future<void> register() async {
    HapticFeedback.lightImpact();
    final username = usernameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (username.isEmpty) {
      _showSnack("Please choose a username", isError: true);
      return;
    }
    if (email.isEmpty || !_emailRegex.hasMatch(email)) {
      _showSnack("Please enter a valid email address", isError: true);
      return;
    }
    if (password.length < 6) {
      _showSnack("Password must be at least 6 characters", isError: true);
      return;
    }

    setState(() {
      isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.register(email, username, password);

      if (!mounted) return;

      if (result != null && result.containsKey("user_id")) {
        _showSnack("Account created successfully!");
        Navigator.pop(context);
      } else if (result != null && result.containsKey("error")) {
        _showSnack(result["error"].toString(), isError: true);
      } else {
        _showSnack("Something went wrong — try again", isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack("Connection error: $e", isError: true);
    }
    if (mounted) setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        return Scaffold(
          backgroundColor: activeTheme.bg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: activeTheme.textPrimary, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Emblem
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: activeTheme.surfaceRaised,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: activeTheme.border, width: 1),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.person_add_outlined,
                            size: 26,
                            color: activeTheme.isDark
                                ? activeTheme.accentBright
                                : activeTheme.accentFill,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Title
                      Text(
                        "Create Account",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: activeTheme.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 6),

                      Text(
                        "End-to-end encrypted private messaging",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: activeTheme.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 32),

                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: activeTheme.danger.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: activeTheme.danger.withOpacity(0.4), width: 1),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, color: activeTheme.danger, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: activeTheme.danger,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Username field
                      AppTextField(
                        controller: usernameController,
                        label: "Username",
                        hintText: "Choose a display username",
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                      const SizedBox(height: 16),

                      // Email field
                      AppTextField(
                        controller: emailController,
                        label: "Email",
                        hintText: "Enter your email address",
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(Icons.mail_outline_rounded),
                      ),
                      const SizedBox(height: 16),

                      // Password field
                      AppTextField(
                        controller: passwordController,
                        label: "Password",
                        hintText: "Minimum 6 characters",
                        isPassword: true,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        onSubmitted: (_) => register(),
                      ),
                      const SizedBox(height: 28),

                      // Submit button
                      AppButton(
                        text: "Create Account",
                        isLoading: isLoading,
                        isFullWidth: true,
                        onPressed: register,
                      ),
                      const SizedBox(height: 20),

                      // Sign in row
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            "Already have an account?",
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: activeTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              "Sign in",
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: activeTheme.isDark
                                    ? activeTheme.accentBright
                                    : activeTheme.accentFill,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
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
      },
    );
  }
}