import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:yardline_worker/controller.dart';
import 'package:yardline_worker/domain.dart';
import 'package:yardline_worker/services.dart';

Json fixture() => {
  'yard': {'id': 'yard-a', 'code': 'YD01', 'name': 'Test Yard'},
  'yards': [
    {'id': 'yard-a', 'code': 'YD01', 'name': 'Test Yard'},
  ],
  'blocks': [
    {
      'id': 'b1',
      'code': 'B01',
      'name': 'Import',
      'capacity_limit': 8,
      'max_size': 45,
      'max_tiers': 2,
    },
  ],
  'rows': [
    {'id': 'r1', 'block_id': 'b1', 'code': 'R01', 'ordinal': 1},
  ],
  'bays': [
    {
      'id': 'bay1',
      'row_id': 'r1',
      'code': 'BY01',
      'ordinal': 1,
      'max_tiers': 2,
    },
    {
      'id': 'bay2',
      'row_id': 'r1',
      'code': 'BY02',
      'ordinal': 2,
      'max_tiers': 2,
    },
  ],
  'slots': [
    position('s1', 'bay1', 1, 1),
    position('s2', 'bay1', 1, 2),
    position('s3', 'bay2', 2, 1),
    position('s4', 'bay2', 2, 2),
  ],
  'zones': [],
  'containers': [
    {
      'id': 'c1',
      'number': 'MSCU1234566',
      'size': 40,
      'type': 'Dry',
      'owner': 'Test owner',
      'status': 'stored',
      'current_yard_id': 'yard-a',
      'current_slot_id': 's1',
      'identity_verified': 1,
      'registered_at': '2026-10-18T10:00:00Z',
      'verified_at': null,
      'notes': '',
      'has_photo': 0,
      'location_code': 'YD01-B01-R01-BY01-T01',
    },
  ],
  'movements': [],
  'metrics': {'occupied': 1, 'capacity': 8, 'assignable': 2, 'unassigned': 0},
  'actor': {'id': 'worker', 'name': 'Priya Sharma', 'role': 'operator'},
  'authMode': 'demo',
  'persistence': 'postgres',
  'generatedAt': '2026-10-18T10:00:00Z',
};
Json position(String id, String bay, int ordinal, int tier) => {
  'id': id,
  'bay_id': bay,
  'tier': tier,
  'code': 'YD01-B01-R01-BY0$ordinal-T0$tier',
  'x': 0,
  'y': 0,
  'status': 'available',
  'max_size': 45,
  'capacity': 1,
  'yard_id': 'yard-a',
  'block_id': 'b1',
  'row_id': 'r1',
  'block_code': 'B01',
  'row_code': 'R01',
  'bay_code': 'BY0$ordinal',
  'row_ordinal': 1,
  'bay_ordinal': ordinal,
};
Json copy(Json value) => jsonDecode(jsonEncode(value)) as Json;

class MemoryStore implements LocalStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FakeApi implements YardApi {
  Json value = fixture();
  final List<Json> writes = [];
  int sessions = 0, reads = 0;
  ApiFailure? readFailure, writeFailure;
  Future<Snapshot> Function()? nextRead;
  Completer<Json>? heldWrite;
  Json Function(String, Json)? onAction;
  @override
  Future<void> operatorSession() async {
    sessions++;
  }

  @override
  Future<Snapshot> state(String? yardId) async {
    reads++;
    if (readFailure != null) throw readFailure!;
    if (nextRead != null) return nextRead!();
    return Snapshot(copy(value));
  }

  @override
  Future<Json> action(String action, Json payload) async {
    writes.add({'action': action, 'payload': copy(payload)});
    if (writeFailure != null) throw writeFailure!;
    if (heldWrite != null) return heldWrite!.future;
    if (onAction != null) return onAction!(action, payload);
    return {
      'state': copy(value),
      'entityId': action == 'register' ? 'new-container' : null,
    };
  }

  @override
  Future<Uint8List> photo(String id) async => Uint8List(0);
}

YardController controller(FakeApi api, MemoryStore store) => YardController(
  api: api,
  store: store,
  config: const AppConfig(),
  scope: 'test',
);

class StubAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  final List<RequestOptions> requests = [];
  StubAdapter(this.handler);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(
  dynamic body,
  int status, {
  Map<String, List<String>>? headers,
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    'content-type': ['application/json'],
    ...?headers,
  },
);
