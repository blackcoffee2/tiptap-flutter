// Debug overlay that shows the raw editor state, document JSON, and bridge
// logs as a draggable bottom sheet.
//
// This is the same debug information from the original PoC, packaged as
// a togglable overlay so it doesn't interfere with the editor experience
// but remains accessible during development and extension building.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../engine/protocol_types.dart';
import '../engine/tiptap_bridge.dart';
import 'editor_controller.dart';

/// A draggable bottom sheet overlay showing debug information about the
/// editor state, document JSON, and bridge communication logs.
class DebugOverlay extends StatefulWidget {
  final EditorController controller;
  final EditorStatePayload? editorState;
  final SchemaMetadata? schema;
  final VoidCallback onClose;

  const DebugOverlay({
    super.key,
    required this.controller,
    required this.editorState,
    required this.schema,
    required this.onClose,
  });

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// Log entries collected from the bridge's log stream.
  final List<BridgeLogEntry> _logEntries = [];
  StreamSubscription? _logSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    /// Subscribe to the log stream to collect entries in real time.
    _logSubscription = widget.controller.logStream.listen((entry) {
      setState(() {
        _logEntries.add(entry);
        if (_logEntries.length > 200) {
          _logEntries.removeRange(0, _logEntries.length - 200);
        }
      });
    });
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.1,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(51),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              /// Drag handle and close button.
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    const Spacer(),
                    Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),

              /// Tab bar for switching between debug panels.
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'State'),
                  Tab(text: 'Document'),
                  Tab(text: 'Selection'),
                  Tab(text: 'Logs'),
                ],
              ),

              /// Tab content.
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildStateTab(scrollController),
                    _buildDocumentTab(scrollController),
                    _buildSelectionTab(scrollController),
                    _buildLogsTab(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// State tab: shows active marks, active nodes, command states, and schema summary.
  Widget _buildStateTab(ScrollController scrollController) {
    final state = widget.editorState;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      children: [
        _debugSection('Active Marks', state?.activeMarks.join(', ') ?? 'None'),
        const SizedBox(height: 8),
        _debugSection(
          'Active Nodes',
          state?.activeNodes
                  .map(
                    (n) =>
                        '${n.type}${n.attrs.isNotEmpty ? '(${n.attrs})' : ''}',
                  )
                  .join(', ') ??
              'None',
        ),
        const SizedBox(height: 8),
        _debugSection(
          'Stored Marks',
          state?.storedMarks.map((m) => m.type).join(', ') ?? 'None',
        ),
        const SizedBox(height: 8),
        _debugSection('Editable', '${state?.editable ?? "unknown"}'),
        const SizedBox(height: 8),
        _debugSection(
          'Command States',
          state?.commandStates.entries
                  .map(
                    (e) =>
                        '${e.key}: exec=${e.value.canExec}, active=${e.value.isActive}'
                        '${e.value.depth != null ? ', depth=${e.value.depth}' : ''}',
                  )
                  .join('\n') ??
              'None',
        ),
      ],
    );
  }

  /// Document tab: shows the annotated document JSON.
  Widget _buildDocumentTab(ScrollController scrollController) {
    final doc = widget.editorState?.doc;
    final jsonStr = doc != null
        ? const JsonEncoder.withIndent('  ').convert(doc.toJson())
        : 'No document';

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        jsonStr,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }

  /// Selection tab: shows the current selection state.
  Widget _buildSelectionTab(ScrollController scrollController) {
    final selection = widget.editorState?.selection;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      children: [
        if (selection == null)
          const Text('No selection data')
        else ...[
          _debugSection('Type', selection.type ?? 'unknown'),
          const SizedBox(height: 8),
          _debugSection('Anchor', '${selection.anchor}'),
          const SizedBox(height: 8),
          _debugSection('Head', '${selection.head}'),
          const SizedBox(height: 8),
          _debugSection('From', '${selection.from}'),
          const SizedBox(height: 8),
          _debugSection('To', '${selection.to}'),
          const SizedBox(height: 8),
          _debugSection('Empty', '${selection.empty}'),
        ],
      ],
    );
  }

  /// Logs tab: shows the bridge communication log.
  Widget _buildLogsTab() {
    return Column(
      children: [
        /// Clear button.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Text(
                '${_logEntries.length} entries',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear'),
                onPressed: () {
                  setState(() {
                    _logEntries.clear();
                  });
                },
              ),
            ],
          ),
        ),

        /// Log list.
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _logEntries.length,
            reverse: true,
            itemBuilder: (context, index) {
              final entry = _logEntries[_logEntries.length - 1 - index];
              final timeStr =
                  '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
                  '${entry.timestamp.second.toString().padLeft(2, '0')}';

              final Color directionColor;
              switch (entry.direction) {
                case 'sent':
                  directionColor = Colors.blue;
                case 'received':
                  directionColor = Colors.green;
                case 'error':
                  directionColor = Colors.red;
                case 'warning':
                  directionColor = Colors.orange;
                default:
                  directionColor = Colors.grey;
              }

              final displayMessage = entry.message.length > 200
                  ? '${entry.message.substring(0, 200)}...'
                  : entry.message;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$timeStr ',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      TextSpan(
                        text: '[${entry.direction}] ',
                        style: TextStyle(
                          color: directionColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextSpan(text: displayMessage),
                    ],
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Helper to build a labeled debug section.
  Widget _debugSection(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value.isEmpty ? '(empty)' : value,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ],
    );
  }
}
