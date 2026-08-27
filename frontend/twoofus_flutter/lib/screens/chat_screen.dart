import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/e2ee_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';
import '../widgets/passcode_lock_button.dart';
import 'account_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'partner_profile_screen.dart';
import 'security_screen.dart';
import 'theme_selection_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../models/media.dart';
import '../models/diary_memory.dart';
import '../widgets/chat_media_bubble.dart';
import '../widgets/full_screen_image_viewer.dart';
import '../widgets/media_composer_modal.dart';
import '../widgets/encryption_verification_modal.dart';
import '../services/call_service.dart';
import 'media_gallery_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TwoOfUs — ChatScreen
// ─────────────────────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final int partnerId;
  final String partnerName;

  const ChatScreen({
    super.key,
    required this.partnerId,
    required this.partnerName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {

  // ── Controllers ──────────────────────────────────────────────────────────
  final _msgCtrl     = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final _memoryCtrl  = TextEditingController();

  // ── Search State ──────────────────────────────────────────────────────────
  final _searchCtrl       = TextEditingController();
  final _searchFocusNode  = FocusNode();
  bool _isSearching       = false;
  String _searchQuery     = '';
  List<int> _matchingIndices = [];
  int _currentMatchIndex  = 0;

  // ── Attachment State ──────────────────────────────────────────────────────
  XFile? _selectedImage;
  String? _selectedFileName;

  // ── Data ─────────────────────────────────────────────────────────────────
  List<Message> _messages = [];
  int?   _myId;
  String _myUsername = '';
  String _userToken = '';
  String? _partnerPubKey;
  bool   _loading    = true;
  bool   _isSending  = false;

  // ── Theme & Preferences ───────────────────────────────────────────────────
  bool _isDark               = true;
  bool _isOnline             = true;
  bool _isPartnerTyping      = false;
  bool _notificationsEnabled = true;
  bool _isPartnerVerified    = false;

  // ── Panels ────────────────────────────────────────────────────────────────
  bool _leftOpen  = false;   // memories  (swipe →)
  bool _rightOpen = false;   // settings  (swipe ←)

  // ── Chat state ────────────────────────────────────────────────────────────
  Message?    _replyingTo;
  Message?    _editingMsg;
  final Set<int>    _deletedIds  = {};
  final Map<int, String> _reactions = {};

  // ── Calendar & Couple Diary State ──────────────────────────────────────────
  List<DiaryMemoryItem> _sharedMemories = [];
  bool _loadingMemories = false;
  int _diaryTab = 0; // 0 = 📔 Diary Notes, 1 = 🖼️ Photo Album
  DateTime _calMonth = DateTime.now();
  DateTime? _selDate = DateTime.now();
  String _selectedMoodEmoji = '❤️';
  File? _memorySelectedPhoto;
  bool _isSavingMemory = false;

  // ── Animation ─────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── Palette ───────────────────────────────────────────────────────────────
  Color get _rose      => ThemeController.currentTheme.value.primary;
  Color get _violet    => ThemeController.currentTheme.value.secondary;
  Color get _lavender  => ThemeController.currentTheme.value.gradientEnd;
  Color get _darkBg    => ThemeController.currentTheme.value.bg;
  Color get _darkSurf  => ThemeController.currentTheme.value.surface;
  static const _lightBg   = Color(0xFFF4F0FF);
  static const _lightSurf = Color(0xFFFFFFFF);

  Color get _bg     => _isDark ? _darkBg    : _lightBg;
  Color get _surf   => _isDark ? _darkSurf  : _lightSurf;
  Color get _text   => _isDark ? Colors.white : const Color(0xFF1A0A2E);
  Color get _sub    => _isDark ? Colors.white.withOpacity(0.42) : Colors.black.withOpacity(0.42);
  Color get _border => _isDark ? ThemeController.currentTheme.value.border : Colors.black.withOpacity(0.07);
  Color get _msgBg  => _isDark ? ThemeController.currentTheme.value.bubblePartner : const Color(0xFFEDE9FF);

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _initialize();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _memoryCtrl.dispose();
    _pulseCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> _initialize() async {
    _myId = await Session.getUserId();
    final prefs = await SharedPreferences.getInstance();
    final token = await Session.getToken();
    if (mounted) {
      setState(() {
        _myUsername = prefs.getString('username') ?? 'You';
        _userToken = token ?? prefs.getString('token') ?? '';
      });
    }
    try {
      await E2EEService.initialize();
      _partnerPubKey = await E2EEService.getPartnerPublicKey(widget.partnerId, token: _userToken);
      final verified = await E2EEService.isPartnerVerified(widget.partnerId);
      if (mounted) setState(() => _isPartnerVerified = verified);
      await _loadMessages();
    } catch (e) {
      if (kDebugMode) print("LOAD MESSAGES ERROR: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  Future<void> _loadMessages() async {
    if (_myId == null) return;
    final result = await ApiService.getMessages(_myId!, widget.partnerId);
    final rawMessages = result.map<Message>((e) => Message.fromJson(e)).toList();

    List<Message> decryptedMessages = [];
    for (var m in rawMessages) {
      if (m.isEncrypted && m.nonce != null && m.nonce!.isNotEmpty) {
        if (_partnerPubKey != null && _partnerPubKey!.isNotEmpty) {
          final decryptedContent = await E2EEService.decryptText(
            ciphertextBase64: m.content,
            nonceBase64: m.nonce!,
            remotePublicKeyBase64: _partnerPubKey!,
          );
          decryptedMessages.add(Message(
            id: m.id,
            senderId: m.senderId,
            receiverId: m.receiverId,
            content: decryptedContent,
            nonce: m.nonce,
            isEncrypted: true,
            isEdited: m.isEdited,
            createdAt: m.createdAt,
            mediaAttachments: m.mediaAttachments,
          ));
        } else {
          decryptedMessages.add(m);
        }
      } else {
        decryptedMessages.add(m);
      }
    }

    if (mounted) {
      setState(() => _messages = decryptedMessages);
    }
  }

  // ── Attachment Helpers ───────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) {
        setState(() {
          _selectedImage = picked;
          _selectedFileName = picked.name;
        });
      }
    } catch (e) {
      _toast("Failed to pick media", isError: true);
    }
  }

  void _removeSelectedMedia() {
    setState(() {
      _selectedImage = null;
      _selectedFileName = null;
    });
  }

  Future<void> _pickPhotos() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final files = result.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
        if (files.isNotEmpty) {
          _showMediaComposer(files);
          return;
        }
      }
    } catch (_) {
      // Fallback to ImagePicker gallery selection
      try {
        final picker = ImagePicker();
        final pickedImages = await picker.pickMultiImage();
        if (pickedImages.isNotEmpty) {
          _showMediaComposer(pickedImages.map((x) => File(x.path)).toList());
          return;
        }
        final singleImage = await picker.pickImage(source: ImageSource.gallery);
        if (singleImage != null) {
          _showMediaComposer([File(singleImage.path)]);
          return;
        }
      } catch (e) {
        _toast("Error selecting photos: $e", isError: true);
      }
    }
  }

  Future<void> _pickCamera() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (picked != null) {
        _showMediaComposer([File(picked.path)]);
      }
    } catch (e) {
      _toast("Error launching camera: $e", isError: true);
    }
  }

  Future<void> _pickVideos() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final files = result.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
        if (files.isNotEmpty) {
          _showMediaComposer(files);
          return;
        }
      }
    } catch (_) {
      // Fallback to ImagePicker video selection if native FilePicker channel needs restart
      try {
        final picker = ImagePicker();
        final pickedVideo = await picker.pickVideo(source: ImageSource.gallery);
        if (pickedVideo != null) {
          _showMediaComposer([File(pickedVideo.path)]);
          return;
        }
      } catch (e) {
        _toast("Error selecting videos: $e", isError: true);
      }
    }
  }

  Future<void> _pickDocuments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final files = result.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
        if (files.isNotEmpty) {
          _showMediaComposer(files);
        }
      }
    } catch (e) {
      _toast("Error selecting document: $e", isError: true);
    }
  }

  void _showMediaComposer(List<File> files) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => MediaComposerModal(
          receiverId: widget.partnerId,
          selectedFiles: files,
          token: _userToken,
          partnerPubKey: _partnerPubKey,
          onSendComplete: (uploadedMediaIds, caption) async {
            if (_myId != null) {
              String sendContent = caption;
              String? sendNonce;
              bool isEncrypted = false;

              if (caption.isNotEmpty && _partnerPubKey != null && _partnerPubKey!.isNotEmpty) {
                final payload = await E2EEService.encryptText(caption, _partnerPubKey!);
                if (payload != null) {
                  sendContent = payload.ciphertext;
                  sendNonce = payload.nonce;
                  isEncrypted = true;
                }
              }

              final ok = await ApiService.sendMessage(
                _myId!,
                widget.partnerId,
                sendContent,
                nonce: sendNonce,
                isEncrypted: isEncrypted,
                mediaIds: uploadedMediaIds,
              );
              if (ok) {
                await _loadMessages();
                _scrollToBottom();
              }
            }
          },
        ),
      ),
    );
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: _surf,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: _border),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: _sub.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "Share Media & Content",
              style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _attachOption(
                  icon: Icons.camera_alt_rounded,
                  label: "Camera",
                  color: Colors.pinkAccent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickCamera();
                  },
                ),
                _attachOption(
                  icon: Icons.photo_library_rounded,
                  label: "Photos",
                  color: Colors.purpleAccent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickPhotos();
                  },
                ),
                _attachOption(
                  icon: Icons.videocam_rounded,
                  label: "Video",
                  color: Colors.deepPurpleAccent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickVideos();
                  },
                ),
                _attachOption(
                  icon: Icons.insert_drive_file_rounded,
                  label: "Document",
                  color: Colors.blueAccent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickDocuments();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.15),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreviewBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _rose.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          if (_selectedImage != null && !kIsWeb)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(_selectedImage!.path),
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(Icons.image_rounded, color: _rose, size: 28),
              ),
            )
          else
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _rose.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.attachment_rounded, color: _rose, size: 22),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedFileName ?? "Photo / Media attached",
                  style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "Ready to send with message",
                  style: TextStyle(color: _sub, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: _sub, size: 18),
            onPressed: _removeSelectedMedia,
          ),
        ],
      ),
    );
  }

  // ── Messaging ─────────────────────────────────────────────────────────────
  Future<void> _sendMessage() async {
    String text = _msgCtrl.text.trim();
    if (text.isEmpty && _selectedImage == null && _selectedFileName == null) return;
    if (_myId == null) return;
    setState(() => _isSending = true);

    if (_selectedImage != null) {
      final label = _selectedFileName ?? 'photo.jpg';
      text = text.isNotEmpty ? "📷 [Photo] $label\n$text" : "📷 [Photo] $label";
    } else if (_selectedFileName != null) {
      text = text.isNotEmpty ? "📁 [File] $_selectedFileName\n$text" : "📁 [File] $_selectedFileName";
    }

    if (_editingMsg != null) {
      String editContent = text;
      String? editNonce;
      bool isEncrypted = false;

      if (_partnerPubKey != null && _partnerPubKey!.isNotEmpty) {
        final payload = await E2EEService.encryptText(text, _partnerPubKey!);
        if (payload != null) {
          editContent = payload.ciphertext;
          editNonce = payload.nonce;
          isEncrypted = true;
        }
      }

      final success = await ApiService.editMessage(
        _editingMsg!.id,
        editContent,
        nonce: editNonce,
        isEncrypted: isEncrypted,
      );
      if (success) {
        _toast("Message updated ❤️");
        _msgCtrl.clear();
        _removeSelectedMedia();
        setState(() {
          _editingMsg = null;
          _replyingTo = null;
        });
        await _loadMessages();
      }
      setState(() => _isSending = false);
      return;
    } else {
      String sendContent = text;
      String? sendNonce;
      bool isEncrypted = false;

      if (_partnerPubKey != null && _partnerPubKey!.isNotEmpty) {
        final payload = await E2EEService.encryptText(text, _partnerPubKey!);
        if (payload != null) {
          sendContent = payload.ciphertext;
          sendNonce = payload.nonce;
          isEncrypted = true;
        }
      }

      final ok = await ApiService.sendMessage(
        _myId!,
        widget.partnerId,
        sendContent,
        nonce: sendNonce,
        isEncrypted: isEncrypted,
      );
      if (ok) {
        _msgCtrl.clear();
        _removeSelectedMedia();
        setState(() { _replyingTo = null; });
        await _loadMessages();
        _scrollToBottom();
      }
    }
    if (mounted) setState(() => _isSending = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _openLeft() {
    setState(() {
      _leftOpen = true;
      _rightOpen = false;
    });
    _loadMemories();
  }
  void _openRight()   => setState(() { _rightOpen = true; _leftOpen = false;  });
  void _closeAll()    => setState(() { _leftOpen = false; _rightOpen = false; });

  // ── Message options ───────────────────────────────────────────────────────
  void _showMsgOptions(Message msg) {
    final isMe = msg.senderId == _myId;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _optionsSheet(ctx, msg, isMe),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _fmtTime(DateTime dt) {
    final now = DateTime.now();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    if (_sameDay(dt, now)) return '$h:$m';
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${mo[dt.month-1]} ${dt.day}  $h:$m';
  }

  String _fmtDateLabel(DateTime dt) {
    final now = DateTime.now();
    if (_sameDay(dt, now)) return 'Today';
    if (_sameDay(dt, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${mo[dt.month-1]} ${dt.day}, ${dt.year}';
  }

  void _toast(String msg, {bool isError = false}) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final topMargin = screenHeight - topPadding - 110;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: isError ? Colors.redAccent : Colors.pinkAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
      backgroundColor: isError ? const Color(0xFF2E0916) : const Color(0xFF1D1826),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 2200),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isError ? Colors.redAccent.withOpacity(0.4) : _rose.withOpacity(0.4)),
      ),
      margin: EdgeInsets.only(
        bottom: topMargin > 100 ? topMargin : 100,
        left: 20,
        right: 20,
      ),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        final sw  = MediaQuery.of(context).size.width;
        final pw  = sw * 0.86;

        return Scaffold(
          backgroundColor: _bg,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          if (_leftOpen || _rightOpen) { _closeAll(); return; }
          final v = d.primaryVelocity ?? 0;
          if (v > 250) _openLeft();
          else if (v < -250) _openRight();
        },
        child: Stack(
          children: [
            // ── Main content ──────────────────────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  _buildAppBar(),
                  Expanded(child: _buildMsgList()),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: (_replyingTo != null || _editingMsg != null)
                        ? _buildContextBar()
                        : const SizedBox.shrink(),
                  ),
                  _buildInputBar(),
                ],
              ),
            ),

            // ── Scrim ─────────────────────────────────────────────────────
            if (_leftOpen || _rightOpen)
              GestureDetector(
                onTap: _closeAll,
                child: Container(color: Colors.black.withOpacity(0.52)),
              ),

            // ── Left panel — Memories (swipe right) ───────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              left: _leftOpen ? 0 : -pw,
              top: 0, bottom: 0,
              width: pw,
              child: _buildMemoryPanel(),
            ),

            // ── Right panel — Settings (swipe left) ───────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              right: _rightOpen ? 0 : -pw,
              top: 0, bottom: 0,
              width: pw,
              child: _buildSettingsPanel(),
            ),
          ],
        ),
      ),
        );
      },
    );
  }

  Future<void> _openPartnerProfile() async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PartnerProfileScreen(
          partnerId: widget.partnerId,
          partnerName: widget.partnerName,
          isOnline: _isOnline,
          messages: _messages,
          memories: _sharedMemories,
        ),
      ),
    );

    if (res == 'open_search' && mounted) {
      _startSearch();
    }
  }

  // ── Search Logic ─────────────────────────────────────────────────────────
  void _startSearch() {
    setState(() {
      _isSearching = true;
      _searchQuery = '';
      _matchingIndices.clear();
      _currentMatchIndex = 0;
    });
    _searchCtrl.clear();
    _searchFocusNode.requestFocus();
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _matchingIndices.clear();
      _currentMatchIndex = 0;
    });
    _searchCtrl.clear();
    _searchFocusNode.unfocus();
  }

  void _onSearchQueryChanged(String text) {
    final query = text.trim().toLowerCase();
    final visible = _messages.where((m) => !_deletedIds.contains(m.id)).toList();
    List<int> matches = [];

    if (query.isNotEmpty) {
      for (int i = 0; i < visible.length; i++) {
        if (visible[i].content.toLowerCase().contains(query)) {
          matches.add(i);
        }
      }
    }

    setState(() {
      _searchQuery = query;
      _matchingIndices = matches;
      _currentMatchIndex = 0;
    });

    if (matches.isNotEmpty) {
      _scrollToMatch(matches[0]);
    }
  }

  void _nextMatch() {
    if (_matchingIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matchingIndices.length;
    });
    _scrollToMatch(_matchingIndices[_currentMatchIndex]);
  }

  void _prevMatch() {
    if (_matchingIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _matchingIndices.length) % _matchingIndices.length;
    });
    _scrollToMatch(_matchingIndices[_currentMatchIndex]);
  }

  void _scrollToMatch(int matchIdx) {
    if (!_scrollCtrl.hasClients) return;
    final double targetOffset = (matchIdx * 68.0).clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    if (_isSearching) {
      return _buildSearchBarAppBar();
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: _surf,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          // Clickable Partner Profile Header Area (Avatar + Name + Status)
          Expanded(
            child: InkWell(
              onTap: _openPartnerProfile,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  children: [
                    // Avatar
                    Hero(
                      tag: 'partner_avatar_${widget.partnerId}',
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [_rose, _violet]),
                          boxShadow: [
                            BoxShadow(
                              color: _rose.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Name + online status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.partnerName,
                                  style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_isOnline) ...[
                                const SizedBox(width: 6),
                                // Pulsing green online dot
                                AnimatedBuilder(
                                  animation: _pulseAnim,
                                  builder: (_, __) => Transform.scale(
                                    scale: _pulseAnim.value,
                                    child: Container(
                                      width: 8, height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.greenAccent,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.greenAccent.withValues(alpha: 0.55),
                                            blurRadius: 6, spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              // Only show lock icon if chats are genuinely E2EE (partner public key is loaded & active)
                              if (_partnerPubKey != null && _partnerPubKey!.isNotEmpty) ...[
                                const SizedBox(width: 5),
                                GestureDetector(
                                  onTap: () async {
                                    await EncryptionVerificationModal.show(
                                      context,
                                      partnerId: widget.partnerId,
                                      partnerName: widget.partnerName,
                                      partnerPubKey: _partnerPubKey,
                                    );
                                    final v = await E2EEService.isPartnerVerified(widget.partnerId);
                                    if (mounted) setState(() => _isPartnerVerified = v);
                                  },
                                  child: Tooltip(
                                    message: _isPartnerVerified
                                        ? "Verified E2EE Session"
                                        : "End-to-End Encrypted (Tap to verify)",
                                    child: Icon(
                                      _isPartnerVerified ? Icons.verified_user_rounded : Icons.lock_rounded,
                                      color: _isPartnerVerified ? Colors.greenAccent : _rose.withValues(alpha: 0.85),
                                      size: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_isPartnerTyping)
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Text(
                                'typing...',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                _isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  color: _isOnline ? Colors.greenAccent.withValues(alpha: 0.85) : _sub,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 1. Video call
          IconButton(
            icon: ShaderMask(
              shaderCallback: (b) => LinearGradient(colors: [_rose, _violet]).createShader(b),
              blendMode: BlendMode.srcIn,
              child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 24),
            ),
            onPressed: () {
              CallService.startCall(
                context: context,
                partnerId: widget.partnerId,
                partnerName: widget.partnerName,
                callType: 'video',
              ).then((_) => _loadMessages());
            },
          ),
          // 2. Voice call
          IconButton(
            icon: ShaderMask(
              shaderCallback: (b) => LinearGradient(colors: [_rose, _violet]).createShader(b),
              blendMode: BlendMode.srcIn,
              child: const Icon(Icons.call_rounded, color: Colors.white, size: 22),
            ),
            onPressed: () {
              CallService.startCall(
                context: context,
                partnerId: widget.partnerId,
                partnerName: widget.partnerName,
                callType: 'voice',
              ).then((_) => _loadMessages());
            },
          ),
          // 3. Search Button
          IconButton(
            icon: ShaderMask(
              shaderCallback: (b) => LinearGradient(colors: [_rose, _violet]).createShader(b),
              blendMode: BlendMode.srcIn,
              child: const Icon(Icons.search_rounded, color: Colors.white, size: 22),
            ),
            onPressed: _startSearch,
          ),
          // 4. Passcode Lock Button
          const PasscodeLockButton(),
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  Widget _buildSearchBarAppBar() {
    final totalMatches = _matchingIndices.length;
    final matchText = _searchQuery.isEmpty
        ? ""
        : (totalMatches > 0
            ? "${_currentMatchIndex + 1}/$totalMatches"
            : "No matches");

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: _surf,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: _text, size: 22),
            onPressed: _closeSearch,
          ),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocusNode,
              onChanged: _onSearchQueryChanged,
              style: TextStyle(color: _text, fontSize: 16),
              decoration: InputDecoration(
                hintText: "Search messages...",
                hintStyle: TextStyle(color: _sub, fontSize: 15),
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: totalMatches > 0 ? _rose.withOpacity(0.18) : Colors.redAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                matchText,
                style: TextStyle(
                  color: totalMatches > 0 ? _rose : Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.keyboard_arrow_up_rounded, color: totalMatches > 0 ? _text : _sub, size: 24),
              onPressed: totalMatches > 0 ? _prevMatch : null,
            ),
            IconButton(
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: totalMatches > 0 ? _text : _sub, size: 24),
              onPressed: totalMatches > 0 ? _nextMatch : null,
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, color: _sub, size: 20),
              onPressed: () {
                _searchCtrl.clear();
                _onSearchQueryChanged('');
              },
            ),
          ],
        ],
      ),
    );
  }

  // ── Message List ──────────────────────────────────────────────────────────
  Widget _buildMsgList() {
    final visible = _messages.where((m) => !_deletedIds.contains(m.id)).toList();

    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _rose, strokeWidth: 2));
    }
    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (b) => LinearGradient(colors: [_rose, _violet]).createShader(b),
              blendMode: BlendMode.srcIn,
              child: const Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text('Send the first message ❤️', style: TextStyle(color: _sub, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: visible.length,
      itemBuilder: (ctx, i) {
        final msg = visible[i];
        final isMe = msg.senderId == _myId;
        final showDateSep = i == 0 || !_sameDay(visible[i - 1].createdAt, msg.createdAt);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDateSep) _dateSep(msg.createdAt),
            _msgBubble(msg, isMe),
          ],
        );
      },
    );
  }

  Widget _dateSep(DateTime dt) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(children: [
      Expanded(child: Divider(color: _border, height: 1)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(_fmtDateLabel(dt),
            style: TextStyle(color: _sub, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
      Expanded(child: Divider(color: _border, height: 1)),
    ]),
  );

  Widget _buildHighlightedText(String text, String query, TextStyle baseStyle) {
    if (query.isEmpty) {
      return Text(text, style: baseStyle);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    if (!lowerText.contains(lowerQuery)) {
      return Text(text, style: baseStyle);
    }

    List<TextSpan> spans = [];
    int start = 0;
    int indexOfMatch;

    while ((indexOfMatch = lowerText.indexOf(lowerQuery, start)) != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfMatch), style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: text.substring(indexOfMatch, indexOfMatch + query.length),
          style: baseStyle.copyWith(
            backgroundColor: Colors.amberAccent,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = indexOfMatch + query.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }

    return RichText(text: TextSpan(children: spans));
  }

  Widget _msgBubble(Message msg, bool isMe) {
    if (msg.content.startsWith("CALL_LOG:")) {
      return _buildCallLogBubble(msg, isMe);
    }
    final reaction = _reactions[msg.id];
    return GestureDetector(
      onLongPress: () => _showMsgOptions(msg),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Bubble
            Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: EdgeInsets.only(
                  bottom: 2,
                  left:  isMe ? 64 : 0,
                  right: isMe ? 0  : 64,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: const BoxConstraints(maxWidth: 280),
                decoration: BoxDecoration(
                  gradient: isMe ? LinearGradient(colors: [_rose, _violet]) : null,
                  color: isMe ? null : _msgBg,
                  borderRadius: BorderRadius.only(
                    topLeft:     const Radius.circular(18),
                    topRight:    const Radius.circular(18),
                    bottomLeft:  Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4  : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isMe
                          ? _rose.withOpacity(0.22)
                          : Colors.black.withOpacity(_isDark ? 0.18 : 0.06),
                      blurRadius: 10, offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (msg.mediaAttachments.isNotEmpty)
                      ...msg.mediaAttachments.map((media) => ChatMediaBubble(
                            media: media,
                            token: _userToken,
                            isMe: isMe,
                          )),
                    if (msg.content.isNotEmpty)
                      _buildHighlightedText(
                        msg.content,
                        _searchQuery,
                        TextStyle(
                          color: isMe ? Colors.white : _text,
                          fontSize: 15, height: 1.4,
                        ),
                      ),
                    const SizedBox(height: 3),
                    // Timestamp & Edited indicator
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (msg.isEdited) ...[
                          Icon(
                            Icons.edit_rounded,
                            size: 10,
                            color: isMe ? Colors.white.withOpacity(0.6) : _sub,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            "edited",
                            style: TextStyle(
                              color: isMe ? Colors.white.withOpacity(0.6) : _sub,
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          _fmtTime(msg.createdAt),
                          style: TextStyle(
                            color: isMe ? Colors.white.withOpacity(0.55) : _sub,
                            fontSize: 10, fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Reaction bubble
            if (reaction != null)
              Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: EdgeInsets.only(
                    bottom: 6, top: 2,
                    right: isMe ? 6 : 0,
                    left:  isMe ? 0 : 6,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _surf,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _border),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                  ),
                  child: Text(reaction, style: const TextStyle(fontSize: 14)),
                ),
              ),
            if (reaction == null) const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildCallLogBubble(Message msg, bool isMe) {
    Map<String, dynamic> data = {};
    try {
      final raw = msg.content.substring("CALL_LOG:".length);
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}

    final callType = (data['call_type'] as String?) ?? 'voice';
    final status = (data['status'] as String?) ?? 'ended';
    final durationSecs = (data['duration_seconds'] as int?) ?? 0;
    final isVideo = callType == 'video';

    // Determine direction and status details
    final bool isMissed = (status == 'missed' || status == 'rejected');
    final bool isAnswered = status == 'ongoing' || status == 'ended';

    String title;
    String subtitle;
    IconData iconData;
    Color iconColor;
    IconData directionIcon;

    if (isMe) {
      // Outgoing
      if (isAnswered && durationSecs > 0) {
        title = isVideo ? "Outgoing video call" : "Outgoing voice call";
        subtitle = "${_fmtCallDuration(durationSecs)} • ${_fmtTime(msg.createdAt)}";
        iconColor = Colors.cyanAccent;
        directionIcon = Icons.call_made_rounded;
      } else {
        title = isVideo ? "Cancelled video call" : "Cancelled voice call";
        subtitle = "Cancelled • ${_fmtTime(msg.createdAt)}";
        iconColor = Colors.white60;
        directionIcon = Icons.call_made_rounded;
      }
    } else {
      // Incoming
      if (isAnswered && durationSecs > 0) {
        title = isVideo ? "Incoming video call" : "Incoming voice call";
        subtitle = "${_fmtCallDuration(durationSecs)} • ${_fmtTime(msg.createdAt)}";
        iconColor = Colors.greenAccent;
        directionIcon = Icons.call_received_rounded;
      } else {
        title = isVideo ? "Missed video call" : "Missed voice call";
        subtitle = "Missed • ${_fmtTime(msg.createdAt)}";
        iconColor = Colors.redAccent;
        directionIcon = Icons.call_missed_rounded;
      }
    }

    iconData = isVideo ? Icons.videocam_rounded : Icons.call_rounded;

    return Center(
      child: GestureDetector(
        onLongPress: () => _showCallLogOptions(msg, isMe, title, subtitle, isVideo),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _surf.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isMissed && !isMe ? Colors.redAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon Badge with direction indicator
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(iconData, color: iconColor, size: 20),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: _surf,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(directionIcon, color: iconColor, size: 10),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Call Details (Type, Duration, Time)
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isMissed && !isMe ? Colors.redAccent : _text,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _sub,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Quick Call Back action button
              IconButton(
                icon: Icon(
                  isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  color: _rose,
                  size: 22,
                ),
                tooltip: "Call Back",
                onPressed: () {
                  CallService.startCall(
                    context: context,
                    partnerId: widget.partnerId,
                    partnerName: widget.partnerName,
                    callType: isVideo ? 'video' : 'voice',
                  ).then((_) => _loadMessages());
                },
              ),

              // Call Options / Delete menu
              IconButton(
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: _sub,
                  size: 18,
                ),
                tooltip: "Call Options",
                onPressed: () => _showCallLogOptions(msg, isMe, title, subtitle, isVideo),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCallLogOptions(
    Message msg,
    bool isMe,
    String title,
    String subtitle,
    bool isVideo,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surf,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _sub.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Call Summary Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _rose.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      color: _rose,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: _text,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: _sub,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Actions
            _sheetAction(ctx, isVideo ? Icons.videocam_rounded : Icons.call_rounded, 'Call Back', () {
              CallService.startCall(
                context: context,
                partnerId: widget.partnerId,
                partnerName: widget.partnerName,
                callType: isVideo ? 'video' : 'voice',
              ).then((_) => _loadMessages());
            }, color: _rose),

            _sheetAction(
              ctx,
              Icons.delete_outline_rounded,
              'Delete for me',
              () async {
                setState(() {
                  _deletedIds.add(msg.id);
                  _messages.removeWhere((m) => m.id == msg.id);
                });
                await ApiService.deleteMessage(msg.id, token: _userToken);
                _toast("Call log deleted");
              },
              color: Colors.redAccent,
            ),

            _sheetAction(
              ctx,
              Icons.delete_forever_rounded,
              'Delete for everyone',
              () async {
                setState(() {
                  _deletedIds.add(msg.id);
                  _messages.removeWhere((m) => m.id == msg.id);
                });
                final success = await ApiService.deleteMessage(msg.id, token: _userToken);
                if (success) {
                  await _loadMessages();
                  _toast("Call log deleted from database");
                }
              },
              color: Colors.redAccent,
            ),
          ],
        ),
      ),
    );
  }

  String _fmtCallDuration(int seconds) {
    if (seconds <= 0) return "0s";
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) {
      return "${m}m ${s}s";
    }
    return "${s}s";
  }

  // ── Context Bar (reply / edit indicator) ──────────────────────────────────
  Widget _buildContextBar() {
    final isEditing = _editingMsg != null;
    final previewText = isEditing ? _editingMsg!.content : _replyingTo!.content;
    final label = isEditing
        ? 'Editing message'
        : 'Replying to ${_replyingTo!.senderId == _myId ? 'yourself' : widget.partnerName}';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        color: _surf,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            width: 3, height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [_rose, _violet],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(color: _rose, fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(previewText,
                    style: TextStyle(color: _sub, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              final wasEditing = _editingMsg != null;
              setState(() { _replyingTo = null; _editingMsg = null; });
              if (wasEditing) _msgCtrl.clear();
            },
            child: Icon(Icons.close_rounded, color: _sub, size: 20),
          ),
        ],
      ),
    );
  }

  // ── Input Bar ─────────────────────────────────────────────────────────────
  Widget _buildInputBar() => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.fromLTRB(8, 8, 12, 16),
    decoration: BoxDecoration(
      color: _surf,
      border: Border(top: BorderSide(color: _border)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selectedImage != null || _selectedFileName != null)
          _buildMediaPreviewBar(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Telegram Paperclip Attachment Button
            IconButton(
              icon: ShaderMask(
                shaderCallback: (b) => LinearGradient(colors: [_rose, _violet]).createShader(b),
                blendMode: BlendMode.srcIn,
                child: const Icon(Icons.attach_file_rounded, color: Colors.white, size: 24),
              ),
              onPressed: _showAttachmentSheet,
            ),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _border),
                ),
                child: TextField(
                  controller: _msgCtrl,
                  style: TextStyle(color: _text, fontSize: 15),
                  maxLines: 4, minLines: 1,
                  cursorColor: _rose,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _editingMsg != null
                        ? 'Edit message…'
                        : (_selectedImage != null || _selectedFileName != null
                            ? 'Add caption…'
                            : 'Send a message…'),
                    hintStyle: TextStyle(color: _sub, fontSize: 15),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _isSending ? null : _sendMessage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _isSending ? null : LinearGradient(colors: [_rose, _violet]),
                  color: _isSending ? _surf : null,
                  border: _isSending ? Border.all(color: _border) : null,
                  boxShadow: _isSending ? [] : [
                    BoxShadow(color: _rose.withOpacity(0.38), blurRadius: 12, offset: const Offset(0, 3)),
                  ],
                ),
                child: _isSending
                    ? Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: _rose, strokeWidth: 2)))
                    : Icon(
                        _editingMsg != null ? Icons.check_rounded : Icons.send_rounded,
                        color: Colors.white, size: 19,
                      ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  // ── Options Bottom Sheet ───────────────────────────────────────────────────
  Widget _optionsSheet(BuildContext ctx, Message msg, bool isMe) {
    return Container(
      decoration: BoxDecoration(
        color: _surf,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          // Preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Text(msg.content,
                style: TextStyle(color: _sub, fontSize: 13, height: 1.4),
                maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(height: 14),
          // Emoji row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: _border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['❤️', '😂', '😮', '😢', '👍', '🔥'].map((e) {
                final sel = _reactions[msg.id] == e;
                return GestureDetector(
                  onTap: () {
                    setState(() => sel ? _reactions.remove(msg.id) : _reactions[msg.id] = e);
                    Navigator.pop(ctx);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sel ? _rose.withOpacity(0.20) : Colors.transparent,
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          // Actions
          _sheetAction(ctx, Icons.reply_rounded, 'Reply', () {
            setState(() { _replyingTo = msg; _editingMsg = null; });
            _msgCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _msgCtrl.text.length));
          }),
          if (isMe && msg.mediaAttachments.isEmpty && DateTime.now().toUtc().difference(msg.createdAt.toUtc()).inSeconds < 900)
            _sheetAction(ctx, Icons.edit_rounded, 'Edit', () {
              setState(() { _editingMsg = msg; _replyingTo = null; _msgCtrl.text = msg.content; });
              _msgCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _msgCtrl.text.length));
            }),
          _sheetAction(
            ctx,
            Icons.delete_outline_rounded,
            'Delete for me',
            () async {
              setState(() {
                _deletedIds.add(msg.id);
                _messages.removeWhere((m) => m.id == msg.id);
              });
              await ApiService.deleteMessage(msg.id, token: _userToken);
              _toast("Message deleted");
            },
            color: Colors.redAccent,
          ),
          _sheetAction(
            ctx,
            Icons.delete_forever_rounded,
            'Delete for everyone',
            () async {
              setState(() {
                _deletedIds.add(msg.id);
                _messages.removeWhere((m) => m.id == msg.id);
              });
              final success = await ApiService.deleteMessage(msg.id, token: _userToken);
              if (success) {
                await _loadMessages();
                _toast("Message deleted from database");
              }
            },
            color: Colors.redAccent,
          ),
        ],
      ),
    );
  }

  Widget _sheetAction(BuildContext ctx, IconData icon, String label, VoidCallback action, {Color? color}) {
    final c = color ?? _text;
    return InkWell(
      onTap: () { Navigator.pop(ctx); action(); },
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (color ?? _rose).withOpacity(0.12),
              ),
              child: Icon(icon, color: color ?? _rose, size: 20),
            ),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Diary & Memories Logic ────────────────────────────────────────────────
  Future<void> _loadMemories() async {
    setState(() => _loadingMemories = true);
    try {
      final token = await Session.getToken() ?? _userToken;
      final raw = await ApiService.getPairMemories(widget.partnerId, token: token);
      final list = raw.map((e) => DiaryMemoryItem.fromJson(e)).toList();
      if (mounted) {
        setState(() {
          _sharedMemories = list;
          _loadingMemories = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMemories = false);
    }
  }

  Future<void> _pickMemoryPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) {
        setState(() {
          _memorySelectedPhoto = File(picked.path);
        });
      }
    } catch (e) {
      _toast("Failed to pick photo", isError: true);
    }
  }

  void _removeMemoryPhoto() {
    setState(() {
      _memorySelectedPhoto = null;
    });
  }

  String _formatDateYMD(DateTime dt) =>
      "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";

  Future<void> _saveDiaryMemory() async {
    final text = _memoryCtrl.text.trim();
    if (text.isEmpty && _memorySelectedPhoto == null) {
      _toast("Write a note or attach a photo first ❤️", isError: true);
      return;
    }

    final targetDate = _selDate ?? DateTime.now();
    final dateStr = _formatDateYMD(targetDate);

    HapticFeedback.mediumImpact();
    setState(() => _isSavingMemory = true);

    final res = await ApiService.createDiaryMemory(
      partnerId: widget.partnerId,
      entryDate: dateStr,
      content: text,
      moodEmoji: _selectedMoodEmoji,
      photo: _memorySelectedPhoto,
      token: _userToken,
    );

    if (mounted) {
      setState(() {
        _isSavingMemory = false;
        _memoryCtrl.clear();
        _memorySelectedPhoto = null;
      });

      if (res != null) {
        _toast("Saved to couple's diary for ${_fmtDateLabel(targetDate)} ❤️");
        await _loadMemories();
      } else {
        _toast("Failed to save memory entry", isError: true);
      }
    }
  }

  Future<void> _deleteMemory(int memoryId) async {
    HapticFeedback.lightImpact();
    final ok = await ApiService.deleteDiaryMemory(memoryId, token: _userToken);
    if (ok && mounted) {
      setState(() {
        _sharedMemories.removeWhere((m) => m.id == memoryId);
      });
      _toast("Memory deleted");
    }
  }

  bool _memoryMatchesDate(DiaryMemoryItem m, DateTime target) {
    final p = m.parsedDate;
    if (p == null) return false;
    return _sameDay(p, target);
  }

  void _showMemoryPhotoPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surf,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)),
            ),
            Text("Attach Photo to Memory", style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _attachOption(
                  icon: Icons.camera_alt_rounded,
                  label: "Camera",
                  color: Colors.pinkAccent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickMemoryPhoto(ImageSource.camera);
                  },
                ),
                _attachOption(
                  icon: Icons.photo_library_rounded,
                  label: "Gallery",
                  color: Colors.purpleAccent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickMemoryPhoto(ImageSource.gallery);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _openMemoryImageFullScreen(DiaryMemoryItem memory) {
    if (memory.fullImageUrl == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black54,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              "Memory • ${memory.entryDate}",
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Image.network(
                memory.fullImageUrl!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Memory / Calendar / Diary Drawer Panel ─────────────────────────────────
  Widget _buildMemoryPanel() {
    final photoMemories = _sharedMemories.where((m) => m.hasPhoto).toList();
    final displayedMemories = _selDate == null
        ? _sharedMemories
        : _sharedMemories.where((m) => _memoryMatchesDate(m, _selDate!)).toList();

    return Material(
      color: _surf,
      elevation: 20,
      shadowColor: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [_rose, _violet]),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_stories_rounded, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Couple\'s Diary & Album',
                        style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Shared memories & dates ❤️',
                        style: TextStyle(color: _sub, fontSize: 11),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: Icon(Icons.refresh_rounded, color: _rose, size: 20),
                    onPressed: () {
                      _loadMemories();
                      _toast("Refreshed diary entries");
                    },
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: Icon(Icons.close_rounded, color: _sub, size: 22),
                    onPressed: _closeAll,
                  ),
                ],
              ),
            ),

            // Tab Selector: [ 📔 Diary Notes ] | [ 🖼️ Photo Album ]
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _diaryTab = 0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(11),
                            gradient: _diaryTab == 0 ? LinearGradient(colors: [_rose, _violet]) : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.edit_note_rounded, size: 16, color: _diaryTab == 0 ? Colors.white : _sub),
                              const SizedBox(width: 6),
                              Text(
                                "Diary (${_sharedMemories.length})",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: _diaryTab == 0 ? FontWeight.bold : FontWeight.w500,
                                  color: _diaryTab == 0 ? Colors.white : _sub,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _diaryTab = 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(11),
                            gradient: _diaryTab == 1 ? LinearGradient(colors: [_rose, _violet]) : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.photo_library_rounded, size: 16, color: _diaryTab == 1 ? Colors.white : _sub),
                              const SizedBox(width: 6),
                              Text(
                                "Album (${photoMemories.length})",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: _diaryTab == 1 ? FontWeight.bold : FontWeight.w500,
                                  color: _diaryTab == 1 ? Colors.white : _sub,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Interactive Calendar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: _buildCalendar(),
            ),

            Divider(color: _border, height: 12),

            // Composer Area (Add memory to selected date)
            _buildDiaryComposer(),

            const SizedBox(height: 6),

            // Content Area (Timeline or Photo Album)
            Expanded(
              child: _loadingMemories
                  ? Center(child: CircularProgressIndicator(color: _rose, strokeWidth: 2))
                  : _diaryTab == 0
                      ? _buildDiaryTimelineView(displayedMemories)
                      : _buildPhotoAlbumView(photoMemories),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiaryComposer() {
    final dateLabel = _selDate != null ? _fmtDateLabel(_selDate!) : 'Today';
    const moods = ['❤️', '🥰', '✨', '🌟', '✈️', '🎂', '🥂', '💍', '🏖️', '💌', '☕', '🌙'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _rose.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header of Composer
          Row(
            children: [
              Icon(Icons.edit_calendar_rounded, size: 14, color: _rose),
              const SizedBox(width: 6),
              Text(
                "Add Memory for $dateLabel",
                style: TextStyle(color: _rose, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (_memorySelectedPhoto != null)
                const Text(
                  "1 Photo Attached 📷",
                  style: TextStyle(color: Colors.greenAccent, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Mood Emoji Selector Ribbon
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: moods.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (ctx, idx) {
                final m = moods[idx];
                final isSel = _selectedMoodEmoji == m;
                return GestureDetector(
                  onTap: () => setState(() => _selectedMoodEmoji = m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSel ? _rose.withValues(alpha: 0.25) : _surf,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSel ? _rose : _border,
                        width: isSel ? 1.5 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(m, style: TextStyle(fontSize: isSel ? 16 : 14)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Attached Photo Preview
          if (_memorySelectedPhoto != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _surf,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _memorySelectedPhoto!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Photo ready to post",
                      style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: _sub),
                    onPressed: _removeMemoryPhoto,
                  ),
                ],
              ),
            ),
          ],

          // Text Field + Actions Row
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _surf,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: TextField(
                    controller: _memoryCtrl,
                    style: TextStyle(color: _text, fontSize: 13),
                    cursorColor: _rose,
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Write a thought, note or memory…',
                      hintStyle: TextStyle(color: _sub, fontSize: 12.5),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Attach Photo Button
              IconButton(
                tooltip: "Attach Photo",
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _memorySelectedPhoto != null ? _rose.withValues(alpha: 0.2) : _surf,
                    shape: BoxShape.circle,
                    border: Border.all(color: _memorySelectedPhoto != null ? _rose : _border),
                  ),
                  child: Icon(
                    Icons.add_a_photo_rounded,
                    color: _memorySelectedPhoto != null ? _rose : _sub,
                    size: 18,
                  ),
                ),
                onPressed: _showMemoryPhotoPickerSheet,
              ),

              // Post Button
              GestureDetector(
                onTap: _isSavingMemory ? null : _saveDiaryMemory,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [_rose, _violet]),
                    boxShadow: [
                      BoxShadow(
                        color: _rose.withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: _isSavingMemory
                      ? const Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          ),
                        )
                      : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiaryTimelineView(List<DiaryMemoryItem> displayedMemories) {
    if (displayedMemories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (b) => LinearGradient(colors: [_rose, _violet]).createShader(b),
                blendMode: BlendMode.srcIn,
                child: const Icon(Icons.favorite_border_rounded, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                _selDate != null
                    ? 'No entries for ${_fmtDateLabel(_selDate!)}'
                    : 'No diary entries yet ❤️',
                style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Write your thoughts or attach a photo to this date above!',
                style: TextStyle(color: _sub, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      physics: const BouncingScrollPhysics(),
      itemCount: displayedMemories.length,
      itemBuilder: (ctx, i) {
        final mem = displayedMemories[i];
        final isMe = mem.senderId == _myId;
        final authorLabel = isMe ? "You" : widget.partnerName;

        return Dismissible(
          key: Key('memory_${mem.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            return await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: _surf,
                    title: Text("Delete Memory?", style: TextStyle(color: _text)),
                    content: Text("Are you sure you want to delete this diary entry?", style: TextStyle(color: _sub)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text("Cancel", style: TextStyle(color: _sub))),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("Delete", style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                ) ??
                false;
          },
          onDismissed: (_) => _deleteMemory(mem.id),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 22),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _isDark ? 0.25 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Mood Emoji + Author Badge + Date Badge
                Row(
                  children: [
                    if (mem.moodEmoji != null && mem.moodEmoji!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _rose.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(mem.moodEmoji!, style: const TextStyle(fontSize: 14)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isMe ? _rose.withValues(alpha: 0.12) : _violet.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        authorLabel,
                        style: TextStyle(
                          color: isMe ? _rose : _lavender,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      mem.entryDate,
                      style: TextStyle(color: _sub, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, size: 16, color: _sub),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () => _deleteMemory(mem.id),
                    ),
                  ],
                ),

                // Attached Photo
                if (mem.hasPhoto && mem.fullImageUrl != null) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _openMemoryImageFullScreen(mem),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          Container(
                            height: 150,
                            width: double.infinity,
                            color: _surf,
                            child: Image.network(
                              mem.fullImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Icon(Icons.broken_image_rounded, color: _sub, size: 32),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Content Note
                if (mem.content.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    mem.content,
                    style: TextStyle(
                      color: _text,
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhotoAlbumView(List<DiaryMemoryItem> photoMemories) {
    if (photoMemories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (b) => LinearGradient(colors: [_rose, _violet]).createShader(b),
                blendMode: BlendMode.srcIn,
                child: const Icon(Icons.photo_album_rounded, size: 42, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                'No scrapbook photos yet 🖼️',
                style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Attach a photo to any date above and it will show up here!',
                style: TextStyle(color: _sub, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.9,
      ),
      itemCount: photoMemories.length,
      itemBuilder: (ctx, idx) {
        final mem = photoMemories[idx];
        return GestureDetector(
          onTap: () => _openMemoryImageFullScreen(mem),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: _surf,
                  child: Image.network(
                    mem.fullImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(Icons.image_not_supported_rounded, color: _sub, size: 28),
                    ),
                  ),
                ),
                // Gradient overlay at bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Mood emoji
                if (mem.moodEmoji != null && mem.moodEmoji!.isNotEmpty)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Text(mem.moodEmoji!, style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                // Date tag at bottom
                Positioned(
                  bottom: 6,
                  left: 8,
                  right: 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        mem.entryDate,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                        ),
                      ),
                      Icon(Icons.zoom_in_rounded, color: Colors.white.withValues(alpha: 0.9), size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalendar() {
    final m = _calMonth;
    final first = DateTime(m.year, m.month, 1);
    final last = DateTime(m.year, m.month + 1, 0);
    final startWd = first.weekday % 7; // 0 = Sun
    const dow = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    const mons = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    final cells = <Widget>[];
    for (int i = 0; i < startWd; i++) cells.add(const SizedBox());

    for (int d = 1; d <= last.day; d++) {
      final date = DateTime(m.year, m.month, d);
      final isSel = _selDate != null && _sameDay(_selDate!, date);
      final hasMem = _sharedMemories.any((x) => _memoryMatchesDate(x, date));
      final isToday = _sameDay(DateTime.now(), date);

      cells.add(GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            if (_selDate != null && _sameDay(_selDate!, date)) {
              // Tap again on selected date resets filter to all dates
              _selDate = null;
            } else {
              _selDate = date;
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isSel ? LinearGradient(colors: [_rose, _violet]) : null,
            color: !isSel && hasMem ? _rose.withValues(alpha: 0.18) : null,
            border: isToday && !isSel ? Border.all(color: _rose, width: 1.5) : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '$d',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: (isToday || isSel) ? FontWeight.w800 : FontWeight.w500,
                  color: isSel ? Colors.white : isToday ? _rose : _text,
                ),
              ),
              if (hasMem && !isSel)
                Positioned(
                  bottom: 2,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _rose,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ));
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: Icon(Icons.chevron_left_rounded, color: _rose),
              onPressed: () => setState(() => _calMonth = DateTime(m.year, m.month - 1)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            GestureDetector(
              onTap: () => setState(() {
                _calMonth = DateTime.now();
                _selDate = DateTime.now();
              }),
              child: Row(
                children: [
                  Text(
                    '${mons[m.month - 1]} ${m.year}',
                    style: TextStyle(color: _text, fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.touch_app_rounded, size: 12, color: _rose),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.chevron_right_rounded, color: _rose),
              onPressed: () => setState(() => _calMonth = DateTime(m.year, m.month + 1)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
        Row(
          children: dow
              .map((d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(color: _sub, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 2),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 7,
          childAspectRatio: 1.15,
          children: cells,
        ),
      ],
    );
  }

  // ── Settings Panel ────────────────────────────────────────────────────────
  Widget _buildSettingsPanel() => Material(
    color: _surf,
    elevation: 16,
    shadowColor: Colors.black45,
    child: SafeArea(
      child: Column(
        children: [
          // Profile header
          InkWell(
            onTap: () {
              _closeAll();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileScreen(),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_violet.withOpacity(0.20), _rose.withOpacity(0.10)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                border: Border(bottom: BorderSide(color: _border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [_rose, _violet]),
                    ),
                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_myUsername.isNotEmpty ? _myUsername : 'My Profile',
                            style: TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text('View & Edit Profile', style: TextStyle(color: _rose, fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 4),
                            Icon(Icons.edit_outlined, size: 12, color: _rose),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: _sub, size: 22),
                    onPressed: _closeAll,
                  ),
                ],
              ),
            ),
          ),
          // Merged Partner Info & Connection Card
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: InkWell(
              onTap: () {
                _closeAll();
                _openPartnerProfile();
              },
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _rose.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: _rose.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10, height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.greenAccent,
                        boxShadow: [
                          BoxShadow(color: Colors.greenAccent, blurRadius: 6, spreadRadius: 1),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Connected to ${widget.partnerName} ❤️',
                              style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text('Tap to view profile, shared media & info',
                              style: TextStyle(color: _rose, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, color: _sub, size: 14),
                  ],
                ),
              ),
            ),
          ),
          // Settings items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _sTile(
                  Icons.photo_library_outlined,
                  'Media Gallery',
                  'Photos, videos & shared files',
                  () {
                    _closeAll();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MediaGalleryScreen(
                          partnerId: widget.partnerId,
                          partnerName: widget.partnerName,
                          token: _userToken,
                        ),
                      ),
                    );
                  },
                ),
                _sTile(
                  Icons.person_outline_rounded,
                  'My Profile',
                  'View & edit personal details',
                  () {
                    _closeAll();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ProfileScreen(),
                      ),
                    );
                  },
                ),
                _sTile(
                  Icons.tune_rounded,
                  'Account & Settings',
                  'Profile, privacy, account details',
                  () {
                    _closeAll();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AccountScreen(),
                      ),
                    );
                  },
                ),
                _sTile(
                  Icons.shield_outlined,
                  'App Security',
                  'Passcode lock, biometrics & auto-lock',
                  () {
                    _closeAll();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SecurityScreen(),
                      ),
                    );
                  },
                ),
                _notificationsToggleTile(),
                _themesTile(),
              ],
            ),
          ),
          // Logout
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: SizedBox(
              width: double.infinity, height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: TextButton(
                  onPressed: _showLogoutDialog,
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                      SizedBox(width: 8),
                      Text('Sign Out', style: TextStyle(
                          color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _notificationsToggleTile() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [_rose, _violet]),
            ),
            child: Icon(
              _notificationsEnabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
              color: Colors.white, size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notifications', style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700)),
                Text(_notificationsEnabled ? 'Chat sounds & alerts active' : 'Chat alerts muted',
                    style: TextStyle(color: _sub, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            activeColor: _rose,
            value: _notificationsEnabled,
            onChanged: (val) => setState(() => _notificationsEnabled = val),
          ),
        ],
      ),
    ),
  );

  Widget _themesTile() {
    return ValueListenableBuilder<AppTheme>(
      valueListenable: ThemeController.currentTheme,
      builder: (context, activeTheme, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: GestureDetector(
            onTap: () {
              _closeAll();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ThemeSelectionScreen(),
                ),
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [activeTheme.gradientStart, activeTheme.gradientEnd],
                      ),
                    ),
                    child: const Icon(
                      Icons.palette_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Themes',
                          style: TextStyle(
                            color: _text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Customize your TwoOfUs',
                          style: TextStyle(
                            color: _sub,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      _smallDot(activeTheme.bg),
                      const SizedBox(width: 3),
                      _smallDot(activeTheme.surface),
                      const SizedBox(width: 3),
                      _smallDot(activeTheme.primary),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: _sub,
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _smallDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white30, width: 0.8),
      ),
    );
  }

  Widget _sTile(IconData icon, String title, String sub, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [_rose, _violet]),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(sub, style: TextStyle(color: _sub, fontSize: 11)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: _sub, size: 14),
              ],
            ),
          ),
        ),
      );

  // ── Logout Dialog ─────────────────────────────────────────────────────────
  void _showLogoutDialog() {
    _closeAll();
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (ctx) => Dialog(
          backgroundColor: _surf,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (b) => LinearGradient(colors: [_rose, _violet]).createShader(b),
                  blendMode: BlendMode.srcIn,
                  child: const Icon(Icons.logout_rounded, size: 40, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text('Leaving so soon?',
                    style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text("You'll need your credentials to get back.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _sub, fontSize: 14)),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text('Stay', style: TextStyle(color: _sub, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [_rose, _violet]),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ElevatedButton(                        
                            onPressed: () async {
                            await Session.logout();

                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                              (route) => false,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Sign out',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}