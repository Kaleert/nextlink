import '../providers/profiles_provider.dart';

/// Each enabled automation owns its interval; firing one never resets others.
class ProfileTimerSchedule {
  final Map<String, DateTime> _lastActions = {};

  void markTriggered(String id, DateTime now) => _lastActions[id] = now;

  AppProfile? nextDue(
    List<AppProfile> profiles, {
    required bool connected,
    required DateTime now,
  }) {
    final timers = profiles
        .where((p) => p.isEnabled && p.hasTrigger('timer'))
        .toList();
    final ids = timers.map((p) => p.id).toSet();
    _lastActions.removeWhere((id, _) => !ids.contains(id));
    if (!connected) {
      _lastActions.clear();
      return null;
    }
    AppProfile? due;
    for (final profile in timers) {
      final last = _lastActions.putIfAbsent(profile.id, () => now);
      if (due == null &&
          now.difference(last).inMinutes >= profile.intervalMinutes)
        due = profile;
    }
    if (due != null) _lastActions[due.id] = now;
    return due;
  }
}
