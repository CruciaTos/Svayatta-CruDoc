/// Where the evening session starts. The clinic's own session times are
/// not stored anywhere yet (see IMPLEMENTATION_REPORT.md, GAP "clinic
/// hours"), so this is the spec's default: 17:00.
const int kEveningSessionStartHour = 17;

/// Where Auto appearance hands back to Day in the morning.
const int kDaySessionStartHour = 5;

bool isEveningSession(DateTime t) =>
    t.hour >= kEveningSessionStartHour || t.hour < kDaySessionStartHour;
