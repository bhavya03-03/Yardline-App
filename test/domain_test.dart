import 'package:flutter_test/flutter_test.dart';
import 'package:yardline_worker/domain.dart';

import 'support.dart';

void main() {
  test('ISO format/check digit matches the website implementation', () {
    expect(validNumber('MSCU1234566'), isTrue);
    expect(validNumber('MSCU 123456 6'), isTrue);
    expect(validNumber('tghu-7599330'), isTrue);
    expect(validNumber('MSCU1234567'), isFalse);
    expect(validNumber('MSCA1234566'), isFalse);
    expect(validNumber('MSCU12345'), isFalse);
    expect(checkDigit('MSCU123456'), 6);
    expect(checkDigit('ABCD123456'), isNull);
  });
  test('OCR extracts split lines, deduplicates and suggests numeric corrections only', () {
    expect(extractCandidates('MSCU 123456\n6\nMSCU1234566'), ['MSCU1234566']);
    expect(extractCandidates('TGHU 759933O'), ['TGHU7599330']);
    expect(extractCandidates('MSCU1234567'), [
      'MSCU1234567',
    ]); // Does not fix check digits.
    expect(extractCandidates('no number here'), isEmpty);
  });
  test('available flags do not override actual occupancy', () {
    final s = Snapshot(fixture());
    expect(s.destinationProblem(s.slot('s1')!, 40), 'Occupied');
    expect(s.destinationProblem(s.slot('s2')!, 40), isNull);
    expect(s.destinationProblem(s.slot('s2')!, 20), 'Stack length mismatch');
    expect(s.destinationProblem(s.slot('s4')!, 40), 'Fill lower tiers first');
    expect(s.destinationProblem(s.slot('s3')!, 40), isNull);
  });
  test(
    'move previews remove source occupancy and preserve tier/capacity rules',
    () {
      final raw = fixture();
      raw['blocks'][0]['capacity_limit'] = 1;
      final s = Snapshot(raw), c = safeContainer(raw);
      expect(s.destinationProblem(s.slot('s3')!, 40), 'Block at capacity');
      expect(s.destinationProblem(s.slot('s3')!, 40, moving: c), isNull);
      expect(
        s.destinationProblem(s.slot('s2')!, 40, moving: c),
        'Fill lower tiers first',
      );
      expect(
        s.destinationProblem(s.slot('s1')!, 40, moving: c),
        'Current position',
      );
    },
  );
  test(
    'stacked source is inaccessible; reserved, length and yard rules apply',
    () {
      final raw = fixture();
      final upper = copy(raw['containers'][0] as Json)
        ..['id'] = 'upper'
        ..['current_slot_id'] = 's2';
      raw['containers'].add(upper);
      raw['slots'][2]['max_size'] = 20;
      raw['slots'][3]['status'] = 'reserved';
      final s = Snapshot(raw);
      expect(s.sourceProblem(s.container('c1')!), isNotNull);
      expect(s.destinationProblem(s.slot('s3')!, 40), 'Up to 20 ft');
      expect(s.destinationProblem(s.slot('s4')!, 40), 'reserved');
      final foreign = Slot({
        ...position('f', 'bay3', 3, 1),
        'yard_id': 'other',
      });
      expect(s.destinationProblem(foreign, 40), 'Different yard');
    },
  );
}

YardContainer safeContainer(Json raw) =>
    YardContainer(raw['containers'][0] as Json);
