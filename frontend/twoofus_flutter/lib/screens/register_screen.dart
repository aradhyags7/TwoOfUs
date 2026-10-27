import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../utils/app_feedback.dart';
import 'login_screen.dart';

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
  bool _isPasswordVisible = false;
  String? _errorMessage;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    usernameController.addListener(_onTextChanged);
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Back Button at Top-Left
                      Align(
                        alignment: Alignment.centerLeft,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF7F2).withOpacity(0.9),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.85),
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x10000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Color(0xFF1E1A17),
                              size: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

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
                                  "Create Account",
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
                                  "Start your private space today.",
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

                                // Username Label
                                const Text(
                                  "Username",
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF423D37),
                                  ),
                                ),
                                const SizedBox(height: 7),

                                // Username Input Pill
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
                                    controller: usernameController,
                                    keyboardType: TextInputType.text,
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      color: Color(0xFF1E1A17),
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: "Choose a display username",
                                      hintStyle: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 13.5,
                                        color: Color(0xFFA39A8F),
                                      ),
                                      prefixIcon: Icon(
                                        Icons.person_outline_rounded,
                                        size: 19,
                                        color: Color(0xFF8A8277),
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Email Label
                                const Text(
                                  "Email",
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
                                      hintText: "Enter your email address",
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
                                    onSubmitted: (_) => register(),
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 14,
                                      color: Color(0xFF1E1A17),
                                    ),
                                    decoration: InputDecoration(
                                      hintText: "Minimum 6 characters",
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
                                const SizedBox(height: 24),

                                // Dark Pill "Create Account" Button with Gold Arrow
                                GestureDetector(
                                  onTap: isLoading ? null : register,
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
                                                  "Create Account",
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

                                // Continue with Google Button
                                GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    AppFeedback.showInfo(
                                      context,
                                      "Google Sign-In will be available in the upcoming release. Please register with your username and email.",
                                    );
                                  },
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
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CustomPaint(
                                          size: const Size(18, 18),
                                          painter: GoogleLogoPainter(),
                                        ),
                                        const SizedBox(width: 10),
                                        const Flexible(
                                          child: Text(
                                            "Continue with Google",
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

                                // Already have an account? Sign in
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    const Text(
                                      "Already have an account? ",
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        color: Color(0xFF756F67),
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: const Text(
                                        "Sign in",
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
                      const SizedBox(height: 16),
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

/// Custom painter for the Google "G" logo
class GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final strokeWidth = w * 0.22;
    final radius = (w - strokeWidth) / 2;
    final center = Offset(w / 2, h / 2);

    final rect = Rect.fromCircle(center: center, radius: radius);

    final paintBlue = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final paintGreen = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final paintYellow = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final paintRed = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Red arc (top)
    canvas.drawArc(rect, -2.4, 1.3, false, paintRed);
    // Yellow arc (left)
    canvas.drawArc(rect, -1.1, 1.2, false, paintYellow);
    // Green arc (bottom)
    canvas.drawArc(rect, 0.1, 1.4, false, paintGreen);
    // Blue arc (right)
    canvas.drawArc(rect, 1.5, 0.9, false, paintBlue);

    // Blue horizontal bar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    final barRect = Rect.fromLTWH(w * 0.44, h * 0.5 - strokeWidth / 2, w * 0.52, strokeWidth);
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}