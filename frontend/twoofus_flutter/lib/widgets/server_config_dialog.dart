import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/theme_controller.dart';

class ServerConfigDialog extends StatefulWidget {
  const ServerConfigDialog({super.key});

  static Future<void> show(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const ServerConfigDialog(),
    );
  }

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog> {
  final _urlCtrl = TextEditingController();
  bool _isTesting = false;
  bool? _testPassed;
  String? _statusMessage;

  Color get _bg => ThemeController.currentTheme.value.bg;
  Color get _surf => ThemeController.currentTheme.value.surface;
  Color get _rose => ThemeController.currentTheme.value.primary;
  Color get _violet => ThemeController.currentTheme.value.secondary;
  bool get _isDark => ThemeController.currentTheme.value.textPrimary == Colors.white;

  Color get _text => _isDark ? Colors.white : const Color(0xFF1A0A2E);
  Color get _sub => _isDark
      ? Colors.white.withValues(alpha: 0.6)
      : Colors.black.withValues(alpha: 0.55);

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = ApiService.baseUrl;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAutoDiscover() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isTesting = true;
      _testPassed = null;
      _statusMessage = "Auto-scanning current network for backend server...";
    });

    final found = await ApiService.autoDiscoverServer(forceScan: true);
    if (!mounted) return;

    if (found != null) {
      setState(() {
        _isTesting = false;
        _testPassed = true;
        _urlCtrl.text = found;
        _statusMessage = "Discovered TwoOfUs server at $found! 🚀";
      });
    } else {
      setState(() {
        _isTesting = false;
        _testPassed = false;
        _statusMessage = "No server responded on this network. Ensure backend is running.";
      });
    }
  }

  Future<void> _runTest() async {
    final target = _urlCtrl.text.trim();
    if (target.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() {
      _isTesting = true;
      _testPassed = null;
      _statusMessage = "Pinging backend server...";
    });

    final success = await ApiService.testConnection(target);
    if (!mounted) return;

    setState(() {
      _isTesting = false;
      _testPassed = success;
      _statusMessage = success
          ? "Connected successfully to TwoOfUs backend! 🚀"
          : "Connection failed. Ensure backend is running and phone is on same Wi-Fi.";
    });
  }

  Future<void> _saveAndApply() async {
    final target = _urlCtrl.text.trim();
    await ApiService.setCustomBaseUrl(target.isNotEmpty ? target : null);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.pinkAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Server updated: ${ApiService.baseUrl}",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF200F35),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _surf,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_rose, _violet]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.dns_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            "Backend Server",
            style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "TwoOfUs automatically discovers and connects to the backend server across any Wi-Fi or Hotspot network.",
              style: TextStyle(color: _sub, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),

            // Server URL Input
            Container(
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: TextField(
                controller: _urlCtrl,
                style: TextStyle(color: _text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "http://192.168.1.X:8000",
                  hintStyle: TextStyle(color: _sub.withValues(alpha: 0.4), fontSize: 13),
                  prefixIcon: Icon(Icons.link_rounded, color: _rose, size: 20),
                  suffixIcon: IconButton(
                    icon: _isTesting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.pinkAccent),
                          )
                        : const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 20),
                    tooltip: "Test Connection",
                    onPressed: _isTesting ? null : _runTest,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isTesting ? null : _runAutoDiscover,
                icon: const Icon(Icons.radar_rounded, size: 18, color: Colors.amberAccent),
                label: const Text(
                  "⚡ Auto-Detect Server IP",
                  style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.amberAccent, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            if (_statusMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _testPassed == true
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _testPassed == true
                        ? Colors.green.withValues(alpha: 0.4)
                        : Colors.red.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testPassed == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      color: _testPassed == true ? Colors.greenAccent : Colors.redAccent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          color: _testPassed == true ? Colors.greenAccent : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),
            Text(
              "QUICK PRESETS:",
              style: TextStyle(
                color: _sub,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _presetChip("🔄 Current (${ApiService.baseUrl})", ApiService.baseUrl),
                _presetChip("📱 Emulator (10.0.2.2)", "http://10.0.2.2:8000"),
                _presetChip("💻 Localhost (127.0.0.1)", "http://127.0.0.1:8000"),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel", style: TextStyle(color: _sub)),
        ),
        ElevatedButton(
          onPressed: _saveAndApply,
          style: ElevatedButton.styleFrom(
            backgroundColor: _rose,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text("Save & Apply", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _presetChip(String label, String url) {
    final isSelected = _urlCtrl.text.trim() == url;
    return InkWell(
      onTap: () {
        setState(() {
          _urlCtrl.text = url;
          _testPassed = null;
          _statusMessage = null;
        });
        HapticFeedback.selectionClick();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _rose.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _rose : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? _rose : _text,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
