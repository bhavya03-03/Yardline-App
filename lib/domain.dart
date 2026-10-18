import 'dart:convert';

typedef Json = Map<String, dynamic>;
int integer(dynamic n) => (n as num?)?.toInt() ?? 0;
String string(dynamic s) => s as String? ?? '';

String normalizeNumber(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
int? checkDigit(String firstTen) {
  if (!RegExp(r'^[A-Z]{3}[UJZ]\d{6}$').hasMatch(firstTen)) return null;
  const values = '0123456789A?BCDEFGHIJK?LMNOPQRSTU?VWXYZ';
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += values.indexOf(firstTen[i]) * (1 << i);
  }
  return (sum % 11) % 10;
}

bool validNumber(String value) {
  final n = normalizeNumber(value);
  return RegExp(r'^[A-Z]{3}[UJZ]\d{7}$').hasMatch(n) &&
      checkDigit(n.substring(0, 10)) == int.parse(n[10]);
}

List<String> extractCandidates(String text) {
  final compact = text.toUpperCase().replaceAll(RegExp(r'[\s.\-]'), '');
  final candidates = RegExp(r'[A-Z]{3}[UJZ][0-9OIL]{7}')
      .allMatches(compact)
      .map((m) {
        final n = m.group(0)!;
        return n.substring(0, 4) +
            n.substring(4).replaceAll('O', '0').replaceAll(RegExp('[IL]'), '1');
      })
      .toSet()
      .toList();
  candidates.sort(
    (a, b) => (validNumber(b) ? 1 : 0).compareTo(validNumber(a) ? 1 : 0),
  );
  return candidates;
}

class Yard {
  final String id, code, name;
  Yard(Json j)
    : id = string(j['id']),
      code = string(j['code']),
      name = string(j['name']);
}

class YardBlock {
  final String id, code, name;
  final int capacityLimit, maxSize, maxTiers;
  YardBlock(Json j)
    : id = string(j['id']),
      code = string(j['code']),
      name = string(j['name']),
      capacityLimit = integer(j['capacity_limit']),
      maxSize = integer(j['max_size']),
      maxTiers = integer(j['max_tiers']);
}

class Slot {
  final String id,
      bayId,
      code,
      status,
      yardId,
      blockId,
      rowId,
      blockCode,
      rowCode,
      bayCode;
  final int tier, maxSize, rowOrdinal, bayOrdinal;
  Slot(Json j)
    : id = string(j['id']),
      bayId = string(j['bay_id']),
      code = string(j['code']),
      status = string(j['status']),
      yardId = string(j['yard_id']),
      blockId = string(j['block_id']),
      rowId = string(j['row_id']),
      blockCode = string(j['block_code']),
      rowCode = string(j['row_code']),
      bayCode = string(j['bay_code']),
      tier = integer(j['tier']),
      maxSize = integer(j['max_size']),
      rowOrdinal = integer(j['row_ordinal']),
      bayOrdinal = integer(j['bay_ordinal']);
  String get shortCode => '$blockCode · $rowCode · $bayCode · T$tier';
}

class YardContainer {
  final String id, number, type, owner, status, yardId, notes;
  final String? slotId, locationCode, verifiedAt;
  final int size;
  final bool identityVerified, hasPhoto;
  YardContainer(Json j)
    : id = string(j['id']),
      number = string(j['number']),
      type = string(j['type']),
      owner = string(j['owner']),
      status = string(j['status']),
      yardId = string(j['current_yard_id']),
      notes = string(j['notes']),
      slotId = j['current_slot_id'] as String?,
      locationCode = j['location_code'] as String?,
      verifiedAt = j['verified_at'] as String?,
      size = integer(j['size']),
      identityVerified = integer(j['identity_verified']) == 1,
      hasPhoto = integer(j['has_photo']) == 1;
}

class Movement {
  final String id, containerId, number, event, occurredAt, actor, notes;
  final String? from, to;
  Movement(Json j)
    : id = string(j['id']),
      containerId = string(j['container_id']),
      number = string(j['container_number']),
      event = string(j['event_type']),
      occurredAt = string(j['occurred_at']),
      actor = string(j['actor_name']),
      notes = string(j['notes']),
      from = j['from_code'] as String?,
      to = j['to_code'] as String?;
}

class Snapshot {
  final Json raw;
  late final Yard yard;
  late final List<Yard> yards;
  late final List<YardBlock> blocks;
  late final List<Slot> slots;
  late final List<YardContainer> containers;
  late final List<Movement> movements;
  late final Json metrics, actor;
  late final String authMode, generatedAt;
  late final Map<String, YardContainer> occupants;
  Snapshot(this.raw) {
    yard = Yard(raw['yard'] as Json);
    yards = (raw['yards'] as List).map((j) => Yard(j as Json)).toList();
    blocks = (raw['blocks'] as List).map((j) => YardBlock(j as Json)).toList();
    slots = (raw['slots'] as List).map((j) => Slot(j as Json)).toList();
    containers = (raw['containers'] as List)
        .map((j) => YardContainer(j as Json))
        .toList();
    movements = (raw['movements'] as List)
        .map((j) => Movement(j as Json))
        .toList();
    metrics = raw['metrics'] as Json;
    actor = raw['actor'] as Json;
    authMode = string(raw['authMode']);
    generatedAt = string(raw['generatedAt']);
    occupants = {
      for (final c in containers)
        if (c.slotId != null) c.slotId!: c,
    };
  }
  factory Snapshot.decode(String encoded) =>
      Snapshot(jsonDecode(encoded) as Json);
  YardContainer? container(String id) {
    for (final c in containers) {
      if (c.id == id) return c;
    }
    return null;
  }

  Slot? slot(String? id) {
    for (final s in slots) {
      if (s.id == id) return s;
    }
    return null;
  }

  String? sourceProblem(YardContainer c) {
    if (c.status == 'dispatched') {
      return 'This container has already been dispatched.';
    }
    final source = slot(c.slotId);
    if (source != null &&
        slots.any(
          (s) =>
              s.bayId == source.bayId &&
              s.tier > source.tier &&
              occupants.containsKey(s.id),
        )) {
      return 'Move the containers above this one first.';
    }
    return null;
  }

  /// Preview only: the shared backend revalidates all rules transactionally.
  String? destinationProblem(Slot s, int size, {YardContainer? moving}) {
    if (s.yardId != yard.id) return 'Different yard';
    if (moving?.slotId == s.id) return 'Current position';
    if (s.status != 'available') return s.status;
    final occupancy = {...occupants};
    if (moving?.slotId != null) occupancy.remove(moving!.slotId);
    if (occupancy.containsKey(s.id)) return 'Occupied';
    if (size > s.maxSize) return 'Up to ${s.maxSize} ft';
    final lower = slots
        .where((l) => l.bayId == s.bayId && l.tier < s.tier)
        .toList();
    if (lower.length != s.tier - 1 ||
        lower.any((l) => !occupancy.containsKey(l.id))) {
      return 'Fill lower tiers first';
    }
    if (lower.any((l) => occupancy[l.id]!.size != size)) {
      return 'Stack length mismatch';
    }
    final block = blocks.where((b) => b.id == s.blockId).firstOrNull;
    final used = slots
        .where((l) => l.blockId == s.blockId && occupancy.containsKey(l.id))
        .length;
    if (block != null && used >= block.capacityLimit) {
      return 'Block at capacity';
    }
    return null;
  }
}
