// TvChartWidget — TradingView Lightweight Charts embedded via WebView.
//
// Renders an inline HTML page that loads the lightweight-charts CDN library,
// feeds candle data from Flutter, and matches the app's dark theme.
//
// Usage:
//   TvChartWidget(
//     candles: _candles,
//     chartType: TvChartType.candlestick,
//     height: 320,
//   )

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../models/candle.dart';

enum TvChartType { candlestick, line, area }

class TvChartWidget extends StatefulWidget {
  final List<Candle> candles;
  final TvChartType chartType;
  final double height;
  /// Timeframe string (e.g. '1m','5m','15m','1h','1D').
  /// Used to pick a sensible initial visible-bar count so short-interval
  /// candles are not squashed to hairlines by fitContent().
  final String? timeframe;

  const TvChartWidget({
    super.key,
    required this.candles,
    this.chartType = TvChartType.candlestick,
    this.height = 320,
    this.timeframe,
  });

  @override
  State<TvChartWidget> createState() => _TvChartWidgetState();
}

class _TvChartWidgetState extends State<TvChartWidget> {
  late final WebViewController _controller;
  bool _ready = false;

  // ─── App colour constants (mirror theme) ─────────────────────────────────
  static const _bg         = '#0D131A';
  static const _bgGrid     = '#111925';
  static const _bull       = '#26A69A';
  static const _bear       = '#EF5350';
  static const _textColor  = '#8A95A3';
  static const _lineColor  = '#12A28C';

  // ─── TradingView Lightweight Charts CDN (v4 — stable) ────────────────────
  static const _cdnUrl =
      'https://unpkg.com/lightweight-charts@4.2.0/dist/lightweight-charts.standalone.production.js';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0D131A))
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (_) {}, // reserved for future crosshair callbacks
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          _ready = true;
          _pushData();
        },
      ))
      ..loadHtmlString(_buildHtml());
  }

  @override
  void didUpdateWidget(TvChartWidget old) {
    super.didUpdateWidget(old);
    final candlesChanged = widget.candles.length != old.candles.length ||
        (widget.candles.isNotEmpty &&
            old.candles.isNotEmpty &&
            widget.candles.last.time != old.candles.last.time);
    if (candlesChanged || widget.chartType != old.chartType) {
      if (_ready) _pushData();
    }
  }

  // Build the static HTML shell. Chart data is pushed later via JS.
  String _buildHtml() => '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html, body { background:$_bg; width:100%; height:100%; overflow:hidden; }
  #chart { width:100%; height:100%; }
  #loading { position:absolute; top:50%; left:50%; transform:translate(-50%,-50%);
             color:$_textColor; font-family:sans-serif; font-size:13px; }
</style>
</head>
<body>
<div id="chart"></div>
<div id="loading">Loading chart…</div>
<script src="$_cdnUrl"></script>
<script>
var chart, series;

function initChart(type, data, visibleBars) {
  var loader = document.getElementById('loading');
  if (loader) loader.remove();

  if (chart) { chart.remove(); chart = null; series = null; }

  chart = LightweightCharts.createChart(document.getElementById('chart'), {
    width: window.innerWidth,
    height: window.innerHeight,
    layout: {
      background: { type: 'solid', color: '$_bg' },
      textColor: '$_textColor',
      fontSize: 11,
    },
    grid: {
      vertLines: { color: '$_bgGrid' },
      horzLines: { color: '$_bgGrid' },
    },
    crosshair: {
      mode: LightweightCharts.CrosshairMode.Normal,
    },
    rightPriceScale: {
      borderColor: '$_bgGrid',
    },
    timeScale: {
      borderColor: '$_bgGrid',
      timeVisible: true,
      secondsVisible: false,
    },
    handleScroll: true,
    handleScale: true,
  });

  if (type === 'candlestick') {
    series = chart.addCandlestickSeries({
      upColor: '$_bull',
      downColor: '$_bear',
      borderUpColor: '$_bull',
      borderDownColor: '$_bear',
      wickUpColor: '$_bull',
      wickDownColor: '$_bear',
    });
  } else if (type === 'area') {
    series = chart.addAreaSeries({
      lineColor: '$_lineColor',
      topColor: '$_lineColor' + '55',
      bottomColor: '$_lineColor' + '00',
      lineWidth: 2,
    });
  } else {
    series = chart.addLineSeries({
      color: '$_lineColor',
      lineWidth: 2,
    });
  }

  if (data && data.length > 0) {
    series.setData(data);
    if (visibleBars > 0 && data.length > visibleBars) {
      chart.timeScale().setVisibleLogicalRange({
        from: data.length - visibleBars,
        to: data.length - 1
      });
    } else {
      chart.timeScale().fitContent();
    }
  }

  window.addEventListener('resize', function() {
    chart.applyOptions({ width: window.innerWidth, height: window.innerHeight });
  });
}

function updateData(type, dataJson, visibleBars) {
  var data = JSON.parse(dataJson);
  initChart(type, data, visibleBars || 0);
}
</script>
</body>
</html>
''';

  // How many bars to show on initial render for short-interval timeframes.
  // Returns 0 to fall back to fitContent() for daily+ charts.
  int _visibleBars() {
    switch (widget.timeframe) {
      case '1m':  return 60;
      case '5m':  return 50;
      case '15m': return 40;
      case '30m': return 60;
      case '1h':  return 72;
      case '2h':  return 60;
      case '4h':  return 60;
      default:    return 0;
    }
  }

  // Serialise candles and call JS updateData().
  void _pushData() {
    if (widget.candles.isEmpty) return;

    final type = switch (widget.chartType) {
      TvChartType.candlestick => 'candlestick',
      TvChartType.area        => 'area',
      TvChartType.line        => 'line',
    };

    final List<Map<String, dynamic>> points;
    if (widget.chartType == TvChartType.candlestick) {
      points = widget.candles.map((c) => {
        'time': c.time.millisecondsSinceEpoch ~/ 1000,
        'open': c.open,
        'high': c.high,
        'low': c.low,
        'close': c.close,
      }).toList();
    } else {
      points = widget.candles.map((c) => {
        'time': c.time.millisecondsSinceEpoch ~/ 1000,
        'value': c.close,
      }).toList();
    }

    // De-duplicate by time (TV lib rejects duplicate timestamps).
    final seen = <int>{};
    final deduped = points.where((p) => seen.add(p['time'] as int)).toList();

    final json = jsonEncode(deduped);
    final bars = _visibleBars();
    _controller.runJavaScript('updateData("$type", ${jsonEncode(json)}, $bars)');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: WebViewWidget(
        controller: _controller,
        // Allow the chart's own pan/pinch gestures to win over the outer scroll.
        gestureRecognizers: {
          Factory<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer()),
          Factory<HorizontalDragGestureRecognizer>(
              () => HorizontalDragGestureRecognizer()),
          Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
        },
      ),
    );
  }
}
