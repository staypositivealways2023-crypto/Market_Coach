/// Market status / session detection.
/// All logic is client-side — no API call required.
library market_hours;

enum MarketStatus {
  alwaysOpen,   // crypto
  preMarket,    // 04:00–09:29 ET
  open,         // 09:30–15:59 ET
  afterHours,   // 16:00–19:59 ET
  closed,       // nights + weekends
}

extension MarketStatusLabel on MarketStatus {
  String get label {
    switch (this) {
      case MarketStatus.alwaysOpen:  return 'LIVE';
      case MarketStatus.open:        return 'MARKET OPEN';
      case MarketStatus.preMarket:   return 'PRE-MARKET';
      case MarketStatus.afterHours:  return 'AFTER-HOURS';
      case MarketStatus.closed:      return 'CLOSED';
    }
  }
}

/// Returns the current US equity market status.
/// [isCrypto] — crypto markets trade 24/7, always returns [MarketStatus.alwaysOpen].
MarketStatus getMarketStatus({required bool isCrypto}) {
  if (isCrypto) return MarketStatus.alwaysOpen;

  // Convert UTC → US Eastern (approximate; ignores DST transitions mid-day).
  // EDT = UTC-4, EST = UTC-5.  April → October is EDT.
  final now = DateTime.now().toUtc();
  final isDst = _isDaylightSaving(now);
  final est = now.add(Duration(hours: isDst ? -4 : -5));

  // Weekend
  if (est.weekday == DateTime.saturday || est.weekday == DateTime.sunday) {
    return MarketStatus.closed;
  }

  final minutesSinceMidnight = est.hour * 60 + est.minute;
  const preMarketOpen  = 4 * 60;       // 04:00
  const marketOpen     = 9 * 60 + 30;  // 09:30
  const marketClose    = 16 * 60;      // 16:00
  const afterClose     = 20 * 60;      // 20:00

  if (minutesSinceMidnight < preMarketOpen)  return MarketStatus.closed;
  if (minutesSinceMidnight < marketOpen)     return MarketStatus.preMarket;
  if (minutesSinceMidnight < marketClose)    return MarketStatus.open;
  if (minutesSinceMidnight < afterClose)     return MarketStatus.afterHours;
  return MarketStatus.closed;
}

/// Rough DST check: second Sunday March → first Sunday November.
bool _isDaylightSaving(DateTime utc) {
  if (utc.month < 3 || utc.month > 11) return false;
  if (utc.month > 3 && utc.month < 11) return true;
  if (utc.month == 3) {
    // Second Sunday of March
    final secondSunday = _nthWeekdayOfMonth(utc.year, 3, DateTime.sunday, 2);
    return utc.day >= secondSunday;
  }
  // November: before first Sunday
  final firstSunday = _nthWeekdayOfMonth(utc.year, 11, DateTime.sunday, 1);
  return utc.day < firstSunday;
}

int _nthWeekdayOfMonth(int year, int month, int weekday, int n) {
  int day = 1;
  int count = 0;
  while (true) {
    final d = DateTime(year, month, day);
    if (d.weekday == weekday) {
      count++;
      if (count == n) return day;
    }
    day++;
  }
}
