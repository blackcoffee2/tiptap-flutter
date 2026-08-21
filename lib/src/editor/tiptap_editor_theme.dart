// Visual theming for the Tiptap editor: text styles and colors for every
// node the renderer draws, plus the caret and selection highlight.
//
// The renderer builds RichText directly, and RichText — unlike Text — does
// not inherit DefaultTextStyle. Nothing about the document's appearance can
// therefore follow the app's theme implicitly; the renderer has to read a
// theme explicitly and pass resolved styles into the span builder. This file
// is that theme.
//
// Three types cooperate:
//
//   - [TiptapEditorTheme] is the configuration surface. Every field is
//     nullable; a null means "derive from the Material theme". It is a
//     ThemeExtension so an app can register light and dark variants once in
//     ThemeData.extensions, and it can also be passed per-instance through
//     TiptapEditor.theme for a single screen that deviates.
//
//   - [TiptapEditorThemeData] is the fully resolved, non-null result the
//     renderer consumes. It is produced by [TiptapEditorThemeData.resolve],
//     which layers: widget override → ThemeData extension → values derived
//     from ColorScheme/TextTheme. With no configuration at all, the derived
//     values give a correct dark mode (text follows onSurface, caret and
//     links follow primary, code and placeholder backgrounds follow the
//     surface containers).
//
//   - [TiptapEditorThemeScope] is the inherited widget the document renderer
//     places above the node tree so every builder — default or app-supplied
//     — can read the resolved data through [TiptapEditorThemeData.of].
//
// Heading sizes and block spacing are deliberately not part of the theme:
// they are layout metrics derived from the base style, and live as internal
// tables in the node builders. The theme is about color and typographic
// identity; anyone needing different heading metrics is in custom-builder
// territory.

import 'package:flutter/material.dart';

/// User-facing theme configuration for the Tiptap editor.
///
/// All fields are optional. A null field is resolved from the ambient
/// Material theme by [TiptapEditorThemeData.resolve]. Text-style fields are
/// merged over the derived default, so a partial style such as
/// `TextStyle(color: Colors.white)` overrides only the color and keeps the
/// derived size, height, and font family.
///
/// Supply it either globally:
///
///   ThemeData(extensions: [TiptapEditorTheme(linkColor: Colors.teal)])
///
/// or per editor:
///
///   TiptapEditor(controller: c, theme: TiptapEditorTheme(...))
///
/// where the per-editor value takes precedence field by field.
class TiptapEditorTheme extends ThemeExtension<TiptapEditorTheme> {
  /// Style for body text; headings derive from it. Merged over the Material
  /// default (textTheme.bodyLarge with the editor's fixed size and line
  /// height, colored onSurface).
  final TextStyle? baseTextStyle;

  /// Text and underline color of link marks.
  final Color? linkColor;

  /// Background behind inline `code` marks.
  final Color? inlineCodeBackgroundColor;

  /// Background of code blocks.
  final Color? codeBlockBackgroundColor;

  /// Style of code-block text. Merged over a monospace default.
  final TextStyle? codeBlockTextStyle;

  /// Color of the language label shown above a code block's content.
  final Color? codeBlockLabelColor;

  /// Color of the vertical rule on the left of a blockquote.
  final Color? blockquoteBorderColor;

  /// Color of horizontal rules.
  final Color? dividerColor;

  /// Background of image and unknown-node placeholders.
  final Color? placeholderBackgroundColor;

  /// Text color inside placeholders.
  final Color? placeholderForegroundColor;

  /// Color of image captions (the image node's title attribute).
  final Color? captionColor;

  /// Caret color. Falls back to TextSelectionTheme.cursorColor, then
  /// colorScheme.primary.
  final Color? cursorColor;

  /// Selection highlight color. Falls back to
  /// TextSelectionTheme.selectionColor, then primary at low alpha.
  final Color? selectionColor;

  const TiptapEditorTheme({
    this.baseTextStyle,
    this.linkColor,
    this.inlineCodeBackgroundColor,
    this.codeBlockBackgroundColor,
    this.codeBlockTextStyle,
    this.codeBlockLabelColor,
    this.blockquoteBorderColor,
    this.dividerColor,
    this.placeholderBackgroundColor,
    this.placeholderForegroundColor,
    this.captionColor,
    this.cursorColor,
    this.selectionColor,
  });

  @override
  TiptapEditorTheme copyWith({
    TextStyle? baseTextStyle,
    Color? linkColor,
    Color? inlineCodeBackgroundColor,
    Color? codeBlockBackgroundColor,
    TextStyle? codeBlockTextStyle,
    Color? codeBlockLabelColor,
    Color? blockquoteBorderColor,
    Color? dividerColor,
    Color? placeholderBackgroundColor,
    Color? placeholderForegroundColor,
    Color? captionColor,
    Color? cursorColor,
    Color? selectionColor,
  }) {
    return TiptapEditorTheme(
      baseTextStyle: baseTextStyle ?? this.baseTextStyle,
      linkColor: linkColor ?? this.linkColor,
      inlineCodeBackgroundColor:
          inlineCodeBackgroundColor ?? this.inlineCodeBackgroundColor,
      codeBlockBackgroundColor:
          codeBlockBackgroundColor ?? this.codeBlockBackgroundColor,
      codeBlockTextStyle: codeBlockTextStyle ?? this.codeBlockTextStyle,
      codeBlockLabelColor: codeBlockLabelColor ?? this.codeBlockLabelColor,
      blockquoteBorderColor:
          blockquoteBorderColor ?? this.blockquoteBorderColor,
      dividerColor: dividerColor ?? this.dividerColor,
      placeholderBackgroundColor:
          placeholderBackgroundColor ?? this.placeholderBackgroundColor,
      placeholderForegroundColor:
          placeholderForegroundColor ?? this.placeholderForegroundColor,
      captionColor: captionColor ?? this.captionColor,
      cursorColor: cursorColor ?? this.cursorColor,
      selectionColor: selectionColor ?? this.selectionColor,
    );
  }

  /// Layer [other] over this theme: every non-null field of [other] wins.
  /// Used to apply a per-editor override on top of the ThemeData extension.
  TiptapEditorTheme merge(TiptapEditorTheme? other) {
    if (other == null) return this;
    return copyWith(
      baseTextStyle: other.baseTextStyle,
      linkColor: other.linkColor,
      inlineCodeBackgroundColor: other.inlineCodeBackgroundColor,
      codeBlockBackgroundColor: other.codeBlockBackgroundColor,
      codeBlockTextStyle: other.codeBlockTextStyle,
      codeBlockLabelColor: other.codeBlockLabelColor,
      blockquoteBorderColor: other.blockquoteBorderColor,
      dividerColor: other.dividerColor,
      placeholderBackgroundColor: other.placeholderBackgroundColor,
      placeholderForegroundColor: other.placeholderForegroundColor,
      captionColor: other.captionColor,
      cursorColor: other.cursorColor,
      selectionColor: other.selectionColor,
    );
  }

  /// Interpolate for theme animations (e.g. an animated light/dark switch).
  /// Color.lerp and TextStyle.lerp both tolerate nulls, so an unset field on
  /// either side interpolates toward unset, which then resolves from the
  /// Material theme at that point of the animation.
  @override
  TiptapEditorTheme lerp(ThemeExtension<TiptapEditorTheme>? other, double t) {
    if (other is! TiptapEditorTheme) return this;
    return TiptapEditorTheme(
      baseTextStyle: TextStyle.lerp(baseTextStyle, other.baseTextStyle, t),
      linkColor: Color.lerp(linkColor, other.linkColor, t),
      inlineCodeBackgroundColor: Color.lerp(
        inlineCodeBackgroundColor,
        other.inlineCodeBackgroundColor,
        t,
      ),
      codeBlockBackgroundColor: Color.lerp(
        codeBlockBackgroundColor,
        other.codeBlockBackgroundColor,
        t,
      ),
      codeBlockTextStyle: TextStyle.lerp(
        codeBlockTextStyle,
        other.codeBlockTextStyle,
        t,
      ),
      codeBlockLabelColor: Color.lerp(
        codeBlockLabelColor,
        other.codeBlockLabelColor,
        t,
      ),
      blockquoteBorderColor: Color.lerp(
        blockquoteBorderColor,
        other.blockquoteBorderColor,
        t,
      ),
      dividerColor: Color.lerp(dividerColor, other.dividerColor, t),
      placeholderBackgroundColor: Color.lerp(
        placeholderBackgroundColor,
        other.placeholderBackgroundColor,
        t,
      ),
      placeholderForegroundColor: Color.lerp(
        placeholderForegroundColor,
        other.placeholderForegroundColor,
        t,
      ),
      captionColor: Color.lerp(captionColor, other.captionColor, t),
      cursorColor: Color.lerp(cursorColor, other.cursorColor, t),
      selectionColor: Color.lerp(selectionColor, other.selectionColor, t),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TiptapEditorTheme &&
        other.baseTextStyle == baseTextStyle &&
        other.linkColor == linkColor &&
        other.inlineCodeBackgroundColor == inlineCodeBackgroundColor &&
        other.codeBlockBackgroundColor == codeBlockBackgroundColor &&
        other.codeBlockTextStyle == codeBlockTextStyle &&
        other.codeBlockLabelColor == codeBlockLabelColor &&
        other.blockquoteBorderColor == blockquoteBorderColor &&
        other.dividerColor == dividerColor &&
        other.placeholderBackgroundColor == placeholderBackgroundColor &&
        other.placeholderForegroundColor == placeholderForegroundColor &&
        other.captionColor == captionColor &&
        other.cursorColor == cursorColor &&
        other.selectionColor == selectionColor;
  }

  @override
  int get hashCode => Object.hash(
    baseTextStyle,
    linkColor,
    inlineCodeBackgroundColor,
    codeBlockBackgroundColor,
    codeBlockTextStyle,
    codeBlockLabelColor,
    blockquoteBorderColor,
    dividerColor,
    placeholderBackgroundColor,
    placeholderForegroundColor,
    captionColor,
    cursorColor,
    selectionColor,
  );
}

/// The fully resolved theme the renderer and selection overlay consume.
///
/// Every field is non-null. Obtain one through [resolve] (at the editor root)
/// or [of] (inside the document tree, below a [TiptapEditorThemeScope]).
///
/// Value equality is implemented so the inherited scope can skip notifying
/// dependents when a rebuild resolves to identical values, which keeps
/// unrelated parent rebuilds from relaying out every text block.
class TiptapEditorThemeData {
  final TextStyle baseTextStyle;
  final Color linkColor;
  final Color inlineCodeBackgroundColor;
  final Color codeBlockBackgroundColor;
  final TextStyle codeBlockTextStyle;
  final Color codeBlockLabelColor;
  final Color blockquoteBorderColor;
  final Color dividerColor;
  final Color placeholderBackgroundColor;
  final Color placeholderForegroundColor;
  final Color captionColor;
  final Color cursorColor;
  final Color selectionColor;

  const TiptapEditorThemeData({
    required this.baseTextStyle,
    required this.linkColor,
    required this.inlineCodeBackgroundColor,
    required this.codeBlockBackgroundColor,
    required this.codeBlockTextStyle,
    required this.codeBlockLabelColor,
    required this.blockquoteBorderColor,
    required this.dividerColor,
    required this.placeholderBackgroundColor,
    required this.placeholderForegroundColor,
    required this.captionColor,
    required this.cursorColor,
    required this.selectionColor,
  });

  /// The editor's fixed body metrics. These are applied on top of the app's
  /// bodyLarge so the font family follows the app while the editor keeps a
  /// consistent reading size and line height across apps.
  static const double _bodyFontSize = 16;
  static const double _bodyLineHeight = 1.6;

  /// Resolve the effective theme for [context].
  ///
  /// Layering, lowest to highest precedence:
  ///   1. values derived from Theme.of(context) — ColorScheme, TextTheme,
  ///      and TextSelectionTheme;
  ///   2. the [TiptapEditorTheme] registered in ThemeData.extensions, if any;
  ///   3. [override], the per-editor theme passed to TiptapEditor.theme.
  ///
  /// Text styles from layers 2 and 3 are merged over the derived style rather
  /// than replacing it, so a caller can set just a color.
  static TiptapEditorThemeData resolve(
    BuildContext context, {
    TiptapEditorTheme? override,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectionTheme = TextSelectionTheme.of(context);

    final configured =
        (theme.extension<TiptapEditorTheme>() ?? const TiptapEditorTheme())
            .merge(override);

    final derivedBase = (theme.textTheme.bodyLarge ?? const TextStyle())
        .copyWith(
          fontSize: _bodyFontSize,
          height: _bodyLineHeight,
          color: scheme.onSurface,
        );

    final derivedCode = TextStyle(
      fontFamily: 'monospace',
      fontSize: 14,
      height: 1.5,
      color: scheme.onSurface,
    );

    /// The inline-code background is an alpha of the text color rather than
    /// a surface container so it reads as a subtle tint on any background,
    /// light or dark, without needing its own per-brightness value.
    final derivedInlineCodeBg = scheme.onSurface.withAlpha(0x1A);

    /// The selection default matches what Material's TextField uses when no
    /// TextSelectionTheme is set: primary at low alpha.
    final derivedSelection = scheme.primary.withAlpha(0x40);

    return TiptapEditorThemeData(
      baseTextStyle: derivedBase.merge(configured.baseTextStyle),
      linkColor: configured.linkColor ?? scheme.primary,
      inlineCodeBackgroundColor:
          configured.inlineCodeBackgroundColor ?? derivedInlineCodeBg,
      codeBlockBackgroundColor:
          configured.codeBlockBackgroundColor ?? scheme.surfaceContainerHighest,
      codeBlockTextStyle: derivedCode.merge(configured.codeBlockTextStyle),
      codeBlockLabelColor:
          configured.codeBlockLabelColor ?? scheme.onSurfaceVariant,
      blockquoteBorderColor:
          configured.blockquoteBorderColor ?? scheme.outlineVariant,
      dividerColor: configured.dividerColor ?? scheme.outlineVariant,
      placeholderBackgroundColor:
          configured.placeholderBackgroundColor ??
          scheme.surfaceContainerHighest,
      placeholderForegroundColor:
          configured.placeholderForegroundColor ?? scheme.onSurfaceVariant,
      captionColor: configured.captionColor ?? scheme.onSurfaceVariant,
      cursorColor:
          configured.cursorColor ??
          selectionTheme.cursorColor ??
          scheme.primary,
      selectionColor:
          configured.selectionColor ??
          selectionTheme.selectionColor ??
          derivedSelection,
    );
  }

  /// Read the resolved theme from the nearest [TiptapEditorThemeScope].
  ///
  /// Falls back to resolving from the Material theme when no scope is present,
  /// so a builder invoked outside a DocumentRenderer (tests, previews) still
  /// gets sensible values instead of throwing.
  static TiptapEditorThemeData of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TiptapEditorThemeScope>();
    return scope?.data ?? resolve(context);
  }

  @override
  bool operator ==(Object other) {
    return other is TiptapEditorThemeData &&
        other.baseTextStyle == baseTextStyle &&
        other.linkColor == linkColor &&
        other.inlineCodeBackgroundColor == inlineCodeBackgroundColor &&
        other.codeBlockBackgroundColor == codeBlockBackgroundColor &&
        other.codeBlockTextStyle == codeBlockTextStyle &&
        other.codeBlockLabelColor == codeBlockLabelColor &&
        other.blockquoteBorderColor == blockquoteBorderColor &&
        other.dividerColor == dividerColor &&
        other.placeholderBackgroundColor == placeholderBackgroundColor &&
        other.placeholderForegroundColor == placeholderForegroundColor &&
        other.captionColor == captionColor &&
        other.cursorColor == cursorColor &&
        other.selectionColor == selectionColor;
  }

  @override
  int get hashCode => Object.hash(
    baseTextStyle,
    linkColor,
    inlineCodeBackgroundColor,
    codeBlockBackgroundColor,
    codeBlockTextStyle,
    codeBlockLabelColor,
    blockquoteBorderColor,
    dividerColor,
    placeholderBackgroundColor,
    placeholderForegroundColor,
    captionColor,
    cursorColor,
    selectionColor,
  );
}

/// Inherited widget that carries the resolved [TiptapEditorThemeData] to every
/// node builder below the document renderer.
///
/// Node builders receive a BuildContext and read the theme through
/// [TiptapEditorThemeData.of]; the renderer places this scope above the
/// document tree so that lookup succeeds for default and custom builders
/// alike.
class TiptapEditorThemeScope extends InheritedWidget {
  final TiptapEditorThemeData data;

  const TiptapEditorThemeScope({
    super.key,
    required this.data,
    required super.child,
  });

  /// Only notify when the resolved values actually changed. The renderer
  /// resolves a fresh data object on every build; without value comparison
  /// here, any parent rebuild would invalidate every block's span tree and
  /// force a full-document relayout for no visible change.
  @override
  bool updateShouldNotify(TiptapEditorThemeScope oldWidget) =>
      oldWidget.data != data;
}
