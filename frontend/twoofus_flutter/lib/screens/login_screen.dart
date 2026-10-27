import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../services/api_service.dart';
import '../services/call_service.dart';
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
  bool _isPasswordVisible = false;
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

      if (!mounted) return;
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
      if (!mounted) return;
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
                    child: Icon(
                      Icons.shield_outlined,
                      color: theme.isDark ? theme.accentBright : theme.accentFill,
                      size: 20,
                    ),
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

  Future<void> _handleBiometricAuth() async {
    HapticFeedback.lightImpact();
    final localAuth = LocalAuthentication();
    try {
      final canCheck = await localAuth.canCheckBiometrics;
      final isSupported = await localAuth.isDeviceSupported();
      if (!canCheck && !isSupported) {
        if (!mounted) return;
        AppFeedback.showInfo(context, "Biometrics are not configured or available on this device.");
        return;
      }

      final authenticated = await localAuth.authenticate(
        localizedReason: 'Scan biometrics to sign in to TwoOfUs',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (authenticated && mounted) {
        final token = await Session.getToken();
        final userId = await Session.getUserId();
        if (token != null && token.isNotEmpty && userId != null) {
          await _handleSuccessfulAuth({
            "access_token": token,
            "user_id": userId,
            "username": await Session.getUsername() ?? "User",
            "email": await Session.getEmail() ?? "",
          });
        } else {
          if (!mounted) return;
          AppFeedback.showInfo(context, "Please sign in with password first to enable biometric quick access.");
        }
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, "Biometric authentication failed: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F2EB),
      body: Stack(
        children: [
          // Background scenic mountain landscape with soft golden curves
          Positioned.fill(
            child: Image.asset(
              'assets/images/login_bg.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const ColoredBox(
                color: Color(0xFFF7F2EB),
              ),
            ),
          ),

          // Main scrollable content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),

                      // App Emblem & Branding
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFF191715),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0x33D4AF37),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: CustomPaint(
                            size: const Size(38, 38),
                            painter: TwoOfUsLogoPainter(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Brand Title
                      const Text(
                        "TwoOfUs",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E1A17),
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Brand Subtitle
                      const Text(
                        "A private space for every connection.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: Color(0xFF756F67),
                          fontSize: 13,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Floating Frosted Form Card
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF7F2).withOpacity(0.92),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.85),
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 28,
                                  offset: Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Card Title
                                const Text(
                                  "Welcome back",
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1C1A17),
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 4),

                                // Card Subtitle
                                const Text(
                                  "Continue your private conversations.",
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: Color(0xFF7D776F),
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Error message callout
                                if (_errorMessage != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFBA3838).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFBA3838).withOpacity(0.35),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.error_outline_rounded,
                                          color: Color(0xFFBA3838),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _errorMessage!,
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              color: Color(0xFFBA3838),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                ],

                                // Email or Username Label
                                const Text(
                                  "Email or Username",
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF423D37),
                                  ),
                                ),
                                const SizedBox(height: 7),

                                // Email Input Pill
                                Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3EEE6).withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFE2DBD0),
                                      width: 1,
                                    ),
                                  ),
                                  child: TextField(
                                    controller: emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      color: Color(0xFF1E1A17),
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: "Enter your email or username",
                                      hintStyle: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 13.5,
                                        color: Color(0xFFA39A8F),
                                      ),
                                      prefixIcon: Icon(
                                        Icons.mail_outline_rounded,
                                        size: 19,
                                        color: Color(0xFF8A8277),
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Password Label
                                const Text(
                                  "Password",
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF423D37),
                                  ),
                                ),
                                const SizedBox(height: 7),

                                // Password Input Pill
                                Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3EEE6).withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFE2DBD0),
                                      width: 1,
                                    ),
                                  ),
                                  child: TextField(
                                    controller: passwordController,
                                    obscureText: !_isPasswordVisible,
                                    onSubmitted: (_) => login(),
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      color: Color(0xFF1E1A17),
                                    ),
                                    decoration: InputDecoration(
                                      hintText: "Enter your password",
                                      hintStyle: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 13.5,
                                        color: Color(0xFFA39A8F),
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                        size: 19,
                                        color: Color(0xFF8A8277),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isPasswordVisible
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: 19,
                                          color: const Color(0xFF8A8277),
                                        ),
                                        onPressed: () {
                                          setState(() => _isPasswordVisible = !_isPasswordVisible);
                                        },
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                  ),
                                ),

                                // Forgot Password Link
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
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.only(top: 6, bottom: 12),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      "Forgot password?",
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: Color(0xFFB88235),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Dark Pill "Sign In" Button with Gold Arrow
                                GestureDetector(
                                  onTap: isLoading ? null : login,
                                  child: Container(
                                    height: 52,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF262320), Color(0xFF161413)],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                      borderRadius: BorderRadius.circular(26),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x35000000),
                                          blurRadius: 14,
                                          offset: Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: isLoading
                                        ? const Center(
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: Colors.white,
                                              ),
                                            ),
                                          )
                                        : Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              const Center(
                                                child: Text(
                                                  "Sign In",
                                                  style: TextStyle(
                                                    fontFamily: 'Inter',
                                                    color: Colors.white,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 0.1,
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                right: 7,
                                                child: Container(
                                                  width: 38,
                                                  height: 38,
                                                  decoration: const BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    gradient: LinearGradient(
                                                      colors: [Color(0xFFE8BA60), Color(0xFFC79237)],
                                                      begin: Alignment.topLeft,
                                                      end: Alignment.bottomRight,
                                                    ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.arrow_forward_rounded,
                                                    color: Color(0xFF1D170A),
                                                    size: 18,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 18),

                                // OR Divider
                                const Row(
                                  children: [
                                    Expanded(
                                      child: Divider(
                                        color: Color(0xFFE5DDD2),
                                        thickness: 1,
                                      ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 14),
                                      child: Text(
                                        "OR",
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          color: Color(0xFFA8A196),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(
                                        color: Color(0xFFE5DDD2),
                                        thickness: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),

                                // Sign in with Biometrics
                                GestureDetector(
                                  onTap: _handleBiometricAuth,
                                  child: Container(
                                    height: 48,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFBF8F4),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: const Color(0xFFE5DDD2),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.fingerprint_rounded,
                                          size: 20,
                                          color: Color(0xFF4A443D),
                                        ),
                                        SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            "Sign in with Biometrics",
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF2B2723),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Create Account Row
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    const Text(
                                      "Don't have an account? ",
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: Color(0xFF756F67),
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const RegisterScreen(),
                                          ),
                                        );
                                      },
                                      child: const Text(
                                        "Create account >",
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          color: Color(0xFFB88235),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5,
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
                      const SizedBox(height: 24),

                      // Carousel Dots Indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 16,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD49B42),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0x66B0A89C),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: Color(0x66B0A89C),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Bottom Tagline & Privacy Statement
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 14,
                              height: 2,
                              decoration: BoxDecoration(
                                color: const Color(0xFFB88235),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Your connections.\nYour privacy.",
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11.5,
                                height: 1.35,
                                color: Color(0xFF6E685F),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the TwoOfUs couple heart + keyhole logo
class TwoOfUsLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paintStroke = Paint()
      ..color = const Color(0xFFE5B562)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final paintFill = Paint()
      ..color = const Color(0xFFE5B562)
      ..style = PaintingStyle.fill;

    // Two Heads (Circles)
    final leftHeadCenter = Offset(w * 0.35, h * 0.22);
    final rightHeadCenter = Offset(w * 0.65, h * 0.22);
    final headRadius = w * 0.115;

    canvas.drawCircle(leftHeadCenter, headRadius, paintStroke);
    canvas.drawCircle(rightHeadCenter, headRadius, paintStroke);

    // Heart Body Path
    final heartPath = Path();
    heartPath.moveTo(w * 0.50, h * 0.44); // Top center dip

    // Left lobe down to tip
    heartPath.cubicTo(
      w * 0.40, h * 0.33,
      w * 0.12, h * 0.42,
      w * 0.18, h * 0.64,
    );
    heartPath.cubicTo(
      w * 0.22, h * 0.77,
      w * 0.38, h * 0.85,
      w * 0.50, h * 0.90, // Bottom tip
    );

    // Right lobe back up to center dip
    heartPath.cubicTo(
      w * 0.62, h * 0.85,
      w * 0.78, h * 0.77,
      w * 0.82, h * 0.64,
    );
    heartPath.cubicTo(
      w * 0.88, h * 0.42,
      w * 0.60, h * 0.33,
      w * 0.50, h * 0.44,
    );

    canvas.drawPath(heartPath, paintStroke);

    // Center Keyhole
    final keyholeCircleCenter = Offset(w * 0.50, h * 0.60);
    final keyholeCircleRadius = w * 0.055;
    canvas.drawCircle(keyholeCircleCenter, keyholeCircleRadius, paintFill);

    final keyholePath = Path();
    keyholePath.moveTo(w * 0.47, h * 0.62);
    keyholePath.lineTo(w * 0.45, h * 0.73);
    keyholePath.lineTo(w * 0.55, h * 0.73);
    keyholePath.lineTo(w * 0.53, h * 0.62);
    keyholePath.close();

    canvas.drawPath(keyholePath, paintFill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}