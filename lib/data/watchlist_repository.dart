import 'package:shared_preferences/shared_preferences.dart';

class WatchlistRepository {
  static const _key = 'watchlist_symbols';
  final SharedPreferences _prefs;

  WatchlistRepository(this._prefs);

  static Future<WatchlistRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return WatchlistRepository(prefs);
  }

  Future<Set<String>> getWatchlist() async {
    final symbols = _prefs.getStringList(_key) ?? [];
    return symbols.toSet();
  }

  Future<void> addSymbol(String symbol) async {
    final watchlist = await getWatchlist();
    watchlist.add(symbol);
    await _prefs.setStringList(_key, watchlist.toList());
  }

  Future<void> removeSymbol(String symbol) async {
    final watchlist = await getWatchlist();
    watchlist.remove(symbol);
    await _prefs.setStringList(_key, watchlist.toList());
  }
}
