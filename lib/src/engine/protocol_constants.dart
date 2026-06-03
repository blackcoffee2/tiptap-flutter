// Constants for the engine communication protocol.
//
// These mirror the wire contract defined in the engine's TypeScript protocol
// types. Every string here corresponds to a field name, command name, event
// name, message type, content format, or error code that crosses the bridge
// between the Flutter port and the Tiptap engine.
//
// The values in this file are authoritative against the engine source: they
// match the keys the engine reads off incoming commands and writes onto
// outgoing responses and events. When the engine protocol changes, this is
// the single file to reconcile.
//
// These classes are pure namespaces. They are declared abstract with a private
// constructor so they cannot be instantiated or extended — they exist only to
// group related string constants under a typed name.

/// Top-level message-class discriminant values, carried in the `type` field
/// of every message that flows across the bridge.
///
/// This is the coarse discriminant. The finer discriminant — which specific
/// command or event a message is — lives in the `name` field (see
/// [ProtocolKey.name]). A message with `type: "event"` and `name: "ready"`
/// is the ready event.
abstract class MessageType {
  MessageType._();

  /// A request from the port to the engine. Carries an `id` for correlation.
  static const String command = 'command';

  /// A reply from the engine correlated to a command by `id`.
  static const String response = 'response';

  /// An asynchronous push from the engine that is not a reply to any command.
  static const String event = 'event';
}

/// Internal bridge-handshake message types injected by the port's own WebView
/// bootstrap script — NOT part of the engine protocol.
///
/// The engine never sends these. They are emitted by the adapter/poll script
/// the bridge injects into the page to report when the JS adapter is wired up
/// and when (or whether) the `TiptapEngine` global becomes available. They are
/// deliberately separated from [MessageType] so a future port author reading
/// the protocol contract does not mistake them for engine-originated messages.
abstract class BridgeInternalMessage {
  BridgeInternalMessage._();

  /// The injected adapter script finished wiring up message forwarding.
  static const String bridgeAdapterReady = 'bridgeAdapterReady';

  /// The `TiptapEngine` global was found and `handleCommand` exists.
  static const String engineGlobalReady = 'engineGlobalReady';

  /// Polling for the `TiptapEngine` global exhausted its attempts.
  static const String engineGlobalTimeout = 'engineGlobalTimeout';
}

/// Command names sent in the `name` field of a command message.
///
/// These are the bridge-level commands the engine's central dispatcher
/// switches on. They are a fixed, engine-defined set — distinct from the
/// editor command names passed through [CommandName.exec] (see
/// [EditorCommand]), which are arbitrary Tiptap command strings the engine
/// forwards to the editor's command chain.
abstract class CommandName {
  CommandName._();

  // Lifecycle.
  static const String init = 'init';
  static const String destroy = 'destroy';
  static const String setEditable = 'setEditable';

  // Content.
  static const String setContent = 'setContent';
  static const String getContent = 'getContent';
  static const String insertContentAt = 'insertContentAt';

  // Text input.
  static const String insertText = 'insertText';
  static const String deleteRange = 'deleteRange';
  static const String backspace = 'backspace';
  static const String enter = 'enter';

  // Generic execution. The actual editor command travels in the payload's
  // `command` field; see [EditorCommand].
  static const String exec = 'exec';

  // Selection.
  static const String setTextSelection = 'setTextSelection';
  static const String setNodeSelection = 'setNodeSelection';
  static const String selectAll = 'selectAll';
  static const String focus = 'focus';
  static const String blur = 'blur';

  // Query.
  static const String getState = 'getState';
  static const String isActive = 'isActive';
  static const String canExec = 'canExec';
  static const String getAttributes = 'getAttributes';
}

/// Event names carried in the `name` field of an event message.
///
/// The engine pushes these asynchronously. [stateChanged] is the primary
/// full-state event; [contentChanged] and [selectionChanged] are the lighter
/// partial events the bridge merges into cached state.
abstract class EventName {
  EventName._();

  /// Full schema introspection, emitted once after init and before [ready].
  static const String schemaReady = 'schemaReady';

  /// Emitted once after [schemaReady]; the engine is operational.
  static const String ready = 'ready';

  /// Full editor state, emitted after every transaction.
  static const String stateChanged = 'stateChanged';

  /// Document-only change. Carries `doc`; omits selection and command state.
  static const String contentChanged = 'contentChanged';

  /// Selection-only change. Carries selection, active marks/nodes, and
  /// command states; omits the document tree and stored marks.
  static const String selectionChanged = 'selectionChanged';

  /// An engine error, optionally correlated to a command via `commandId`.
  static const String error = 'error';

  /// A passthrough event emitted by an extension; the engine does not
  /// interpret it.
  static const String extensionEvent = 'extensionEvent';
}

/// JSON field keys used across every message on the wire.
///
/// Grouped only by comment for readability; all are flat string constants so
/// a single key shared by multiple message shapes (for example [name], which
/// holds both a command name and an event name depending on [type], or
/// [content], which appears in both `setContent` payloads and `getContent`
/// results) is declared exactly once.
abstract class ProtocolKey {
  ProtocolKey._();

  // Message envelope.
  static const String type = 'type';
  static const String id = 'id';

  /// Dual-purpose: the command name on a command message and the event name
  /// on an event message. The [type] field disambiguates which.
  static const String name = 'name';
  static const String payload = 'payload';
  static const String success = 'success';
  static const String error = 'error';

  // Error body (also the shape of an error event's payload).
  static const String code = 'code';
  static const String message = 'message';
  static const String commandId = 'commandId';

  // Command payload fields.
  static const String content = 'content';
  static const String editable = 'editable';
  static const String emitUpdate = 'emitUpdate';
  static const String format = 'format';
  static const String position = 'position';
  static const String text = 'text';
  static const String range = 'range';
  static const String command = 'command';
  static const String args = 'args';
  static const String anchor = 'anchor';
  static const String head = 'head';
  static const String attrs = 'attrs';

  // Range sub-object keys (the {from, to} map built for ranges/selections).
  static const String from = 'from';
  static const String to = 'to';

  // Query-result payload fields.
  // `content` (reused above) holds getContent's result.
  static const String active = 'active';
  static const String canExec = 'canExec';
  // `attrs` (reused above) holds getAttributes' result.
  static const String executed = 'executed';

  // State payload fields.
  static const String doc = 'doc';
  static const String selection = 'selection';
  static const String activeMarks = 'activeMarks';
  static const String activeNodes = 'activeNodes';
  static const String commandStates = 'commandStates';
  static const String decorations = 'decorations';
  static const String storedMarks = 'storedMarks';

  // Selection sub-object fields.
  static const String selectionType = 'type';
  static const String empty = 'empty';

  // Command-state sub-object fields.
  static const String isActive = 'isActive';
  static const String depth = 'depth';

  // Extension-event payload fields.
  static const String extensionName = 'extensionName';
  static const String eventName = 'eventName';
  static const String data = 'data';
}

/// Values for the `format` field of a `getContent` command.
///
/// The engine returns the result in the `content` key of the response
/// payload, where the runtime shape is discriminated by this format: a String
/// for [html] and [text], a JSON object for [json].
abstract class ContentFormat {
  ContentFormat._();

  static const String json = 'json';
  static const String html = 'html';
  static const String text = 'text';
}

/// Editor command names passed through [CommandName.exec] in the payload's
/// `command` field.
///
/// Unlike [CommandName], this is NOT an exhaustive or gating set. The engine
/// forwards any string here to the editor's command chain, so ports and apps
/// may call commands not listed here. These constants cover the commands the
/// current StarterKit + Image build exposes and the toolbar uses; they exist
/// as a convenience to replace bare literals, not as a restriction on what
/// `exec` accepts.
abstract class EditorCommand {
  EditorCommand._();

  // Formatting marks.
  static const String toggleBold = 'toggleBold';
  static const String toggleItalic = 'toggleItalic';
  static const String toggleStrike = 'toggleStrike';
  static const String toggleCode = 'toggleCode';

  // Block types.
  static const String toggleHeading = 'toggleHeading';
  static const String toggleCodeBlock = 'toggleCodeBlock';
  static const String toggleBlockquote = 'toggleBlockquote';

  // Lists.
  static const String toggleBulletList = 'toggleBulletList';
  static const String toggleOrderedList = 'toggleOrderedList';

  // Inserts.
  static const String setHorizontalRule = 'setHorizontalRule';
  static const String setImage = 'setImage';

  // History.
  static const String undo = 'undo';
  static const String redo = 'redo';
}

/// Machine-readable error codes the engine emits in the `code` field of error
/// responses and error events.
///
/// This is the fixed set defined by the engine's command dispatcher and
/// guards. App code may branch on these instead of matching message strings.
abstract class ErrorCode {
  ErrorCode._();

  /// A command was sent before init or after destroy.
  static const String notInitialized = 'NOT_INITIALIZED';

  /// An init command arrived while the engine was already running.
  static const String alreadyInitialized = 'ALREADY_INITIALIZED';

  /// The top-level command name was not recognized by the dispatcher.
  static const String unknownCommand = 'UNKNOWN_COMMAND';

  /// The command passed to `exec` does not exist on the editor.
  static const String unknownExecCommand = 'UNKNOWN_EXEC_COMMAND';

  /// An unknown format was passed to `getContent`.
  static const String invalidFormat = 'INVALID_FORMAT';

  /// A command threw during execution.
  static const String commandFailed = 'COMMAND_FAILED';
}
