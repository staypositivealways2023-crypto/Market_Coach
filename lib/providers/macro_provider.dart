import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market_detail.dart';
import '../services/backend_service.dart';

final _backend = BackendService();

/// All key macro indicators in one call (fed funds, CPI, yield curve, etc.)
final macroOverviewProvider = FutureProvider<MacroOverview?>(
  (ref) async {
    return _backend.getMacroOverview();
  },
);

/// Earnings data for a specific ticker
final earningsProvider = FutureProvider.family<Map<String, dynamic>?, String>(
  (ref, symbol) async {
    return _backend.getEarnings(symbol);
  },
);
