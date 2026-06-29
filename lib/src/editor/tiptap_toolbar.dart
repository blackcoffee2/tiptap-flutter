// Standalone formatting toolbar for the Tiptap editor.
//
// This widget listens to the [EditorController]'s state stream and rebuilds
// automatically when command states or active marks change. It can be placed
// anywhere in the widget tree — above, below, or beside the [TiptapEditor].
//
// The toolbar is entirely data-driven — it reads [CommandState] values
// from the engine's stateChanged event and doesn't hardcode any assumptions
// about which commands exist.
//
// For custom toolbars, use the controller's [editorStateStream],
// [activeMarks], [canCommandExec], and [isCommandActive] directly.

import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/protocol_constants.dart';
import '../engine/protocol_types.dart';
import '../engine/tiptap_bridge.dart';
import 'editor_controller.dart';
import 'rendering/node_types.dart';

/// The result of an image pick operation, returned by the [TiptapToolbar]'s
/// [onPickImage] callback.
///
/// Only [src] is required — it can be a remote URL, a base64 data URI,
/// or any string the engine's image node accepts as a src attribute.
/// [alt] and [title] are optional metadata passed through to the engine.
class ImageInsertResult {
  /// The image source — a URL, data URI, or any valid src string.
  final String src;

  /// Optional alt text describing the image for accessibility.
  final String alt;

  /// Optional title displayed as a caption below the image.
  final String title;

  const ImageInsertResult({required this.src, this.alt = '', this.title = ''});
}

/// A standalone formatting toolbar for the Tiptap editor.
///
/// Listens to the [EditorController]'s state stream and rebuilds when
/// command states change. Place it anywhere relative to the [TiptapEditor].
///
/// Wrapping this widget in a [Focus] with `canRequestFocus: false` prevents
/// toolbar taps from stealing focus away from the editor and dismissing
/// the keyboard.
class TiptapToolbar extends StatefulWidget {
  /// The editor controller to send commands to and receive state from.
  final EditorController controller;

  /// Optional callback invoked when the user taps the image insert button.
  ///
  /// The callback is responsible for the entire image acquisition flow —
  /// picking a file, uploading it, converting to base64, or whatever the
  /// developer's app requires. It returns an [ImageInsertResult] containing
  /// the src string (and optional alt/title), or null to cancel the insert.
  ///
  /// This keeps the library free of image picker or upload dependencies.
  /// The developer adds those to their own app and wires them up here.
  ///
  /// If null, the image insert button is not shown in the toolbar.
  final Future<ImageInsertResult?> Function()? onPickImage;

  const TiptapToolbar({super.key, required this.controller, this.onPickImage});

  @override
  State<TiptapToolbar> createState() => _TiptapToolbarState();
}

class _TiptapToolbarState extends State<TiptapToolbar> {
  final List<StreamSubscription> _subscriptions = [];

  EngineState _engineState = EngineState.uninitialized;

  EditorStatePayload? _editorState;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(TiptapToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _unsubscribe();
      _subscribe();
    }
  }

  void _subscribe() {
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
    super.dispose();
  }

  /// Handle the image insert button tap. Invokes the developer's callback
  /// directly — no intermediate dialog. If the callback returns a result
  /// with a non-empty src, the image is inserted into the editor.
  Future<void> _handleImageInsert() async {
    final result = await widget.onPickImage!();
    if (result != null && result.src.isNotEmpty) {
      await widget.controller.execCommand(EditorCommand.setImage, {
        NodeAttr.src: result.src,
        if (result.alt.isNotEmpty) NodeAttr.alt: result.alt,
        if (result.title.isNotEmpty) NodeAttr.title: result.title,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_engineState != EngineState.ready || _editorState == null) {
      return const SizedBox.shrink();
    }

    final commandStates = _editorState!.commandStates;
    final activeMarks = _editorState!.activeMarks;

    return Focus(
      /// Prevent toolbar taps from stealing focus from the editor,
      /// which would dismiss the keyboard.
      canRequestFocus: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 1,
            ),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              /// Mark toggle buttons derive their active state from
              /// [activeMarks] rather than commandStates: the engine reports
              /// active marks on every stateChanged, covering both stored
              /// marks (toggled with an empty selection) and marks at the
              /// current cursor position.
              _ToolbarButton(
                icon: Icons.format_bold,
                tooltip: 'Bold',
                commandName: EditorCommand.toggleBold,
                commandStates: commandStates,
                isActiveOverride: activeMarks.contains(MarkType.bold),
                onPressed: () =>
                    widget.controller.execCommand(EditorCommand.toggleBold),
              ),
              _ToolbarButton(
                icon: Icons.format_italic,
                tooltip: 'Italic',
                commandName: EditorCommand.toggleItalic,
                commandStates: commandStates,
                isActiveOverride: activeMarks.contains(MarkType.italic),
                onPressed: () =>
                    widget.controller.execCommand(EditorCommand.toggleItalic),
              ),
              _ToolbarButton(
                icon: Icons.format_strikethrough,
                tooltip: 'Strikethrough',
                commandName: EditorCommand.toggleStrike,
                commandStates: commandStates,
                isActiveOverride: activeMarks.contains(MarkType.strike),
                onPressed: () =>
                    widget.controller.execCommand(EditorCommand.toggleStrike),
              ),
              _ToolbarButton(
                icon: Icons.code,
                tooltip: 'Inline Code',
                commandName: EditorCommand.toggleCode,
                commandStates: commandStates,
                isActiveOverride: activeMarks.contains(MarkType.code),
                onPressed: () =>
                    widget.controller.execCommand(EditorCommand.toggleCode),
              ),

              _ToolbarDivider(),

              _ToolbarButton(
                icon: Icons.title,
                tooltip: 'Heading 1',
                commandName: EditorCommand.toggleHeading,
                commandStates: commandStates,
                isActiveOverride: _isHeadingActive(1),
                alwaysEnabled: true,
                onPressed: () => widget.controller.execCommand(
                  EditorCommand.toggleHeading,
                  {NodeAttr.level: 1},
                ),
              ),
              _ToolbarButton(
                icon: Icons.text_fields,
                tooltip: 'Heading 2',
                commandName: EditorCommand.toggleHeading,
                commandStates: commandStates,
                isActiveOverride: _isHeadingActive(2),
                alwaysEnabled: true,
                onPressed: () => widget.controller.execCommand(
                  EditorCommand.toggleHeading,
                  {NodeAttr.level: 2},
                ),
              ),
              _ToolbarButton(
                icon: Icons.format_size,
                tooltip: 'Heading 3',
                commandName: EditorCommand.toggleHeading,
                commandStates: commandStates,
                isActiveOverride: _isHeadingActive(3),
                alwaysEnabled: true,
                onPressed: () => widget.controller.execCommand(
                  EditorCommand.toggleHeading,
                  {NodeAttr.level: 3},
                ),
              ),

              _ToolbarDivider(),

              _ToolbarButton(
                icon: Icons.format_list_bulleted,
                tooltip: 'Bullet List',
                commandName: EditorCommand.toggleBulletList,
                commandStates: commandStates,
                alwaysEnabled: true,
                onPressed: () => widget.controller.execCommand(
                  EditorCommand.toggleBulletList,
                ),
              ),
              _ToolbarButton(
                icon: Icons.format_list_numbered,
                tooltip: 'Ordered List',
                commandName: EditorCommand.toggleOrderedList,
                commandStates: commandStates,
                alwaysEnabled: true,
                onPressed: () => widget.controller.execCommand(
                  EditorCommand.toggleOrderedList,
                ),
              ),

              _ToolbarDivider(),

              _ToolbarButton(
                icon: Icons.format_quote,
                tooltip: 'Blockquote',
                commandName: EditorCommand.toggleBlockquote,
                commandStates: commandStates,
                alwaysEnabled: true,
                onPressed: () => widget.controller.execCommand(
                  EditorCommand.toggleBlockquote,
                ),
              ),
              _ToolbarButton(
                icon: Icons.data_object,
                tooltip: 'Code Block',
                commandName: EditorCommand.toggleCodeBlock,
                commandStates: commandStates,
                alwaysEnabled: true,
                onPressed: () => widget.controller.execCommand(
                  EditorCommand.toggleCodeBlock,
                ),
              ),
              _ToolbarButton(
                icon: Icons.horizontal_rule,
                tooltip: 'Horizontal Rule',
                commandName: EditorCommand.setHorizontalRule,
                commandStates: commandStates,
                onPressed: () => widget.controller.execCommand(
                  EditorCommand.setHorizontalRule,
                ),
              ),

              /// Image insert button — only shown when the developer provides
              /// an [onPickImage] callback.
              if (widget.onPickImage != null) ...[
                _ToolbarDivider(),
                _ToolbarButton(
                  icon: Icons.image_outlined,
                  tooltip: 'Insert Image',
                  commandName: EditorCommand.setImage,
                  commandStates: commandStates,
                  alwaysEnabled: true,
                  onPressed: _handleImageInsert,
                ),
              ],

              _ToolbarDivider(),

              _ToolbarButton(
                icon: Icons.undo,
                tooltip: 'Undo',
                commandName: EditorCommand.undo,
                commandStates: commandStates,
                onPressed: () =>
                    widget.controller.execCommand(EditorCommand.undo),
              ),
              _ToolbarButton(
                icon: Icons.redo,
                tooltip: 'Redo',
                commandName: EditorCommand.redo,
                commandStates: commandStates,
                onPressed: () =>
                    widget.controller.execCommand(EditorCommand.redo),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether a heading of [level] is active. Always returns null: commandStates
  /// don't carry the heading level, so level-specific active state can't be
  /// resolved from them — a known limitation. The activeNodes list (which
  /// carries the level attr) is what a precise check would use.
  bool? _isHeadingActive(int level) {
    return null;
  }
}

/// A single toolbar button.
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String commandName;
  final Map<String, CommandState> commandStates;
  final VoidCallback onPressed;

  /// If true, the button is always enabled regardless of canExec state.
  /// Used for commands whose canExec depends on args the engine doesn't have.
  final bool alwaysEnabled;

  /// Override the active state detection. When null, uses the command state.
  final bool? isActiveOverride;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.commandName,
    required this.commandStates,
    required this.onPressed,
    this.alwaysEnabled = false,
    this.isActiveOverride,
  });

  @override
  Widget build(BuildContext context) {
    final state = commandStates[commandName];
    final isActive = isActiveOverride ?? (state?.isActive ?? false);
    final canExec = alwaysEnabled || (state?.canExec ?? true);

    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isActive ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: canExec ? onPressed : null,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                icon,
                size: 20,
                color: canExec
                    ? (isActive
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant)
                    : colorScheme.onSurface.withAlpha(97),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A visual divider between toolbar button groups.
class _ToolbarDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 24,
        child: VerticalDivider(
          width: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}
