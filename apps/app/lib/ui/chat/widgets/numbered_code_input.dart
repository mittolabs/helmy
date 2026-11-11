import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../core/ashlar/input.dart';
import '../../core/ashlar/theme.dart';

/// Line numbers share the editor's scroll and use its actual caret positions,
/// so wrapped lines, font scaling and blank lines stay aligned.
class NumberedCodeInput extends StatefulWidget {
  const NumberedCodeInput({super.key, required this.controller, required this.focusNode});
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  State<NumberedCodeInput> createState() => _NumberedCodeInputState();
}

class _NumberedCodeInputState extends State<NumberedCodeInput> {
  final _inputKey = GlobalKey();
  final _gutterKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final style = t.text.sm.copyWith(
      color: t.colors.foreground,
      fontFamily: 'monospace',
      height: 1.6,
    );
    final scaler = MediaQuery.textScalerOf(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final lines = '\n'.allMatches(value.text).length + 1;
        final measure = TextPainter(
          text: TextSpan(text: '$lines', style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final width = measure.width + 24;
        measure.dispose();
        return Stack(
          children: [
            Padding(
              padding: EdgeInsetsDirectional.only(start: width),
              child: Input(
                key: _inputKey,
                controller: widget.controller,
                focusNode: widget.focusNode,
                decorated: false,
                maxLines: 100000,
                minLines: 1,
                semanticLabel: 'Code editor',
                style: style,
                autocorrect: false,
                enableSuggestions: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                keyboardType: TextInputType.multiline,
              ),
            ),
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: width,
              child: ExcludeSemantics(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: _gutterKey,
                    foregroundPainter: _LineNumbers(
                      inputKey: _inputKey,
                      gutterKey: _gutterKey,
                      text: value.text,
                      scaler: scaler,
                      style: style.copyWith(color: t.colors.mutedForeground),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LineNumbers extends CustomPainter {
  _LineNumbers({
    required this.inputKey,
    required this.gutterKey,
    required this.text,
    required this.style,
    required this.scaler,
  });
  final GlobalKey inputKey, gutterKey;
  final String text;
  final TextStyle style;
  final TextScaler scaler;

  RenderEditable? _editable(RenderObject? object) {
    if (object is RenderEditable) return object;
    RenderEditable? found;
    object?.visitChildren((child) => found ??= _editable(child));
    return found;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final editor = _editable(inputKey.currentContext?.findRenderObject());
    final gutter = gutterKey.currentContext?.findRenderObject();
    if (editor == null || gutter is! RenderBox) return;
    final clip = canvas.getLocalClipBounds();
    final label = TextPainter(textDirection: TextDirection.ltr, textScaler: scaler);
    var offset = 0;
    var number = 1;
    while (true) {
      final caret = editor.getLocalRectForCaret(TextPosition(offset: offset));
      final top = gutter.globalToLocal(editor.localToGlobal(caret.topLeft)).dy;
      if (top > clip.bottom) break;
      if (top + caret.height >= clip.top) {
        label.text = TextSpan(text: '$number', style: style);
        label.layout();
        label.paint(
          canvas,
          Offset(size.width - 12 - label.width, top + (caret.height - label.height) / 2),
        );
      }
      final newline = text.indexOf('\n', offset);
      if (newline < 0) break;
      offset = newline + 1;
      number++;
    }
    label.dispose();
  }

  @override
  bool shouldRepaint(_LineNumbers oldDelegate) => true;
}
