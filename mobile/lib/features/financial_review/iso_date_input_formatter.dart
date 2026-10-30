import 'package:flutter/services.dart';

/// Formats up to eight date digits as YYYY-MM-DD while preserving the cursor.
class IsoDateInputFormatter extends TextInputFormatter {
  const IsoDateInputFormatter();

  static final RegExp _nonDigit = RegExp(r'[^0-9]');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }

    final rawDigits = newValue.text.replaceAll(_nonDigit, '');
    final digits = rawDigits.length > 8 ? rawDigits.substring(0, 8) : rawDigits;
    final formatted = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index == 4 || index == 6) formatted.write('-');
      formatted.write(digits[index]);
    }
    final text = formatted.toString();

    int cursorFor(int offset) {
      if (offset < 0) return text.length;
      final beforeCursor = newValue.text
          .substring(0, offset.clamp(0, newValue.text.length))
          .replaceAll(_nonDigit, '');
      final targetDigits = beforeCursor.length.clamp(0, digits.length);
      if (targetDigits == 0) return 0;

      var seenDigits = 0;
      for (var index = 0; index < text.length; index++) {
        if (text[index] != '-') seenDigits++;
        if (seenDigits == targetDigits) return index + 1;
      }
      return text.length;
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: cursorFor(newValue.selection.baseOffset),
        extentOffset: cursorFor(newValue.selection.extentOffset),
      ),
    );
  }
}
