/// The category booking's time slots, the same as the web's
/// (`AppointmentBookingForm.jsx`): every half hour of the day.
final List<String> kTimeSlots = List.unmodifiable([
  for (var hour = 0; hour < 24; hour++)
    for (final minute in const ['00', '30'])
      '${hour % 12 == 0 ? 12 : hour % 12}:$minute ${hour < 12 ? 'AM' : 'PM'}',
]);

const String kSlotPassedMessage =
    'This time slot has passed. Please choose another time.';

final RegExp _slotPattern = RegExp(r'^(\d{1,2}):(\d{2}) (AM|PM)$');

/// Whether [slot] ("1:30 PM") on the calendar day of [date] starts at [now] or
/// earlier. Both are the phone's local time: unlike the web, "today" is never
/// taken from the UTC date.
bool isSlotPassed(DateTime date, String slot, DateTime now) {
  final match = _slotPattern.firstMatch(slot);
  if (match == null) return false;
  var hour = int.parse(match.group(1)!) % 12;
  if (match.group(3) == 'PM') hour += 12;
  final start = DateTime(
    date.year,
    date.month,
    date.day,
    hour,
    int.parse(match.group(2)!),
  );
  return !start.isAfter(now);
}
