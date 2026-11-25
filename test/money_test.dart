import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/domain/money.dart';

void main() {
  test('formats sen as ringgit with grouping', () {
    expect(formatRm(0), 'RM 0.00');
    expect(formatRm(5), 'RM 0.05');
    expect(formatRm(1450), 'RM 14.50');
    expect(formatRm(123456789), 'RM 1,234,567.89');
    expect(formatRm(-250), '-RM 2.50');
  });

  test('parses amounts the organiser types', () {
    expect(parseRm('20'), 2000);
    expect(parseRm('4.5'), 450);
    expect(parseRm(' 4.50 '), 450);
    expect(parseRm('RM 1,200.00'), 120000);
    expect(parseRm('rm3'), 300);
    for (final bad in ['', 'abc', '-1', '1.234', '1.', '.5', '99999999']) {
      expect(parseRm(bad), isNull, reason: bad);
    }
  });
}
