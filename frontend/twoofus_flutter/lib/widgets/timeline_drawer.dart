import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/diary_memory.dart';
import '../services/api_service.dart';
import '../services/e2ee_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../utils/session.dart';
import 'design_system/design_system.dart';

class TimelineDrawer extends StatefulWidget {
  final List<DiaryMemoryItem> memories;
  final bool isLoading;
  final DateTime? selectedDate;
  final ValueChanged<DateTime?> onSelectDate;
  final VoidCallback onRefresh;
  final VoidCallback onClose;
  final Future<void> Function(String content, String? mood, File? photo) onSaveMemory;
  final ValueChanged<int> onDeleteMemory;
  final String partnerName;
  final int? myId;
  final String? partnerPublicKey;
  final String? token;
  final void Function(DiaryMemoryItem memory)? onPhotoTap;

  const TimelineDrawer({
    super.key,
    required this.memories,
    this.isLoading = false,
    this.selectedDate,
    required this.onSelectDate,
    required this.onRefresh,
    required this.onClose,
    required this.onSaveMemory,
    required this.onDeleteMemory,
    required this.partnerName,
    this.myId,
    this.partnerPublicKey,
    this.token,
    this.onPhotoTap,
  });

  @override
  State<TimelineDrawer> createState() => _TimelineDrawerState();
}

class _TimelineDrawerState extends State<TimelineDrawer> {
  int _diaryTab = 0; // 0 = Timeline, 1 = Photo Album
  DateTime _calMonth = DateTime.now();
  String _selectedMoodEmoji = '✨';
  File? _selectedPhoto;
  final _memoryCtrl = TextEditingController();
  bool _isSaving = false;

  static const List<String> _moods = [
    '✨', '🌟', '☕', '🔥', '🎉', '🚀', '💡', '✈️',
    '🏖️', '🎧', '🍕', '🌙', '❤️', '😊', '🌿', '🎨'
  ];

  @override
  void dispose() {
    _memoryCtrl.dispose();
    super.dispose();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _memoryMatchesDate(DiaryMemoryItem m, DateTime target) {
    final p = m.parsedDate;
    if (p == null) return false;
    return _sameDay(p, target);
  }

  String _fmtDateLabel(DateTime dt) {
    final now = DateTime.now();
    if (_sameDay(dt, now)) return 'Today';
    if (_sameDay(dt, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return "${m[dt.month - 1]} ${dt.day}, ${dt.year}";
  }

  void _showMoodPickerSheet(AppTheme theme) {
    AppSheet.show(
      context: context,
      builder: (ctx) => AppSheet(
        title: 'Choose Mood',
        subtitle: 'Select an emoji for this memory',
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: _moods.map((m) {
            final isSel = _selectedMoodEmoji == m;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedMoodEmoji = m);
                Navigator.pop(ctx);
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSel ? theme.accentFill.withValues(alpha: 0.15) : theme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSel ? theme.accentFill : theme.border,
                    width: isSel ? 1.5 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(m, style: const TextStyle(fontSize: 22)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showPhotoPickerSheet(AppTheme theme) {
    AppSheet.show(
      context: context,
      builder: (ctx) => AppSheet(
        title: 'Attach Photo',
        subtitle: 'Add an image to your timeline memory',
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _photoOption(
              theme: theme,
              icon: Icons.camera_alt_outlined,
              label: 'Camera',
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            _photoOption(
              theme: theme,
              icon: Icons.photo_library_outlined,
              label: 'Gallery',
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoOption({
    required AppTheme theme,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: theme.accentFill.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.accentFill.withValues(alpha: 0.25)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: theme.accentFill, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              color: theme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 85);
      if (picked != null) {
        setState(() {
          _selectedPhoto = File(picked.path);
        });
      }
    } catch (_) {}
  }

  Future<void> _handleSubmit() async {
    final text = _memoryCtrl.text.trim();
    if (text.isEmpty && _selectedPhoto == null) return;

    setState(() => _isSaving = true);
    await widget.onSaveMemory(text, _selectedMoodEmoji, _selectedPhoto);
    if (mounted) {
      setState(() {
        _isSaving = false;
        _memoryCtrl.clear();
        _selectedPhoto = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final photoMemories = widget.memories.where((m) => m.hasPhoto).toList();
    final displayedMemories = widget.selectedDate == null
        ? widget.memories
        : widget.memories.where((m) => _memoryMatchesDate(m, widget.selectedDate!)).toList();

    return Material(
      color: theme.bg,
      child: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              decoration: BoxDecoration(
                color: theme.surface,
                border: Border(bottom: BorderSide(color: theme.border, width: 1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: theme.surfaceRaised,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.border),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.auto_stories_rounded, size: 18, color: theme.accentFill),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shared Timeline',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: theme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Shared milestones & notes',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: theme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: Icon(Icons.refresh_rounded, color: theme.textSecondary, size: 20),
                    onPressed: widget.onRefresh,
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: Icon(Icons.close_rounded, color: theme.textSecondary, size: 22),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),

            // Tab Selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: theme.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _diaryTab = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(
                            color: _diaryTab == 0 ? theme.surface : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: _diaryTab == 0 ? Border.all(color: theme.border) : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.edit_note_rounded,
                                size: 16,
                                color: _diaryTab == 0 ? theme.accentFill : theme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  "Timeline (${widget.memories.length})",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    fontWeight: _diaryTab == 0 ? FontWeight.w600 : FontWeight.w500,
                                    color: _diaryTab == 0 ? theme.textPrimary : theme.textSecondary,
                                  ),
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
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(
                            color: _diaryTab == 1 ? theme.surface : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: _diaryTab == 1 ? Border.all(color: theme.border) : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.photo_library_outlined,
                                size: 16,
                                color: _diaryTab == 1 ? theme.accentFill : theme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  "Album (${photoMemories.length})",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    fontWeight: _diaryTab == 1 ? FontWeight.w600 : FontWeight.w500,
                                    color: _diaryTab == 1 ? theme.textPrimary : theme.textSecondary,
                                  ),
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

            // Compact Calendar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: _buildCalendar(theme),
            ),

            Divider(color: theme.divider, height: 16),

            // Composer Area
            _buildComposer(theme),

            const SizedBox(height: 8),

            // Content Area
            Expanded(
              child: widget.isLoading
                  ? Center(child: CircularProgressIndicator(color: theme.accentFill, strokeWidth: 2))
                  : _diaryTab == 0
                      ? _buildTimelineList(theme, displayedMemories)
                      : _buildPhotoAlbum(theme, photoMemories),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar(AppTheme theme) {
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
    for (int i = 0; i < startWd; i++) {
      cells.add(const SizedBox());
    }

    for (int d = 1; d <= last.day; d++) {
      final date = DateTime(m.year, m.month, d);
      final isSel = widget.selectedDate != null && _sameDay(widget.selectedDate!, date);
      final hasMem = widget.memories.any((x) => _memoryMatchesDate(x, date));
      final isToday = _sameDay(DateTime.now(), date);

      cells.add(GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          if (widget.selectedDate != null && _sameDay(widget.selectedDate!, date)) {
            widget.onSelectDate(null);
          } else {
            widget.onSelectDate(date);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSel
                ? theme.accentFill
                : (hasMem ? theme.accentFill.withValues(alpha: 0.15) : null),
            border: isToday && !isSel
                ? Border.all(color: theme.accentFill, width: 1.5)
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '$d',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: (isToday || isSel) ? FontWeight.w700 : FontWeight.w500,
                  color: isSel
                      ? theme.onAccent
                      : (isToday ? theme.accentFill : theme.textPrimary),
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
                      color: theme.accentFill,
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
              icon: Icon(Icons.chevron_left_rounded, color: theme.textSecondary),
              onPressed: () => setState(() => _calMonth = DateTime(m.year, m.month - 1)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            GestureDetector(
              onTap: () => setState(() {
                _calMonth = DateTime.now();
                widget.onSelectDate(DateTime.now());
              }),
              child: Row(
                children: [
                  Text(
                    '${mons[m.month - 1]} ${m.year}',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: theme.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.touch_app_rounded, size: 12, color: theme.textTertiary),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.chevron_right_rounded, color: theme.textSecondary),
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
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: theme.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
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

  Widget _buildComposer(AppTheme theme) {
    final dateLabel = widget.selectedDate != null ? _fmtDateLabel(widget.selectedDate!) : 'Today';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.edit_calendar_rounded, size: 14, color: theme.accentFill),
              const SizedBox(width: 6),
              Text(
                "Entry for $dateLabel",
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: theme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_selectedPhoto != null)
                Text(
                  "Photo attached",
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: theme.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Attached Photo Preview
          if (_selectedPhoto != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.border),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _selectedPhoto!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Photo ready to post",
                      style: TextStyle(fontFamily: 'Inter', color: theme.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: theme.textSecondary),
                    onPressed: () => setState(() => _selectedPhoto = null),
                  ),
                ],
              ),
            ),
          ],

          // Text Field + Actions Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Mood Picker Button
              GestureDetector(
                onTap: () => _showMoodPickerSheet(theme),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.border),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedMoodEmoji,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down_rounded, size: 18, color: theme.textSecondary),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Note Input
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.border),
                  ),
                  child: TextField(
                    controller: _memoryCtrl,
                    style: TextStyle(fontFamily: 'Inter', color: theme.textPrimary, fontSize: 13),
                    cursorColor: theme.accentFill,
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Write a thought or note…',
                      hintStyle: TextStyle(fontFamily: 'Inter', color: theme.textTertiary, fontSize: 12.5),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Attach Photo Button
              IconButton(
                tooltip: "Attach Photo",
                icon: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _selectedPhoto != null ? theme.accentFill.withValues(alpha: 0.15) : theme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _selectedPhoto != null ? theme.accentFill : theme.border),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add_a_photo_outlined,
                    color: _selectedPhoto != null ? theme.accentFill : theme.textSecondary,
                    size: 18,
                  ),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                onPressed: () => _showPhotoPickerSheet(theme),
              ),
              const SizedBox(width: 6),

              // Post Button
              GestureDetector(
                onTap: _isSaving ? null : _handleSubmit,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: theme.accentFill,
                  ),
                  child: _isSaving
                      ? Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: theme.onAccent, strokeWidth: 2),
                          ),
                        )
                      : Icon(Icons.arrow_upward_rounded, color: theme.onAccent, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineList(AppTheme theme, List<DiaryMemoryItem> items) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.auto_stories_rounded,
        title: widget.selectedDate != null
            ? 'No entries for ${_fmtDateLabel(widget.selectedDate!)}'
            : 'No timeline entries yet',
        description: 'Write a thought or attach a photo for this date above.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final mem = items[i];
        final isMe = mem.senderId == widget.myId;
        final authorLabel = isMe ? "You" : widget.partnerName;

        return Dismissible(
          key: Key('memory_${mem.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            return await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    backgroundColor: theme.surfaceRaised,
                    title: Text(
                      "Delete Entry?",
                      style: TextStyle(fontFamily: 'Inter', color: theme.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    content: Text(
                      "Are you sure you want to delete this timeline entry?",
                      style: TextStyle(fontFamily: 'Inter', color: theme.textSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: Text("Cancel", style: TextStyle(color: theme.textSecondary)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: Text("Delete", style: TextStyle(color: theme.danger)),
                      ),
                    ],
                  ),
                ) ??
                false;
          },
          onDismissed: (_) => widget.onDeleteMemory(mem.id),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: theme.danger.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.delete_rounded, color: theme.danger, size: 22),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Mood Emoji + Author Badge + Date Badge
                Row(
                  children: [
                    if (mem.moodEmoji != null && mem.moodEmoji!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.border),
                        ),
                        child: Text(mem.moodEmoji!, style: const TextStyle(fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isMe ? theme.accentFill.withValues(alpha: 0.12) : theme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isMe ? theme.accentFill.withValues(alpha: 0.25) : theme.border),
                      ),
                      child: Text(
                        authorLabel,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: isMe ? theme.accentFill : theme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      mem.entryDate,
                      style: TextStyle(fontFamily: 'Inter', color: theme.textTertiary, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, size: 16, color: theme.textTertiary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: () => widget.onDeleteMemory(mem.id),
                    ),
                  ],
                ),

                // Attached Photo
                if (mem.hasPhoto && mem.fullImageUrl != null) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => widget.onPhotoTap?.call(mem),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Container(
                            height: 150,
                            width: double.infinity,
                            color: theme.surface,
                            child: TimelineMemoryImage(
                              memory: mem,
                              partnerPublicKey: widget.partnerPublicKey,
                              token: widget.token,
                              fit: BoxFit.cover,
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
                      fontFamily: 'Inter',
                      color: theme.textPrimary,
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

  Widget _buildPhotoAlbum(AppTheme theme, List<DiaryMemoryItem> photos) {
    if (photos.isEmpty) {
      return const EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'No scrapbook photos yet',
        description: 'Attach a photo to any timeline entry above and it will show up here.',
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
      itemCount: photos.length,
      itemBuilder: (ctx, idx) {
        final mem = photos[idx];
        return GestureDetector(
          onTap: () => widget.onPhotoTap?.call(mem),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: theme.surfaceRaised,
                  child: TimelineMemoryImage(
                    memory: mem,
                    partnerPublicKey: widget.partnerPublicKey,
                    token: widget.token,
                    fit: BoxFit.cover,
                  ),
                ),
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
                          Colors.black.withValues(alpha: 0.75),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
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
}

class TimelineMemoryImage extends StatefulWidget {
  final DiaryMemoryItem memory;
  final String? partnerPublicKey;
  final String? token;
  final BoxFit fit;

  const TimelineMemoryImage({
    super.key,
    required this.memory,
    this.partnerPublicKey,
    this.token,
    this.fit = BoxFit.cover,
  });

  @override
  State<TimelineMemoryImage> createState() => _TimelineMemoryImageState();
}

class _TimelineMemoryImageState extends State<TimelineMemoryImage> {
  Uint8List? _decryptedBytes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant TimelineMemoryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memory.id != widget.memory.id || oldWidget.memory.imageUrl != widget.memory.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (!widget.memory.isEncrypted || widget.memory.photoNonce == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final token = widget.token ?? (await Session.getToken() ?? '');
      final url = widget.memory.fullImageUrl;
      if (url == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final rawBytes = await ApiService.fetchAuthenticatedBytes(url, token);
      if (rawBytes != null) {
        final myId = await Session.getUserId();
        final cachedPartnerId = await Session.getCachedPartnerId();
        final partnerId = (myId != null && widget.memory.senderId == myId)
            ? widget.memory.receiverId
            : ((cachedPartnerId != null && widget.memory.receiverId == cachedPartnerId)
                ? cachedPartnerId
                : widget.memory.senderId);
        final partnerKey = widget.partnerPublicKey ?? await E2EEService.getPartnerPublicKey(partnerId, token: token);
        if (partnerKey != null && partnerKey.isNotEmpty) {
          final decrypted = await E2EEService.decryptTimelinePhoto(
            encryptedPhotoBytes: rawBytes,
            nonceBase64: widget.memory.photoNonce!,
            remotePublicKeyBase64: partnerKey,
          );
          if (mounted) {
            setState(() {
              _decryptedBytes = decrypted;
              _isLoading = false;
            });
            return;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    if (widget.memory.isEncrypted && widget.memory.photoNonce != null) {
      if (_isLoading) {
        return Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: theme.accentFill),
          ),
        );
      }
      if (_decryptedBytes != null) {
        return Image.memory(_decryptedBytes!, fit: widget.fit);
      }
      return Center(
        child: Icon(Icons.lock_outline_rounded, color: theme.textTertiary, size: 32),
      );
    }

    return Image.network(
      widget.memory.fullImageUrl ?? '',
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) => Center(
        child: Icon(Icons.broken_image_rounded, color: theme.textTertiary, size: 32),
      ),
    );
  }
}
