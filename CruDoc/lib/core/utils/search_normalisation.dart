/// Small text-normalization helpers used when matching user-typed search
/// input against stored records (patients today; anything else that needs
/// case/format-insensitive search later). Kept dependency-free and pure
/// so they're trivially testable and reusable outside the patients feature.

/// Lowercases and trims [value] for case-insensitive comparisons.
///
/// e.g. `normalizeForSearch('  John Doe ')` and `normalizeForSearch('john doe')`
/// both produce `'john doe'`, so a search for "john" matches "John".
String normalizeForSearch(String value) => value.trim().toLowerCase();

/// Strips every non-digit character from [value], then keeps only the
/// last 10 digits (standard Indian mobile number length).
///
/// This makes '9876543210', '98765 43210', and '+91 98765 43210' all
/// normalize to the same '9876543210' — so phone search works regardless
/// of spacing, dashes, or a leading country code/trunk prefix. Numbers
/// with 10 or fewer digits (e.g. a landline missing a code) pass through
/// unchanged rather than being truncated further.
String normalizePhoneDigits(String value) {
  final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.length <= 10) return digitsOnly;
  return digitsOnly.substring(digitsOnly.length - 10);
}