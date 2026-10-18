import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yardline_worker/domain.dart';
import 'package:yardline_worker/main.dart' as app;
import 'package:yardline_worker/services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native ML Kit recognizes a real raster image and validates ISO',
    (tester) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
      final paragraph =
          (ui.ParagraphBuilder(
                  ui.ParagraphStyle(
                    fontSize: 90,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                )
                ..pushStyle(ui.TextStyle(color: Colors.black))
                ..addText('MSCU 123456 6'))
              .build()
            ..layout(const ui.ParagraphConstraints(width: 1200));
      canvas.drawParagraph(paragraph, const Offset(40, 80));
      final picture = recorder.endRecording();
      final image = await picture.toImage(1200, 300);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = await Directory.systemTemp.createTemp('yardline-ocr-');
      final file = File('${directory.path}/container.png');
      try {
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        final result = await OcrService().recognize(file.path);
        expect(result.candidates, contains('MSCU1234566'));
        expect(validNumber(result.candidates.first), isTrue);
      } finally {
        image.dispose();
        picture.dispose();
        await file.delete();
        await directory.delete();
      }
    },
  );
  testWidgets(
    'live shared backend read and demo operator cookie; no yard writes',
    (tester) async {
      final api = HttpYardApi(const AppConfig());
      await api.operatorSession();
      final state = await api.state(null);
      expect(state.actor['role'], 'operator');
      expect(state.authMode, 'demo');
      expect(state.yards, isNotEmpty);
      expect(state.slots, isNotEmpty);
      expect(state.containers, isNotEmpty);
      debugPrint(
        'Live shared snapshot: ${state.containers.length} containers, ${state.slots.length} positions, ${state.raw['persistence']} persistence.',
      );
    },
  );
  testWidgets('installed app connects and renders the actual shared yard', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Enter demo yard'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Enter demo yard'));
    for (
      var i = 0;
      i < 90 &&
          find.text('Your yard, connected'.toUpperCase()).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('YOUR YARD, CONNECTED'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Find'));
    await tester.pumpAndSettle();
    expect(find.text('Find a container.'), findsOneWidget);
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Every move,\nrecorded.'), findsOneWidget);
  });
}
