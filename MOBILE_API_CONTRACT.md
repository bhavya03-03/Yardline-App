# Yardline mobile API contract

> **Flutter implementation:** The [Yardline App repository](https://github.com/bhavya03-03/Yardline-App) consumes this contract; see its [README](https://github.com/bhavya03-03/Yardline-App#readme). Registration and OCR are mobile workflows; the website registration tab and shortcuts have been removed, while `/api/actions/register` remains available to authorized clients. The website reads shared state every 30 seconds while visible and on focus, visibility, and connectivity restoration. Backend source paths below refer to the [website repository](https://github.com/bhavya03-03/Yardline/tree/master/yardline). Snapshot counts describe earlier verification, not constants to hardcode.

Source baseline: `f3b3cc3` (`figmafinal`), inspected 2026-10-18. This describes **existing HTTP behavior**, not a proposed REST API. See [MOBILE_INTEGRATION.md](MOBILE_INTEGRATION.md) for physical schema, JSON request schemas, error catalog, security audit, and limitations. [MOBILE_IMPLEMENTATION_GUIDE.md](MOBILE_IMPLEMENTATION_GUIDE.md) applies this contract to Flutter.

## Verified Netlify demonstration (2026-10-18)

The live API origin is **`https://yardline-bhavya0303.netlify.app`**. It uses one Netlify-managed PostgreSQL database and `AUTH_MODE=demo`. The owner requested public access without sign-in; the optional HTTP Basic gate is disabled for production. Live checks verified 102 containers, 212 movements, viewer write rejection, and transaction rollback for an invalid relocation. Supabase worker sign-in remains unverified.

For this deployment, do not prompt for access credentials or send a Basic authorization header. Select `operator` through `/api/session` and persist its `yardline_role` cookie on subsequent requests. Without a role cookie, the demo defaults to administrator. Anyone with the link can select a shared demo persona. This is not individual worker authentication. Always use HTTPS.

Production page and state requests are accessible without credentials. Previews retain Netlify team login; use the production origin above for the worker demonstration. Local SQLite and deployed PostgreSQL do not automatically synchronize: both web and mobile must use the deployed API to share records. The original source baseline below is superseded by this section for deployment details.

## Connection and authentication

Configure `YARDLINE_API_BASE_URL` as an origin, using the deployed URL above or development `http://<CONTROL_LAPTOP_LAN_IP>:3000`. This is a **proposed mobile config name**, not an existing server variable. Routes below include `/api` already. The deployed demo requires no sign-in or Basic header.

- Secure backend (`AUTH_MODE=supabase`): sign in through the existing Supabase Auth project, attach `Authorization: Bearer <ACCESS_TOKEN>` to JSON and photo requests. Account must have `user_profiles` and selected `yard_memberships` records provisioned by the backend owner. Refresh tokens through the auth SDK, not a Yardline refresh route.
- Trusted demo (`AUTH_MODE` unset/`demo`): POST `/api/session` with `{"role":"operator"}` and preserve the `yardline_role` cookie on subsequent requests. No cookie defaults to **administrator**, not anonymous. Role switching is not authentication. Demo role identities are shared personas.
- Native Flutter normally sends no Origin; supported by current backend. Flutter Web on a different origin needs same-origin proxying or a future CORS change.
- JSON POST: `Content-Type: application/json`; all JSON reads should bypass caches. Photos are binary. Remote use requires HTTPS.
- Never place database credentials or service-role keys in the mobile project. Optional public Supabase URL/anon key must match the backend's project.

## Endpoint index

| Method | Full route                    | Request                        | Success                      | Permission              |
| ------ | ----------------------------- | ------------------------------ | ---------------------------- | ----------------------- |
| GET    | `/api/state`                  | Optional `?yard=<yard-id>`     | `200 Snapshot`               | Yard member / demo role |
| POST   | `/api/actions/register`       | `RegisterRequest`              | `200 ActionResult`, new ID   | Administrator/operator  |
| POST   | `/api/actions/move`           | `MoveRequest`                  | `200 ActionResult`, null ID  | Administrator/operator  |
| POST   | `/api/actions/dispatch`       | `DispatchRequest`              | `200 ActionResult`, null ID  | Administrator/operator  |
| POST   | `/api/actions/verify`         | `VerifyRequest`                | `200 ActionResult`, null ID  | Administrator/operator  |
| GET    | `/api/containers/<id>/photo`  | ID in path, auth header/cookie | `200 image bytes`            | Yard member / demo role |
| POST   | `/api/session`                | `DemoSessionRequest`           | `200 {ok:true}` + cookie     | Demo only               |
| POST   | `/api/actions/create-yard`    | `CreateYardRequest`            | `200 ActionResult`, yard ID  | Administrator           |
| POST   | `/api/actions/update-yard`    | `UpdateYardRequest`            | `200 ActionResult`, null ID  | Administrator           |
| POST   | `/api/actions/generate-block` | `GenerateBlockRequest`         | `200 ActionResult`, block ID | Administrator           |
| POST   | `/api/actions/create-zone`    | `CreateZoneRequest`            | `200 ActionResult`, null ID  | Administrator           |
| POST   | `/api/actions/update-slot`    | `UpdateSlotRequest`            | `200 ActionResult`, null ID  | Administrator           |

No dedicated login, secure session, OCR, container-search, container-detail JSON, availability, movement-history, pagination, re-entry, metadata-update, sync-events, or health endpoint exists. Read those supported resources from `/api/state`; do not call invented routes. Secure login/refresh/logout belongs to Supabase Auth, not `/api/session`.

## Wire interfaces

These TypeScript interfaces document JSON for the Flutter developer; port to Dart models. Response models mirror `src/lib/types.ts`; request interfaces describe `src/server/validation.ts` (the repository does not export these request interfaces). Models are snake_case, action inputs camelCase. Nullable properties must remain nullable. Omit optional request fields when unused; optional does not mean null is accepted.

```ts
export type Id = string; // opaque; do not require UUID syntax
export type IsoUtc = string;
export type Role = 'administrator' | 'operator' | 'viewer';
export type SlotStatus = 'available' | 'reserved' | 'blocked' | 'restricted';
export type ContainerStatus = 'stored' | 'unassigned' | 'dispatched';
export type EventType = 'arrival' | 'placement' | 'relocation' | 'dispatch' | 'verification';
export type ContainerSize = 20 | 40 | 45;
export type ZoneKind = 'road' | 'loading' | 'restricted';
export type Point = [number, number];

export interface Yard {
  id: Id;
  code: string;
  name: string;
  width: number;
  height: number;
  boundary: string; // JSON ENCODED array of points; decode separately, not a JSON array here
  is_demo: number; // integer flag, normally 0 or 1, not JSON boolean
  created_at: IsoUtc;
}
export interface Block {
  id: Id;
  yard_id: Id;
  code: string;
  name: string;
  x: number;
  y: number;
  width: number;
  height: number;
  max_tiers: number;
  capacity_limit: number;
  max_size: number;
}
export interface StorageRow {
  id: Id;
  block_id: Id;
  code: string;
  ordinal: number;
}
export interface Bay {
  id: Id;
  row_id: Id;
  code: string;
  ordinal: number;
  max_tiers: number;
}
export interface Slot {
  id: Id;
  bay_id: Id;
  tier: number;
  code: string;
  x: number;
  y: number;
  status: SlotStatus; // administrative state, NOT occupied/free
  max_size: number;
  capacity: number; // DB constrains to 1
  // These extra fields come from joins, not physical storage_slots columns:
  yard_id: Id;
  block_id: Id;
  row_id: Id;
  block_code: string;
  row_code: string;
  bay_code: string;
  row_ordinal: number;
  bay_ordinal: number;
}
export interface Container {
  id: Id;
  number: string;
  size: number;
  type: string;
  owner: string;
  status: ContainerStatus;
  current_yard_id: Id;
  current_slot_id: Id | null;
  identity_verified: number; // integer flag, normally 0 or 1
  registered_at: IsoUtc;
  verified_at: IsoUtc | null; // LOCATION verification timestamp
  notes: string;
  has_photo?: number; // SELECT currently returns this integer flag
  location_code?: string | null; // SELECT currently returns joined code, nullable
  // photo payload is deliberately absent; fetch protected image endpoint
}
export interface Movement {
  id: Id;
  container_id: Id;
  from_slot_id: Id | null;
  to_slot_id: Id | null;
  event_type: EventType;
  occurred_at: IsoUtc;
  user_id: Id | null;
  actor_name: string;
  notes: string;
  container_number: string; // join
  from_code: string | null; // join
  to_code: string | null; // join
}
export interface Zone {
  id: Id;
  yard_id: Id;
  kind: ZoneKind;
  label: string;
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface Actor {
  id: Id;
  name: string;
  role: Role; // active yard role, can differ between yards
}
export interface Metrics {
  capacity: number;
  occupied: number;
  available: number;
  usable: number;
  reserved: number;
  blocked: number;
  restricted: number;
  assignable: number;
  utilization: number; // rounded integer percent
  unassigned: number;
  attention: number;
  movesToday: number;
}
export interface Snapshot {
  yards: Yard[]; // accessible yards, not global list in secure mode
  yard: Yard; // selected yard
  blocks: Block[];
  rows: StorageRow[];
  bays: Bay[];
  slots: Slot[];
  zones: Zone[];
  containers: Container[]; // selected yard including dispatched
  movements: Movement[]; // latest 1000, not complete history
  metrics: Metrics;
  actor: Actor;
  persistence: 'sqlite' | 'postgres';
  authMode: 'demo' | 'supabase';
  generatedAt: IsoUtc; // not a revision number or cursor
}
export interface ActionResult {
  state: Snapshot;
  entityId: Id | null;
}
export interface ApiError {
  error: { code: string; message: string };
}
export interface DemoSessionResult {
  ok: true;
}

export interface RegisterRequest {
  yardId: Id; // all request IDs: nonempty, <=100 characters
  number: string; // input 5..30 chars, then normalize and ISO-check
  size: ContainerSize;
  type?: string; // trimmed 1..40, default Dry
  owner?: string; // trimmed <=80, default ''
  notes?: string; // trimmed <=1500, default ''
  slotId?: Id | null; // default null = unassigned
  physicalConfirmed?: boolean; // default false; must be true with a slot
  allowException?: boolean; // default false; only administrator may bypass invalid ISO
  photo?: string; // data:image/(jpeg|png|webp);base64,... <=2,800,000 chars
}
export interface MoveRequest {
  yardId: Id;
  containerId: Id;
  slotId: Id;
  expectedSlotId: Id | null; // REQUIRED even when null
  physicalConfirmed: true;
  notes?: string; // trimmed <=1500
}
export interface DispatchRequest {
  yardId: Id;
  containerId: Id;
  expectedSlotId: Id | null; // REQUIRED even when null
  confirmed: true;
  notes?: string; // trimmed <=1500
}
export interface VerifyRequest {
  yardId: Id;
  containerId: Id;
  expectedSlotId: Id; // cannot be null
  physicalConfirmed: true;
}
export interface DemoSessionRequest {
  role: Role;
}

// Administrative request documentation; do not expose configuration to workers.
export interface CreateYardRequest {
  code: string; // 2..8 uppercase letters/digits, first character letter
  name: string; // trimmed 2..80
  width: number; // 20..2000
  height: number; // 20..2000
  boundary?: Point[]; // default [], <=40; empty or >=3, within plot
}
export interface UpdateYardRequest extends Omit<CreateYardRequest, 'code'> {
  yardId: Id;
}
export interface GenerateBlockRequest {
  yardId: Id;
  code: string;
  name: string; // trimmed 2..80
  rows: number; // int 1..20
  bays: number; // int 1..30, required even with rowBayCounts
  rowBayCounts?: number[]; // each int 1..30, one per row
  tiers: number; // int 1..6
  x: number; // >=0
  y: number; // >=0
  width: number; // 10..1000
  height: number; // 10..1000
  maxSize?: ContainerSize; // default 40
  capacityLimit?: number; // positive int <= generated slot count
}
export interface CreateZoneRequest {
  yardId: Id;
  kind: ZoneKind;
  label: string; // trimmed 2..70
  x: number; // >=0
  y: number; // >=0
  width: number; // >=1
  height: number; // >=1
}
export interface UpdateSlotRequest {
  yardId: Id;
  slotId: Id;
  status: SlotStatus;
}
```

In Dart, use a distinct name such as `YardContainer` to avoid confusion with Flutter's `Container` widget. Treat numeric JSON as `num` before converting to `double`/`int`; coordinates can be fractional. Integer flags use `value == 1`, not a boolean cast. Do not remove null `expectedSlotId` from move/dispatch JSON.

## Worker request examples and outcomes

All IDs below are placeholders populated from the latest snapshot. The supplied slot codes are demonstration lookup aids, not request IDs. Numbers are checksum-valid examples; registration will reject an example already present globally.

### Read and search

```http
GET /api/state?yard=<YARD_ID>
Authorization: Bearer <ACCESS_TOKEN>
Accept: application/json
```

Returns a bare `Snapshot`. Find a number by uppercase/whitespace-hyphen normalization in `containers`. Find slots by ID/code in `slots`. For history, filter `movements` by `container_id`. No server search parameters beyond `yard` are implemented.

An actual container object shape in a snapshot (illustrative IDs/time):

```json
{
  "id": "<CONTAINER_ID>",
  "number": "MSCU1234566",
  "size": 40,
  "type": "Dry",
  "owner": "Example shipping line",
  "status": "stored",
  "current_yard_id": "<YARD_ID>",
  "current_slot_id": "<CURRENT_SLOT_ID>",
  "identity_verified": 1,
  "registered_at": "2026-10-18T08:00:00.000Z",
  "verified_at": "2026-10-18T09:00:00.000Z",
  "notes": "Worker reviewed.",
  "has_photo": 0,
  "location_code": "YD01-B01-R01-BY01-T01"
}
```

### Register and assign

```http
POST /api/actions/register
Content-Type: application/json
Authorization: Bearer <ACCESS_TOKEN>

{
  "yardId": "<YARD_ID>", "number": "TGHU7599330", "size": 40,
  "type": "Dry", "owner": "Example shipping line", "notes": "Door number reviewed.",
  "slotId": "<AVAILABLE_SLOT_ID>", "physicalConfirmed": true,
  "allowException": false
}
```

200 `ActionResult`: created ID in `entityId`, full `state`, arrival plus placement events. For unassigned arrival, omit slot/photo/confirmation or send `slotId:null`. No OCR confidence/worker ID/client timestamp fields exist. Human identity-review checkbox must be enforced by the mobile UI.

### Relocate or place unassigned

```http
POST /api/actions/move
Content-Type: application/json
Authorization: Bearer <ACCESS_TOKEN>

{
  "yardId": "<YARD_ID>", "containerId": "<CONTAINER_ID>",
  "slotId": "<DESTINATION_SLOT_ID>", "expectedSlotId": "<CURRENT_SLOT_ID>",
  "physicalConfirmed": true, "notes": "Confirmed at destination."
}
```

200 `ActionResult`, `entityId:null`. Use explicit `expectedSlotId:null` for unassigned placement. Do not register the number again.

### Dispatch

```http
POST /api/actions/dispatch
Content-Type: application/json
Authorization: Bearer <ACCESS_TOKEN>

{
  "yardId": "<YARD_ID>", "containerId": "<CONTAINER_ID>",
  "expectedSlotId": "<CURRENT_SLOT_ID>", "confirmed": true, "notes": "Gate-out checked."
}
```

200 `ActionResult`, `entityId:null`, new status dispatched and slot null. Explicit expected null also works for unassigned departure. No separate gate-pass/truck workflow exists. Dispatched numbers cannot re-register or move.

### Verify

```http
POST /api/actions/verify
Content-Type: application/json
Authorization: Bearer <ACCESS_TOKEN>

{
  "yardId": "<YARD_ID>", "containerId": "<CONTAINER_ID>",
  "expectedSlotId": "<CURRENT_SLOT_ID>", "physicalConfirmed": true
}
```

200 `ActionResult`, `entityId:null`; location timestamp and verification event updated. Identity flag unchanged. No request notes field is accepted by this schema. Repeating adds another event.

Example movement response object:

```json
{
  "id": "<MOVEMENT_ID>",
  "container_id": "<CONTAINER_ID>",
  "from_slot_id": "<SOURCE_SLOT_ID>",
  "to_slot_id": "<DESTINATION_SLOT_ID>",
  "event_type": "relocation",
  "occurred_at": "2026-10-18T09:05:00.000Z",
  "user_id": "demo-operator",
  "actor_name": "Priya Patel",
  "notes": "Confirmed at destination.",
  "container_number": "MSCU1234566",
  "from_code": "YD01-B01-R01-BY01-T01",
  "to_code": "YD01-B02-R04-BY01-T01"
}
```

### Photo

```http
GET /api/containers/<CONTAINER_ID>/photo
Authorization: Bearer <ACCESS_TOKEN>
Accept: image/jpeg,image/png,image/webp
```

200 bytes with image Content-Type. On non-200 parse JSON error if available. The state only exposes `has_photo`; no data URL/photo bytes are in the snapshot. POST registration is the only existing attachment operation.

## Error handling

```json
{
  "error": {
    "code": "SLOT_OCCUPIED",
    "message": "This position is already occupied. Choose another position."
  }
}
```

| Status / codes                                | Mobile behavior                                                                     |
| --------------------------------------------- | ----------------------------------------------------------------------------------- |
| 400 rule error                                | Preserve form, explain the rule; no blind retry                                     |
| 401 `UNAUTHENTICATED`                         | Renew session/re-login, refetch; retry GET only when safe                           |
| 403 `FORBIDDEN`, `NO_YARD`                    | Access/role issue; stop writes and request provisioning                             |
| 403 `CROSS_ORIGIN`                            | Browser origin/deployment issue; not bad worker credentials                         |
| 404 `NOT_FOUND`                               | Missing entity/action/image; refresh/check route/ID                                 |
| 409 `DUPLICATE_CONTAINER`                     | Open existing record when visible; no second registration                           |
| 409 `SLOT_OCCUPIED`, `SLOT_UNAVAILABLE`       | Refresh and review destination availability                                         |
| 409 `STALE_LOCATION`, `STACK_BLOCKED`         | Re-read and require worker review                                                   |
| 409 `CONFLICT`                                | DB unique conflict; refresh and reconcile                                           |
| 413 `TOO_LARGE`                               | Reduce optional image/JSON payload                                                  |
| 422 `VALIDATION_ERROR`, `IDENTITY_UNVERIFIED` | Fix form/number; operators cannot use exceptions                                    |
| 503 `AUTH_CONFIGURATION`, `DATABASE_ERROR`    | Server/configuration problem; preserve draft; write outcome may need reconciliation |
| Timeout/non-JSON/connection loss              | Handle as transport error; POST outcome unknown                                     |

Full code/status matrix is in the comprehensive document. Session invalid-role uses 400; malformed session JSON may yield 503. `error.message` is plain text with no guaranteed field details. Middleware/proxies/framework errors may be non-JSON. Unknown error codes must remain displayable without crashing.

## Placement, synchronization, and recovery rules

- One container per slot. Build `occupantsBySlotId` from non-null `current_slot_id`; `status:'available'` alone does not imply vacancy.
- Real slot IDs come from current layout. Respect lower-tier support, matching lengths, slot max size, block capacity, and source accessibility. Backend is authoritative, even if client hints say valid.
- Save success only after HTTP 200, valid `ActionResult`, and server-confirmed state. Do not optimistically mark occupancy as committed.
- Serialize mutations; do not let a late polling GET replace a newer mutation result. Poll while foregrounded (30 seconds matches current web behavior); refetch on foreground/reconnect/yard switch and before confirming an operation.
- No subscription endpoint exists. A mobile commit appears in web at the next successful visible-tab poll. Do not promise instantaneous realtime.
- On disconnection, show last state with age and keep drafts separate. Disable final write actions until connected; cached vacancies are not reserved. A connectivity indicator is advisory; real requests determine reachability.
- No automatic POST retries: a lost response may follow a successful commit. Reconcile by fresh snapshot/history and human review. Do not change `expectedSlotId` and automatically replay stale intent.
- Repeated verify creates duplicate events; register/move/dispatch retries may conflict. No idempotency or client operation lookup exists.
- History is limited to 1,000 events; `generatedAt` is not a sync cursor. Do not infer exactly-once completion from current location alone.
- No automatic cross-yard transfer or dispatched-container re-entry. Escalate those cases to the backend owner.

## Backend-owner changes versus client work

**Existing and sufficient for a trusted online demo:** state, register, move, dispatch, verify, binary photo, demo operator cookie, shared SQLite persistence, polling.

**Must be supplied/verified:** reachable API origin; consistent auth mode; native device transport/camera setup; live Supabase project and provisioned accounts if using secure mode; persistent hosting when off-LAN. PostgreSQL/Supabase integrations are not validated by the local SQLite test suite.

**Proposed, not implemented:** authenticated push stream, paginated reads, structured OCR audit metadata, client timestamps, idempotency/outbox/versioning, safe automatic offline replay, controlled re-entry. Do not implement a second backend to fill these gaps.
