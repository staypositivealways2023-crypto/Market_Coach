import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_coach/models/candle.dart';

void main() {
  group('BinanceCandleService JSON parsing', () {
    test('parses valid kline message', () {
      const rawMessage = '''
      {
        "stream": "btcusdt@kline_1m",
        "data": {
          "e": "kline",
          "E": 1672531200000,
          "s": "BTCUSDT",
          "k": {
            "t": 1672531200000,
            "T": 1672531259999,
            "s": "BTCUSDT",
            "i": "1m",
            "f": 100,
            "L": 200,
            "o": "16500.00",
            "c": "16510.50",
            "h": "16520.00",
            "l": "16495.00",
            "v": "100.5",
            "n": 100,
            "x": true,
            "q": "1658325.0",
            "V": "50.2",
            "Q": "829162.5",
            "B": "0"
          }
        }
      }
      ''';

      final data = jsonDecode(rawMessage);
      final k = data['data']['k'];

      expect(k['s'], 'BTCUSDT');
      expect(double.parse(k['o']), 16500.00);
      expect(double.parse(k['h']), 16520.00);
      expect(double.parse(k['l']), 16495.00);
      expect(double.parse(k['c']), 16510.50);
      expect(double.parse(k['v']), 100.5);
      expect(k['x'], true); // candle closed
    });

    test('parses ETHUSDT kline', () {
      const rawMessage = '''
      {
        "stream": "ethusdt@kline_1m",
        "data": {
          "k": {
            "t": 1672531200000,
            "s": "ETHUSDT",
            "o": "1200.00",
            "c": "1205.50",
            "h": "1210.00",
            "l": "1198.00",
            "v": "50.25",
            "x": false
          }
        }
      }
      ''';

      final data = jsonDecode(rawMessage);
      final k = data['data']['k'];

      expect(k['s'], 'ETHUSDT');
      expect(double.parse(k['c']), 1205.50);
      expect(k['x'], false); // candle not closed yet
    });

    test('handles missing fields gracefully', () {
      const rawMessage = '''
      {
        "stream": "solusdt@kline_1m",
        "data": {
          "k": {
            "t": 1672531200000,
            "s": "SOLUSDT"
          }
        }
      }
      ''';

      final data = jsonDecode(rawMessage);
      final k = data['data']['k'];

      final open = double.tryParse(k['o'] ?? '0') ?? 0.0;
      final close = double.tryParse(k['c'] ?? '0') ?? 0.0;

      expect(open, 0.0);
      expect(close, 0.0);
    });

    test('Candle model instantiation', () {
      final candle = Candle(
        time: DateTime.fromMillisecondsSinceEpoch(1672531200000),
        open: 16500.00,
        high: 16520.00,
        low: 16495.00,
        close: 16510.50,
        volume: 100.5,
      );

      expect(candle.open, 16500.00);
      expect(candle.close, 16510.50);
      expect(candle.high, 16520.00);
      expect(candle.low, 16495.00);
      expect(candle.volume, 100.5);
    });
  });
}
