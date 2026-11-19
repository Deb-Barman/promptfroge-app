/// Parses the loose date text accepted by "Search by date": today / yesterday, "12 September 2026",
/// "September 12th, 2026", "2026-09-12", "12/9/2026" (day first) or "12-9-2026". Returns local midnight, or null.
/// A port of the original `_parseFlexibleDate`, including its month-prefix matching ("sep" -> September).
DateTime? parseFlexibleDate(String? raw, {DateTime? now}) {
  const months = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return null;
  final base = now ?? DateTime.now();
  if (s == 'today') return DateTime(base.year, base.month, base.day);
  if (s == 'yesterday') return DateTime(base.year, base.month, base.day - 1);

  var m = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?\s+([a-z]+)\s+(\d{4})$').firstMatch(s) ?? RegExp(r'^([a-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})$').firstMatch(s);
  if (m != null) {
    int day, year;
    String monthName;
    if (RegExp(r'^\d+$').hasMatch(m.group(1)!)) {
      day = int.parse(m.group(1)!);
      monthName = m.group(2)!;
      year = int.parse(m.group(3)!);
    } else {
      monthName = m.group(1)!;
      day = int.parse(m.group(2)!);
      year = int.parse(m.group(3)!);
    }
    final idx = months.indexWhere((mo) => mo.startsWith(monthName));
    if (idx == -1) return null;
    return DateTime(year, idx + 1, day);
  }
  m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
  if (m != null) return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  m = RegExp(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})$').firstMatch(s);
  if (m != null) return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  return null;
}

const List<String> kMonthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// "12 September 2026" - the text the date pickers write into the input, which parseFlexibleDate reads back.
String dateToFlexibleText(DateTime d) => '${d.day} ${kMonthNames[d.month - 1].toLowerCase()} ${d.year}';
