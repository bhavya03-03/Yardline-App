import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yardline_worker/domain.dart';
import 'package:yardline_worker/services.dart';

import 'support.dart';

void main() {
  test(
    'serializes concurrent submissions, including the preflight refresh',
    () async {
      final api = FakeApi(), store = MemoryStore();
      final c = controller(api, store);
      addTearDown(c.dispose);
      await c.start();
      final preflight = Completer<Snapshot>();
      api.nextRead = () => preflight.future;
      final first = c.mutate('register', {
        'yardId': 'yard-a',
        'number': 'TGHU7599330',
        'size': 40,
      });
      await expectLater(
        c.mutate('register', {
          'yardId': 'yard-a',
          'number': 'TGHU7599330',
          'size': 40,
        }),
        throwsA(isA<ApiFailure>()),
      );
      preflight.complete(Snapshot(fixture()));
      await first;
      expect(api.writes.length, 1);
    },
  );
  test(
    'cached snapshot and draft survive offline startup; writes remain disabled',
    () async {
      final api = FakeApi()
        ..readFailure = const ApiFailure('CONNECTION', 'offline');
      final store = MemoryStore();
      final c = controller(api, store);
      addTearDown(c.dispose);
      await store.write(c.key('snapshot'), jsonEncode(fixture()));
      await c.saveDraft({'number': 'TGHU7599330'});
      await c.start();
      expect(c.snapshot!.containers.length, 1);
      expect(c.online, isFalse);
      expect(c.canWrite, isFalse);
      expect(await c.draft(), contains('TGHU7599330'));
      expect(api.sessions, 1);
    },
  );
  test('stale source move is rejected before any POST', () async {
    final api = FakeApi(), store = MemoryStore();
    final c = controller(api, store);
    addTearDown(c.dispose);
    await c.start();
    api.value['containers'][0]['current_slot_id'] = 's3';
    await expectLater(
      c.mutate('move', {
        'yardId': 'yard-a',
        'containerId': 'c1',
        'expectedSlotId': 's1',
        'slotId': 's2',
      }),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'STALE_LOCATION'),
      ),
    );
    expect(api.writes, isEmpty);
  });
  test('duplicate registration found in fresh snapshot never posts', () async {
    final api = FakeApi(), store = MemoryStore();
    final c = controller(api, store);
    addTearDown(c.dispose);
    await c.start();
    await expectLater(
      c.mutate('register', {
        'yardId': 'yard-a',
        'number': 'MSCU1234566',
        'size': 40,
      }),
      throwsA(
        isA<ApiFailure>().having((e) => e.code, 'code', 'DUPLICATE_CONTAINER'),
      ),
    );
    expect(api.writes, isEmpty);
  });
  test('late poll response cannot overwrite a newer state', () async {
    final api = FakeApi(), store = MemoryStore();
    final c = controller(api, store);
    addTearDown(c.dispose);
    await c.start();
    final old = Completer<Snapshot>(), fresh = Completer<Snapshot>();
    int calls = 0;
    api.nextRead = () => calls++ == 0 ? old.future : fresh.future;
    final first = c.refresh(), second = c.refresh();
    final latest = fixture()..['generatedAt'] = 'new';
    fresh.complete(Snapshot(latest));
    await second;
    old.complete(Snapshot(fixture()));
    await first;
    expect(c.snapshot!.generatedAt, 'new');
  });
  test(
    'lost write response persists pending intent and prevents automatic replay',
    () async {
      final api = FakeApi()
        ..writeFailure = const ApiFailure(
          'CONNECTION',
          'lost',
          uncertain: true,
        );
      final store = MemoryStore();
      final c = controller(api, store);
      addTearDown(c.dispose);
      await c.start();
      final payload = {
        'yardId': 'yard-a',
        'number': 'TGHU7599330',
        'size': 40,
        'slotId': null,
      };
      await expectLater(
        c.mutate('register', payload),
        throwsA(isA<ApiFailure>()),
      );
      expect(c.pending, isNotNull);
      expect(api.writes.length, 1);
      await expectLater(
        c.mutate('register', payload),
        throwsA(isA<ApiFailure>()),
      );
      expect(api.writes.length, 1);
      final restarted = controller(api, store);
      addTearDown(restarted.dispose);
      await restarted.start();
      expect(restarted.pending, isNotNull);
      expect(restarted.canWrite, isFalse);
      await restarted.acknowledgePending();
      expect(restarted.pending, isNull);
      expect(api.writes.length, 1);
    },
  );
  test(
    'conflict unlocks retry; success uses server snapshot and clears pending',
    () async {
      final api = FakeApi()
        ..writeFailure = const ApiFailure(
          'SLOT_OCCUPIED',
          'Occupied',
          status: 409,
        );
      final c = controller(api, MemoryStore());
      addTearDown(c.dispose);
      await c.start();
      final payload = {
        'yardId': 'yard-a',
        'number': 'TGHU7599330',
        'size': 40,
        'slotId': null,
      };
      await expectLater(
        c.mutate('register', payload),
        throwsA(isA<ApiFailure>()),
      );
      expect(c.pending, isNull);
      api.writeFailure = null;
      expect(await c.mutate('register', payload), 'new-container');
      expect(c.pending, isNull);
      expect(c.online, isTrue);
    },
  );
}
