// Converts inline content nodes (text, hardBreak) with their marks into
// a Flutter [InlineSpan] tree suitable for use in [RichText] widgets.
//
// Each text node becomes a [TextSpan] with a style derived from its marks
// (bold, italic, code, link, etc.). Hard breaks become newline characters in
// the text flow.
//
// The builder also produces position mappings that track the correspondence
// between each span's character offsets and ProseMirror document positions,
// enabling tap-to-cursor and cursor painting.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../engine/protocol_types.dart';
import '../selection/position_registry.dart';
import 'node_types.dart';

/// The result of building a text span tree from inline content nodes.
///
/// Contains both the [TextSpan] for rendering and the [spanMappings] for
/// position translation between local text offsets and ProseMirror positions.
class TextSpanBuildResult {
  /// The root text span for use in a [RichText] widget.
  final TextSpan span;

  /// Position mappings for each inline text node within the span tree.
  /// Used by the position registry for tap-to-cursor and cursor painting.
  final List<InlineSpanMapping> spanMappings;

  const TextSpanBuildResult({required this.span, required this.spanMappings});
}

/// Builds an [InlineSpan] tree from a list of inline content nodes,
/// along with position mappings for the position registry.
///
/// [children] is the list of inline nodes (text, hardBreak, etc.) from
/// a block node's content array.
/// [baseStyle] is the default text style inherited from the parent block
/// (e.g., heading size, blockquote color).
/// [onLinkTap] is an optional callback invoked when a link is tapped.
TextSpanBuildResult buildTextSpanWithMappings({
  required List<AnnotatedNode> children,
  required TextStyle baseStyle,
  void Function(String url)? onLinkTap,
}) {
  final spans = <InlineSpan>[];
  final mappings = <InlineSpanMapping>[];

  /// Running character offset within the flattened text of this block.
  var localOffset = 0;

  for (final child in children) {
    if (child.type == NodeType.hardBreak) {
      spans.add(const TextSpan(text: '\n'));
      localOffset += 1;
      continue;
    }

    if (child.type == NodeType.text && child.text != null) {
      final style = _resolveMarkStyles(child.marks, baseStyle);
      final linkHref = _extractLinkHref(child.marks);
      final textLength = child.text!.length;

      spans.add(
        TextSpan(
          text: child.text,
          style: style,
          recognizer: linkHref != null && onLinkTap != null
              ? (TapGestureRecognizer()..onTap = () => onLinkTap(linkHref))
              : null,
        ),
      );

      if (child.pos != null && child.end != null) {
        mappings.add(
          InlineSpanMapping(
            pos: child.pos!,
            end: child.end!,
            localStart: localOffset,
            length: textLength,
          ),
        );
      }

      localOffset += textLength;
      continue;
    }

    /// Any other inline node type: render its text content if available,
    /// otherwise skip it.
    if (child.text != null) {
      spans.add(TextSpan(text: child.text, style: baseStyle));
      localOffset += child.text!.length;
    }
  }

  return TextSpanBuildResult(
    span: TextSpan(children: spans, style: baseStyle),
    spanMappings: mappings,
  );
}

/// Convenience wrapper that returns just the [TextSpan] without position
/// mappings. Used in contexts where position tracking isn't needed (e.g.,
/// code blocks where hit-testing is handled differently).
TextSpan buildTextSpan({
  required List<AnnotatedNode> children,
  required TextStyle baseStyle,
  void Function(String url)? onLinkTap,
}) {
  return buildTextSpanWithMappings(
    children: children,
    baseStyle: baseStyle,
    onLinkTap: onLinkTap,
  ).span;
}

/// Resolve the combined text style for a set of marks applied to a text node.
///
/// Multiple marks stack (e.g., bold + italic + code all apply together). The
/// supported marks match the engine's fixed extension set: bold, italic,
/// strike, underline, code, and link. Any mark outside this set is silently
/// ignored, which keeps the renderer safe if an unexpected mark arrives.
TextStyle _resolveMarkStyles(List<MarkData>? marks, TextStyle baseStyle) {
  if (marks == null || marks.isEmpty) return baseStyle;

  var style = baseStyle;

  for (final mark in marks) {
    switch (mark.type) {
      case MarkType.bold:
        style = style.copyWith(fontWeight: FontWeight.w700);
        break;

      case MarkType.italic:
        style = style.copyWith(fontStyle: FontStyle.italic);
        break;

      case MarkType.strike:
        style = style.copyWith(
          decoration: _addDecoration(
            style.decoration,
            TextDecoration.lineThrough,
          ),
        );
        break;

      case MarkType.underline:
        style = style.copyWith(
          decoration: _addDecoration(
            style.decoration,
            TextDecoration.underline,
          ),
        );
        break;

      case MarkType.code:
        style = style.copyWith(
          fontFamily: 'monospace',
          fontSize: (style.fontSize ?? 14) * 0.9,
          backgroundColor: const Color(0x1A000000),
          letterSpacing: -0.5,
        );
        break;

      case MarkType.link:
        style = style.copyWith(
          color: const Color(0xFF1A73E8),
          decoration: _addDecoration(
            style.decoration,
            TextDecoration.underline,
          ),
          decorationColor: const Color(0xFF1A73E8),
        );
        break;

      default:
        break;
    }
  }

  return style;
}

/// Combine two TextDecoration values. Handles the case where the existing
/// decoration is null or TextDecoration.none.
TextDecoration _addDecoration(TextDecoration? existing, TextDecoration added) {
  if (existing == null || existing == TextDecoration.none) {
    return added;
  }
  return TextDecoration.combine([existing, added]);
}

/// Extract the href attribute from a link mark, if present.
String? _extractLinkHref(List<MarkData>? marks) {
  if (marks == null) return null;
  for (final mark in marks) {
    if (mark.type == MarkType.link) {
      return mark.attrs?[MarkAttr.href] as String?;
    }
  }
  return null;
}
