extension DurationFormatting on Duration {
  String get mmss {
    final m = inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Duración larga para resúmenes de biblioteca: «3 h 24 min» o «47 min».
  String get hoursMinutes {
    if (inHours > 0) return '$inHours h ${inMinutes.remainder(60)} min';
    return '$inMinutes min';
  }
}
