import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState
    extends State<ChangePasswordScreen> {

  final _currentController =
      TextEditingController();

  final _newController =
      TextEditingController();

  final _confirmController =
      TextEditingController();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
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

        title: const Text(
          "Change Password",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),

          child: Column(
            children: [

              const SizedBox(height: 20),

              Container(
                width: 90,
                height: 90,

                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF5FA2),
                      Color(0xFF8A4DFF),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(.4),
                      blurRadius: 20,
                    )
                  ],
                ),

                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                "Change Password",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Keep your account secure by updating your password regularly.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                ),
              ),

              const SizedBox(height: 40),

              _passwordField(
                "Current Password",
                _currentController,
                _showCurrent,
                () {
                  setState(() {
                    _showCurrent = !_showCurrent;
                  });
                },
              ),

              const SizedBox(height: 20),

              _passwordField(
                "New Password",
                _newController,
                _showNew,
                () {
                  setState(() {
                    _showNew = !_showNew;
                  });
                },
              ),

              const SizedBox(height: 20),

              _passwordField(
                "Confirm Password",
                _confirmController,
                _showConfirm,
                () {
                  setState(() {
                    _showConfirm = !_showConfirm;
                  });
                },
              ),

              const SizedBox(height: 35),

              _rule(
                _newController.text.length >= 8,
                "Minimum 8 characters",
              ),

              _rule(
                RegExp(r'[A-Z]')
                    .hasMatch(_newController.text),
                "Uppercase letter",
              ),

              _rule(
                RegExp(r'[a-z]')
                    .hasMatch(_newController.text),
                "Lowercase letter",
              ),

              _rule(
                RegExp(r'[0-9]')
                    .hasMatch(_newController.text),
                "Number",
              ),

              _rule(
                RegExp(r'[!@#\$%^&*(),.?":{}|<>]')
                    .hasMatch(_newController.text),
                "Special character",
              ),

              const SizedBox(height: 45),

              SizedBox(
                width: double.infinity,
                height: 56,

                child: ElevatedButton(

                  onPressed: () {

                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF8A4DFF),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(18),
                    ),
                  ),

                  child: const Text(
                    "Change Password",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
        );
      },
    );
  }

  Widget _passwordField(
    String hint,
    TextEditingController controller,
    bool visible,
    VoidCallback toggle,
  ) {

    return TextField(

      controller: controller,

      obscureText: !visible,

      onChanged: (_) {
        setState(() {});
      },

      style: const TextStyle(
        color: Colors.white,
      ),

      decoration: InputDecoration(

        filled: true,

        fillColor:
            const Color(0xFF1A1A36),

        hintText: hint,

        hintStyle: const TextStyle(
          color: Colors.white54,
        ),

        border: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(18),
        ),

        suffixIcon: IconButton(
          icon: Icon(
            visible
                ? Icons.visibility
                : Icons.visibility_off,
            color: Colors.white70,
          ),
          onPressed: toggle,
        ),
      ),
    );
  }

  Widget _rule(
    bool ok,
    String text,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 8),

      child: Row(
        children: [

          Icon(
            ok
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: ok
                ? Colors.green
                : Colors.white38,
            size: 18,
          ),

          const SizedBox(width: 10),

          Text(
            text,
            style: TextStyle(
              color: ok
                  ? Colors.green
                  : Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}