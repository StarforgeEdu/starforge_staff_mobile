import 'package:flutter_test/flutter_test.dart';
import 'package:starforge_staff/data/workflow_models.dart';

void main() {
  test('form choice values retain the backend option text', () {
    final field = StaffFormFieldInfo.fromJson({
      'id': 2,
      'label': 'Available days',
      'field_type': 'multi_choice',
      'required': true,
      'options': ['Monday', 'Tuesday'],
      'help_text': '',
    });

    expect(field.options, ['Monday', 'Tuesday']);
  });

  test('object-shaped choices use their explicit value', () {
    final field = StaffFormFieldInfo.fromJson({
      'id': 3,
      'label': 'Shift',
      'field_type': 'single_choice',
      'required': true,
      'options': [
        {'value': 'morning', 'label': 'Morning'},
      ],
      'help_text': '',
    });

    expect(field.options, ['morning']);
  });
}
