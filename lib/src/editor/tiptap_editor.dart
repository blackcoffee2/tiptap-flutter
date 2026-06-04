// The core editor content widget that renders the document, handles gestures,
// paints selections, and manages keyboard input.
//
// This widget is the Flutter equivalent of Tiptap React's <EditorContent />.
// It is a composable building block — it does NOT include a toolbar, scaffold,
// app bar, or debug overlay. Developers compose those separately:
//
//   Column(
//     children: [
//       TiptapToolbar(controller: controller),
//       Expanded(child: TiptapEditor(controller: controller)),
//     ],
//   )
//
// The widget manages the position registry for tap-to-cursor, the selection
// overlay for cursor/highlight painting, and the text input handler for
// keyboard input. It also places the invisible WebView in the widget tree
// (required by webview_flutter for the controller to function).
//
// Two pieces of input-side logic live in their own files and are owned by this
// widget rather than implemented inline:
//   - block_text_extractor.dart: the pure document-tree walk that produces the
//     text and cursor offset for the block under the cursor (carries the +1
//     serializer compensation). Called from the syncState path.
//   - typing_latency_tracker.dart: the keystroke-to-repaint pairing that
//     measures end-to-end typing latency. The widget records a keystroke on
//     each input callback and asks the tracker to pair it on each repaint.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/protocol_types.dart';
import '../engine/tiptap_bridge.dart';
import 'editor_controller.dart';
import 'input/block_text_extractor.dart';
import 'input/text_input_handler.dart';
import 'input/typing_latency_tracker.dart';
import 'rendering/document_renderer.dart';
import 'selection/position_registry.dart';
import 'selection/selection_painter.dart';

/// The core editor content area that renders the document, handles gestures,
/// paints selections, and manages keyboard input.
///
/// Requires an [EditorController] that has been (or is being) initialized.
/// The widget handles all state transitions gracefully, showing appropriate
/// loading and error states.
///
/// This widget does not include a toolbar, scaffold, or debug overlay.
/// Compose those separately using [TiptapToolbar] and [PerformanceOverlay].
class TiptapEditor extends StatefulWidget {
  /// The editor controller that manages the bridge and editor state.
  final EditorController controller;

  /// Padding around the document content area.
  final EdgeInsets padding;

  /// Builder for a custom loading indicator. If null, a default
  /// [CircularProgressIndicator] is shown while the engine initializes.
  final WidgetBuilder? loadingBuilder;

  /// Builder for a custom error display. If null, a default error message
  /// with an icon is shown when the engine encounters an error.
  /// The builder receives the error message string.
  final Widget Function(BuildContext context, String? errorMessage)?
  errorBuilder;

  const TiptapEditor({
    super.key,
    required this.controller,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    this.loadingBuilder,
    this.errorBuilder,
  });

  @override
  State<TiptapEditor> createState() => _TiptapEditorState();
}

class _TiptapEditorState extends State<TiptapEditor> {
  /// Subscriptions to controller streams, cancelled on dispose.
  final List<StreamSubscription> _subscriptions = [];

  /// Current engine state for determining what to render.
  EngineState _engineState = EngineState.uninitialized;

  /// Latest editor state for rendering the document.
  EditorStatePayload? _editorState;

  /// The position registry shared between the document renderer and the
  /// selection overlay. Populated on each document render, consumed by the
  /// selection painter for cursor/highlight positioning.
  final PositionRegistry _positionRegistry = PositionRegistry();

  /// Whether the editor currently has logical focus for cursor blinking
  /// and keyboard input.
  bool _hasFocus = false;

  /// The text input handler that manages the platform keyboard connection
  /// using the delta-based input model.
  late final TextInputHandler _inputHandler;

  /// Tracks end-to-end typing latency by pairing each keystroke with the
  /// repaint it produces. The widget records a keystroke on every input
  /// callback and asks the tracker to pair it on every state-driven repaint;
  /// the tracker forwards measured and dropped samples to the controller.
  late final TypingLatencyTracker _latencyTracker;

  /// Focus node for managing keyboard focus within Flutter's focus system.
  final FocusNode _focusNode = FocusNode();

  /// Flag indicating that a sync of the platform's editing state is needed.
  /// Set to true when the user taps to place the cursor, so that
  /// the next stateChanged event from the engine triggers a syncState call.
  /// This prevents syncState from firing after every keystroke, which would
  /// disrupt the platform's input state and cause off-by-one insertion bugs.
  ///
  /// The key insight: syncState (which calls setEditingState on the platform)
  /// should only happen when the cursor moved due to a user gesture (tap)
  /// or a non-typing engine action — never as a side-effect of typing. During
  /// typing, the platform tracks its own cursor position via deltas, and the
  /// engine tracks its own via the insertText command. Calling setEditingState
  /// between keystrokes resets the platform's internal state and causes the
  /// next delta to reference stale offsets.
  bool _syncNeeded = false;

  /// Flag set to true when the delta-based input handler processes a deletion
  /// or newline in the current frame. The hardware key event handler checks
  /// this flag to avoid double-processing the same keystroke. Reset at the
  /// end of each frame via a post-frame callback.
  bool _deltaHandledBackspace = false;
  bool _deltaHandledEnter = false;

  @override
  void initState() {
    super.initState();

    _inputHandler = TextInputHandler(
      onInsertText: _handleInsertText,
      onDelete: _handleDelete,
      onNewline: _handleNewline,
    );

    /// Construct the typing-latency tracker, wiring its sample and dropped
    /// callbacks to the controller's metric-recording methods. The tracker
    /// owns the pending-keystroke queue and the pairing rule; it schedules
    /// its own post-frame callback for the T1 timestamp, so nothing about it
    /// needs teardown in dispose().
    _latencyTracker = TypingLatencyTracker(
      onSample: (operation, ms, {required exact}) {
        widget.controller.recordTypingSample(operation, ms, exact: exact);
      },
      onDropped: () {
        widget.controller.recordDroppedTypingSample();
      },
    );

    _focusNode.addListener(_onFocusChanged);

    _subscribe();
  }

  @override
  void didUpdateWidget(TiptapEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _unsubscribe();
      _subscribe();
    }
  }

  void _subscribe() {
    /// Sync cached state from the controller in case it was initialized
    /// before this widget was built.
    _engineState = widget.controller.engineState;
    _editorState = widget.controller.editorState;

    _subscriptions.add(
      widget.controller.engineStateStream.listen((state) {
        setState(() {
          _engineState = state;
        });
      }),
    );

    _subscriptions.add(
      widget.controller.editorStateStream.listen((state) {
        setState(() {
          _editorState = state;
        });

        /// Pair this state-driven repaint with the oldest pending keystroke
        /// to measure end-to-end typing latency. The tracker schedules the
        /// post-frame callback so T1 is taken after the rebuild this state
        /// produced has actually painted.
        _latencyTracker.pairWithRepaint();

        /// Only sync the platform's text input state when a tap
        /// gesture initiated the cursor move. During typing, the platform
        /// and engine each track the cursor independently — calling
        /// setEditingState between keystrokes disrupts the platform's
        /// internal state and causes off-by-one errors and missed backspaces.
        if (_syncNeeded &&
            _hasFocus &&
            _inputHandler.isAttached &&
            state.selection != null) {
          _syncNeeded = false;
          _syncInputState(state);
        }
      }),
    );
  }

  void _unsubscribe() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  @override
  void dispose() {
    _unsubscribe();
    _inputHandler.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Focus management
  // ---------------------------------------------------------------------------

  /// Called when the Flutter focus node's focus state changes.
  void _onFocusChanged() {
    if (!_focusNode.hasFocus && _hasFocus) {
      _blur();
    }
  }

  /// Give focus to the editor: show cursor, attach to keyboard.
  ///
  /// Always detaches and re-attaches the platform input connection on every
  /// focus request. This handles the case where the system dismissed the
  /// keyboard (swipe down, back button) without going through our [_blur]
  /// method — the old connection may be in a stale state where
  /// [_connection.show()] no longer brings up the keyboard. Creating a
  /// fresh connection on every tap is cheap and guarantees the keyboard
  /// appears reliably.
  void _gainFocus() {
    if (!_hasFocus) {
      setState(() {
        _hasFocus = true;
      });
    }

    _focusNode.requestFocus();

    /// Force a fresh connection to the platform input system. Detach first
    /// to close any stale connection, then attach to create a new one and
    /// show the keyboard.
    _inputHandler.detach();
    _inputHandler.attach();
  }

  /// Remove focus from the editor: hide cursor, detach from keyboard.
  void _blur() {
    if (!_hasFocus) return;

    setState(() {
      _hasFocus = false;
    });

    _inputHandler.detach();
  }

  // ---------------------------------------------------------------------------
  // Text input callbacks
  // ---------------------------------------------------------------------------

  /// Called when the user types text on the keyboard. With the delta-based
  /// input model, this receives the exact inserted text from the platform
  /// without any diffing or echo detection.
  void _handleInsertText(String text) {
    if (_engineState != EngineState.ready) return;

    /// Record the keystroke start time (T0) for typing-latency measurement.
    _latencyTracker.recordKeystroke('insert');

    widget.controller.insertText(text);
  }

  /// Called when the user presses backspace. [count] is the number of
  /// characters deleted, derived from the deletion delta's range length.
  /// For single-character backspace, count is 1. For word-delete or
  /// selection-delete, count may be larger. Each deletion is sent as a
  /// separate backspace command to the engine, which runs the full
  /// ProseMirror backspace chain (handling structural operations like
  /// joining blocks and lifting list items).
  void _handleDelete(int count) {
    if (_engineState != EngineState.ready) return;

    /// Record the keystroke start time (T0) for typing-latency measurement.
    _latencyTracker.recordKeystroke('delete');

    /// Mark that the delta handler processed a backspace this frame,
    /// so the hardware key event handler won't double-process it.
    _markDeltaHandledBackspace();

    Future<void> deleteSequence() async {
      for (var i = 0; i < count; i++) {
        await widget.controller.backspace();
      }
    }

    deleteSequence();
  }

  /// Called when the user presses Enter. With the delta-based model, this
  /// can arrive either as a newline insertion delta or as a
  /// performAction(TextInputAction.newline) — the handler normalizes both
  /// paths into this single callback.
  void _handleNewline() {
    if (_engineState != EngineState.ready) return;

    /// Record the keystroke start time (T0) for typing-latency measurement.
    _latencyTracker.recordKeystroke('newline');

    /// Mark that the delta handler processed an enter this frame,
    /// so the hardware key event handler won't double-process it.
    _markDeltaHandledEnter();

    widget.controller.enter();
  }

  /// Set the backspace-handled flag and schedule a reset at the end of
  /// the current frame. This prevents the hardware key event handler from
  /// sending a duplicate backspace command for the same keystroke.
  void _markDeltaHandledBackspace() {
    _deltaHandledBackspace = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deltaHandledBackspace = false;
    });
  }

  /// Set the enter-handled flag and schedule a reset at the end of
  /// the current frame.
  void _markDeltaHandledEnter() {
    _deltaHandledEnter = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deltaHandledEnter = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Hardware keyboard fallback
  // ---------------------------------------------------------------------------

  /// Handle hardware key events as a fallback for backspace and enter.
  ///
  /// Some platforms and soft keyboards don't produce a deletion delta for
  /// backspace (e.g., when the platform buffer is empty at cursor position 0)
  /// or send Enter as a key event rather than a newline delta. This handler
  /// catches those cases.
  ///
  /// The delta-handled flags prevent double-processing when both a delta and
  /// a key event arrive for the same keystroke.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_engineState != EngineState.ready) return KeyEventResult.ignored;

    /// Only handle key-down and repeat events to avoid processing the same
    /// key twice (once on down, once on up).
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (!_deltaHandledBackspace) {
        widget.controller.backspace().catchError((e) {});
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (!_deltaHandledEnter) {
        widget.controller.enter().catchError((e) {});
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Platform input state sync
  // ---------------------------------------------------------------------------

  /// Sync the platform's text input state with the engine's current state.
  ///
  /// Extracts the text of the block containing the cursor and maps the
  /// ProseMirror cursor position to a local offset within that block text.
  /// The platform then knows the real text around the cursor for word
  /// boundaries, autocorrect context, and deletion behavior.
  ///
  /// IMPORTANT: This is only called after tap gestures, never after
  /// typing. During typing, the platform tracks its own cursor via deltas
  /// and calling setEditingState would disrupt it.
  void _syncInputState(EditorStatePayload state) {
    if (state.doc == null || state.selection == null) return;

    final cursorPos = state.selection!.from;
    final result = extractBlockText(state.doc!, cursorPos);
    if (result != null) {
      _inputHandler.syncState(result.text, result.cursorOffset);
    }
  }

  // ---------------------------------------------------------------------------
  // Gesture handling
  // ---------------------------------------------------------------------------

  /// Handle a single tap on the document area. Converts the tap position
  /// to a ProseMirror document position and places a collapsed cursor.
  void _onTapUp(TapUpDetails details) {
    if (_engineState != EngineState.ready) return;

    _gainFocus();

    /// Use a post-frame callback to ensure the position registry has been
    /// populated by the current frame's layout pass before we query it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final docPos = _positionRegistry.positionFromGlobalOffset(
        details.globalPosition,
      );

      if (docPos != null) {
        /// Empty blocks (e.g., an empty paragraph created by pressing Enter
        /// twice) use a zero-width space for rendering, which causes
        /// localOffsetToPos to compute a position between the block's opening
        /// and closing tokens (e.g., 148 for a block at pos:147, end:149).
        /// ProseMirror does not recognize that position as inside the
        /// paragraph's content — it reports activeNodes:[] and insertText
        /// at that position creates a new paragraph instead of filling the
        /// empty one. The correct cursor position for an empty block is
        /// the block's own pos value, which ProseMirror resolves as the
        /// content start of that paragraph. We detect empty blocks by
        /// finding a registered block near the computed position that has
        /// exactly one span mapping with zero length.
        final tappedBlock = _positionRegistry.blocks.where(
          (b) =>
              docPos >= b.pos - 1 &&
              docPos <= b.end + 1 &&
              b.spanMappings.length == 1 &&
              b.spanMappings.first.length == 0,
        );

        int positionToSend = docPos;
        if (tappedBlock.isNotEmpty) {
          positionToSend = tappedBlock.first.pos;
        }

        /// Mark that the next stateChanged event should trigger a sync
        /// of the platform's editing state. This tells the platform what
        /// text surrounds the new cursor position so it can handle
        /// backspace, word boundaries, and autocorrect correctly.
        _syncNeeded = true;
        widget.controller.setTextSelection(positionToSend);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        /// The invisible WebView — must be in the widget tree for the
        /// webview_flutter controller to function. Wrapped in a zero-height
        /// Offstage so it takes no space in the layout.
        Offstage(
          offstage: true,
          child: SizedBox(
            width: 1,
            height: 1,
            child: widget.controller.webViewWidget,
          ),
        ),

        /// The editor content area with gesture detection and selection overlay.
        Expanded(
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: _handleKeyEvent,
            child: _buildContent(),
          ),
        ),
      ],
    );
  }

  /// Build the main content area based on the current engine state.
  Widget _buildContent() {
    if (_engineState == EngineState.error) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, widget.controller.errorMessage);
      }
      return _buildDefaultError();
    }

    if (_engineState != EngineState.ready || _editorState?.doc == null) {
      if (widget.loadingBuilder != null) {
        return widget.loadingBuilder!(context);
      }
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onTapUp: _onTapUp,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          /// The rendered document.
          SingleChildScrollView(
            padding: widget.padding,
            child: DocumentRenderer(
              doc: _editorState!.doc!,
              positionRegistry: _positionRegistry,
            ),
          ),

          /// The selection overlay (cursor and highlight painting).
          Positioned.fill(
            child: IgnorePointer(
              child: EditorSelectionOverlay(
                selection: _editorState!.selection,
                registry: _positionRegistry,
                hasFocus: _hasFocus,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Default error display when no custom [errorBuilder] is provided.
  Widget _buildDefaultError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Engine Error',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.controller.errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
