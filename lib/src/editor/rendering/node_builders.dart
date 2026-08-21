// Block-node widget builders for the document renderer.
//
// This is a part of the `document_renderer` library (see document_renderer.dart).
// It holds the builders for the block-level node types — paragraph, heading,
// bullet and ordered lists, list items, blockquote, code block, and horizontal
// rule — along with the shared [_buildRichTextBlock] helper that paragraph and
// heading use to produce a position-registered RichText, and the
// [_ListItemWrapper] widget that lays out a list marker beside item content.
//
// Every color and base text style comes from the resolved
// [TiptapEditorThemeData], read through the builder's BuildContext. Heading
// sizes and block spacing remain internal tables here: they are layout
// metrics derived from the base style, not part of the theme's surface.
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
  required TiptapEditorThemeData theme,
  required PositionRegistry? registry,
  EdgeInsets padding = const EdgeInsets.symmetric(vertical: 4),
}) {
  final isEmpty = node.content == null || node.content!.isEmpty;

  /// The position registry uses this key to find the RichText's
  /// RenderParagraph later for hit-testing and caret positioning.
  ///
  /// The key comes from the registry's stable per-ordinal store rather than
  /// a fresh GlobalKey per build: a stable key lets Flutter update the
  /// block's existing RichText element in place, so RenderParagraph.text can
  /// short-circuit on value-equal span trees and unchanged blocks skip
  /// layout entirely on a keystroke. With per-build keys, every block's
  /// element was deactivated and re-inflated on every rebuild, relaying out
  /// the whole document per keystroke. Null when position tracking is
  /// disabled — an unkeyed RichText is then matched positionally, which
  /// reuses elements just as well.
  final GlobalKey? richTextKey = registry?.takeNextBlockKey();

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
          key: richTextKey!,
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
    linkRecognizerFor: _linkRecognizerFor,
    linkColor: theme.linkColor,
    inlineCodeBackgroundColor: theme.inlineCodeBackgroundColor,
  );

  if (registry != null && node.pos != null && node.end != null) {
    registry.registerBlock(
      RegisteredBlock(
        pos: node.pos!,
        end: node.end!,
        key: richTextKey!,
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
  BuildContext context,
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final theme = TiptapEditorThemeData.of(context);
  return _buildRichTextBlock(
    node: node,
    style: theme.baseTextStyle,
    theme: theme,
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
  BuildContext context,
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final theme = TiptapEditorThemeData.of(context);
  final level = node.attrs?[NodeAttr.level] as int? ?? 1;
  final fontSize = _headingSizes[level] ?? 16.0;
  final topPadding = _headingTopPadding[level] ?? 8.0;

  final style = theme.baseTextStyle.copyWith(
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  return _buildRichTextBlock(
    node: node,
    style: style,
    theme: theme,
    registry: registry,
    padding: EdgeInsets.only(top: topPadding, bottom: 4),
  );
}

// -----------------------------------------------------------------------------
// Bullet List
// -----------------------------------------------------------------------------

Widget _buildBulletList(
  BuildContext context,
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final theme = TiptapEditorThemeData.of(context);
  final items = node.content ?? [];

  /// Markers use the base text style so they share the paragraph's color
  /// and line metrics and stay aligned with the first line of the item.
  final markerStyle = theme.baseTextStyle;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          _ListItemWrapper(
            bulletBuilder: (context) => Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Text('•', style: markerStyle),
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
  BuildContext context,
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final theme = TiptapEditorThemeData.of(context);
  final items = node.content ?? [];
  final startIndex = node.attrs?[NodeAttr.start] as int? ?? 1;
  final markerStyle = theme.baseTextStyle;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          _ListItemWrapper(
            bulletBuilder: (context) => Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Text('${startIndex + i}.', style: markerStyle),
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
  BuildContext context,
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
  BuildContext context,
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final theme = TiptapEditorThemeData.of(context);
  final children = node.content ?? [];

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.blockquoteBorderColor, width: 3),
        ),
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
  BuildContext context,
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final theme = TiptapEditorThemeData.of(context);

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
        color: theme.codeBlockBackgroundColor,
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
                style: TextStyle(
                  fontSize: 11,
                  color: theme.codeBlockLabelColor,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              buffer.toString(),
              style: theme.codeBlockTextStyle,
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
  BuildContext context,
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final theme = TiptapEditorThemeData.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Divider(thickness: 1, color: theme.dividerColor),
  );
}
