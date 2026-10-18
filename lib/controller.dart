import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'domain.dart';
import 'services.dart';

/// The encrypted local store holds drafts/cache only; every write uses Yardline.
class YardController extends ChangeNotifier {
  final YardApi api;
  final LocalStore store;
  final AppConfig config;
  final String scope;
  Snapshot? snapshot;
  ApiFailure? error;
  bool online = false, loading = false, writing = false, foreground = true;
  bool _disposed = false;
  bool _submitting = false;
  bool _clearing = false;
  Future<void> _draftWrites = Future.value();
  int _epoch = 0;
  Timer? _poll;
  String? pending;
  YardController({
    required this.api,
    required this.store,
    required this.config,
    required this.scope,
  });
  String key(String suffix) => 'yardline:$scope:$suffix';
  bool get canWrite =>
      online &&
      !writing &&
      !loading &&
      pending == null &&
      ['operator', 'administrator'].contains(snapshot?.actor['role']);
  void emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    loading = true;
    emit();
    try {
      pending = await store.read(key('pending'));
      final cached = await store.read(key('snapshot'));
      if (_disposed) return;
      if (cached != null) {
        try {
          snapshot = Snapshot.decode(cached);
        } catch (_) {
          await store.delete(key('snapshot'));
        }
      }
      if (config.authMode == 'demo') await api.operatorSession();
      await refresh();
    } catch (e) {
      online = false;
      error = asFailure(e);
    } finally {
      loading = false;
      emit();
    }
    _poll?.cancel();
    if (_disposed) return;
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (foreground && !writing && !loading) unawaited(refresh());
    });
  }

  ApiFailure asFailure(Object e) => e is ApiFailure
      ? e
      : const ApiFailure(
          'LOCAL_ERROR',
          'Unable to complete this operation. Refresh and try again.',
        );
  Future<bool> refresh({String? yardId}) async {
    if (writing) return false;
    final epoch = ++_epoch;
    loading = true;
    emit();
    try {
      final next = await api.state(yardId ?? snapshot?.yard.id);
      if (_disposed || epoch != _epoch) return false;
      snapshot = next;
      online = true;
      error = null;
      await cache(next);
      return true;
    } catch (e) {
      if (epoch == _epoch) {
        online = false;
        error = asFailure(e);
      }
      return false;
    } finally {
      if (epoch == _epoch) {
        loading = false;
        emit();
      }
    }
  }

  Future<void> cache(Snapshot state) async {
    try {
      await store.write(key('snapshot'), jsonEncode(state.raw));
    } catch (_) {
      /* Server remains authoritative. */
    }
  }

  Future<String?> draft() => store.read(key('registration'));
  Future<void> saveDraft(Json draft) {
    if (_disposed || _clearing) return Future.value();
    final value = jsonEncode(draft);
    _draftWrites = _draftWrites
        .catchError((Object _) {})
        .then((_) => store.write(key('registration'), value));
    return _draftWrites;
  }

  Future<void> clearDraft() async {
    await _draftWrites.catchError((Object _) {});
    await store.delete(key('registration'));
  }

  void setForeground(bool value) {
    foreground = value;
    if (value && !writing) unawaited(refresh());
  }

  /// Stale source positions are rejected, never silently replaced with new ones.
  Future<String?> mutate(String action, Json payload) async {
    if (_submitting || writing || pending != null) {
      throw const ApiFailure(
        'PENDING_OPERATION',
        'Review the unresolved operation before submitting another.',
      );
    }
    _submitting = true;
    try {
      return await _performMutation(action, payload);
    } finally {
      _submitting = false;
    }
  }

  Future<String?> _performMutation(String action, Json payload) async {
    if (!await refresh() || !canWrite) {
      throw error ??
          const ApiFailure(
            'READ_ONLY',
            'Connect as a worker and refresh before submitting.',
          );
    }
    final state = snapshot!;
    if (payload['yardId'] != state.yard.id) {
      throw const ApiFailure(
        'STALE_YARD',
        'The selected yard changed. Review this operation again.',
      );
    }
    if (action != 'register') {
      final container = state.container(string(payload['containerId']));
      if (container == null || container.slotId != payload['expectedSlotId']) {
        throw const ApiFailure(
          'STALE_LOCATION',
          'The recorded location changed. Review the current container details.',
        );
      }
      if (action != 'verify' && state.sourceProblem(container) != null) {
        throw ApiFailure('STACK_BLOCKED', state.sourceProblem(container)!);
      }
    }
    if (action == 'register' &&
        state.containers.any(
          (c) =>
              normalizeNumber(c.number) ==
              normalizeNumber(string(payload['number'])),
        )) {
      throw const ApiFailure(
        'DUPLICATE_CONTAINER',
        'This container already exists. Open its record instead.',
      );
    }
    final destinationId = payload['slotId'];
    if (destinationId != null) {
      final s = state.slot(destinationId as String);
      final moving = state.container(string(payload['containerId']));
      final problem = s == null
          ? 'Position no longer exists'
          : state.destinationProblem(
              s,
              moving?.size ?? integer(payload['size']),
              moving: moving,
            );
      if (problem != null) {
        throw ApiFailure(
          'POSITION_CHANGED',
          '$problem. Choose a position again.',
        );
      }
    }
    writing = true;
    _epoch++;
    emit();
    final intent = jsonEncode({
      'action': action,
      'payload': {...payload}..remove('photo'),
      'startedAt': DateTime.now().toUtc().toIso8601String(),
    });
    try {
      await store.write(key('pending'), intent);
      pending = intent;
      final result = await api.action(action, payload);
      snapshot = Snapshot(result['state'] as Json);
      online = true;
      error = null;
      await store.delete(key('pending'));
      pending = null;
      await cache(snapshot!);
      return result['entityId'] as String?;
    } catch (e) {
      final failure = asFailure(e);
      if (e is ApiFailure && !failure.uncertain) {
        await store.delete(key('pending'));
        pending = null;
      } else {
        online = false;
      }
      error = failure;
      rethrow;
    } finally {
      writing = false;
      emit();
    }
  }

  Future<void> acknowledgePending() async {
    if (!await refresh()) {
      throw error ??
          const ApiFailure(
            'CONNECTION',
            'Refresh before resolving this operation.',
          );
    }
    await store.delete(key('pending'));
    pending = null;
    emit();
  }

  Future<void> clearLocalData() async {
    _clearing = true;
    _epoch++;
    _poll?.cancel();
    await _draftWrites.catchError((Object _) {});
    snapshot = null;
    online = false;
    for (final name in ['snapshot', 'registration']) {
      await store.delete(key(name));
    }
    emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _poll?.cancel();
    super.dispose();
  }
}
