import 'dart:async';

/// Temporizador reutilizable que deja detener la sesión tras una pausa.
class IdleStopTimer {
  IdleStopTimer(this.onExpire);

  final void Function() onExpire;
  Timer? _timer;

  void schedule(Duration duration) {
    cancel();
    _timer = Timer(duration, onExpire);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}
