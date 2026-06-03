// Recursive document renderer that walks the [AnnotatedNode] tree and
// produces Flutter widgets for each node.
//
// This is the entry point for document rendering. It dispatches each node
// to its registered builder in the [NodeRendererRegistry], falling back to
// a debug placeholder for unknown node types.
//
// The renderer registers all standard Tiptap node builders on first use.
// Extension developers can add custom builders to the registry before
// the renderer is instantiated, or override the default ones.
//
// Each text-rendering block (paragraph, heading) registers itself with
// the [PositionRegistry] so that taps can be mapped to document positions
// and cursors can be painted at the correct pixel locations.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../engine/protocol_types.dart';
import '../selection/position_registry.dart';
import 'node_renderer_registry.dart';
import 'node_types.dart';
import 'text_span_builder.dart';

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

  const DocumentRenderer({
    super.key,
    required this.doc,
    this.positionRegistry,
    this.registry,
  });

  @override
  State<DocumentRenderer> createState() => _DocumentRendererState();
}

class _DocumentRendererState extends State<DocumentRenderer> {
  @override
  Widget build(BuildContext context) {
    final reg = widget.registry ?? NodeRendererRegistry.defaultRegistry;

    /// Register default builders if the registry is empty.
    if (!reg.hasBuilder(NodeType.paragraph)) {
      _registerDefaultBuilders(reg);
    }

    /// Clear the position registry before rebuilding so stale entries
    /// from previous renders don't persist.
    widget.positionRegistry?.clear();

    /// The doc node's children are the top-level block nodes.
    final children = widget.doc.content ?? [];
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
        node,
        (child) => _buildNode(context, child, reg),
        widget.positionRegistry,
      );
    }

    /// Unknown node type — render a debug placeholder.
    return _UnknownNodePlaceholder(node: node);
  }
}

/// Debug placeholder widget for unrecognized node types.
class _UnknownNodePlaceholder extends StatelessWidget {
  final AnnotatedNode node;

  const _UnknownNodePlaceholder({required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Text(
        'Unknown node: ${node.type}',
        style: TextStyle(
          color: Colors.grey.shade600,
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
/// StarterKit plus the Image node. Each block node that can appear in the
/// document tree has a hand-written builder. The builders are registered
/// through the [NodeRendererRegistry] rather than collapsed into a single
/// switch, preserving an extension seam: if the engine ever regains dynamic
/// extension loading, app-supplied custom builders can be added to the
/// registry without restructuring this code.
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

/// The default base text style used for body text.
const _baseTextStyle = TextStyle(
  fontSize: 16,
  height: 1.6,
  color: Color(0xFF1F1F1F),
);

/// Handle link taps. For now, prints the URL to console.
/// In a production app, this would use url_launcher or a custom callback.
void _onLinkTap(String url) {
  // ignore: avoid_print
  print('[TiptapEditor] Link tapped: $url');
}

/// Build a [RichText] widget for a block node that contains inline content,
/// and register it with the position registry for tap-to-cursor support.
///
/// This is the shared logic used by paragraph and heading builders.
///
/// Empty blocks (no content children) still render a [RichText] with a
/// zero-width space so they produce a [RenderParagraph] that registers
/// with the position registry. This ensures taps on empty paragraphs
/// (e.g., after pressing Enter) correctly place the cursor there.
Widget _buildRichTextBlock({
  required AnnotatedNode node,
  required TextStyle style,
  required PositionRegistry? registry,
  EdgeInsets padding = const EdgeInsets.symmetric(vertical: 4),
}) {
  final isEmpty = node.content == null || node.content!.isEmpty;

  /// Create a GlobalKey for this RichText so the position registry can
  /// find its RenderParagraph later for hit-testing and caret positioning.
  final richTextKey = GlobalKey();

  if (isEmpty) {
    /// Empty blocks render as a RichText with a zero-width space character.
    /// This produces a real RenderParagraph with measurable line height,
    /// which the position registry needs for tap-to-cursor hit testing.
    /// A plain SizedBox would be invisible to the position registry since
    /// it has no RenderParagraph to query.
    ///
    /// The zero-width space (\u200B) takes up no horizontal space but gives
    /// the RenderParagraph a valid text layout with the correct line height.
    final emptySpan = TextSpan(text: '\u200B', style: style);

    /// Register this empty block with the position registry. The span
    /// mapping covers the block's full position range but has zero length,
    /// so any tap within the block's vertical bounds maps to the block's
    /// content start position — exactly where the cursor should go.
    if (registry != null && node.pos != null && node.end != null) {
      registry.registerBlock(
        RegisteredBlock(
          pos: node.pos!,
          end: node.end!,
          key: richTextKey,
          spanMappings: [
            InlineSpanMapping(
              pos: node.pos!,
              end: node.end!,
              localStart: 0,
              length: 0,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: padding,
      child: RichText(key: richTextKey, text: emptySpan),
    );
  }

  /// Build the text span tree and collect position mappings.
  final result = buildTextSpanWithMappings(
    children: node.content!,
    baseStyle: style,
    onLinkTap: _onLinkTap,
  );

  /// Register this block with the position registry.
  if (registry != null && node.pos != null && node.end != null) {
    registry.registerBlock(
      RegisteredBlock(
        pos: node.pos!,
        end: node.end!,
        key: richTextKey,
        spanMappings: result.spanMappings,
      ),
    );
  }

  return Padding(
    padding: padding,
    child: RichText(key: richTextKey, text: result.span),
  );
}

// -----------------------------------------------------------------------------
// Paragraph
// -----------------------------------------------------------------------------

Widget _buildParagraph(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  return _buildRichTextBlock(
    node: node,
    style: _baseTextStyle,
    registry: registry,
  );
}

// -----------------------------------------------------------------------------
// Heading
// -----------------------------------------------------------------------------

const _headingSizes = <int, double>{1: 32, 2: 24, 3: 20, 4: 18, 5: 16, 6: 14};

const _headingTopPadding = <int, double>{
  1: 24,
  2: 20,
  3: 16,
  4: 12,
  5: 8,
  6: 8,
};

Widget _buildHeading(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final level = node.attrs?[NodeAttr.level] as int? ?? 1;
  final fontSize = _headingSizes[level] ?? 16.0;
  final topPadding = _headingTopPadding[level] ?? 8.0;

  final style = _baseTextStyle.copyWith(
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  return _buildRichTextBlock(
    node: node,
    style: style,
    registry: registry,
    padding: EdgeInsets.only(top: topPadding, bottom: 4),
  );
}

// -----------------------------------------------------------------------------
// Bullet List
// -----------------------------------------------------------------------------

Widget _buildBulletList(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final items = node.content ?? [];
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          _ListItemWrapper(
            bulletBuilder: (context) => const Padding(
              padding: EdgeInsets.only(right: 8, top: 2),
              child: Text('•', style: TextStyle(fontSize: 16, height: 1.6)),
            ),
            child: childBuilder(item),
          ),
      ],
    ),
  );
}

// -----------------------------------------------------------------------------
// Ordered List
// -----------------------------------------------------------------------------

Widget _buildOrderedList(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final items = node.content ?? [];
  final startIndex = node.attrs?[NodeAttr.start] as int? ?? 1;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          _ListItemWrapper(
            bulletBuilder: (context) => Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Text(
                '${startIndex + i}.',
                style: const TextStyle(fontSize: 16, height: 1.6),
              ),
            ),
            child: childBuilder(items[i]),
          ),
      ],
    ),
  );
}

// -----------------------------------------------------------------------------
// List Item
// -----------------------------------------------------------------------------

Widget _buildListItem(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final children = node.content ?? [];
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final child in children) childBuilder(child)],
  );
}

/// Wrapper that lays out a bullet/number marker alongside a list item's content.
class _ListItemWrapper extends StatelessWidget {
  final WidgetBuilder bulletBuilder;
  final Widget child;

  const _ListItemWrapper({required this.bulletBuilder, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bulletBuilder(context),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Blockquote
// -----------------------------------------------------------------------------

Widget _buildBlockquote(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final children = node.content ?? [];

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFFBDBDBD), width: 3)),
      ),
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final child in children) childBuilder(child)],
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Code Block
// -----------------------------------------------------------------------------

Widget _buildCodeBlock(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  /// Code blocks contain text nodes directly. Concatenate all text content.
  final buffer = StringBuffer();
  if (node.content != null) {
    for (final child in node.content!) {
      if (child.text != null) {
        buffer.write(child.text);
      } else if (child.type == NodeType.hardBreak) {
        buffer.write('\n');
      }
    }
  }

  final language = node.attrs?[NodeAttr.language] as String?;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (language != null && language.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                language,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF9E9E9E),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              buffer.toString(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.5,
                color: Color(0xFF37474F),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Horizontal Rule
// -----------------------------------------------------------------------------

Widget _buildHorizontalRule(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  return const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Divider(thickness: 1, color: Color(0xFFE0E0E0)),
  );
}

// -----------------------------------------------------------------------------
// Image
// -----------------------------------------------------------------------------

/// Build an image widget from the node's src attribute. Supports both
/// network URLs (http/https) and base64 data URIs (data:image/...).
Widget _buildImage(
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final src = node.attrs?[NodeAttr.src] as String?;
  final alt = node.attrs?[NodeAttr.alt] as String?;
  final title = node.attrs?[NodeAttr.title] as String?;

  if (src == null || src.isEmpty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'Image: no src',
            style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
          ),
        ),
      ),
    );
  }

  /// Determine whether the src is a base64 data URI or a network URL
  /// and build the appropriate image widget.
  final imageWidget = _buildImageFromSrc(src, alt);

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: imageWidget),
        if (title != null && title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF757575),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Build an [Image] widget from a src string, handling both base64 data URIs
/// and network URLs.
///
/// Data URIs follow the format: data:[mediatype];base64,[data]
/// For example: data:image/png;base64,iVBORw0KGgo...
///
/// Network URLs are loaded via [Image.network] with an error fallback.
Widget _buildImageFromSrc(String src, String? alt) {
  /// Check if the src is a base64 data URI.
  if (src.startsWith('data:')) {
    return _buildBase64Image(src, alt);
  }

  /// Fall back to network image loading for http/https URLs and any
  /// other src format.
  return Image.network(
    src,
    fit: BoxFit.contain,
    errorBuilder: (context, error, stackTrace) {
      return _buildImageErrorPlaceholder(alt);
    },
  );
}

/// Decode a base64 data URI and build an [Image.memory] widget.
///
/// Extracts the base64 payload from the data URI by splitting on the
/// comma separator. If decoding fails, shows an error placeholder.
Widget _buildBase64Image(String dataUri, String? alt) {
  try {
    /// The base64 data follows the comma in the data URI.
    /// Example: data:image/png;base64,iVBORw0KGgo...
    final commaIndex = dataUri.indexOf(',');
    if (commaIndex == -1) {
      return _buildImageErrorPlaceholder(alt);
    }

    final base64Data = dataUri.substring(commaIndex + 1);
    final bytes = base64Decode(base64Data);

    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return _buildImageErrorPlaceholder(alt);
      },
    );
  } catch (e) {
    return _buildImageErrorPlaceholder(alt);
  }
}

/// Placeholder widget shown when an image fails to load or decode.
Widget _buildImageErrorPlaceholder(String? alt) {
  return Container(
    height: 100,
    decoration: BoxDecoration(
      color: const Color(0xFFF5F5F5),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(
      child: Text(
        alt ?? 'Failed to load image',
        style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
      ),
    ),
  );
}
