class DateTimeUtils {
  DateTimeUtils._();

  /// Universally parses server timestamp (which is in UTC) and converts it to local device timezone
  static DateTime parseToLocal(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is DateTime) return val.toLocal();

    final s = val.toString().trim();
    if (s.isEmpty) return DateTime.now();

    try {
      DateTime dt;
      if (s.endsWith('Z') || s.endsWith('z')) {
        dt = DateTime.parse(s);
      } else if (s.contains('+') || (s.length > 19 && (s.substring(19).contains('-')))) {
        dt = DateTime.parse(s);
      } else {
        // Server sent naive UTC string e.g. "2026-09-01 13:30:00" or "2026-09-01T13:30:00"
        final normalized = s.replaceAll(' ', 'T');
        dt = DateTime.parse('${normalized}Z');
      }
      return dt.toLocal();
    } catch (_) {
      try {
        return DateTime.parse(s).toLocal();
      } catch (_) {
        return DateTime.now();
      }
    }
  }

  static bool isSameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  /// Formats message time in 12-hour format with AM/PM (e.g. "6:30 PM" or "Jan 15  6:30 PM")
  static String formatTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();

    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour12:$minute $period';

    if (isSameDay(local, now)) {
      return timeStr;
    }

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[local.month - 1]} ${local.day}  $timeStr';
  }

  /// Formats date header labels: "Today", "Yesterday", "Jan 15, 2026"
  static String formatDateLabel(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();

    if (isSameDay(local, now)) return 'Today';
    if (isSameDay(local, now.subtract(const Duration(days: 1)))) return 'Yesterday';

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (local.year == now.year) {
      return '${months[local.month - 1]} ${local.day}';
    }
    return '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  /// Formats call time (e.g. "6:30 PM")
  static String formatCallTime(DateTime dt) {
    final local = dt.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }
}
