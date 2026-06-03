// Tiptap Flutter — A composable rich-text editor for Flutter powered by the
// Tiptap engine running inside a headless WebView.
//
// This library exposes a controller-based API inspired by Tiptap React:
//   - [EditorController] is the core — create one, initialize it, send commands,
//     listen to state streams.
//   - [TiptapEditor] is the content area widget that renders the document,
//     handles gestures, selection painting, and keyboard input.
//   - [TiptapToolbar] is a standalone formatting toolbar you can place anywhere.
//   - [TiptapPerformanceOverlay] is an opt-in performance metrics panel for
//     development.
//   - [NodeRendererRegistry] lets you register custom node type renderers.
//
// Minimal usage:
//   final controller = EditorController();
//   await controller.initialize(content: '<p>Hello</p>');
//
//   // In your widget tree:
//   Column(
//     children: [
//       TiptapToolbar(controller: controller),
//       Expanded(child: TiptapEditor(controller: controller)),
//     ],
//   )

// Engine layer — protocol types and lifecycle state
export 'src/engine/protocol_types.dart';
export 'src/engine/tiptap_bridge.dart' show EngineState, BridgeLogEntry;
export 'src/engine/metrics.dart';

// Editor controller — the primary public API
export 'src/editor/editor_controller.dart';

// Composable widgets
export 'src/editor/tiptap_editor.dart';
export 'src/editor/tiptap_toolbar.dart' show TiptapToolbar, ImageInsertResult;
export 'src/editor/performance_overlay.dart';

// Rendering extensibility
export 'src/editor/rendering/node_renderer_registry.dart';
