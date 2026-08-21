// Tiptap Flutter — Example application.
//
// Demonstrates how to compose the tiptap_flutter package widgets into a
// complete editor experience with a toolbar, content area, status bar,
// and performance overlay.
//
// It also demonstrates the two ways to theme the editor:
//   - Globally, by registering a [TiptapEditorTheme] in ThemeData.extensions
//     for the light and dark themes. Everything left unset there derives from
//     the Material ColorScheme, so the editor's text, caret, and links follow
//     the app automatically when the theme mode switches.
//   - Per editor, by passing a [TiptapEditorTheme] to [TiptapEditor.theme],
//     which layers over the global one field by field.
//
// The app bar has a light/dark toggle so the automatic dark-mode behavior
// can be seen without changing system settings.
//
// This is the same functionality as the original PoC app, now built on
// top of the package's composable widget API.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tiptap_flutter/tiptap_flutter.dart';

void main() {
  runApp(const TiptapEditorApp());
}

class TiptapEditorApp extends StatefulWidget {
  const TiptapEditorApp({super.key});

  @override
  State<TiptapEditorApp> createState() => _TiptapEditorAppState();
}

class _TiptapEditorAppState extends State<TiptapEditorApp> {
  /// Starts on the system setting; the app bar toggle flips between light
  /// and dark explicitly from there.
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleThemeMode() {
    setState(() {
      final isDark =
          _themeMode == ThemeMode.dark ||
          (_themeMode == ThemeMode.system &&
              WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                  Brightness.dark);
      _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiptap Editor Example',
      themeMode: _themeMode,

      /// Only the link color is customized globally; every other editor
      /// color (text, caret, selection, code backgrounds) is derived from
      /// the ColorScheme, which is what makes the dark theme below work
      /// without listing each color again.
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        extensions: const [TiptapEditorTheme(linkColor: Colors.indigo)],
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
        extensions: const [TiptapEditorTheme(linkColor: Colors.lightBlue)],
      ),
      home: EditorScreen(onToggleThemeMode: _toggleThemeMode),
    );
  }
}

class EditorScreen extends StatefulWidget {
  /// Flips the app between light and dark mode.
  final VoidCallback onToggleThemeMode;

  const EditorScreen({super.key, required this.onToggleThemeMode});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final EditorController _controller = EditorController();
  final ImagePicker _imagePicker = ImagePicker();

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
<p>Inline <code>code</code> and a <a href="https://tiptap.dev">link</a> pick up
theme colors too.</p>
<pre><code class="language-dart">void main() => print('theme-aware');</code></pre>
''';

  /// Subscriptions to controller streams for the status bar.
  final List<StreamSubscription> _subscriptions = [];

  /// Current engine state for the status bar indicator.
  EngineState _engineState = EngineState.uninitialized;

  /// Schema metadata for the status bar summary.
  SchemaMetadata? _schema;

  /// Whether the performance overlay is currently visible.
  bool _showPerformance = false;

  /// Whether the per-editor override is applied on top of the global theme.
  /// Toggled from the app bar to show the two layers composing.
  bool _usePerEditorOverride = false;

  /// A deliberately conspicuous per-editor override so its effect is
  /// unmistakable when toggled: serif body text and an amber caret. Fields
  /// left null here (links, code backgrounds, etc.) continue to come from
  /// the global theme.
  static const _perEditorTheme = TiptapEditorTheme(
    baseTextStyle: TextStyle(fontFamily: 'serif'),
    cursorColor: Colors.amber,
    selectionColor: Color(0x40FFC107),
  );

  @override
  void initState() {
    super.initState();

    /// Subscribe to controller streams for the status bar.
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

  /// Pick an image from the device gallery, convert it to a base64 data URI,
  /// and return an [ImageInsertResult] for the toolbar to insert into the
  /// editor. Returns null if the user cancels the picker.
  ///
  /// This demonstrates the simplest possible image insertion flow using
  /// base64 encoding. In a production app, you would typically upload the
  /// image to a server or CDN and return the hosted URL instead — base64
  /// data URIs work but bloat the document size.
  Future<ImageInsertResult?> _pickImage() async {
    final XFile? pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (pickedFile == null) return null;

    final bytes = await pickedFile.readAsBytes();
    final base64Data = base64Encode(bytes);

    /// Determine the MIME type from the file extension. Falls back to
    /// a generic image type if the extension isn't recognized.
    final mimeType = _mimeTypeFromPath(pickedFile.path);

    return ImageInsertResult(
      src: 'data:$mimeType;base64,$base64Data',
      alt: pickedFile.name,
    );
  }

  /// Map common image file extensions to their MIME types.
  String _mimeTypeFromPath(String path) {
    final extension = path.split('.').last.toLowerCase();
    const mimeTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'heic': 'image/heic',
      'heif': 'image/heif',
    };
    return mimeTypes[extension] ?? 'image/png';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiptap Editor'),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: widget.onToggleThemeMode,
          ),
          IconButton(
            icon: Icon(
              _usePerEditorOverride
                  ? Icons.format_paint
                  : Icons.format_paint_outlined,
            ),
            tooltip: 'Toggle per-editor theme override',
            onPressed: () {
              setState(() {
                _usePerEditorOverride = !_usePerEditorOverride;
              });
            },
          ),
          IconButton(
            icon: Icon(_showPerformance ? Icons.speed : Icons.speed_outlined),
            tooltip: 'Toggle performance overlay',
            onPressed: () {
              setState(() {
                _showPerformance = !_showPerformance;
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
              /// The formatting toolbar with image picker wired up.
              TiptapToolbar(controller: _controller, onPickImage: _pickImage),

              /// The rendered document with input and selection. With
              /// theme: null the editor follows the global theme alone.
              Expanded(
                child: TiptapEditor(
                  controller: _controller,
                  theme: _usePerEditorOverride ? _perEditorTheme : null,
                ),
              ),
            ],
          ),

          /// Performance overlay, shown when toggled.
          if (_showPerformance)
            TiptapPerformanceOverlay(
              controller: _controller,
              onClose: () {
                setState(() {
                  _showPerformance = false;
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
