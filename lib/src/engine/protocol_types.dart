// Protocol types for communication between the Flutter port and the Tiptap engine.
//
// These are simple data classes that mirror the TypeScript protocol types
// defined in the tiptap-engine package. They use hand-written fromJson
// factory constructors rather than code generation, keeping the project
// dependency-free and straightforward.
//
// The types here cover the full engine API surface as documented in the
// API reference, including schema introspection, editor state, selection,
// command states, marks, and error payloads.

// =============================================================================
// Marks
// =============================================================================

/// Represents a mark applied to a text node (e.g., bold, italic, link).
///
/// Marks carry a [type] identifier and an optional [attrs] map for
/// parameterized marks like links (which have an href attribute).
class MarkData {
  final String type;
  final Map<String, dynamic>? attrs;

  const MarkData({required this.type, this.attrs});

  factory MarkData.fromJson(Map<String, dynamic> json) {
    return MarkData(
      type: json['type'] as String,
      attrs: json['attrs'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'type': type, if (attrs != null) 'attrs': attrs};
  }

  @override
  String toString() => 'MarkData(type: $type, attrs: $attrs)';
}

// =============================================================================
// Annotated Document Tree
// =============================================================================

/// Represents a node in the annotated document tree emitted by the engine.
///
/// Every node carries [pos] and [end] position offsets that map the node's
/// location in the ProseMirror document model. These offsets are critical
/// for mapping pixel coordinates (from tap events) back to document positions
/// for selection and editing.
///
/// Position rules (from the engine API):
///   - For block nodes: [pos] is after the opening token, [end] is after the
///     closing token.
///   - For text nodes: [pos] is the first character, [end] - [pos] equals the
///     text length.
///   - The document node starts at pos: 0.
///   - A child's [pos] equals its parent's pos + 1 (for the first child of a
///     block node).
///
/// The [content] list holds child nodes, forming a tree. Leaf text nodes
/// have a [text] field instead of children. Marks on text nodes appear in
/// the [marks] list.
class AnnotatedNode {
  /// The ProseMirror node type identifier (e.g., "paragraph", "heading", "text").
  final String type;

  /// The resolved start position of this node in the document.
  final int? pos;

  /// The resolved end position of this node in the document.
  final int? end;

  /// Child nodes. Empty for leaf nodes like text.
  final List<AnnotatedNode>? content;

  /// The text content, present only on text nodes.
  final String? text;

  /// Marks applied to this node (bold, italic, link, etc.).
  final List<MarkData>? marks;

  /// Node-specific attributes (e.g., level for headings, src for images).
  final Map<String, dynamic>? attrs;

  const AnnotatedNode({
    required this.type,
    this.pos,
    this.end,
    this.content,
    this.text,
    this.marks,
    this.attrs,
  });

  factory AnnotatedNode.fromJson(Map<String, dynamic> json) {
    return AnnotatedNode(
      type: json['type'] as String,
      pos: json['pos'] as int?,
      end: json['end'] as int?,
      content: (json['content'] as List<dynamic>?)
          ?.map((item) => AnnotatedNode.fromJson(item as Map<String, dynamic>))
          .toList(),
      text: json['text'] as String?,
      marks: (json['marks'] as List<dynamic>?)
          ?.map((item) => MarkData.fromJson(item as Map<String, dynamic>))
          .toList(),
      attrs: json['attrs'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (pos != null) 'pos': pos,
      if (end != null) 'end': end,
      if (content != null)
        'content': content!.map((node) => node.toJson()).toList(),
      if (text != null) 'text': text,
      if (marks != null) 'marks': marks!.map((mark) => mark.toJson()).toList(),
      if (attrs != null) 'attrs': attrs,
    };
  }

  @override
  String toString() => 'AnnotatedNode(type: $type, pos: $pos, end: $end)';
}

// =============================================================================
// Selection
// =============================================================================

/// Represents the current selection state in the ProseMirror document.
///
/// ProseMirror selections have an [anchor] (where the user started selecting)
/// and a [head] (where the selection ends). The [from] and [to] fields are
/// the normalized (min/max) versions — [from] is always <= [to].
/// [empty] is true when anchor == head (i.e., a cursor with no range).
///
/// Selection types from the engine:
///   - "text": a standard text selection (cursor or range)
///   - "node": an entire node is selected (e.g., an image)
///   - "all": the entire document is selected
///   - "gapcursor": a cursor in a position between nodes where text can't exist
class SelectionState {
  /// The selection type (e.g., "text", "node", "all", "gapcursor").
  final String? type;

  /// The anchor position — where the selection was initiated.
  final int anchor;

  /// The head position — where the selection currently ends.
  final int head;

  /// The lower bound of the selection range (min of anchor, head).
  final int from;

  /// The upper bound of the selection range (max of anchor, head).
  final int to;

  /// Whether the selection is collapsed (cursor only, no range).
  final bool empty;

  const SelectionState({
    this.type,
    required this.anchor,
    required this.head,
    required this.from,
    required this.to,
    required this.empty,
  });

  factory SelectionState.fromJson(Map<String, dynamic> json) {
    return SelectionState(
      type: json['type'] as String?,
      anchor: json['anchor'] as int,
      head: json['head'] as int,
      from: json['from'] as int,
      to: json['to'] as int,
      empty: json['empty'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (type != null) 'type': type,
      'anchor': anchor,
      'head': head,
      'from': from,
      'to': to,
      'empty': empty,
    };
  }

  @override
  String toString() =>
      'SelectionState(type: $type, anchor: $anchor, head: $head, '
      'from: $from, to: $to, empty: $empty)';
}

// =============================================================================
// Command State
// =============================================================================

/// Represents the state of a single editor command.
///
/// The engine reports this for every registered command on each state change,
/// allowing the UI to enable/disable toolbar buttons and show active states
/// (e.g., the bold button appears pressed when the cursor is inside bold text).
class CommandState {
  /// Whether the command can currently be executed given the document state.
  final bool canExec;

  /// Whether the command's associated mark or node is active at the current selection.
  final bool isActive;

  /// The nesting depth, relevant for undo/redo commands. Indicates how many
  /// steps are available in the history stack.
  final int? depth;

  const CommandState({
    required this.canExec,
    required this.isActive,
    this.depth,
  });

  factory CommandState.fromJson(Map<String, dynamic> json) {
    return CommandState(
      canExec: json['canExec'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? false,
      depth: json['depth'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'canExec': canExec,
      'isActive': isActive,
      if (depth != null) 'depth': depth,
    };
  }

  @override
  String toString() =>
      'CommandState(canExec: $canExec, isActive: $isActive, depth: $depth)';
}

// =============================================================================
// Active Node
// =============================================================================

/// Represents a node type that is active at the current selection.
///
/// The engine reports this as part of the stateChanged event. For example,
/// when the cursor is inside a heading, `activeNodes` will contain an entry
/// with type "heading" and attrs { "level": 2 }. This enables the toolbar
/// to show which block type is currently active.
class ActiveNode {
  /// The node type name (e.g., "paragraph", "heading", "blockquote").
  final String type;

  /// The node's attributes at this position (e.g., { "level": 2 } for headings).
  final Map<String, dynamic> attrs;

  const ActiveNode({required this.type, this.attrs = const {}});

  factory ActiveNode.fromJson(Map<String, dynamic> json) {
    return ActiveNode(
      type: json['type'] as String,
      attrs: json['attrs'] as Map<String, dynamic>? ?? const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {'type': type, 'attrs': attrs};
  }

  @override
  String toString() => 'ActiveNode(type: $type, attrs: $attrs)';
}

// =============================================================================
// Schema Introspection Types
// =============================================================================

/// Metadata about a single attribute on a node or mark type.
///
/// Emitted as part of schemaReady to describe the configurable attributes
/// of each node and mark type in the schema.
class SchemaAttrInfo {
  /// The attribute name (e.g., "level", "href", "src").
  final String name;

  /// The default value for this attribute, or null if no default is specified.
  final dynamic defaultValue;

  const SchemaAttrInfo({required this.name, this.defaultValue});

  factory SchemaAttrInfo.fromJson(Map<String, dynamic> json) {
    return SchemaAttrInfo(
      name: json['name'] as String,
      defaultValue: json['default'],
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'default': defaultValue};
  }

  @override
  String toString() => 'SchemaAttrInfo(name: $name, default: $defaultValue)';
}

/// Metadata about a node type in the ProseMirror schema.
///
/// Emitted once during initialization as part of the schemaReady event.
/// Describes the structural properties of each node type, enabling the
/// port to dynamically discover what the editor supports.
class SchemaNodeInfo {
  /// The node type name (e.g., "paragraph", "heading", "image").
  final String name;

  /// The ProseMirror content expression defining what children this node
  /// can contain (e.g., "inline*", "block+", "text*").
  final String? contentExpression;

  /// The group this node type belongs to (e.g., "block", "inline").
  final String? group;

  /// The attribute definitions for this node type.
  final List<SchemaAttrInfo> attrs;

  /// Whether this is a leaf node (has no editable content).
  final bool isLeaf;

  /// Whether this is an inline node.
  final bool isInline;

  /// Whether this is a block-level node.
  final bool isBlock;

  const SchemaNodeInfo({
    required this.name,
    this.contentExpression,
    this.group,
    this.attrs = const [],
    this.isLeaf = false,
    this.isInline = false,
    this.isBlock = false,
  });

  factory SchemaNodeInfo.fromJson(Map<String, dynamic> json) {
    return SchemaNodeInfo(
      name: json['name'] as String,
      contentExpression: json['contentExpression'] as String?,
      group: json['group'] as String?,
      attrs:
          (json['attrs'] as List<dynamic>?)
              ?.map(
                (item) => SchemaAttrInfo.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      isLeaf: json['isLeaf'] as bool? ?? false,
      isInline: json['isInline'] as bool? ?? false,
      isBlock: json['isBlock'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (contentExpression != null) 'contentExpression': contentExpression,
      if (group != null) 'group': group,
      'attrs': attrs.map((a) => a.toJson()).toList(),
      'isLeaf': isLeaf,
      'isInline': isInline,
      'isBlock': isBlock,
    };
  }

  @override
  String toString() => 'SchemaNodeInfo(name: $name, group: $group)';
}

/// Metadata about a mark type in the ProseMirror schema.
///
/// Emitted as part of schemaReady. Marks are inline annotations applied
/// to text (bold, italic, link, etc.).
class SchemaMarkInfo {
  /// The mark type name (e.g., "bold", "italic", "link").
  final String name;

  /// The attribute definitions for this mark type.
  /// Simple marks like bold have no attributes.
  /// Parameterized marks like link have attributes such as href and target.
  final List<SchemaAttrInfo> attrs;

  const SchemaMarkInfo({required this.name, this.attrs = const []});

  factory SchemaMarkInfo.fromJson(Map<String, dynamic> json) {
    return SchemaMarkInfo(
      name: json['name'] as String,
      attrs:
          (json['attrs'] as List<dynamic>?)
              ?.map(
                (item) => SchemaAttrInfo.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'attrs': attrs.map((a) => a.toJson()).toList()};
  }

  @override
  String toString() => 'SchemaMarkInfo(name: $name, attrs: ${attrs.length})';
}

/// Metadata about a command available on the editor.
///
/// Emitted as part of schemaReady. Each command entry describes the command's
/// purpose, what type of action it performs, and what arguments it accepts.
/// This enables the port to dynamically build toolbars and menus without
/// hardcoding knowledge of specific extensions.
///
/// Command types:
///   - "toggle-mark": toggles an inline mark on/off (e.g., toggleBold)
///   - "toggle-node": toggles a block node type (e.g., toggleBlockquote)
///   - "set-node": sets a block node type without toggle (e.g., setHeading)
///   - "wrap": wraps selection in a node (e.g., wrapInBlockquote)
///   - "lift": lifts content out of a wrapping node
///   - "action": one-shot action (e.g., undo, insertTable)
class SchemaCommandInfo {
  /// The command name as used in exec (e.g., "toggleBold", "setHeading").
  final String name;

  /// The command type indicating what kind of action this performs.
  final String? type;

  /// The associated node or mark type name (e.g., "bold" for toggleBold,
  /// "heading" for setHeading).
  final String? associatedType;

  /// The arguments this command accepts, with their names and whether
  /// they are required.
  final List<SchemaCommandArg> args;

  /// The logical group this command belongs to (e.g., "formatting", "blocks",
  /// "lists", "tables", "history").
  final String? group;

  /// The name of the Tiptap extension that provides this command.
  final String? extensionName;

  const SchemaCommandInfo({
    required this.name,
    this.type,
    this.associatedType,
    this.args = const [],
    this.group,
    this.extensionName,
  });

  factory SchemaCommandInfo.fromJson(Map<String, dynamic> json) {
    return SchemaCommandInfo(
      name: json['name'] as String,
      type: json['type'] as String?,
      associatedType: json['associatedType'] as String?,
      args:
          (json['args'] as List<dynamic>?)
              ?.map(
                (item) =>
                    SchemaCommandArg.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      group: json['group'] as String?,
      extensionName: json['extensionName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (type != null) 'type': type,
      if (associatedType != null) 'associatedType': associatedType,
      'args': args.map((a) => a.toJson()).toList(),
      if (group != null) 'group': group,
      if (extensionName != null) 'extensionName': extensionName,
    };
  }

  @override
  String toString() =>
      'SchemaCommandInfo(name: $name, type: $type, group: $group)';
}

/// Describes a single argument accepted by a command.
class SchemaCommandArg {
  /// The argument name (e.g., "level", "rows", "cols").
  final String name;

  /// Whether this argument is required for the command to execute.
  final bool required;

  const SchemaCommandArg({required this.name, this.required = false});

  factory SchemaCommandArg.fromJson(Map<String, dynamic> json) {
    return SchemaCommandArg(
      name: json['name'] as String,
      required: json['required'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'required': required};
  }

  @override
  String toString() => 'SchemaCommandArg(name: $name, required: $required)';
}

/// Full schema metadata emitted by the engine during initialization.
///
/// Contains information about all registered node types, mark types,
/// and available commands. This is used to build dynamic toolbars and
/// to understand the document structure without hardcoded assumptions.
///
/// The engine sends arrays for nodes, marks, and commands (not maps).
/// Each entry is a self-describing object with a "name" field.
class SchemaMetadata {
  /// All registered node types (paragraph, heading, image, etc.).
  final List<SchemaNodeInfo> nodes;

  /// All registered mark types (bold, italic, link, etc.).
  final List<SchemaMarkInfo> marks;

  /// All available commands discovered from the editor instance.
  final List<SchemaCommandInfo> commands;

  const SchemaMetadata({
    required this.nodes,
    required this.marks,
    required this.commands,
  });

  factory SchemaMetadata.fromJson(Map<String, dynamic> json) {
    final nodesJson = json['nodes'] as List<dynamic>? ?? [];
    final marksJson = json['marks'] as List<dynamic>? ?? [];
    final commandsJson = json['commands'] as List<dynamic>? ?? [];

    return SchemaMetadata(
      nodes: nodesJson
          .map((item) => SchemaNodeInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
      marks: marksJson
          .map((item) => SchemaMarkInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
      commands: commandsJson
          .map(
            (item) => SchemaCommandInfo.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  /// Look up a node type by name. Returns null if not found.
  SchemaNodeInfo? findNode(String name) {
    for (final node in nodes) {
      if (node.name == name) return node;
    }
    return null;
  }

  /// Look up a mark type by name. Returns null if not found.
  SchemaMarkInfo? findMark(String name) {
    for (final mark in marks) {
      if (mark.name == name) return mark;
    }
    return null;
  }

  /// Look up a command by name. Returns null if not found.
  SchemaCommandInfo? findCommand(String name) {
    for (final command in commands) {
      if (command.name == name) return command;
    }
    return null;
  }

  @override
  String toString() =>
      'SchemaMetadata(nodes: ${nodes.length}, marks: ${marks.length}, '
      'commands: ${commands.length})';
}

// =============================================================================
// Editor State Payload
// =============================================================================

/// The full state payload emitted by the engine on every transaction.
///
/// This is the primary data structure that flows from the engine to the port
/// on every state change. It contains everything needed to render the document
/// and update the toolbar UI.
class EditorStatePayload {
  /// The annotated document tree with position offsets on every node.
  final AnnotatedNode? doc;

  /// The current selection state.
  final SelectionState? selection;

  /// List of mark type names that are active at the current selection.
  final List<String> activeMarks;

  /// List of node types that are active at the current selection,
  /// with their attributes. For example, when inside a level-2 heading,
  /// this contains ActiveNode(type: "heading", attrs: { "level": 2 }).
  final List<ActiveNode> activeNodes;

  /// Map of command names to their current states (canExec, isActive).
  final Map<String, CommandState> commandStates;

  /// Active decorations in the document. The structure depends on the
  /// extensions that provide decorations. Stored as raw JSON for now
  /// since decoration types are extension-specific.
  final List<dynamic> decorations;

  /// Marks that have been stored via storedMarks (e.g., when the user
  /// toggles bold with an empty selection, the mark is "stored" and will
  /// be applied to the next typed character).
  final List<MarkData> storedMarks;

  /// Whether the editor is currently in editable mode.
  final bool editable;

  const EditorStatePayload({
    this.doc,
    this.selection,
    this.activeMarks = const [],
    this.activeNodes = const [],
    this.commandStates = const {},
    this.decorations = const [],
    this.storedMarks = const [],
    this.editable = true,
  });

  factory EditorStatePayload.fromJson(Map<String, dynamic> json) {
    final docJson = json['doc'] as Map<String, dynamic>?;
    final selectionJson = json['selection'] as Map<String, dynamic>?;
    final activeMarksJson = json['activeMarks'] as List<dynamic>? ?? [];
    final activeNodesJson = json['activeNodes'] as List<dynamic>? ?? [];
    final commandStatesJson =
        json['commandStates'] as Map<String, dynamic>? ?? {};
    final decorationsJson = json['decorations'] as List<dynamic>? ?? [];
    final storedMarksJson = json['storedMarks'] as List<dynamic>? ?? [];

    return EditorStatePayload(
      doc: docJson != null ? AnnotatedNode.fromJson(docJson) : null,
      selection: selectionJson != null
          ? SelectionState.fromJson(selectionJson)
          : null,
      activeMarks: activeMarksJson.cast<String>(),
      activeNodes: activeNodesJson
          .map((item) => ActiveNode.fromJson(item as Map<String, dynamic>))
          .toList(),
      commandStates: commandStatesJson.map(
        (key, value) =>
            MapEntry(key, CommandState.fromJson(value as Map<String, dynamic>)),
      ),
      decorations: decorationsJson,
      storedMarks: storedMarksJson
          .map((item) => MarkData.fromJson(item as Map<String, dynamic>))
          .toList(),
      editable: json['editable'] as bool? ?? true,
    );
  }

  @override
  String toString() =>
      'EditorStatePayload(doc: ${doc?.type}, selection: $selection, '
      'activeMarks: $activeMarks, activeNodes: ${activeNodes.length}, '
      'commands: ${commandStates.length}, editable: $editable)';
}

// =============================================================================
// Error Payload
// =============================================================================

/// Structured error information returned by the engine.
///
/// Used both in error responses (when a command fails) and in error events
/// (when the engine encounters an asynchronous error).
///
/// Error codes:
///   - NOT_INITIALIZED: command sent before init or after destroy
///   - ALREADY_INITIALIZED: init sent when engine is already running
///   - UNKNOWN_COMMAND: unrecognized command name
///   - UNKNOWN_EXEC_COMMAND: the command passed to exec doesn't exist
///   - INVALID_FORMAT: unknown format in getContent
///   - COMMAND_FAILED: the command threw an exception during execution
class ErrorPayload {
  /// A machine-readable error code (e.g., "NOT_INITIALIZED", "COMMAND_FAILED").
  final String code;

  /// A human-readable error description.
  final String message;

  /// The command ID that caused this error, if applicable.
  /// Present in error events but not in error responses (which are already
  /// correlated by the response ID).
  final String? commandId;

  const ErrorPayload({
    required this.code,
    required this.message,
    this.commandId,
  });

  factory ErrorPayload.fromJson(Map<String, dynamic> json) {
    return ErrorPayload(
      code: json['code'] as String? ?? 'UNKNOWN',
      message: json['message'] as String? ?? 'Unknown error',
      commandId: json['commandId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      if (commandId != null) 'commandId': commandId,
    };
  }

  @override
  String toString() =>
      'ErrorPayload(code: $code, message: $message, commandId: $commandId)';
}

// =============================================================================
// Extension Event
// =============================================================================

/// A generic event emitted by a Tiptap extension.
///
/// The engine does not interpret these — it passes them through as-is.
/// Extensions use this mechanism to communicate with the port for things
/// like mention suggestions, slash commands, or collaborative editing events.
class ExtensionEvent {
  /// The name of the extension that emitted this event.
  final String extensionName;

  /// The event name within the extension's namespace.
  final String eventName;

  /// The event-specific payload. Structure depends on the extension.
  final Map<String, dynamic> data;

  const ExtensionEvent({
    required this.extensionName,
    required this.eventName,
    this.data = const {},
  });

  factory ExtensionEvent.fromJson(Map<String, dynamic> json) {
    return ExtensionEvent(
      extensionName: json['extensionName'] as String? ?? '',
      eventName: json['eventName'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>? ?? const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'extensionName': extensionName,
      'eventName': eventName,
      'data': data,
    };
  }

  @override
  String toString() =>
      'ExtensionEvent(extension: $extensionName, event: $eventName)';
}
