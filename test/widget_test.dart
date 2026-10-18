import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yardline_worker/main.dart';
import 'package:yardline_worker/registration.dart';
import 'package:yardline_worker/services.dart';
import 'package:yardline_worker/ui.dart';

import 'support.dart';

void main() {
  testWidgets(
    'confirmed registration submits once and opens the returned record',
    (t) async {
      final api = FakeApi();
      api.onAction = (action, payload) {
        api.value['containers'].add({
          ...api.value['containers'][0] as Map<String, dynamic>,
          'id': 'new-container',
          'number': payload['number'],
          'current_slot_id': null,
          'status': 'unassigned',
          'location_code': null,
        });
        return {'state': copy(api.value), 'entityId': 'new-container'};
      };
      final c = controller(api, MemoryStore());
      await c.start();
      await t.pumpWidget(
        MaterialApp(
          theme: yardlineTheme,
          home: Scaffold(body: RegistrationScreen(controller: c)),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byType(TextFormField).first,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(find.byType(TextFormField).first, 'TGHU7599330');
      await t.pump(const Duration(milliseconds: 400));
      await t.ensureVisible(find.byType(CheckboxListTile).first);
      await t.tap(find.byType(CheckboxListTile).first);
      await t.pump();
      await t.scrollUntilVisible(
        find.text('Review registration'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Review registration'));
      await t.pumpAndSettle();
      expect(find.text('Register container / gate-in'), findsOneWidget);
      await t.tap(find.byType(CheckboxListTile).last);
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await t.pumpAndSettle();
      expect(api.writes.length, 1);
      expect(api.writes.single['action'], 'register');
      expect(api.writes.single['payload']['number'], 'TGHU7599330');
      expect(api.writes.single['payload']['allowException'], false);
      expect(api.writes.single['payload'].containsKey('photo'), false);
      expect(find.text('Container details'), findsOneWidget);
      expect(find.text('TGHU7599330'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      c.dispose();
    },
  );
  testWidgets(
    'relocation and dispatch preserve reviewed sources and physical confirmations',
    (t) async {
      final api = FakeApi();
      api.onAction = (action, payload) {
        final record = api.value['containers'][0];
        record['current_slot_id'] = action == 'dispatch'
            ? null
            : payload['slotId'];
        record['status'] = action == 'dispatch' ? 'dispatched' : 'stored';
        record['location_code'] = action == 'dispatch'
            ? null
            : 'YD01-B01-R01-BY02-T01';
        return {'state': copy(api.value), 'entityId': null};
      };
      final c = controller(api, MemoryStore());
      await c.start();
      await t.pumpWidget(
        MaterialApp(
          theme: yardlineTheme,
          home: ContainerScreen(controller: c, id: 'c1'),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Relocate container'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Relocate container'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('R01 · BY02 · Tier 1'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('R01 · BY02 · Tier 1'));
      await t.pumpAndSettle();
      expect(find.text('Confirm physical placement'), findsOneWidget);
      await t.enterText(
        find.byType(TextField).last,
        'Move confirmed by worker',
      );
      await t.tap(find.byType(CheckboxListTile).last);
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await t.pumpAndSettle();
      expect(api.writes.single['payload']['expectedSlotId'], 's1');
      expect(api.writes.single['payload']['slotId'], 's3');
      expect(api.writes.single['payload']['physicalConfirmed'], true);
      await t.scrollUntilVisible(
        find.text('Dispatch / gate-out'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Dispatch / gate-out'));
      await t.pumpAndSettle();
      await t.tap(find.byType(CheckboxListTile).last);
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await t.pumpAndSettle();
      expect(api.writes.last['action'], 'dispatch');
      expect(api.writes.last['payload']['expectedSlotId'], 's3');
      expect(api.writes.last['payload']['confirmed'], true);
      expect(c.snapshot!.container('c1')!.status, 'dispatched');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      c.dispose();
    },
  );
  testWidgets('demo connection is explicit and needs no invented credentials', (
    t,
  ) async {
    await t.pumpWidget(
      YardlineApp(config: const AppConfig(), store: MemoryStore()),
    );
    await t.scrollUntilVisible(find.text('Enter demo yard'), 200);
    expect(find.text('Enter demo yard'), findsOneWidget);
    expect(find.text('Password'), findsNothing);
  });
  testWidgets('dashboard fits a narrow phone at enlarged text scale', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = controller(FakeApi(), MemoryStore());
    await c.start();
    await t.pumpWidget(
      MaterialApp(
        theme: yardlineTheme,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: Dashboard(controller: c, onScan: () {}, onSearch: () {}),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(find.text('Storage blocks'), 250);
    expect(t.takeException(), isNull);
    c.dispose();
  });
  testWidgets(
    'manual registration checks ISO and requires human verification',
    (t) async {
      final c = controller(FakeApi(), MemoryStore());
      await c.start();
      await t.pumpWidget(
        MaterialApp(
          theme: yardlineTheme,
          home: Scaffold(body: RegistrationScreen(controller: c)),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byType(TextFormField).first,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(find.byType(TextFormField).first, 'MSCU1234567');
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('does not pass ISO'), findsOneWidget);
      await t.enterText(find.byType(TextFormField).first, 'TGHU7599330');
      await t.pump(const Duration(milliseconds: 400));
      expect(
        find.text('ISO 6346 format and check digit verified.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      c.dispose();
    },
  );
}
