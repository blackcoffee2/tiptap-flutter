// Block-node widget builders for the document renderer.
//
// This is a part of the `document_renderer` library (see document_renderer.dart).
// It holds the builders for the block-level node types — paragraph, heading,
// bullet and ordered lists, list items, blockquote, code block, and horizontal
// rule — along with the shared [_buildRichTextBlock] helper that paragraph and
// heading use to produce a position-registered RichText, and the
// [_ListItemWrapper] widget that lays out a list marker beside item content.
//
// A part file shares the imports declared in the parent library file. These
// builders register with the [NodeRendererRegistry] through the parent's
// _registerDefaultBuilders.

part of 'document_renderer.dart';

/// Build a [RichText] widget for a block node that contains inline content,
/// and register it with the position registry for tap-to-cursor support.
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

  /// The position registry uses this key to find the RichText's
  /// RenderParagraph later for hit-testing and caret positioning.
  final richTextKey = GlobalKey();

  if (isEmpty) {
    /// The zero-width space produces a real RenderParagraph with measurable
    /// line height, which the position registry needs for tap-to-cursor hit
    /// testing — a plain SizedBox has no RenderParagraph to query.
    final emptySpan = TextSpan(text: '\u200B', style: style);

    /// The span mapping covers the block's full position range but has zero
    /// length, so any tap within the block's vertical bounds maps to the
    /// block's content start position — exactly where the cursor should go.
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

  final result = buildTextSpanWithMappings(
    children: node.content!,
    baseStyle: style,
    onLinkTap: _onLinkTap,
  );

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
  /// Code blocks contain text nodes directly.
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
