import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Provider for network connectivity status
///
/// Returns true when connected to network, false when offline.
/// Updates in real-time as connectivity changes.
final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
    (result) {
      // connectivity_plus v6+ returns List<ConnectivityResult>
      return !result.contains(ConnectivityResult.none);
    },
  );
});
