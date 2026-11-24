import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/engines/highlighter.dart';
import '../../theme/app_theme.dart';

/// TextEditingController that paints syntax highlighting through [buildTextSpan].
/// The concatenated text of the produced spans always equals [text] (see highlighter
/// invariant), so selection, cursor and IME behave exactly like a plain field.
class HighlightingController extends TextEditingController {
  String format;
  bool highlight;
  HighlightColors colors;

  HighlightingController({super.text, this.format = 'text', this.highlight = true, this.colors = const HighlightColors.dark()});

  void configure({required String format, required bool highlight, required HighlightColors colors}) {
    final changed = this.format != format || this.highlight != highlight || this.colors != colors;
    this.format = format;
    this.highlight = highlight;
    this.colors = colors;
    if (changed) notifyListeners();
  }

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final composing = value.composing;
    final isComposing = withComposing && value.isComposingRangeValid && !composing.isCollapsed;
    if (!highlight || isComposing || text.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    return PromptHighlighter.build(text, format, style ?? const TextStyle(), colors);
  }
}

/// Multi-line editor with an optional line-number gutter. The gutter lives in the same
/// scroll view as the text so the two can never drift apart; with word wrap each logical
/// line gets the height of its wrapped layout.
class CodeEditor extends StatefulWidget {
  final HighlightingController controller;
  final FocusNode focusNode;
  final UndoHistoryController? undoController;
  final String fontFamily;
  final List<String> fontFallback;
  final double fontSize;
  final bool lineNumbers;
  final bool wordWrap;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ScrollController? scrollController;
  final EdgeInsets padding;

  /// Line height multiplier (compact 1.4 / relaxed 1.7 / loose 2.0).
  final double lineHeight;

  /// Spaces inserted by the Tab key.
  final int tabWidth;

  /// Optional floating widget (autocomplete list) shown right under the caret, like in the web editor.
  final Widget? popup;
  final double popupHeight;

  const CodeEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.fontFamily,
    required this.fontFallback,
    required this.fontSize,
    required this.lineNumbers,
    required this.wordWrap,
    this.undoController,
    this.hint = '',
    this.onChanged,
    this.scrollController,
    this.padding = const EdgeInsets.fromLTRB(8, 12, 12, 120),
    this.lineHeight = 1.7,
    this.tabWidth = 2,
    this.popup,
    this.popupHeight = 0,
  });

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  double get _lineHeightFactor => widget.lineHeight;

  void _insertIndent() {
    final c = widget.controller;
    final v = c.value;
    final sel = v.selection;
    if (!sel.isValid) return;
    final spaces = ' ' * (widget.tabWidth < 1 ? 1 : widget.tabWidth);
    final text = v.text.replaceRange(sel.start, sel.end, spaces);
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: sel.start + spaces.length));
  }

  // memo for gutter layout
  String? _memoText;
  double? _memoWidth;
  double? _memoSize;
  double? _memoLH;
  bool? _memoWrap;
  List<double> _memoHeights = const [];

  TextStyle _style(PfPalette p) => TextStyle(
        fontFamily: widget.fontFamily,
        fontFamilyFallback: widget.fontFallback,
        fontSize: widget.fontSize,
        height: _lineHeightFactor,
        color: p.text,
      );

  List<double> _lineHeights(String text, double width, TextStyle style) {
    final lines = text.split('\n');
    final single = widget.fontSize * _lineHeightFactor;
    if (!widget.wordWrap) return List<double>.filled(lines.length, single);
    if (_memoText == text && _memoWidth == width && _memoSize == widget.fontSize && _memoLH == widget.lineHeight && _memoWrap == widget.wordWrap) return _memoHeights;
    final out = <double>[];
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final line in lines) {
      if (line.length < 20) {
        out.add(single);
        continue;
      }
      tp.text = TextSpan(text: line, style: style);
      tp.layout(maxWidth: width);
      out.add(tp.height < single ? single : tp.height);
    }
    tp.dispose();
    _memoText = text;
    _memoWidth = width;
    _memoSize = widget.fontSize;
    _memoLH = widget.lineHeight;
    _memoWrap = widget.wordWrap;
    _memoHeights = out;
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pf;
    final style = _style(p);
    return LayoutBuilder(builder: (context, c) {
      final digits = '${'\n'.allMatches(widget.controller.text).length + 1}'.length;
      final gutterW = widget.lineNumbers ? (digits < 2 ? 2 : digits) * widget.fontSize * 0.62 + 18 : 0.0;
      final textW = (c.maxWidth - gutterW - widget.padding.horizontal).clamp(40.0, 4000.0);
      final minHeight = c.maxHeight.isFinite ? c.maxHeight - widget.padding.vertical : 200.0;

      Widget field = TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        undoController: widget.undoController,
        onChanged: widget.onChanged,
        maxLines: null,
        minLines: (minHeight / (widget.fontSize * _lineHeightFactor)).floor().clamp(4, 400),
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        autocorrect: false,
        enableSuggestions: false,
        style: style,
        cursorColor: p.amber,
        scrollPhysics: const NeverScrollableScrollPhysics(),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          hintText: widget.hint,
          hintStyle: style.copyWith(color: p.textTertiary),
        ),
      );
      field = CallbackShortcuts(bindings: {const SingleActivator(LogicalKeyboardKey.tab): _insertIndent}, child: field);
      if (!widget.wordWrap) {
        field = SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(constraints: BoxConstraints(minWidth: textW), child: IntrinsicWidth(child: field)));
      }

      final editor = Container(
        color: p.editorBg,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          padding: EdgeInsets.only(top: widget.padding.top, bottom: widget.padding.bottom),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final heights = widget.lineNumbers ? _lineHeights(widget.controller.text, textW, style) : const <double>[];
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (widget.lineNumbers)
                  SizedBox(
                    width: gutterW,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: CustomPaint(
                        size: Size(gutterW - 8, heights.fold<double>(0, (a, b) => a + b)),
                        painter: _GutterPainter(heights, style.copyWith(color: p.textTertiary, fontSize: widget.fontSize * 0.85)),
                      ),
                    ),
                  ),
                Expanded(child: Padding(padding: EdgeInsets.only(right: widget.padding.right), child: field)),
              ]);
            },
          ),
        ),
      );
      if (widget.popup == null) return editor;
      final scroll = widget.scrollController;
      return Stack(children: [
        Positioned.fill(child: editor),
        ListenableBuilder(
          listenable: Listenable.merge([widget.controller, if (scroll != null) scroll]),
          builder: (context, _) {
            final sel = widget.controller.selection;
            final text = widget.controller.text;
            if (!sel.isValid) return const SizedBox.shrink();
            final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout(maxWidth: widget.wordWrap ? textW : double.infinity);
            final caret = tp.getOffsetForCaret(TextPosition(offset: sel.baseOffset.clamp(0, text.length)), Rect.zero);
            final lh = widget.fontSize * _lineHeightFactor;
            tp.dispose();
            final off = (scroll != null && scroll.hasClients) ? scroll.offset : 0.0;
            final popupW = (c.maxWidth - 16).clamp(160.0, 340.0);
            final x = (gutterW + caret.dx - 10).clamp(8.0, (c.maxWidth - popupW - 8).clamp(8.0, 4000.0));
            final yBelow = widget.padding.top + caret.dy + lh - off + 4;
            var y = yBelow;
            if (yBelow + widget.popupHeight > c.maxHeight - 4) {
              final yAbove = widget.padding.top + caret.dy - off - widget.popupHeight - 4;
              y = yAbove >= 4 ? yAbove : (c.maxHeight - widget.popupHeight - 4).clamp(4.0, 4000.0);
            }
            return Positioned(left: x, top: y, width: popupW, child: widget.popup!);
          },
        ),
      ]);
    });
  }
}

class _GutterPainter extends CustomPainter {
  final List<double> heights;
  final TextStyle style;
  _GutterPainter(this.heights, this.style);

  @override
  void paint(Canvas canvas, Size size) {
    var y = 0.0;
    for (var i = 0; i < heights.length; i++) {
      final tp = TextPainter(text: TextSpan(text: '${i + 1}', style: style), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(size.width - tp.width, y));
      tp.dispose();
      y += heights[i];
    }
  }

  @override
  bool shouldRepaint(covariant _GutterPainter old) => old.style != style || old.heights.length != heights.length || !_same(old.heights, heights);

  static bool _same(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
