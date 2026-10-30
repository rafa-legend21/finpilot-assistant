import 'package:finpilot_assistant/features/financial_review/iso_date_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = IsoDateInputFormatter();

  TextEditingValue edit(String text, {int? cursor}) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: cursor ?? text.length),
      );

  test('inserts separators only when the next date group starts', () {
    expect(formatter.formatEditUpdate(edit(''), edit('2026')).text, '2026');
    expect(
        formatter.formatEditUpdate(edit('2026'), edit('20260')).text, '2026-0');
    expect(formatter.formatEditUpdate(edit('2026-10'), edit('2026103')).text,
        '2026-10-3');
    expect(formatter.formatEditUpdate(edit('2026-10-3'), edit('20261030')).text,
        '2026-10-30');
  });

  test('pasting a date preserves its form and caps at eight digits', () {
    expect(formatter.formatEditUpdate(edit(''), edit('2026-10-30')).text,
        '2026-10-30');
    expect(formatter.formatEditUpdate(edit(''), edit('202610301234')).text,
        '2026-10-30');
  });

  test('backspace removes digits and can move across a separator', () {
    final shortened =
        formatter.formatEditUpdate(edit('2026-10-30'), edit('2026-10-3'));
    expect(shortened.text, '2026-10-3');
    expect(shortened.selection.baseOffset, shortened.text.length);

    final acrossSeparator = formatter.formatEditUpdate(
        edit('2026-10', cursor: 5), edit('202610', cursor: 4));
    expect(acrossSeparator.text, '2026-10');
    expect(acrossSeparator.selection.baseOffset, 4);
  });
}
