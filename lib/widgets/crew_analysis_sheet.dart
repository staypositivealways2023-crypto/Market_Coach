/// CrewAI Agent Progress Sheet — Phase 9
///
/// Shows a bottom sheet that streams the 4-agent analysis progress via SSE.
/// Each agent "lights up" as it completes, then the final Scenario Card is shown.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:firebase_auth/firebase_auth.dart';

import '../config/api_config.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

enum _AgentStatus { waiting, running, done, error }

class _AgentState {
  final String name;
  final String description;
  final IconData icon;
  _AgentStatus status;

  _AgentState({
    required this.name,
    required this.description,
    required this.icon,
    this.status = _AgentStatus.waiting,
  });
}

// ── Public entry point ────────────────────────────────────────────────────────

/// Shows the CrewAI streaming analysis bottom sheet.
/// Returns the final result map when done, or null if dismissed/errored.
Future<Map<String, dynamic>?> showCrewAnalysisSheet(
  BuildContext context, {
  required String symbol,
  String userLevel = 'intermediate',
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CrewAnalysisSheet(
      symbol: symbol,
      userLevel: userLevel,
    ),
  );
}

// ── Sheet widget ──────────────────────────────────────────────────────────────

class _CrewAnalysisSheet extends StatefulWidget {
  final String symbol;
  final String userLevel;

  const _CrewAnalysisSheet({
    required this.symbol,
    required this.userLevel,
  });

  @override
  State<_CrewAnalysisSheet> createState() => _CrewAnalysisSheetState();
}

class _CrewAnalysisSheetState extends State<_CrewAnalysisSheet> {
  static const _streamTimeout = Duration(seconds: 25);
  static const _stallTimeout = Duration(seconds: 8);

  final List<_AgentState> _agents = [
    _AgentState(
      name: 'MarketDataAgent',
      description: 'Fetching price, indicators & chart patterns…',
      icon: Icons.bar_chart_rounded,
    ),
    _AgentState(
      name: 'SentimentAgent',
      description: 'Reading news & macro context…',
      icon: Icons.newspaper_rounded,
    ),
    _AgentState(
      name: 'TechnicalAgent',
      description: 'Interpreting signals & key levels…',
      icon: Icons.analytics_rounded,
    ),
    _AgentState(
      name: 'CoachAgent',
      description: 'Personalising coaching for you…',
      icon: Icons.school_rounded,
    ),
  ];

  Map<String, dynamic>? _result;
  String? _error;
  String? _notice;
  bool _done = false;

  StreamSubscription<String>? _sub;
  Timer? _streamTimer;
  Timer? _stallTimer;
  http.Client? _client;

  @override
  void initState() {
    super.initState();
    _armStreamTimeout();
    _startStream();
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _stallTimer?.cancel();
    _sub?.cancel();
    _client?.close();
    super.dispose();
  }

  int get _completedAgentCount =>
      _agents.where((agent) => agent.status == _AgentStatus.done).length;

  void _armStreamTimeout() {
    _streamTimer?.cancel();
    _streamTimer = Timer(_streamTimeout, () {
      _finishPartial('Analysis timed out. Showing completed agent results.');
    });
  }

  void _armStallTimeout() {
    _stallTimer?.cancel();
    _stallTimer = Timer(_stallTimeout, () {
      _finishPartial('One agent stalled. Showing completed agent results.');
    });
  }

  Map<String, dynamic> _buildPartialResult() {
    return {
      'partial': true,
      'symbol': widget.symbol.toUpperCase(),
      'completed_agents': _agents
          .where((agent) => agent.status == _AgentStatus.done)
          .map((agent) => agent.name)
          .toList(),
    };
  }

  void _markIncompleteAgentsError() {
    for (final agent in _agents) {
      if (agent.status != _AgentStatus.done) {
        agent.status = _AgentStatus.error;
      }
    }
  }

  void _finishSuccess(Map<String, dynamic> result) {
    if (_done || !mounted) return;

    _streamTimer?.cancel();
    _stallTimer?.cancel();
    _client?.close();

    setState(() {
      _result = result;
      _notice = null;
      _error = null;
      _done = true;
      for (final agent in _agents) {
        agent.status = _AgentStatus.done;
      }
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) Navigator.of(context).pop(_result);
    });
  }

  void _finishPartial(String notice) {
    if (_done || !mounted) return;

    if (_completedAgentCount == 0) {
      _streamTimer?.cancel();
      _stallTimer?.cancel();
      _client?.close();
      setState(() {
        _error = notice;
        _done = true;
      });
      return;
    }

    _streamTimer?.cancel();
    _stallTimer?.cancel();
    _client?.close();

    setState(() {
      _markIncompleteAgentsError();
      _result = _result ?? _buildPartialResult();
      _notice = notice;
      _error = null;
      _done = true;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) Navigator.of(context).pop(_result);
    });
  }

  Future<void> _startStream() async {
    final user  = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    final base  = APIConfig.backendBaseUrl;
    final url = Uri.parse(
      '$base/api/analyse/${widget.symbol.toUpperCase()}/stream'
      '?user_level=${widget.userLevel}',
    );

    final request = http.Request('GET', url);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    try {
      _client = http.Client();
      final response = await _client!.send(request);

      if (response.statusCode != 200) {
        if (mounted) {
          setState(() {
            _error = 'Server returned ${response.statusCode}';
            _done = true;
          });
        }
        _client?.close();
        return;
      }

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      _sub = lines.listen(
        (line) {
          if (!line.startsWith('data: ')) return;
          final raw = line.substring(6).trim();
          if (raw.isEmpty) return;

          try {
            final event = jsonDecode(raw) as Map<String, dynamic>;
            final agentName = event['agent'] as String? ?? '';
            final status    = event['status'] as String? ?? '';
            _armStallTimeout();

            if (agentName == 'done') {
              final res = event['result'] as Map<String, dynamic>? ?? {};
              _finishSuccess(res);
              return;
            }

            if (agentName == 'error') {
              _finishPartial(
                event['error'] as String? ??
                    'Analysis ended early. Showing completed agent results.',
              );
              return;
            }

            // Update individual agent status
            if (mounted) {
              setState(() {
                final idx = _agents.indexWhere((a) => a.name == agentName);
                if (idx >= 0) {
                  if (status == 'running') {
                    // Mark previous agents done
                    for (int i = 0; i < idx; i++) {
                      _agents[i].status = _AgentStatus.done;
                    }
                    _agents[idx].status = _AgentStatus.running;
                  } else if (status == 'done') {
                    _agents[idx].status = _AgentStatus.done;
                  } else if (status == 'error') {
                    _agents[idx].status = _AgentStatus.error;
                  }
                }
              });
            }
          } catch (_) {}
        },
        onError: (e) {
          _finishPartial('Analysis stream failed. Showing completed agent results.');
        },
        onDone: () {
          _finishPartial('Analysis stream ended before all agents finished.');
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _done = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF111925),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Agent Swarm',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${widget.symbol} · Deep analysis',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_done)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF12A28C)),
                  ),
                ),
              if (_done && _error == null)
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF0C9E6A), size: 22),
              if (_done && _error != null)
                const Icon(Icons.error_outline_rounded,
                    color: Color(0xFFCF3B2E), size: 22),
            ],
          ),

          const SizedBox(height: 24),

          // Agent list
          ..._agents.map((agent) => _AgentRow(agent: agent)),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFCF3B2E).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCF3B2E).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Color(0xFFCF3B2E), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFCF3B2E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Dismiss'),
              ),
            ),
          ],

          if (_notice != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB020).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFB020).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: Color(0xFFFFB020), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _notice!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFFFB020),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_done && _error == null) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Analysis complete — updating chart…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF0C9E6A),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Agent Row ─────────────────────────────────────────────────────────────────

class _AgentRow extends StatelessWidget {
  final _AgentState agent;
  const _AgentRow({super.key, required this.agent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color iconBg;
    Widget statusIcon;

    switch (agent.status) {
      case _AgentStatus.waiting:
        iconBg    = Colors.white10;
        statusIcon = Icon(agent.icon, size: 18, color: Colors.white38);
      case _AgentStatus.running:
        iconBg    = const Color(0xFF12A28C).withOpacity(0.15);
        statusIcon = SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: const AlwaysStoppedAnimation(Color(0xFF12A28C)),
          ),
        );
      case _AgentStatus.done:
        iconBg    = const Color(0xFF0C9E6A).withOpacity(0.15);
        statusIcon = const Icon(Icons.check_rounded,
            size: 18, color: Color(0xFF0C9E6A));
      case _AgentStatus.error:
        iconBg    = const Color(0xFFCF3B2E).withOpacity(0.15);
        statusIcon = const Icon(Icons.close_rounded,
            size: 18, color: Color(0xFFCF3B2E));
    }

    final isActive = agent.status == _AgentStatus.running;
    final isDone   = agent.status == _AgentStatus.done;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: statusIcon),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agent.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isActive || isDone ? Colors.white : Colors.white54,
                  ),
                ),
                Text(
                  agent.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isActive
                        ? const Color(0xFF12A28C)
                        : isDone
                            ? Colors.white54
                            : Colors.white24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
