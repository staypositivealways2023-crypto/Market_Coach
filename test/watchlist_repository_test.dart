import 'package:flutter_test/flutter_test.dart';
import 'package:market_coach/data/watchlist_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('WatchlistRepository', () {
    late WatchlistRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repository = WatchlistRepository(prefs);
    });

    test('getWatchlist returns empty set initially', () async {
      final watchlist = await repository.getWatchlist();
      expect(watchlist, isEmpty);
    });

    test('addSymbol adds symbol to watchlist', () async {
      await repository.addSymbol('AAPL');
      final watchlist = await repository.getWatchlist();
      expect(watchlist, contains('AAPL'));
      expect(watchlist.length, 1);
    });

    test('addSymbol handles duplicates correctly', () async {
      await repository.addSymbol('AAPL');
      await repository.addSymbol('AAPL');
      final watchlist = await repository.getWatchlist();
      expect(watchlist.length, 1);
    });

    test('removeSymbol removes symbol from watchlist', () async {
      await repository.addSymbol('AAPL');
      await repository.addSymbol('BTC');
      await repository.removeSymbol('AAPL');
      final watchlist = await repository.getWatchlist();
      expect(watchlist, isNot(contains('AAPL')));
      expect(watchlist, contains('BTC'));
    });

    test('multiple operations work correctly', () async {
      await repository.addSymbol('AAPL');
      await repository.addSymbol('BHP');
      await repository.addSymbol('BTC');
      var watchlist = await repository.getWatchlist();
      expect(watchlist.length, 3);

      await repository.removeSymbol('BHP');
      watchlist = await repository.getWatchlist();
      expect(watchlist.length, 2);
      expect(watchlist, containsAll(['AAPL', 'BTC']));
    });
  });
}
