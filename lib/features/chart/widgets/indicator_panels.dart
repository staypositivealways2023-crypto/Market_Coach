import 'package:flutter/material.dart';
import '../controllers/chart_controller.dart';
import '../painters/indicator_painter.dart';

/// Native RSI sub-panel using CustomPainter
class RsiPanel extends StatefulWidget {
  final ChartController controller;
  final List<double?> rsiValues;

  const RsiPanel({
    super.key,
    required this.controller,
    required this.rsiValues,
  });

  @override
  State<RsiPanel> createState() => _RsiPanelState();
}

class _RsiPanelState extends State<RsiPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(RsiPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: 90,
        child: CustomPaint(
          painter: RsiPainter(widget.controller, widget.rsiValues),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Native MACD sub-panel using CustomPainter
class MacdPanel extends StatefulWidget {
  final ChartController controller;
  final List<double?> macdLine;
  final List<double?> signalLine;
  final List<double?> histogram;

  const MacdPanel({
    super.key,
    required this.controller,
    required this.macdLine,
    required this.signalLine,
    required this.histogram,
  });

  @override
  State<MacdPanel> createState() => _MacdPanelState();
}

class _MacdPanelState extends State<MacdPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(MacdPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: 90,
        child: CustomPaint(
          painter: MacdPainter(
            widget.controller,
            widget.macdLine,
            widget.signalLine,
            widget.histogram,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}
