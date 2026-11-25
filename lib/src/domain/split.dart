/// Splits [totalSen] in proportion to [weights] with the largest remainder
/// method, so the shares always add up to exactly [totalSen].
///
/// Everyone first gets the rounded-down share; the sen left over go one each
/// to the largest remainders. Ties go to the larger weight, then to the earlier
/// position, so the result is deterministic. A zero weight gets nothing.
List<int> splitByWeights(int totalSen, List<int> weights) {
  if (totalSen < 0) throw ArgumentError.value(totalSen, 'totalSen');
  if (weights.any((w) => w < 0)) {
    throw ArgumentError.value(weights, 'weights', 'must not be negative');
  }
  final sum = weights.fold<int>(0, (a, w) => a + w);
  if (sum == 0) {
    if (totalSen == 0) return List.filled(weights.length, 0);
    throw ArgumentError('Nobody to split between');
  }
  final shares = <int>[];
  final remainders = <({int index, int remainder, int weight})>[];
  var given = 0;
  for (var i = 0; i < weights.length; i++) {
    final exact = totalSen * weights[i];
    final share = exact ~/ sum;
    shares.add(share);
    given += share;
    remainders.add((index: i, remainder: exact % sum, weight: weights[i]));
  }
  remainders.sort(
    (a, b) => b.remainder != a.remainder
        ? b.remainder.compareTo(a.remainder)
        : b.weight != a.weight
        ? b.weight.compareTo(a.weight)
        : a.index.compareTo(b.index),
  );
  for (var k = 0; k < totalSen - given; k++) {
    shares[remainders[k].index]++;
  }
  return shares;
}
