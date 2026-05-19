// Position registry that maps ProseMirror document positions to rendered
// Flutter widgets and vice versa.
//
// This is the core data structure enabling tap-to-cursor and cursor painting.
// Each text-rendering block widget registers itself here with its position
// range and inline span mappings. The registry then provides two-way lookups:
//
//   Tap → pos:  globalOffset → which block → local text offset → ProseMirror pos
//   Pos → paint: ProseMirror pos → which block → local text offset → pixel offset
//
// Position mapping note:
// The engine's serializer annotates text nodes with pos/end values where
// pos is the position after the parent block's opening token. In ProseMirror's
// position model, the parent's content starts one position earlier than the
// text node's annotated pos. For example, a paragraph at position 116 has
// its content starting at position 117, but the text node inside is annotated
// with pos: 118. The local-to-document position conversion accounts for this
// by using (textNode.pos - 1) as the base, which equals the parent's content
// start position. This makes the mapping consistent with ProseMirror's
// parentOffset semantics where parentOffset 0 corresponds to the content
// start position.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Describes how a single inline text span within a block maps to the
/// ProseMirror document position space.
///
/// [pos] and [end] are ProseMirror positions from the engine's AnnotatedNode.
/// [localStart] is the character offset within the block's combined text
/// where this span begins (i.e., the sum of all preceding spans' lengths).
/// [length] is the number of characters in this span.
class InlineSpanMapping {
  /// ProseMirror start position of this text span (as reported by the engine's
  /// serializer — note this is 1 higher than the actual content start).
  final int pos;

  /// ProseMirror end position of this text span.
  final int end;

  /// Character offset within the block's flattened text where this span starts.
  final int localStart;

  /// Number of characters in this span.
  final int length;

  const InlineSpanMapping({
    required this.pos,
    required this.end,
    required this.localStart,
    required this.length,
  });

  @override
  String toString() =>
      'InlineSpanMapping(pos: $pos, end: $end, local: $localStart, len: $length)';
}

/// A registered text block in the position registry.
///
/// Each block-level node that renders text (paragraph, heading, etc.)
/// creates one of these entries. It holds a reference to the block's
/// [RenderParagraph] (via a [GlobalKey]) and the inline span mappings
/// that enable position translation.
class RegisteredBlock {
  /// The ProseMirror start position of this block's content.
  final int pos;

  /// The ProseMirror end position of this block.
  final int end;

  /// Key attached to the [RichText] widget, used to find its [RenderParagraph].
  final GlobalKey key;

  /// Ordered list of inline span mappings within this block. The mappings
  /// are sorted by [localStart] (which matches the order of text nodes in
  /// the document).
  final List<InlineSpanMapping> spanMappings;

  const RegisteredBlock({
    required this.pos,
    required this.end,
    required this.key,
    required this.spanMappings,
  });

  /// Get the [RenderParagraph] for this block, or null if the widget hasn't
  /// been laid out yet or has been removed from the tree.
  RenderParagraph? get renderParagraph {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is RenderParagraph) return renderObject;
    return null;
  }

  /// Convert a local text offset (character index within this block's
  /// flattened text) to a ProseMirror document position.
  ///
  /// Walks the span mappings to find which span contains the local offset,
  /// then computes the ProseMirror position within that span.
  ///
  /// The engine's serializer annotates text node positions with a +1 offset
  /// relative to the actual ProseMirror content start. We compensate by
  /// subtracting 1 from the span's pos when computing the document position.
  /// This makes localOffset 0 map to the parent block's content start
  /// position, which matches ProseMirror's parentOffset semantics.
  int localOffsetToPos(int localOffset) {
    for (final mapping in spanMappings) {
      final localEnd = mapping.localStart + mapping.length;
      if (localOffset >= mapping.localStart && localOffset <= localEnd) {
        /// Compute the ProseMirror position. We subtract 1 from mapping.pos
        /// because the serializer's pos is 1 higher than the actual content
        /// start in ProseMirror's position space.
        final offsetWithinSpan = localOffset - mapping.localStart;
        return (mapping.pos - 1) + offsetWithinSpan;
      }
    }

    /// If we didn't find a matching span (shouldn't happen in normal use),
    /// clamp to the block's position range.
    if (spanMappings.isNotEmpty) {
      if (localOffset <= 0) return spanMappings.first.pos - 1;
      return spanMappings.last.end - 1;
    }
    return pos;
  }

  /// Convert a ProseMirror document position to a local text offset
  /// (character index within this block's flattened text).
  ///
  /// Returns null if the position is outside this block's range.
  ///
  /// Because the serializer's pos values are 1 higher than actual ProseMirror
  /// positions, we add 1 to the docPos before comparing against span ranges.
  int? posToLocalOffset(int docPos) {
    /// Shift the document position to match the serializer's coordinate space.
    final adjustedPos = docPos + 1;
    for (final mapping in spanMappings) {
      if (adjustedPos >= mapping.pos && adjustedPos <= mapping.end) {
        final offsetWithinSpan = adjustedPos - mapping.pos;
        return mapping.localStart + offsetWithinSpan;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'RegisteredBlock(pos: $pos, end: $end, spans: ${spanMappings.length})';
}

/// The position registry maintains a sorted list of registered blocks and
/// provides two-way lookups between pixel coordinates and document positions.
class PositionRegistry {
  /// All registered blocks, sorted by [pos].
  final List<RegisteredBlock> _blocks = [];

  /// Read-only access to the registered blocks for debugging.
  List<RegisteredBlock> get blocks => List.unmodifiable(_blocks);

  /// Clear all registrations. Called before each document re-render to
  /// ensure stale entries don't persist.
  void clear() {
    _blocks.clear();
  }

  /// Register a text block with its position range and span mappings.
  void registerBlock(RegisteredBlock block) {
    _blocks.add(block);

    /// Keep blocks sorted by pos for efficient lookup.
    _blocks.sort((a, b) => a.pos.compareTo(b.pos));
  }

  /// Convert a global pixel offset to a ProseMirror document position.
  ///
  /// Finds which registered block contains the tap point by checking each
  /// block's render object bounds, then uses the [RenderParagraph]'s
  /// [getPositionForOffset] to get the local text offset, and finally
  /// converts that to a ProseMirror position using the span mappings.
  ///
  /// Returns null if the offset doesn't fall within any registered block.
  int? positionFromGlobalOffset(Offset globalOffset) {
    for (final block in _blocks) {
      final rp = block.renderParagraph;
      if (rp == null || !rp.attached) continue;

      /// Convert global offset to the render object's local coordinate space.
      final localOffset = rp.globalToLocal(globalOffset);

      /// Check if the point is within this render object's bounds.
      /// We use the semantic bounds (size) rather than hit testing to be
      /// more forgiving — taps slightly outside the text should still register.
      final size = rp.size;
      if (localOffset.dy >= 0 && localOffset.dy <= size.height) {
        /// Use TextPainter's position-for-offset to get the character index.
        final textPosition = rp.getPositionForOffset(localOffset);
        final localTextOffset = textPosition.offset;

        /// Convert the local text offset to a ProseMirror position.
        final docPos = block.localOffsetToPos(localTextOffset);

        return docPos;
      }
    }

    /// If the tap is below all blocks, place the cursor at the end of
    /// the last block. If above all blocks, place it at the start of
    /// the first block.
    if (_blocks.isNotEmpty) {
      final firstBlock = _blocks.first;
      final firstRp = firstBlock.renderParagraph;
      if (firstRp != null && firstRp.attached) {
        final firstLocal = firstRp.globalToLocal(globalOffset);
        if (firstLocal.dy < 0) {
          /// Place cursor at the start of the first block's content.
          if (firstBlock.spanMappings.isNotEmpty) {
            return firstBlock.spanMappings.first.pos - 1;
          }
          return firstBlock.pos;
        }
      }

      final lastBlock = _blocks.last;
      final lastRp = lastBlock.renderParagraph;
      if (lastRp != null && lastRp.attached) {
        final lastLocal = lastRp.globalToLocal(globalOffset);
        if (lastLocal.dy > lastRp.size.height) {
          /// Place cursor at the end of the last text span in the last block.
          if (lastBlock.spanMappings.isNotEmpty) {
            return lastBlock.spanMappings.last.end - 1;
          }
          return lastBlock.end;
        }
      }
    }

    return null;
  }

  /// Convert a ProseMirror document position to a global pixel offset.
  ///
  /// Finds which registered block contains the position, converts it to
  /// a local text offset, then uses the [RenderParagraph]'s
  /// [getOffsetForCaret] to get the pixel position.
  ///
  /// Returns null if the position doesn't fall within any registered block
  /// or if the block's render object is unavailable.
  Offset? globalOffsetFromPosition(int docPos) {
    final block = _blockForPosition(docPos);
    if (block == null) return null;

    final rp = block.renderParagraph;
    if (rp == null || !rp.attached) return null;

    final localTextOffset = block.posToLocalOffset(docPos);
    if (localTextOffset == null) return null;

    /// Get the pixel offset for the caret at this text position.
    final caretOffset = rp.getOffsetForCaret(
      TextPosition(offset: localTextOffset),
      Rect.zero,
    );

    /// Convert from render object local coordinates to global coordinates.
    return rp.localToGlobal(caretOffset);
  }

  /// Get the caret height at a ProseMirror document position.
  ///
  /// Returns the line height at the given position, or null if the position
  /// is not in any registered block.
  double? caretHeightAtPosition(int docPos) {
    final block = _blockForPosition(docPos);
    if (block == null) return null;

    final rp = block.renderParagraph;
    if (rp == null || !rp.attached) return null;

    final localTextOffset = block.posToLocalOffset(docPos);
    if (localTextOffset == null) return null;

    /// Get the full caret metrics at this position. The preferredLineHeight
    /// gives us the appropriate height for the cursor.
    return rp.preferredLineHeight;
  }

  /// Find the registered block that contains a given ProseMirror position.
  /// The block's pos/end values are in the serializer's coordinate space
  /// (1 higher than actual ProseMirror positions), so we adjust the
  /// comparison range accordingly.
  RegisteredBlock? _blockForPosition(int docPos) {
    /// Shift to serializer coordinate space for range comparison.
    final adjustedPos = docPos + 1;
    for (final block in _blocks) {
      if (adjustedPos >= block.pos && adjustedPos <= block.end) {
        return block;
      }
    }
    return null;
  }
}
