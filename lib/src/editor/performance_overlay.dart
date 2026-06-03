// Performance overlay that shows live timing metrics for the editor as a
// draggable bottom sheet.
//
// This replaces the former debug overlay. Document, selection, and raw-state
// inspection happen through terminal logs (the bridge still logs everything
// to the console); this overlay is dedicated to the information the terminal
// cannot easily show: paired timings and rolling statistics. It reads from
// the bridge's [BridgeMetrics] and rebuilds whenever a new sample lands.
//
// Three panels of information are shown:
//   - Engine load: per-phase cold-start breakdown and total.
//   - Command round-trips: per-command count, last, mean, min, and max.
//   - Typing latency: end-to-end keystroke-to-repaint statistics, labeled as
//     an in-order approximation, with a dropped-sample count.

import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/metrics.dart';
import 'editor_controller.dart';

/// A draggable bottom sheet overlay showing live performance metrics for the
/// editor: engine load phases, command round-trips, and typing latency.
///
/// Named with the Tiptap prefix to avoid colliding with Flutter's own
/// [PerformanceOverlay] widget, which is in scope wherever material.dart is
/// imported.
class TiptapPerformanceOverlay extends StatefulWidget {
  /// The controller whose bridge metrics are displayed.
  final EditorController controller;

  /// Called when the user closes the overlay.
  final VoidCallback onClose;

  const TiptapPerformanceOverlay({
    super.key,
    required this.controller,
    required this.onClose,
  });

  @override
  State<TiptapPerformanceOverlay> createState() =>
      _TiptapPerformanceOverlayState();
}

class _TiptapPerformanceOverlayState extends State<TiptapPerformanceOverlay> {
  /// Subscription to the metrics change stream, used to rebuild on new samples.
  StreamSubscription? _metricsSubscription;

  @override
  void initState() {
    super.initState();

    /// Rebuild whenever a new metric sample is recorded so the displayed
    /// values stay live.
    _metricsSubscription = widget.controller.metricsStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _metricsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.controller.metrics;

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.1,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(51),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              /// Drag handle and close button.
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    const Spacer(),
                    Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),

              /// Title.
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Performance',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              /// Metrics content.
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildLoadSection(metrics),
                    const SizedBox(height: 24),
                    _buildRoundTripSection(metrics),
                    const SizedBox(height: 24),
                    _buildTypingSection(metrics),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Engine load section
  // ---------------------------------------------------------------------------

  /// Build the engine cold-start breakdown: each lifecycle phase and the total.
  Widget _buildLoadSection(BridgeMetrics metrics) {
    final phases = metrics.loadPhases;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Engine load'),
        if (phases.isEmpty)
          _emptyHint('No load data yet.')
        else ...[
          for (final phase in phases)
            _metricRow(phase.name, _ms(phase.milliseconds)),
          const Divider(height: 16),
          _metricRow(
            'Total cold start',
            metrics.totalLoadMs != null ? _ms(metrics.totalLoadMs!) : '—',
            emphasize: true,
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Command round-trip section
  // ---------------------------------------------------------------------------

  /// Build the per-command round-trip table: count, last, mean, min, max.
  Widget _buildRoundTripSection(BridgeMetrics metrics) {
    final stats = metrics.commandStats;

    /// Sort command names for stable ordering in the table.
    final names = stats.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Command round-trips'),
        if (names.isEmpty)
          _emptyHint('No commands sent yet.')
        else ...[
          /// Column headers.
          _roundTripHeaderRow(),
          const SizedBox(height: 4),
          for (final name in names) _roundTripRow(name, stats[name]!),
        ],
      ],
    );
  }

  /// Header row for the round-trip table.
  Widget _roundTripHeaderRow() {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Colors.grey,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: const [
          Expanded(flex: 4, child: Text('command', style: headerStyle)),
          Expanded(
            flex: 2,
            child: Text('n', style: headerStyle, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 3,
            child: Text('last', style: headerStyle, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 3,
            child: Text('mean', style: headerStyle, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 3,
            child: Text('min', style: headerStyle, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 3,
            child: Text('max', style: headerStyle, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  /// A single command's round-trip stats row.
  Widget _roundTripRow(String name, RollingStats stats) {
    const cellStyle = TextStyle(fontFamily: 'monospace', fontSize: 12);
    Widget cell(String text, int flex, {bool name = false}) => Expanded(
      flex: flex,
      child: Text(
        text,
        style: cellStyle,
        textAlign: name ? TextAlign.left : TextAlign.right,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          cell(name, 4, name: true),
          cell('${stats.count}', 2),
          cell(_ms(stats.last), 3),
          cell(_ms(stats.mean), 3),
          cell(_ms(stats.displayMin), 3),
          cell(_ms(stats.max), 3),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Typing latency section
  // ---------------------------------------------------------------------------

  /// Build the typing-latency panel with rolling stats and the approximation
  /// caveat.
  Widget _buildTypingSection(BridgeMetrics metrics) {
    final stats = metrics.typingStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Typing latency'),

        /// Honesty note: this is an in-order approximation, not an exact
        /// measurement, until the engine echoes a correlation token.
        _emptyHint(
          'End-to-end keystroke to repaint. Approximate (in-order pairing); '
          'ambiguous samples are dropped, not guessed.',
        ),
        const SizedBox(height: 8),
        if (stats.count == 0)
          _emptyHint('No keystrokes measured yet.')
        else ...[
          _metricRow('Samples', '${stats.count}'),
          _metricRow('Last', _ms(stats.last)),
          _metricRow('Mean', _ms(stats.mean), emphasize: true),
          _metricRow('Min', _ms(stats.displayMin)),
          _metricRow('Max', _ms(stats.max)),
        ],
        _metricRow('Dropped (ambiguous)', '${metrics.droppedTypingSamples}'),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Shared building blocks
  // ---------------------------------------------------------------------------

  /// A section header label.
  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }

  /// A labeled metric row with the value right-aligned.
  Widget _metricRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: emphasize ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  /// A muted hint line for empty states and notes.
  Widget _emptyHint(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
    );
  }

  /// Format a millisecond value for display.
  String _ms(double ms) => '${ms.toStringAsFixed(1)} ms';
}
