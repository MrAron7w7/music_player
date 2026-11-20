import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Estado de conectividad compartido por todas las decisiones de red.
class ConnectivityGate {
  ConnectivityGate({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      _setConnectivity,
      onError: (_) {},
    );
  }

  final Connectivity _connectivity;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  late final StreamSubscription<List<ConnectivityResult>> _subscription;
  bool? _online;
  bool _wifiOrEthernet = false;

  bool? get isOnline => _online;
  bool get canPrefetch => _wifiOrEthernet;

  Stream<bool> get changes async* {
    final current = _online;
    if (current != null) yield current;
    yield* _changes.stream;
  }

  Future<bool> refresh() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _setConnectivity(results);
      return _online!;
    } catch (_) {
      // Si el plugin falla, deja que la resolución del stream informe el error.
      _setConnectivity(const [ConnectivityResult.other]);
      return true;
    }
  }

  bool _hasNetwork(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  void _setConnectivity(List<ConnectivityResult> results) {
    final online = _hasNetwork(results);
    final wifiOrEthernet =
        results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
    final changed = _online != online;
    _online = online;
    _wifiOrEthernet = wifiOrEthernet;
    if (changed) _changes.add(online);
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _changes.close();
  }
}
