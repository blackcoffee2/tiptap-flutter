// Tiptap Flutter — Example application.
//
// Demonstrates how to compose the tiptap_flutter package widgets into a
// complete editor experience with a toolbar, content area, status bar,
// and debug overlay.
//
// This is the same functionality as the original PoC app, now built on
// top of the package's composable widget API.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tiptap_flutter/tiptap_flutter.dart';

void main() {
  runApp(const TiptapEditorApp());
}

class TiptapEditorApp extends StatelessWidget {
  const TiptapEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiptap Editor Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const EditorScreen(),
    );
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final EditorController _controller = EditorController();

  /// Sample HTML content to initialize the editor with.
  static const _sampleContent = '''
<h1>Hello from Tiptap</h1>
<p>This is a <strong>proof of concept</strong> demonstrating the 
<em>headless engine bridge</em> between Flutter and Tiptap.</p>
<p>The engine runs inside a hidden WebView. Every pixel you see 
is rendered by Flutter.</p>
<ul>
  <li>Item one</li>
  <li>Item two</li>
  <li>Item three</li>
</ul>
<blockquote>This is a blockquote to test more node types.</blockquote>
<p>And a final paragraph with a <a href="https://tiptap.dev">link</a>.</p>
''';

  /// Subscriptions to controller streams for the status bar.
  final List<StreamSubscription> _subscriptions = [];

  /// Current engine state for the status bar indicator.
  EngineState _engineState = EngineState.uninitialized;

  /// Schema metadata for the status bar summary.
  SchemaMetadata? _schema;

  /// Editor state for the debug overlay.
  EditorStatePayload? _editorState;

  /// Whether the debug overlay is currently visible.
  bool _showDebug = false;

  @override
  void initState() {
    super.initState();

    /// Subscribe to controller streams for the status bar and debug overlay.
    _subscriptions.add(
      _controller.engineStateStream.listen((state) {
        setState(() {
          _engineState = state;
        });
      }),
    );

    _subscriptions.add(
      _controller.schemaStream.listen((schema) {
        setState(() {
          _schema = schema;
        });
      }),
    );

    _subscriptions.add(
      _controller.editorStateStream.listen((state) {
        setState(() {
          _editorState = state;
        });
      }),
    );

    _initEditor();
  }

  Future<void> _initEditor() async {
    try {
      await _controller.initialize(content: _sampleContent);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Editor initialization failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiptap Editor'),
        actions: [
          IconButton(
            icon: Icon(
              _showDebug ? Icons.bug_report : Icons.bug_report_outlined,
            ),
            tooltip: 'Toggle debug overlay',
            onPressed: () {
              setState(() {
                _showDebug = !_showDebug;
              });
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: _buildStatusBar(),
        ),
      ),
      body: Stack(
        children: [
          /// Main editor content: toolbar + document.
          Column(
            children: [
              /// The formatting toolbar.
              TiptapToolbar(controller: _controller),

              /// The rendered document with input and selection.
              Expanded(child: TiptapEditor(controller: _controller)),
            ],
          ),

          /// Debug overlay, shown when toggled.
          if (_showDebug)
            DebugOverlay(
              controller: _controller,
              editorState: _editorState,
              schema: _schema,
              onClose: () {
                setState(() {
                  _showDebug = false;
                });
              },
            ),
        ],
      ),
    );
  }

  /// Status bar showing the current engine state with a color indicator.
  Widget _buildStatusBar() {
    final Color statusColor;
    final String statusText;

    switch (_engineState) {
      case EngineState.uninitialized:
        statusColor = Colors.grey;
        statusText = 'Uninitialized';
      case EngineState.loading:
        statusColor = Colors.orange;
        statusText = 'Loading Engine...';
      case EngineState.pageLoaded:
        statusColor = Colors.amber;
        statusText = 'Page Loaded, Waiting for Engine JS...';
      case EngineState.engineGlobalReady:
        statusColor = Colors.lime;
        statusText = 'Engine Global Found, Sending Init...';
      case EngineState.schemaReady:
        statusColor = Colors.lightBlue;
        statusText = 'Schema Ready';
      case EngineState.ready:
        statusColor = Colors.green;
        statusText = 'Engine Ready';
      case EngineState.error:
        statusColor = Colors.red;
        statusText = 'Error: ${_controller.errorMessage ?? "Unknown"}';
      case EngineState.destroyed:
        statusColor = Colors.grey;
        statusText = 'Destroyed';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_schema != null)
            Text(
              '${_schema!.nodes.length} nodes, '
              '${_schema!.marks.length} marks, '
              '${_schema!.commands.length} commands',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
