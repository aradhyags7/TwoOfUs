import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/call_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/app_feedback.dart';
import '../utils/session.dart';
import '../widgets/design_system/design_system.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'chat_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    emailController.addListener(_onTextChanged);
    passwordController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSuccessfulAuth(Map<String, dynamic> authData) async {
    await Session.saveLogin(
      token: authData["access_token"],
      userId: authData["user_id"],
      username: authData["username"],
      email: authData["email"],
    );

    CallService.startIncomingCallWatcher();

    if (!mounted) return;

    final pairStatus = await ApiService.getPairStatus(
      authData["user_id"],
      token: authData["access_token"],
    );

    if (!mounted) return;

    if (pairStatus != null &&
        pairStatus["connected"] == true &&
        pairStatus["partner_id"] != null) {
      final partnerId = pairStatus["partner_id"] as int;
      final partnerName = (pairStatus["partner_name"] ?? "Partner").toString();
      await Session.savePartner(partnerId, partnerName);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            partnerId: partnerId,
            partnerName: partnerName.isNotEmpty ? partnerName : "Partner",
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  void _show2FALoginSheet(String tempToken) {
    final codeCtrl = TextEditingController();
    bool isVerifying = false;
    bool isSendingEmail = false;
    String? errorText;
    String? successText;
    int emailCooldown = 0;

    AppSheet.show(
      context: context,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final theme = context.appTheme;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.border, width: 1),
                    ),
                    child: Icon(Icons.shield_outlined, color: theme.isDark ? theme.accentBright : theme.accentFill, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Two-Factor Authentication",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.textPrimary,
                          ),
                        ),
                        Text(
                          "Enter the code from your authenticator app",
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AppTextField(
                controller: codeCtrl,
                hintText: "6-digit verification code",
                keyboardType: TextInputType.number,
                autofocus: true,
                errorText: errorText,
              ),
              if (successText != null) ...[
                const SizedBox(height: 8),
                Text(
                  successText!,
                  style: TextStyle(fontFamily: 'Inter', color: theme.success, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              AppButton(
                text: "Verify & Continue",
                isLoading: isVerifying,
                isFullWidth: true,
                onPressed: () async {
                  final code = codeCtrl.text.trim();
                  if (code.isEmpty) return;
                  setSheetState(() {
                    isVerifying = true;
                    errorText = null;
                  });

                  final verifyRes = await ApiService.verify2FALogin(
                    tempToken: tempToken,
                    code: code,
                  );

                  if (!mounted) return;

                  if (verifyRes != null && verifyRes.containsKey("access_token")) {
                    Navigator.pop(sheetCtx);
                    await _handleSuccessfulAuth(verifyRes);
                  } else {
                    setSheetState(() {
                      isVerifying = false;
                      errorText = verifyRes?["error"] ?? "Invalid code. Try again.";
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: (isSendingEmail || emailCooldown > 0)
                    ? null
                    : () async {
                        setSheetState(() {
                          isSendingEmail = true;
                          errorText = null;
                        });
                        final res = await ApiService.send2FAEmailCode(tempToken: tempToken);
                        setSheetState(() => isSendingEmail = false);
                        if (res != null && !res.containsKey("error")) {
                          setSheetState(() {
                            emailCooldown = 60;
                            successText = "Verification code sent to ${res['email'] ?? 'your email'}.";
                          });
                        } else {
                          setSheetState(() {
                            errorText = res?["error"] ?? "Failed to send email code.";
                          });
                        }
                      },
                icon: isSendingEmail
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.mail_outline_rounded, size: 16, color: theme.textSecondary),
                label: Text(
                  emailCooldown > 0
                      ? "Resend email code in ${emailCooldown}s"
                      : "Send verification code via email",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> login() async {
    HapticFeedback.lightImpact();
    setState(() => isLoading = true);
    try {
      final result = await ApiService.login(
        emailController.text.trim(),
        passwordController.text.trim(),
      );

      if (!mounted) return;

      if (result != null && result["requires_2fa"] == true) {
        final tempToken = result["temp_token"] as String;
        _show2FALoginSheet(tempToken);
      } else if (result != null && result.containsKey("access_token")) {
        await _handleSuccessfulAuth(result);
      } else {
        final errMsg = (result != null && result.containsKey("error"))
            ? result["error"].toString()
            : "Incorrect email or password";
        setState(() => _errorMessage = errMsg);
        AppFeedback.showError(
          context,
          errMsg,
          title: "Sign In Failed",
        );
      }
    } catch (_) {
      if (!mounted) return;
      const errMsg = "Cannot connect to server. Check your connection.";
      setState(() => _errorMessage = errMsg);
      AppFeedback.showError(
        context,
        errMsg,
        title: "Connection Error",
      );
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
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // App Emblem
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
                            Icons.lock_rounded,
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
                        "TwoOfUs",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: activeTheme.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Subtitle
                      Text(
                        "End-to-end encrypted messaging",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: activeTheme.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Error message callout
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

                      // Email / Username input
                      AppTextField(
                        controller: emailController,
                        label: "Email or Username",
                        hintText: "Enter your account email or username",
                        keyboardType: TextInputType.emailAddress,
                        prefixIcon: const Icon(Icons.mail_outline_rounded),
                      ),
                      const SizedBox(height: 16),

                      // Password input
                      AppTextField(
                        controller: passwordController,
                        label: "Password",
                        hintText: "Enter your password",
                        isPassword: true,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        onSubmitted: (_) => login(),
                      ),

                      // Forgot password
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ForgotPasswordScreen(
                                  initialEmailOrUsername: emailController.text.trim(),
                                ),
                              ),
                            );
                          },
                          child: Text(
                            "Forgot password?",
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: activeTheme.isDark
                                  ? activeTheme.accentBright
                                  : activeTheme.accentFill,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Submit button
                      AppButton(
                        text: "Sign In",
                        isLoading: isLoading,
                        isFullWidth: true,
                        onPressed: login,
                      ),
                      const SizedBox(height: 20),

                      // Sign up row
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            "Don't have an account?",
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: activeTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                            child: Text(
                              "Create account",
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