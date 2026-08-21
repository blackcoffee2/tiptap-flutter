// Recursive document renderer that walks the [AnnotatedNode] tree and
// produces Flutter widgets for each node.
//
// It dispatches each node to its registered builder in the
// [NodeRendererRegistry], falling back to a debug placeholder for unknown
// node types. Extension developers can add custom builders to the registry
// before the renderer is instantiated, or override the default ones.
//
// Each text-rendering block (paragraph, heading) registers itself with
// the [PositionRegistry] so that taps can be mapped to document positions
// and cursors can be painted at the correct pixel locations.
//
// Theming: the renderer builds RichText directly, which does not inherit
// DefaultTextStyle, so nothing about the document's appearance follows the
// app theme implicitly. The renderer therefore resolves a
// [TiptapEditorThemeData] once per build (Material theme, the
// [TiptapEditorTheme] extension, and the per-editor [theme] override, in
// that precedence) and places it in a [TiptapEditorThemeScope] above the
// node tree. The tree walk itself runs in a private child widget so that the
// context handed to builders is BELOW the scope — a builder reading
// `TiptapEditorThemeData.of(context)` from the renderer's own context would
// not see a scope the renderer itself places, and would silently fall back
// to the Material defaults, dropping the override.
//
// This file is split across three parts that together form the
// `document_renderer` library:
//
//   - This file: the DocumentRenderer widget, theme resolution, node
//     dispatch, the unknown-node placeholder, the default-builder
//     registration, and the shared link-tap handler used by the builders.
//   - node_builders.dart: the block-node builders (paragraph, heading, lists,
//     blockquote, code block, horizontal rule) and the shared
//     _buildRichTextBlock helper and _ListItemWrapper widget.
//   - image_builders.dart: the image node builder and its helpers for network
//     and base64 sources, plus the error placeholder.
//
// The builders are split out via `part` rather than into a standalone class so
// they keep their library privacy: the default builders are an internal
// implementation detail, not public API. Using `part` lets them live in
// separate files while remaining visible to this file's registration code and
// invisible outside the library.

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../engine/protocol_types.dart';
import '../selection/position_registry.dart';
import '../tiptap_editor_theme.dart';
import 'node_renderer_registry.dart';
import 'node_types.dart';
import 'text_span_builder.dart';

part 'node_builders.dart';
part 'image_builders.dart';

/// Widget that renders an entire annotated document tree.
///
/// Takes the root [AnnotatedNode] (always type "doc") and recursively
/// builds the widget tree for all descendants.
///
/// The [positionRegistry] is populated during build with entries for each
/// text-rendering block, enabling tap-to-cursor and cursor painting.
class DocumentRenderer extends StatefulWidget {
  /// The root document node from the engine's stateChanged event.
  final AnnotatedNode doc;

  /// The position registry to populate with block entries.
  /// If null, position tracking is disabled (read-only mode without cursor).
  final PositionRegistry? positionRegistry;

  /// The renderer registry to use. Defaults to the global default registry,
  /// which includes all standard node type builders.
  final NodeRendererRegistry? registry;

  /// Per-renderer theme override, layered over the Material theme and any
  /// [TiptapEditorTheme] registered in ThemeData.extensions. Null means the
  /// document follows the ambient theme entirely.
  final TiptapEditorTheme? theme;

  const DocumentRenderer({
    super.key,
    required this.doc,
    this.positionRegistry,
    this.registry,
    this.theme,
  });

  @override
  State<DocumentRenderer> createState() => _DocumentRendererState();
}

class _DocumentRendererState extends State<DocumentRenderer> {
  @override
  Widget build(BuildContext context) {
    /// Resolving on every build is cheap (a handful of merges), and the
    /// scope's value-equality updateShouldNotify means a resolution that
    /// produces identical values does not invalidate any block's span tree,
    /// so unrelated parent rebuilds keep skipping text layout.
    final themeData = TiptapEditorThemeData.resolve(
      context,
      override: widget.theme,
    );

    return TiptapEditorThemeScope(
      data: themeData,
      child: _DocumentBody(
        doc: widget.doc,
        positionRegistry: widget.positionRegistry,
        registry: widget.registry,
      ),
    );
  }
}

/// The actual tree walk, kept as a separate widget purely so its
/// [BuildContext] sits below the [TiptapEditorThemeScope] placed by
/// [DocumentRenderer]. Every builder receives this widget's context.
class _DocumentBody extends StatelessWidget {
  final AnnotatedNode doc;
  final PositionRegistry? positionRegistry;
  final NodeRendererRegistry? registry;

  const _DocumentBody({
    required this.doc,
    required this.positionRegistry,
    required this.registry,
  });

  @override
  Widget build(BuildContext context) {
    final reg = registry ?? NodeRendererRegistry.defaultRegistry;

    if (!reg.hasBuilder(NodeType.paragraph)) {
      _registerDefaultBuilders(reg);
    }

    /// Clear before rebuilding so stale entries from previous renders don't
    /// persist. This also rewinds the registry's stable block-key ordinal so
    /// the walk below hands the same keys to the same blocks in document
    /// order (see PositionRegistry.takeNextBlockKey).
    positionRegistry?.clear();

    final children = doc.content ?? [];
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final child in children) _buildNode(context, child, reg)],
    );
  }

  /// Build a widget for a single node, dispatching to the registry.
  Widget _buildNode(
    BuildContext context,
    AnnotatedNode node,
    NodeRendererRegistry reg,
  ) {
    final builder = reg.builderFor(node.type);
    if (builder != null) {
      return builder(
        context,
        node,
        (child) => _buildNode(context, child, reg),
        positionRegistry,
      );
    }

    return _UnknownNodePlaceholder(node: node);
  }
}

/// Debug placeholder widget for unrecognized node types.
class _UnknownNodePlaceholder extends StatelessWidget {
  final AnnotatedNode node;

  const _UnknownNodePlaceholder({required this.node});

  @override
  Widget build(BuildContext context) {
    final theme = TiptapEditorThemeData.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.placeholderBackgroundColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Text(
        'Unknown node: ${node.type}',
        style: TextStyle(
          color: theme.placeholderForegroundColor,
          fontStyle: FontStyle.italic,
          fontSize: 12,
        ),
      ),
    );
  }
}

// =============================================================================
// Default node builders
// =============================================================================

/// Register all standard Tiptap node type builders with the registry.
///
/// The set registered here matches the engine's fixed extension set:
/// StarterKit plus the Image node. The builders are registered through the
/// [NodeRendererRegistry] rather than collapsed into a single switch,
/// preserving an extension seam: if the engine ever regains dynamic extension
/// loading, app-supplied custom builders can be added to the registry without
/// restructuring this code.
void _registerDefaultBuilders(NodeRendererRegistry registry) {
  registry.register(NodeType.paragraph, _buildParagraph);
  registry.register(NodeType.heading, _buildHeading);
  registry.register(NodeType.bulletList, _buildBulletList);
  registry.register(NodeType.orderedList, _buildOrderedList);
  registry.register(NodeType.listItem, _buildListItem);
  registry.register(NodeType.blockquote, _buildBlockquote);
  registry.register(NodeType.codeBlock, _buildCodeBlock);
  registry.register(NodeType.horizontalRule, _buildHorizontalRule);
  registry.register(NodeType.image, _buildImage);
}

/// Handle link taps. In a production app, this would use url_launcher or a
/// custom callback.
void _onLinkTap(String url) {
  // ignore: avoid_print
  print('[TiptapEditor] Link tapped: $url');
}

/// Cache of tap recognizers for link spans, keyed by destination URL.
///
/// Recognizers need a lifetime beyond one build: the previous behavior of
/// constructing a fresh TapGestureRecognizer per link span per build leaked
/// every one of them (nothing ever disposed the previous build's
/// recognizers) and made unchanged link spans compare as changed, invalidating
/// semantics on every keystroke for any block containing a link. Serving the
/// same recognizer for the same URL keeps link spans value-stable across
/// rebuilds.
///
/// Keyed by URL rather than by block or span because the recognizer's only
/// state is its onTap target, which depends solely on the URL — sharing one
/// recognizer across every span linking to the same destination is safe. The
/// cache is bounded at one recognizer per distinct URL seen in the session
/// and is deliberately never cleared: builders are library-level functions
/// with no dispose hook, and an idle recognizer holds no resources beyond
/// its own allocation, so a lifetime cache is strictly cheaper than the
/// per-build churn it replaces.
final Map<String, TapGestureRecognizer> _linkRecognizers = {};

/// Resolve the cached recognizer for a link destination, creating it on
/// first sight of the URL. Passed into the span builder by
/// _buildRichTextBlock.
TapGestureRecognizer _linkRecognizerFor(String url) {
  return _linkRecognizers[url] ??= (TapGestureRecognizer()
    ..onTap = () => _onLinkTap(url));
}
