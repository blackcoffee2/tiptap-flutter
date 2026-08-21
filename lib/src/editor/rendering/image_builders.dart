// Image-node widget builders for the document renderer.
//
// This is a part of the `document_renderer` library (see document_renderer.dart).
// It holds the image node builder and its source-handling helpers: dispatching
// between network URLs and base64 data URIs, decoding base64 payloads into an
// in-memory image, and the placeholder shown when a source is missing or fails
// to load.
//
// Placeholder and caption colors come from the resolved
// [TiptapEditorThemeData]. The helpers below take the theme as a parameter
// rather than a BuildContext because they are also invoked from Image
// errorBuilder callbacks, whose context sits inside the Image subtree; passing
// the already-resolved data avoids a second inherited lookup there.
//
// A part file shares the imports declared in the parent library file,
// including dart:convert (used by the base64 decoder) and material.dart. The
// image builder is registered with the [NodeRendererRegistry] through the
// parent's _registerDefaultBuilders.

part of 'document_renderer.dart';

/// Build an image widget from the node's src attribute. Supports both
/// network URLs (http/https) and base64 data URIs (data:image/...).
Widget _buildImage(
  BuildContext context,
  AnnotatedNode node,
  Widget Function(AnnotatedNode) childBuilder,
  PositionRegistry? registry,
) {
  final theme = TiptapEditorThemeData.of(context);
  final src = node.attrs?[NodeAttr.src] as String?;
  final alt = node.attrs?[NodeAttr.alt] as String?;
  final title = node.attrs?[NodeAttr.title] as String?;

  if (src == null || src.isEmpty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: theme.placeholderBackgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'Image: no src',
            style: TextStyle(
              color: theme.placeholderForegroundColor,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  final imageWidget = _buildImageFromSrc(src, alt, theme);

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
              style: TextStyle(
                fontSize: 12,
                color: theme.captionColor,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Build an [Image] widget from a src string, handling both base64 data URIs
/// (data:[mediatype];base64,[data]) and network URLs.
Widget _buildImageFromSrc(
  String src,
  String? alt,
  TiptapEditorThemeData theme,
) {
  if (src.startsWith('data:')) {
    return _buildBase64Image(src, alt, theme);
  }

  return Image.network(
    src,
    fit: BoxFit.contain,
    errorBuilder: (context, error, stackTrace) {
      return _buildImageErrorPlaceholder(alt, theme);
    },
  );
}

/// Decode a base64 data URI and build an [Image.memory] widget.
/// Shows an error placeholder if decoding fails.
Widget _buildBase64Image(
  String dataUri,
  String? alt,
  TiptapEditorThemeData theme,
) {
  try {
    /// The base64 data follows the comma in the data URI.
    final commaIndex = dataUri.indexOf(',');
    if (commaIndex == -1) {
      return _buildImageErrorPlaceholder(alt, theme);
    }

    final base64Data = dataUri.substring(commaIndex + 1);
    final bytes = base64Decode(base64Data);

    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return _buildImageErrorPlaceholder(alt, theme);
      },
    );
  } catch (e) {
    return _buildImageErrorPlaceholder(alt, theme);
  }
}

/// Placeholder widget shown when an image fails to load or decode.
Widget _buildImageErrorPlaceholder(String? alt, TiptapEditorThemeData theme) {
  return Container(
    height: 100,
    decoration: BoxDecoration(
      color: theme.placeholderBackgroundColor,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(
      child: Text(
        alt ?? 'Failed to load image',
        style: TextStyle(color: theme.placeholderForegroundColor, fontSize: 12),
      ),
    ),
  );
}
