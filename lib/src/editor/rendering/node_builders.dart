// Image-node widget builders for the document renderer.
//
// This is a part of the `document_renderer` library (see document_renderer.dart).
// It holds the image node builder and its source-handling helpers: dispatching
// between network URLs and base64 data URIs, decoding base64 payloads into an
// in-memory image, and the placeholder shown when a source is missing or fails
// to load.
//
// A part file shares the imports declared in the parent library file,
// including dart:convert (used by the base64 decoder) and material.dart. The
// image builder is registered with the [NodeRendererRegistry] through the
// parent's _registerDefaultBuilders.

part of 'document_renderer.dart';

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
/// (data:[mediatype];base64,[data]) and network URLs.
Widget _buildImageFromSrc(String src, String? alt) {
  if (src.startsWith('data:')) {
    return _buildBase64Image(src, alt);
  }

  return Image.network(
    src,
    fit: BoxFit.contain,
    errorBuilder: (context, error, stackTrace) {
      return _buildImageErrorPlaceholder(alt);
    },
  );
}

/// Decode a base64 data URI and build an [Image.memory] widget.
/// Shows an error placeholder if decoding fails.
Widget _buildBase64Image(String dataUri, String? alt) {
  try {
    /// The base64 data follows the comma in the data URI.
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
