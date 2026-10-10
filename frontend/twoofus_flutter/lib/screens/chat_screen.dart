import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/design_system/design_system.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/e2ee_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';
import '../widgets/passcode_lock_button.dart';
import '../widgets/server_config_dialog.dart';
import 'change_password_screen.dart';
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
import '../widgets/timeline_drawer.dart';
import '../widgets/encryption_verification_modal.dart';
import '../services/call_service.dart';
import '../utils/date_time_utils.dart';
import 'media_gallery_screen.dart';
import '../utils/app_feedback.dart';

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

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin, WidgetsBindingObserver {

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
  String? _myAvatarUrl;
  String? _partnerAvatarUrl;
  String _userToken = '';
  String? _partnerPubKey;
  bool   _loading    = true;
  bool   _isSending  = false;

  // ── Theme & Preferences ───────────────────────────────────────────────────
  bool _isDark               = true;
  bool _isOnline             = false;
  bool _isPartnerTyping      = false;
  bool _notificationsEnabled = true;
  bool _isPartnerVerified    = false;
  Timer? _presenceTimer;
  Timer? _messagePollingTimer;
  final Map<int, String> _decryptedCache = {};
  DateTime? _lastTypingSentTime;

  // ── Panels ────────────────────────────────────────────────────────────────
  bool _leftOpen  = false;   // memories  (swipe →)
  bool _rightOpen = false;   // settings  (swipe ←)

  // ── Chat state ────────────────────────────────────────────────────────────
  Message?    _replyingTo;
  Message?    _editingMsg;
  final Set<int>    _deletedIds  = {};
  final Map<int, String> _reactions = {};
  String? _sendErrorMessage;
  String? _lastFailedSendText;

  // ── Calendar & Shared Timeline State ───────────────────────────────────────
  List<DiaryMemoryItem> _sharedMemories = [];
  bool _loadingMemories = false;
  DateTime? _selDate = DateTime.now();

  // ── Animation ─────────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── Palette ───────────────────────────────────────────────────────────────
  AppTheme get _theme   => ThemeController.currentTheme.value;
  Color get _rose       => _theme.primary;
  Color get _violet     => _theme.secondary;
  Color get _lavender   => _theme.gradientEnd;
  Color get _darkBg     => _theme.bg;
  Color get _darkSurf   => _theme.surface;

  Color get _bg         => _theme.bg;
  Color get _surf       => _theme.surface;
  Color get _text       => _theme.textPrimary;
  Color get _sub        => _theme.textMuted;
  Color get _border     => _theme.border;
  Color get _msgBg      => _theme.bubblePartner;


  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _msgCtrl.addListener(_onTypingChanged);
    _initialize();
    _startPresencePolling();
    _startMessagePolling();
    CallService.startIncomingCallWatcher(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _messagePollingTimer?.cancel();
    _msgCtrl.removeListener(_onTypingChanged);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _memoryCtrl.dispose();
    _pulseCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.inactive) {
      ApiService.sendOfflineStatus(token: _userToken);
      if (_lastTypingSentTime != null) {
        _lastTypingSentTime = null;
        ApiService.sendTypingStatus(partnerId: widget.partnerId, isTyping: false, token: _userToken);
      }
    } else if (state == AppLifecycleState.resumed) {
      _syncPresence();
    }
  }

  void _onTypingChanged() {
    final text = _msgCtrl.text.trim();
    if (text.isNotEmpty) {
      final now = DateTime.now();
      if (_lastTypingSentTime == null || now.difference(_lastTypingSentTime!).inSeconds >= 2) {
        _lastTypingSentTime = now;
        ApiService.sendTypingStatus(partnerId: widget.partnerId, isTyping: true, token: _userToken);
      }
    } else {
      if (_lastTypingSentTime != null) {
        _lastTypingSentTime = null;
        ApiService.sendTypingStatus(partnerId: widget.partnerId, isTyping: false, token: _userToken);
      }
    }
  }

  // ── Real-Time Message Polling ─────────────────────────────────────────────
  void _startMessagePolling() {
    _messagePollingTimer?.cancel();
    _messagePollingTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (!mounted || _myId == null) return;
      await _syncMessagesLive();
    });
  }

  // ── Presence & Polling ────────────────────────────────────────────────────
  void _startPresencePolling() {
    _presenceTimer?.cancel();
    _syncPresence();
    _presenceTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      _syncPresence();
    });
  }

  Future<void> _syncPresence() async {
    try {
      ApiService.sendHeartbeat(token: _userToken);
      final status = await ApiService.getOnlineStatus(widget.partnerId, token: _userToken);
      if (status != null && mounted) {
        final online = status['is_online'] == true;
        final typing = status['is_typing'] == true;
        if (_isOnline != online || _isPartnerTyping != typing) {
          setState(() {
            _isOnline = online;
            _isPartnerTyping = typing;
          });
        }
      }
    } catch (_) {}
  }

  Widget _buildAvatarFallback() {
    final initial = widget.partnerName.trim().isNotEmpty
        ? widget.partnerName.trim()[0].toUpperCase()
        : '';
    if (initial.isNotEmpty) {
      return Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      );
    }
    return const Icon(Icons.person_rounded, color: Colors.white, size: 18);
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
    _loadMyProfile();
    _loadPartnerProfile();
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

  Future<void> _loadMyProfile() async {
    final userId = await Session.getUserId();
    if (userId != null) {
      try {
        final prof = await ApiService.getProfile(userId);
        if (prof != null && mounted) {
          setState(() {
            if (prof['username'] != null && prof['username'].toString().isNotEmpty) {
              _myUsername = prof['username'].toString();
            }
            _myAvatarUrl = prof['avatar_url']?.toString();
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _loadPartnerProfile() async {
    try {
      final prof = await ApiService.getProfile(widget.partnerId);
      if (prof != null && mounted) {
        setState(() {
          _partnerAvatarUrl = prof['avatar_url']?.toString();
          if (prof.containsKey('is_online')) {
            _isOnline = prof['is_online'] == true;
          }
        });
      }
    } catch (_) {}
  }

    Future<void> _loadMessages() async {
    if (_myId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = await ApiService.getMessages(_myId!, widget.partnerId);
      final rawMessages = result.map<Message>((e) => Message.fromJson(e)).toList();

      List<Message> decryptedMessages = [];
      for (var m in rawMessages) {
        if (m.isEncrypted && m.nonce != null && m.nonce!.isNotEmpty) {
          final cachedMsg = prefs.getString('cached_msg_body_${m.id}');
          if (cachedMsg != null && cachedMsg.isNotEmpty && !cachedMsg.startsWith("🔒")) {
            _decryptedCache[m.id] = cachedMsg;
            decryptedMessages.add(Message(
              id: m.id,
              senderId: m.senderId,
              receiverId: m.receiverId,
              content: cachedMsg,
              nonce: m.nonce,
              isEncrypted: true,
              isEdited: m.isEdited,
              createdAt: m.createdAt,
              mediaAttachments: m.mediaAttachments,
            ));
          } else if (_decryptedCache.containsKey(m.id) && !_decryptedCache[m.id]!.startsWith("🔒") && !m.isEdited) {
            decryptedMessages.add(Message(
              id: m.id,
              senderId: m.senderId,
              receiverId: m.receiverId,
              content: _decryptedCache[m.id]!,
              nonce: m.nonce,
              isEncrypted: true,
              isEdited: m.isEdited,
              createdAt: m.createdAt,
              mediaAttachments: m.mediaAttachments,
            ));
          } else {
            if (_partnerPubKey == null || _partnerPubKey!.isEmpty) {
              _partnerPubKey = await E2EEService.getPartnerPublicKey(widget.partnerId, token: _userToken);
            }
            if (_partnerPubKey != null && _partnerPubKey!.isNotEmpty) {
              final decryptedContent = await E2EEService.decryptText(
                ciphertextBase64: m.content,
                nonceBase64: m.nonce!,
                remotePublicKeyBase64: _partnerPubKey!,
              );
              _decryptedCache[m.id] = decryptedContent;
              if (!decryptedContent.startsWith("🔒")) {
                await prefs.setString('cached_msg_body_${m.id}', decryptedContent);
              }
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
              decryptedMessages.add(Message(
                id: m.id,
                senderId: m.senderId,
                receiverId: m.receiverId,
                content: "🔒 Encrypted with previous security key",
                nonce: m.nonce,
                isEncrypted: true,
                isEdited: m.isEdited,
                createdAt: m.createdAt,
                mediaAttachments: m.mediaAttachments,
              ));
            }
          }
        } else {
          decryptedMessages.add(m);
        }
      }

      if (mounted) {
        setState(() => _messages = decryptedMessages);
      }
    } catch (_) {}
  }

  Future<void> _syncMessagesLive() async {
    if (_myId == null) return;
    try {
      final result = await ApiService.getMessages(_myId!, widget.partnerId);
      final rawMessages = result.map<Message>((e) => Message.fromJson(e)).toList();

      // Check for changes (length, last message ID, or edited flag)
      bool hasChanges = rawMessages.length != _messages.length;
      if (!hasChanges && rawMessages.isNotEmpty) {
        if (rawMessages.last.id != _messages.last.id) {
          hasChanges = true;
        } else {
          for (int i = 0; i < rawMessages.length; i++) {
            if (rawMessages[i].id != _messages[i].id ||
                rawMessages[i].isEdited != _messages[i].isEdited ||
                rawMessages[i].content != _messages[i].content) {
              hasChanges = true;
              break;
            }
          }
        }
      }

      if (!hasChanges) return;

      final prefs = await SharedPreferences.getInstance();
      List<Message> decryptedMessages = [];
      for (var m in rawMessages) {
        if (m.isEncrypted && m.nonce != null && m.nonce!.isNotEmpty) {
          final cachedMsg = prefs.getString('cached_msg_body_${m.id}');
          if (cachedMsg != null && cachedMsg.isNotEmpty && !cachedMsg.startsWith("🔒")) {
            _decryptedCache[m.id] = cachedMsg;
            decryptedMessages.add(Message(
              id: m.id,
              senderId: m.senderId,
              receiverId: m.receiverId,
              content: cachedMsg,
              nonce: m.nonce,
              isEncrypted: true,
              isEdited: m.isEdited,
              createdAt: m.createdAt,
              mediaAttachments: m.mediaAttachments,
            ));
          } else if (_decryptedCache.containsKey(m.id) && !_decryptedCache[m.id]!.startsWith("🔒") && !m.isEdited) {
            decryptedMessages.add(Message(
              id: m.id,
              senderId: m.senderId,
              receiverId: m.receiverId,
              content: _decryptedCache[m.id]!,
              nonce: m.nonce,
              isEncrypted: true,
              isEdited: m.isEdited,
              createdAt: m.createdAt,
              mediaAttachments: m.mediaAttachments,
            ));
          } else {
            if (_partnerPubKey == null || _partnerPubKey!.isEmpty) {
              _partnerPubKey = await E2EEService.getPartnerPublicKey(widget.partnerId, token: _userToken);
            }
            if (_partnerPubKey != null && _partnerPubKey!.isNotEmpty) {
              final decryptedContent = await E2EEService.decryptText(
                ciphertextBase64: m.content,
                nonceBase64: m.nonce!,
                remotePublicKeyBase64: _partnerPubKey!,
              );
              _decryptedCache[m.id] = decryptedContent;
              if (!decryptedContent.startsWith("🔒")) {
                await prefs.setString('cached_msg_body_${m.id}', decryptedContent);
              }
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
              decryptedMessages.add(Message(
                id: m.id,
                senderId: m.senderId,
                receiverId: m.receiverId,
                content: "🔒 Encrypted with previous security key",
                nonce: m.nonce,
                isEncrypted: true,
                isEdited: m.isEdited,
                createdAt: m.createdAt,
                mediaAttachments: m.mediaAttachments,
              ));
            }
          }
        } else {
          decryptedMessages.add(m);
        }
      }

      if (mounted) {
        final wasAtBottom = !_scrollCtrl.hasClients ||
            (_scrollCtrl.position.maxScrollExtent - _scrollCtrl.position.pixels < 120);
        final bool isNewIncoming = decryptedMessages.length > _messages.length &&
            decryptedMessages.last.senderId != _myId;

        setState(() {
          _messages = decryptedMessages;
        });

        if (isNewIncoming) {
          HapticFeedback.lightImpact();
        }

        if (wasAtBottom) {
          _scrollToBottom();
        }
      }
    } catch (_) {}
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
              if (_partnerPubKey == null || _partnerPubKey!.isEmpty) {
                _partnerPubKey = await E2EEService.getPartnerPublicKey(widget.partnerId, token: _userToken);
              }
              if (_partnerPubKey == null || _partnerPubKey!.isEmpty) {
                setState(() {
                  _sendErrorMessage = "Cannot send media: Partner security key unavailable.";
                });
                return; // FAIL CLOSED: Send nothing!
              }

              // Encrypt caption (or encrypt empty placeholder for strict encrypted envelope)
              final payload = await E2EEService.encryptText(caption, _partnerPubKey!);
              if (payload == null) {
                setState(() {
                  _sendErrorMessage = "Cannot send media: Encryption failed.";
                });
                return; // FAIL CLOSED: Send nothing!
              }

              final ok = await ApiService.sendMessage(
                _myId!,
                widget.partnerId,
                payload.ciphertext,
                nonce: payload.nonce,
                isEncrypted: true,
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

    final trimmed = text.trim();
    if (trimmed.isEmpty && _selectedImage == null && _selectedFileName == null) return;
    setState(() {
      _isSending = true;
      _sendErrorMessage = null;
    });

    // FAIL CLOSED: Ensure partner public key is available before sending any user text
    if (_partnerPubKey == null || _partnerPubKey!.isEmpty) {
      _partnerPubKey = await E2EEService.getPartnerPublicKey(widget.partnerId, token: _userToken);
    }
    if (_partnerPubKey == null || _partnerPubKey!.isEmpty) {
      setState(() {
        _isSending = false;
        _sendErrorMessage = "Cannot send: Partner security key unavailable.";
        _lastFailedSendText = trimmed;
      });
      return; // FAIL CLOSED: Send nothing!
    }

    if (_editingMsg != null) {
      final payload = await E2EEService.encryptText(trimmed, _partnerPubKey!);
      if (payload == null) {
        setState(() {
          _isSending = false;
          _sendErrorMessage = "Cannot edit: Encryption failed.";
          _lastFailedSendText = trimmed;
        });
        return; // FAIL CLOSED: Send nothing!
      }

      final success = await ApiService.editMessage(
        _editingMsg!.id,
        payload.ciphertext,
        nonce: payload.nonce,
        isEncrypted: true,
      );
      if (success) {
        _toast("Message updated");
        _msgCtrl.clear();
        _removeSelectedMedia();
        setState(() {
          _editingMsg = null;
          _replyingTo = null;
          _sendErrorMessage = null;
        });
        await _loadMessages();
      } else {
        setState(() {
          _sendErrorMessage = "Failed to update message on server.";
          _lastFailedSendText = trimmed;
        });
      }
      setState(() => _isSending = false);
      return;
    } else {
      final payload = await E2EEService.encryptText(trimmed, _partnerPubKey!);
      if (payload == null) {
        setState(() {
          _isSending = false;
          _sendErrorMessage = "Cannot send: Encryption failed.";
          _lastFailedSendText = trimmed;
        });
        return; // FAIL CLOSED: Send nothing!
      }

      final tempId = -DateTime.now().millisecondsSinceEpoch;
      final optimisticMsg = Message(
        id: tempId,
        senderId: _myId!,
        receiverId: widget.partnerId,
        content: trimmed,
        isEncrypted: true,
        createdAt: DateTime.now(),
      );
      _decryptedCache[tempId] = trimmed;

      _msgCtrl.clear();
      _removeSelectedMedia();
      HapticFeedback.lightImpact();

      _lastTypingSentTime = null;
      ApiService.sendTypingStatus(partnerId: widget.partnerId, isTyping: false, token: _userToken);

      setState(() {
        _messages.add(optimisticMsg);
        _replyingTo = null;
      });
      _scrollToBottom();

      final ok = await ApiService.sendMessage(
        _myId!,
        widget.partnerId,
        payload.ciphertext,
        nonce: payload.nonce,
        isEncrypted: true,
      );
      if (ok) {
        await _syncMessagesLive();
      } else {
        setState(() {
          _sendErrorMessage = "Message delivery failed. Tap to retry.";
          _lastFailedSendText = trimmed;
        });
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
  bool _sameDay(DateTime a, DateTime b) => DateTimeUtils.isSameDay(a, b);

  String _fmtTime(DateTime dt) => DateTimeUtils.formatTime(dt);

  String _fmtDateLabel(DateTime dt) => DateTimeUtils.formatDateLabel(dt);

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      AppFeedback.showError(context, msg);
    } else {
      AppFeedback.showSuccess(context, msg);
    }
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
                  _buildFloatingTypingIndicator(),
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
    _loadPartnerProfile();
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
  // ── App Bar ───────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    if (_isSearching) {
      return _buildSearchBarAppBar();
    }
    final theme = context.appTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(bottom: BorderSide(color: theme.divider, width: 1)),
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
                    AppAvatar(
                      size: 38,
                      name: widget.partnerName,
                      imageUrl: _partnerAvatarUrl != null && _partnerAvatarUrl!.isNotEmpty
                          ? (_partnerAvatarUrl!.startsWith('http')
                              ? _partnerAvatarUrl!
                              : '${ApiService.baseUrl}${_partnerAvatarUrl!.startsWith('/') ? '' : '/'}$_partnerAvatarUrl')
                          : null,
                      isOnline: _isOnline,
                      showOnlineIndicator: true,
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
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: theme.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
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
                                      color: _isPartnerVerified ? theme.success : theme.textTertiary,
                                      size: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              _isPartnerTyping
                                  ? 'typing…'
                                  : (_isOnline ? 'Online' : 'Offline'),
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: _isPartnerTyping
                                    ? (theme.isDark ? theme.accentBright : theme.accentFill)
                                    : (_isOnline ? theme.success : theme.textTertiary),
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
            icon: Icon(Icons.videocam_rounded, color: theme.textSecondary, size: 22),
            splashRadius: 20,
            tooltip: "Video Call",
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
            icon: Icon(Icons.call_rounded, color: theme.textSecondary, size: 20),
            splashRadius: 20,
            tooltip: "Voice Call",
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
            icon: Icon(Icons.search_rounded, color: theme.textSecondary, size: 20),
            splashRadius: 20,
            tooltip: "Search Messages",
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
            Icon(Icons.chat_bubble_outline_rounded, size: 44, color: _sub.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text('No messages yet', style: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Send the first message', style: TextStyle(color: _sub, fontSize: 13)),
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
    final theme = context.appTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = screenWidth * 0.78;

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
                  left: isMe ? 48 : 0,
                  right: isMe ? 0 : 48,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                decoration: BoxDecoration(
                  color: isMe ? theme.bubbleSent : theme.bubbleReceived,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                  border: isMe ? null : Border.all(color: theme.border, width: 1),
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
                          fontFamily: 'Inter',
                          color: msg.content.startsWith("🔒")
                              ? (isMe ? Colors.white70 : theme.textSecondary)
                              : (isMe ? theme.onBubbleSent : theme.onBubbleReceived),
                          fontSize: msg.content.startsWith("🔒") ? 13 : 15,
                          fontStyle: msg.content.startsWith("🔒") ? FontStyle.italic : FontStyle.normal,
                          height: 1.4,
                        ),
                      ),
                    const SizedBox(height: 4),
                    // Timestamp & Edited indicator
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (msg.isEdited) ...[
                          Icon(
                            Icons.edit_rounded,
                            size: 10,
                            color: isMe ? Colors.white.withOpacity(0.7) : theme.textTertiary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            "edited",
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: isMe ? Colors.white.withOpacity(0.7) : theme.textTertiary,
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
                            fontFamily: 'Inter',
                            color: isMe ? Colors.white.withOpacity(0.7) : theme.textTertiary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
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
                    bottom: 6,
                    top: 2,
                    right: isMe ? 6 : 0,
                    left: isMe ? 0 : 6,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.surfaceRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.border, width: 1),
                  ),
                  child: Text(reaction, style: const TextStyle(fontSize: 14)),
                ),
              ),
            if (reaction == null) const SizedBox(height: 4),
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

    final bool isMissed = (status == 'missed' || status == 'rejected');
    final bool isAnswered = status == 'ongoing' || status == 'ended';

    String title;
    String subtitle;

    if (isMe) {
      if (isAnswered && durationSecs > 0) {
        title = isVideo ? "Outgoing video call" : "Outgoing voice call";
        subtitle = "${_fmtCallDuration(durationSecs)} • ${_fmtTime(msg.createdAt)}";
      } else {
        title = isVideo ? "Cancelled video call" : "Cancelled voice call";
        subtitle = "Cancelled • ${_fmtTime(msg.createdAt)}";
      }
    } else {
      if (isAnswered && durationSecs > 0) {
        title = isVideo ? "Incoming video call" : "Incoming voice call";
        subtitle = "${_fmtCallDuration(durationSecs)} • ${_fmtTime(msg.createdAt)}";
      } else {
        title = isVideo ? "Missed video call" : "Missed voice call";
        subtitle = "Missed • ${_fmtTime(msg.createdAt)}";
      }
    }

    final theme = context.appTheme;
    final durationStr = (isAnswered && durationSecs > 0) ? _fmtCallDuration(durationSecs) : null;

    return SystemEventRow(
      icon: isMissed && !isMe
          ? Icons.call_missed_rounded
          : (isVideo ? Icons.videocam_rounded : (isMe ? Icons.call_made_rounded : Icons.call_received_rounded)),
      iconColor: isMissed && !isMe
          ? theme.danger
          : (isAnswered && durationSecs > 0 ? (theme.isDark ? theme.accentBright : theme.accentFill) : theme.textTertiary),
      text: title,
      duration: durationStr,
      time: _fmtTime(msg.createdAt),
      onTap: () {
        if (!isMe && isMissed) {
          CallService.startCall(
            context: context,
            partnerId: widget.partnerId,
            partnerName: widget.partnerName,
            callType: isVideo ? 'video' : 'voice',
          ).then((_) => _loadMessages());
        } else {
          _showCallLogOptions(msg, isMe, title, subtitle, isVideo);
        }
      },
      onLongPress: () => _showCallLogOptions(msg, isMe, title, subtitle, isVideo),
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

  // ── Floating Typing Indicator Bubble ──────────────────────────────────────
  Widget _buildFloatingTypingIndicator() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.45), end: Offset.zero).animate(anim),
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: _isPartnerTyping
          ? Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: const ValueKey("typing_bubble"),
                margin: const EdgeInsets.only(left: 18, bottom: 6, top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _surf,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(_isDark ? 0.22 : 0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBouncingDots(),
                    const SizedBox(width: 8),
                    Text(
                      "${widget.partnerName} is typing…",
                      style: TextStyle(
                        color: _rose,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey("typing_none")),
    );
  }

  Widget _buildBouncingDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (ctx, child) {
            final delay = i * 0.28;
            final val = ((_pulseCtrl.value + delay) % 1.0);
            final bounce = -4.0 * (0.5 - (val - 0.5).abs());
            return Transform.translate(
              offset: Offset(0, bounce),
              child: Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _rose,
                  boxShadow: [
                    BoxShadow(
                      color: _rose.withOpacity(0.55),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
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

  Widget _buildInlineSendErrorBar(AppTheme theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _sendErrorMessage ?? "Encryption failed. Message not sent.",
              style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          if (_lastFailedSendText != null)
            TextButton(
              onPressed: () {
                final retryText = _lastFailedSendText!;
                setState(() {
                  _sendErrorMessage = null;
                  _lastFailedSendText = null;
                  _msgCtrl.text = retryText;
                });
                _sendMessage();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text("Retry", style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: 16,
            onPressed: () => setState(() => _sendErrorMessage = null),
          ),
        ],
      ),
    );
  }

  // ── Input Bar ─────────────────────────────────────────────────────────────
  Widget _buildInputBar() {
    final theme = context.appTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 14),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(top: BorderSide(color: theme.divider, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_sendErrorMessage != null) _buildInlineSendErrorBar(theme),
          if (_selectedImage != null || _selectedFileName != null)
            _buildMediaPreviewBar(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Clean Paperclip Attachment Button
              IconButton(
                icon: Icon(Icons.attach_file_rounded, color: theme.textSecondary, size: 22),
                onPressed: _showAttachmentSheet,
                splashRadius: 22,
              ),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: theme.surfaceRaised,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.border, width: 1),
                  ),
                  child: TextField(
                    controller: _msgCtrl,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: theme.textPrimary,
                      fontSize: 15,
                    ),
                    maxLines: 4,
                    minLines: 1,
                    cursorColor: theme.focusRing,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: _editingMsg != null
                          ? 'Edit message…'
                          : (_selectedImage != null || _selectedFileName != null
                              ? 'Add caption…'
                              : 'Send a message…'),
                      hintStyle: TextStyle(
                        fontFamily: 'Inter',
                        color: theme.textTertiary,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _isSending ? null : _sendMessage,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isSending
                        ? theme.surfaceRaised
                        : theme.accentFill,
                    border: _isSending ? Border.all(color: theme.border, width: 1) : null,
                  ),
                  child: _isSending
                      ? Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: theme.accentFill,
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : Icon(
                          _editingMsg != null ? Icons.check_rounded : Icons.arrow_upward_rounded,
                          color: theme.onAccent,
                          size: 20,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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

  String _formatDateYMD(DateTime dt) =>
      "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";

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
    return TimelineDrawer(
      memories: _sharedMemories,
      isLoading: _loadingMemories,
      selectedDate: _selDate,
      onSelectDate: (d) => setState(() => _selDate = d),
      onRefresh: () {
        _loadMemories();
        _toast("Refreshed timeline entries");
      },
      onClose: _closeAll,
      onSaveMemory: (content, mood, photo) async {
        final targetDate = _selDate ?? DateTime.now();
        final dateStr = _formatDateYMD(targetDate);
        HapticFeedback.mediumImpact();
        final res = await ApiService.createDiaryMemory(
          partnerId: widget.partnerId,
          entryDate: dateStr,
          content: content,
          moodEmoji: mood,
          photo: photo,
          token: _userToken,
        );
        if (mounted) {
          if (res != null) {
            _toast("Saved to timeline for ${_fmtDateLabel(targetDate)}");
            await _loadMemories();
          } else {
            _toast("Failed to save memory entry", isError: true);
          }
        }
      },
      onDeleteMemory: _deleteMemory,
      partnerName: widget.partnerName,
      myId: _myId,
      onPhotoTap: _openMemoryImageFullScreen,
    );
  }

  // ── Settings & Navigation Drawer Panel ───────────────────────────────────
  Widget _buildSettingsPanel() {
    final theme = context.appTheme;

    return Material(
      color: theme.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top User Profile Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.surface,
                border: Border(bottom: BorderSide(color: theme.border, width: 1)),
              ),
              child: Row(
                children: [
                  AppAvatar(
                    size: 44,
                    name: _myUsername.isNotEmpty ? _myUsername : 'User',
                    imageUrl: _myAvatarUrl != null && _myAvatarUrl!.isNotEmpty
                        ? (_myAvatarUrl!.startsWith('http')
                            ? _myAvatarUrl!
                            : "${ApiService.baseUrl}/${_myAvatarUrl!.startsWith('/') ? _myAvatarUrl!.substring(1) : _myAvatarUrl!}")
                        : null,
                    onTap: () async {
                      _closeAll();
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                      _loadMyProfile();
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        _closeAll();
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ProfileScreen()),
                        );
                        _loadMyProfile();
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _myUsername.isNotEmpty ? _myUsername : 'My Profile',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: theme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Edit profile & account',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              color: theme.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: theme.textSecondary, size: 22),
                    tooltip: 'Close',
                    onPressed: _closeAll,
                  ),
                ],
              ),
            ),

            // Scrollable grouped list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  SectionGroup(
                    title: "Shared Space",
                    children: [
                      AppListTile(
                        leading: AppAvatar(
                          size: 36,
                          name: widget.partnerName,
                          imageUrl: _partnerAvatarUrl != null && _partnerAvatarUrl!.isNotEmpty
                              ? (_partnerAvatarUrl!.startsWith('http')
                                  ? _partnerAvatarUrl!
                                  : '${ApiService.baseUrl}${_partnerAvatarUrl!.startsWith('/') ? '' : '/'}$_partnerAvatarUrl')
                              : null,
                          isOnline: _isOnline,
                          showOnlineIndicator: true,
                        ),
                        title: widget.partnerName,
                        subtitle: _isOnline ? 'Active now' : 'Partner details & encryption',
                        showChevron: true,
                        onTap: () {
                          _closeAll();
                          _openPartnerProfile();
                        },
                      ),
                      AppListTile(
                        icon: Icons.photo_library_outlined,
                        title: "Shared Media Gallery",
                        subtitle: "Photos, videos, audio & files",
                        showChevron: true,
                        onTap: () {
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
                    ],
                  ),
                  SectionGroup(
                    title: "Preferences",
                    children: [
                      AppListTile(
                        icon: Icons.palette_outlined,
                        title: "Appearance",
                        subtitle: "${theme.name} • ${theme.isDark ? 'Dark' : 'Light'}",
                        showChevron: true,
                        onTap: () {
                          _closeAll();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ThemeSelectionScreen(),
                            ),
                          );
                        },
                      ),
                      AppListTile(
                        icon: _notificationsEnabled
                            ? Icons.notifications_active_outlined
                            : Icons.notifications_off_outlined,
                        title: "Notifications",
                        subtitle: _notificationsEnabled ? 'Alerts active' : 'Alerts muted',
                        trailing: Switch.adaptive(
                          value: _notificationsEnabled,
                          activeColor: theme.accentFill,
                          onChanged: (val) => setState(() => _notificationsEnabled = val),
                        ),
                      ),
                    ],
                  ),
                  SectionGroup(
                    title: "Security & Privacy",
                    children: [
                      AppListTile(
                        icon: Icons.shield_outlined,
                        title: "Security & Lock",
                        subtitle: "Passcode, Biometrics & 2FA",
                        showChevron: true,
                        onTap: () {
                          _closeAll();
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SecurityScreen()),
                          );
                        },
                      ),
                      AppListTile(
                        icon: Icons.key_outlined,
                        title: "Change Password",
                        subtitle: "Update account password",
                        showChevron: true,
                        onTap: () {
                          _closeAll();
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                  SectionGroup(
                    title: "Network & Connection",
                    children: [
                      AppListTile(
                        icon: Icons.dns_outlined,
                        title: "Server Configuration",
                        subtitle: "IP, port & connection test",
                        showChevron: true,
                        onTap: () {
                          _closeAll();
                          ServerConfigDialog.show(context);
                        },
                      ),
                    ],
                  ),
                  SectionGroup(
                    children: [
                      AppListTile(
                        icon: Icons.logout_rounded,
                        title: "Sign Out",
                        isDestructive: true,
                        onTap: _showLogoutDialog,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Logout Dialog ─────────────────────────────────────────────────────────
  void _showLogoutDialog() {
    _closeAll();
    final theme = context.appTheme;
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: theme.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.border, width: 1),
          ),
          title: Text(
            'Sign Out',
            style: TextStyle(
              fontFamily: 'Inter',
              color: theme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Text(
            'Are you sure you want to sign out of TwoOfUs? Your local session will be closed.',
            style: TextStyle(
              fontFamily: 'Inter',
              color: theme.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: theme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            AppButton(
              text: 'Sign Out',
              variant: AppButtonVariant.danger,
              size: AppButtonSize.compact,
              onPressed: () async {
                await Session.logout();
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      );
    });
  }
}