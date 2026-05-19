// Converts inline content nodes (text, hardBreak) with their marks into
// a Flutter [InlineSpan] tree suitable for use in [RichText] widgets.
//
// This is the core of inline rendering. Each text node becomes a [TextSpan]
// with a style derived from its marks (bold, italic, code, link, etc.).
// Hard breaks become newline characters in the text flow.
//
// The builder also produces position mappings that track the correspondence
// between each span's character offsets and ProseMirror document positions,
// enabling tap-to-cursor and cursor painting.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../engine/protocol_types.dart';
import '../selection/position_registry.dart';

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
///
/// Returns a [TextSpanBuildResult] containing the span tree and position mappings.
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
    if (child.type == 'hardBreak') {
      /// Hard breaks are rendered as literal newlines in the text flow.
      spans.add(const TextSpan(text: '\n'));
      localOffset += 1;
      continue;
    }

    if (child.type == 'text' && child.text != null) {
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

      /// Record the mapping between this span's local character range
      /// and its ProseMirror position range.
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

    /// For any other inline node type we don't recognize, render its text
    /// content if available, or skip it.
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
/// Each mark modifies the base style independently. Multiple marks stack
/// (e.g., bold + italic + code all apply together).
TextStyle _resolveMarkStyles(List<MarkData>? marks, TextStyle baseStyle) {
  if (marks == null || marks.isEmpty) return baseStyle;

  var style = baseStyle;

  for (final mark in marks) {
    switch (mark.type) {
      case 'bold':
        style = style.copyWith(fontWeight: FontWeight.w700);
        break;

      case 'italic':
        style = style.copyWith(fontStyle: FontStyle.italic);
        break;

      case 'strike':
        style = style.copyWith(
          decoration: _addDecoration(
            style.decoration,
            TextDecoration.lineThrough,
          ),
        );
        break;

      case 'underline':
        style = style.copyWith(
          decoration: _addDecoration(
            style.decoration,
            TextDecoration.underline,
          ),
        );
        break;

      case 'code':

        /// Inline code gets a monospace font and a subtle background.
        style = style.copyWith(
          fontFamily: 'monospace',
          fontSize: (style.fontSize ?? 14) * 0.9,
          backgroundColor: const Color(0x1A000000),
          letterSpacing: -0.5,
        );
        break;

      case 'link':

        /// Links get an underline and a distinct color.
        style = style.copyWith(
          color: const Color(0xFF1A73E8),
          decoration: _addDecoration(
            style.decoration,
            TextDecoration.underline,
          ),
          decorationColor: const Color(0xFF1A73E8),
        );
        break;

      case 'highlight':

        /// Highlight mark uses a background color. The color can be specified
        /// in the mark's attrs, or defaults to yellow.
        final color = _parseHighlightColor(mark.attrs?['color']);
        style = style.copyWith(backgroundColor: color);
        break;

      case 'superscript':
        style = style.copyWith(
          fontSize: (style.fontSize ?? 14) * 0.75,
          fontFeatures: [
            ...?style.fontFeatures,
            const FontFeature.superscripts(),
          ],
        );
        break;

      case 'subscript':
        style = style.copyWith(
          fontSize: (style.fontSize ?? 14) * 0.75,
          fontFeatures: [
            ...?style.fontFeatures,
            const FontFeature.subscripts(),
          ],
        );
        break;

      case 'textStyle':

        /// The textStyle mark carries inline CSS-like properties.
        final colorStr = mark.attrs?['color'] as String?;
        if (colorStr != null) {
          final color = _parseColor(colorStr);
          if (color != null) {
            style = style.copyWith(color: color);
          }
        }
        break;

      default:

        /// Unknown marks are silently ignored.
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
    if (mark.type == 'link') {
      return mark.attrs?['href'] as String?;
    }
  }
  return null;
}

/// Parse a highlight color from the mark's color attribute.
/// Defaults to a semi-transparent yellow if the color can't be parsed.
Color _parseHighlightColor(dynamic colorValue) {
  if (colorValue is String) {
    final parsed = _parseColor(colorValue);
    if (parsed != null) return parsed.withAlpha(80);
  }
  return const Color(0x4DFFEB3B);
}

/// Parse a CSS-style color string into a Flutter [Color].
/// Supports hex (#RRGGBB, #RGB) and basic named colors.
/// Returns null if the string can't be parsed.
Color? _parseColor(String colorStr) {
  final trimmed = colorStr.trim().toLowerCase();

  /// Hex colors: #RGB, #RRGGBB, #RRGGBBAA
  if (trimmed.startsWith('#')) {
    final hex = trimmed.substring(1);
    if (hex.length == 3) {
      final r = int.tryParse('${hex[0]}${hex[0]}', radix: 16);
      final g = int.tryParse('${hex[1]}${hex[1]}', radix: 16);
      final b = int.tryParse('${hex[2]}${hex[2]}', radix: 16);
      if (r != null && g != null && b != null) {
        return Color.fromARGB(255, r, g, b);
      }
    } else if (hex.length == 6) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) return Color(0xFF000000 | value);
    } else if (hex.length == 8) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) return Color(value);
    }
  }

  /// Basic CSS named colors used commonly in editors.
  const namedColors = <String, Color>{
    'red': Color(0xFFFF0000),
    'green': Color(0xFF008000),
    'blue': Color(0xFF0000FF),
    'yellow': Color(0xFFFFFF00),
    'orange': Color(0xFFFFA500),
    'purple': Color(0xFF800080),
    'pink': Color(0xFFFFC0CB),
    'black': Color(0xFF000000),
    'white': Color(0xFFFFFFFF),
    'gray': Color(0xFF808080),
    'grey': Color(0xFF808080),
  };

  return namedColors[trimmed];
}
