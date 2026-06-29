// Measures end-to-end typing latency by pairing keystrokes with the repaints
// they produce.
//
// The editor records a keystroke's start time (T0) when an input callback
// fires, then asks this tracker to pair that keystroke with the next document
// repaint, recording the elapsed time (T1 - T0) once the frame has painted.
// The tracker owns the pending-keystroke queue and the pairing rule; it knows
// nothing about EditorController. It reports results through two callbacks
// supplied at construction:
//   - onSample(operation, milliseconds, exact): a measured latency sample
//   - onDropped(): a keystroke whose latency could not be attributed
//
// The tracker schedules its own post-frame callback (via WidgetsBinding) so
// the T1 timestamp is taken after the repaint has painted.

import 'package:flutter/widgets.dart';

/// A keystroke awaiting a paired repaint for typing-latency measurement.
class _PendingKeystroke {
  /// The input kind ("insert", "delete", "newline").
  final String operation;

  /// When the input callback fired (T0).
  final DateTime startedAt;

  const _PendingKeystroke({required this.operation, required this.startedAt});
}

/// Owns the pending-keystroke queue and pairs keystrokes with repaints to
/// measure end-to-end typing latency.
///
/// Construct one per editor and call [recordKeystroke] when an input callback
/// fires, then [pairWithRepaint] on each state-driven repaint. Results are
/// delivered through the [onSample] and [onDropped] callbacks.
class TypingLatencyTracker {
  /// Called with a measured latency sample: the input kind, the elapsed
  /// milliseconds, and whether the measurement came from an exact correlation
  /// token (always false under the current in-order approximation).
  final void Function(
    String operation,
    double milliseconds, {
    required bool exact,
  })
  onSample;

  /// Called when a keystroke's latency could not be measured because the
  /// in-order approximation was ambiguous.
  final void Function() onDropped;

  TypingLatencyTracker({required this.onSample, required this.onDropped});

  /// Queue of pending keystroke timestamps awaiting a paired repaint.
  ///
  /// Pairing is an in-order approximation: the engine does not yet echo a
  /// correlation token on the stateChanged event a keystroke produces, so the
  /// oldest pending keystroke is matched to the next repaint. This is accurate
  /// during ordinary typing (one key, one update, one frame) and deliberately
  /// drops samples when it cannot attribute a repaint confidently, rather than
  /// reporting a fabricated pairing.
  ///
  /// SEAM: when the engine later includes a causedBy token on stateChanged,
  /// replace the in-order pop in [pairWithRepaint] with a lookup of the
  /// pending entry whose command id matches the token, and report the sample
  /// with exact: true. The queue and timestamps stay; only the pairing rule
  /// changes.
  final List<_PendingKeystroke> _pendingKeystrokes = [];

  /// Record the start time (T0) of a keystroke awaiting its repaint.
  ///
  /// [operation] is the input kind ("insert", "delete", "newline").
  void recordKeystroke(String operation) {
    _pendingKeystrokes.add(
      _PendingKeystroke(operation: operation, startedAt: DateTime.now()),
    );
  }

  /// Pair the oldest pending keystroke with the repaint produced by the
  /// state update currently being processed, recording an end-to-end typing
  /// latency sample once the frame has painted.
  ///
  /// If exactly one keystroke is pending, this repaint is confidently its
  /// result and the sample is recorded. If more than one is pending, the
  /// mapping is ambiguous (fast typing, batched updates, or a non-keystroke
  /// state change interleaved), so the oldest is dropped as unmeasurable
  /// rather than guessed.
  void pairWithRepaint() {
    if (_pendingKeystrokes.isEmpty) return;

    if (_pendingKeystrokes.length > 1) {
      _pendingKeystrokes.removeAt(0);
      onDropped();
      return;
    }

    final pending = _pendingKeystrokes.removeAt(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ms =
          DateTime.now().difference(pending.startedAt).inMicroseconds / 1000.0;
      onSample(pending.operation, ms, exact: false);
    });
  }
}
