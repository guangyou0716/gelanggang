import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gelanggang/src/domain/split.dart';

void main() {
  test('splits evenly and gives leftover sen to the first players', () {
    expect(splitByWeights(1000, [1, 1, 1]), [334, 333, 333]);
    expect(splitByWeights(100, [1, 1, 1, 1]), [25, 25, 25, 25]);
    expect(splitByWeights(0, [1, 1]), [0, 0]);
  });

  test('splits by weight; ties on remainder go to the larger weight', () {
    // 120 vs 60 minutes of a RM 10.00 bill.
    expect(splitByWeights(1000, [120, 60]), [667, 333]);
    expect(splitByWeights(1001, [60, 120, 0]), [334, 667, 0]);
  });

  test('always adds up exactly and never differs by more than 1 sen from the exact share', () {
    final random = Random(42);
    for (var run = 0; run < 2000; run++) {
      final total = random.nextInt(200000);
      final weights = List.generate(
        1 + random.nextInt(12),
        (_) => random.nextInt(240),
      );
      if (weights.every((w) => w == 0)) weights[0] = 1;
      final shares = splitByWeights(total, weights);
      expect(shares.reduce((a, b) => a + b), total);
      final sum = weights.reduce((a, b) => a + b);
      for (var i = 0; i < weights.length; i++) {
        final exact = total * weights[i] / sum;
        expect((shares[i] - exact).abs(), lessThan(1), reason: 'run $run');
      }
    }
  });

  test('rejects impossible splits', () {
    expect(() => splitByWeights(100, [0, 0]), throwsArgumentError);
    expect(() => splitByWeights(100, []), throwsArgumentError);
    expect(() => splitByWeights(-1, [1]), throwsArgumentError);
    expect(() => splitByWeights(100, [1, -1]), throwsArgumentError);
  });
}
