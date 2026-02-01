/// Utility for consistent DateTime handling across the app.
///
/// The API returns two types of date fields:
/// 1. **Date-only fields** (e.g., session.date, program.startDate): Serialized as "yyyy-MM-dd"
/// 2. **Timestamp fields** (e.g., startedAt, createdAt): Serialized as "yyyy-MM-ddTHH:mm:ss.fffZ"
///
/// This helper ensures proper parsing and formatting for both types.
class DateTimeHelper {
  /// Parse date-only string "yyyy-MM-dd" to local DateTime at midnight.
  /// Use this for fields like session.date, program.startDate, goal.targetDate.
  static DateTime parseDate(String dateStr) {
    // Handle both "yyyy-MM-dd" and ISO formats that might come through
    if (dateStr.contains('T')) {
      // If it's a full ISO string, extract just the date part
      dateStr = dateStr.split('T').first;
    }
    final parts = dateStr.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// Parse nullable date-only string.
  static DateTime? parseDateOrNull(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    return parseDate(dateStr);
  }

  /// Parse date from dynamic JSON value (handles both String and already-parsed DateTime).
  static DateTime parseDateFromJson(dynamic json) {
    if (json == null) {
      return DateTime.now();
    }
    if (json is DateTime) {
      // Already parsed by json_serializable, normalize to local midnight
      return DateTime(json.year, json.month, json.day);
    }
    if (json is String) {
      return parseDate(json);
    }
    throw FormatException('Cannot parse date from: $json');
  }

  /// Parse nullable date from dynamic JSON value.
  static DateTime? parseDateOrNullFromJson(dynamic json) {
    if (json == null) return null;
    if (json is DateTime) {
      return DateTime(json.year, json.month, json.day);
    }
    if (json is String && json.isNotEmpty) {
      return parseDate(json);
    }
    return null;
  }

  /// Parse timestamp string to UTC DateTime.
  /// Use this for fields like startedAt, completedAt, createdAt.
  static DateTime parseTimestamp(String timestampStr) {
    final dt = DateTime.parse(timestampStr);
    // If already UTC (has Z suffix), return as-is
    if (dt.isUtc) return dt;
    // Otherwise, treat raw values as UTC (this handles the edge case where
    // the server returns a timestamp without the Z suffix)
    return DateTime.utc(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
      dt.microsecond,
    );
  }

  /// Parse nullable timestamp string.
  static DateTime? parseTimestampOrNull(String? timestampStr) {
    if (timestampStr == null || timestampStr.isEmpty) return null;
    return parseTimestamp(timestampStr);
  }

  /// Parse timestamp from dynamic JSON value.
  static DateTime parseTimestampFromJson(dynamic json) {
    if (json == null) {
      return DateTime.now().toUtc();
    }
    if (json is DateTime) {
      // Ensure it's UTC
      return json.isUtc ? json : json.toUtc();
    }
    if (json is String) {
      return parseTimestamp(json);
    }
    throw FormatException('Cannot parse timestamp from: $json');
  }

  /// Parse nullable timestamp from dynamic JSON value.
  static DateTime? parseTimestampOrNullFromJson(dynamic json) {
    if (json == null) return null;
    if (json is DateTime) {
      return json.isUtc ? json : json.toUtc();
    }
    if (json is String && json.isNotEmpty) {
      return parseTimestamp(json);
    }
    return null;
  }

  /// Format date for API (date-only fields).
  /// Outputs: "yyyy-MM-dd"
  static String formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Format timestamp for API (timestamp fields).
  /// Converts to UTC and outputs ISO 8601 format.
  static String formatTimestamp(DateTime timestamp) {
    final utc = timestamp.toUtc();
    return utc.toIso8601String();
  }

  /// Convert UTC timestamp to local for display.
  static DateTime toLocal(DateTime utcTimestamp) {
    return utcTimestamp.toLocal();
  }

  /// Check if two dates are the same day (ignoring time).
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Get today's date at local midnight.
  static DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
