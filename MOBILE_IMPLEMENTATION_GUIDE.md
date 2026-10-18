# Build the Yardline Flutter worker client

> **Implementation update:** The Android/iOS worker client is implemented in the separate [Yardline App repository](https://github.com/bhavya03-03/Yardline-App). Start with its [README](https://github.com/bhavya03-03/Yardline-App#readme) for current commands, configuration, workflows, and test coverage. Container registration and OCR remain in the mobile app; the web dashboard has no registration tab or shortcuts and refreshes shared state automatically. Backend source paths below refer to the [website repository](https://github.com/bhavya03-03/Yardline/tree/master/yardline). The sections below retain the original handoff and distinguish backend facts from initial client proposals. Do not create another backend or database.

This is an implementation handoff for a **separate Flutter codebase**. It does not create an application, a backend, or a database. It is based on existing Yardline commit `f3b3cc3`, inspected 2026-10-18.

Read [MOBILE_API_CONTRACT.md](MOBILE_API_CONTRACT.md) first for wire types; consult [MOBILE_INTEGRATION.md](MOBILE_INTEGRATION.md) for schema, security, validation, and gaps. These documents describe source-backed behavior. Flutter modules, packages, config names, and code snippets below are **recommended client implementation**, not existing application files.

## Deployment update (2026-10-18)

Use **`https://yardline-bhavya0303.netlify.app`** as the shared API origin for the hosted demonstration. PostgreSQL reads, invalid-operation rollback, viewer restrictions, and preservation of 102 containers / 212 movements are verified. At the owner's request, the public demonstration opens without sign-in. Do not build a password prompt or attach a Basic header for this deployment. Follow the verified Netlify section in [MOBILE_API_CONTRACT.md](MOBILE_API_CONTRACT.md): select operator through `/api/session` and preserve the role cookie. Anyone with the link can select shared demo personas; no cookie defaults to administrator. Never send database credentials to the phone. Both the phone and hosted web UI must use this same origin; the local SQLite instance is a separate, unsynchronized development instance. Individual Supabase worker accounts remain a separate, unverified production setup.

## 1. Agree the connection details before coding

The backend owner must supply:

1. **One API origin** reachable from the worker device: use the verified hosted origin above, or `http://<CONTROL_LAPTOP_LAN_IP>:3000` on a trusted local demonstration LAN.
2. Authentication mode: trusted demo cookie or Supabase worker login. The Flutter app must not silently fall back between them.
3. Secure-mode only: existing Supabase project URL, **public** anon/publishable key, and a worker account provisioned as operator for the existing yard. Account credentials are delivered privately, never embedded in documentation or source code.
4. An existing yard code/name for selecting from the accessible `yards` list. Resolve the real ID from state; do not hardcode IDs from screenshots.

The other developer does **not** receive `DATABASE_URL`, SQLite files, service-role keys, or backend secrets. Do not spin up a second Yardline server with its own seed data on the mobile-development laptop. The phone and web operator must talk to the same running server/database.

## 2. Start/reach the existing backend

These are instructions for the **backend owner**, not commands to run on the separate Flutter laptop to create another server. Do not change authentication/database mode on an already populated instance without coordinating the switch; there is no automatic SQLite-to-PostgreSQL migration.

For the trusted local demonstration, existing project startup is:

```powershell
cd '<PATH_TO_EXISTING_YARDLINE_REPOSITORY>'
# On first setup only; use Node >=24.12. Existing installs can skip npm ci.
npm.cmd ci
npm.cmd run dev
```

The dev command binds to `0.0.0.0`; keep the existing server if it is already running. Default port is 3000. An empty demo DB can seed automatically. `npm run db:seed` leaves an existing yard intact; **do not reset the working database** or run a second copy for mobile.

- Put laptop and phone on a LAN permitting device-to-device traffic. A managed/guest Wi-Fi may isolate clients.
- Use the control laptop's reachable private IPv4 address in `YARDLINE_API_BASE_URL`. The other laptop's address is not the backend unless explicitly hosting that same shared service.
- Request `/api/state` in a phone browser first as a network smoke test for a trusted demo. This browser session does not authenticate the native app, and demo GET without a cookie appears as administrator.
- If unreachable, verify server port/bind, selected Wi-Fi, routing, and a narrow firewall allowance for the private network. Do not disable the firewall globally.
- Android emulator commonly reaches its host via `10.0.2.2`; this is not the address of a backend on a different laptop. For a separate backend host use its LAN address.
- iOS simulator localhost reaches its Mac host, not the Windows control laptop. Physical device localhost always refers to that device.
- Android cleartext and iOS ATS may reject local HTTP. Add only documented **debug/development** exceptions in the Flutter project, or use a configured HTTPS endpoint. Keep release traffic HTTPS. Camera/browser checks do not prove native transport settings are correct.

For individually authenticated remote operation, the owner completes the existing backend's Supabase worker provisioning and replaces the shared demonstration gate with the worker-authentication design. Supabase sign-in alone does not create a Yardline membership. Use `scripts/provision.ts` against the intended existing yard. Do not deploy the SQLite file to ephemeral Netlify functions; the verified Netlify deployment instead uses managed PostgreSQL.

## 3. Initialize a separate Flutter client project

On the Flutter developer's machine, install the supported Flutter SDK and Android tooling, then:

```sh
flutter doctor
flutter create yardline_mobile
cd yardline_mobile
```

Keep this outside the web codebase unless the owner explicitly chooses a monorepo. Android is a practical first demo target on a Windows laptop. Native iOS builds/signing require macOS and Xcode. Flutter Web is a separate target with current CORS restrictions; a browser build is not a substitute for native integration validation.

Recommended packages to evaluate, add only as needed, and pin in the new client's lockfile:

| Need                                       | Candidate                                                      | Notes                                                                           |
| ------------------------------------------ | -------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| HTTP, timeouts, interceptors, binary reads | `dio`                                                          | Disable implicit mutation retry behavior; handle status/errors explicitly       |
| Demo cookie persistence                    | `cookie_jar`, `dio_cookie_manager`                             | In-memory jar + role selection on every app startup is sufficient for demo      |
| Existing secure login                      | `supabase_flutter`                                             | Auth only; do not use application table CRUD or Realtime                        |
| Photograph capture/picker                  | `image_picker`                                                 | Native platform configuration/permission handling required                      |
| Native OCR                                 | `google_mlkit_text_recognition`                                | Evaluate supported Android/iOS SDK versions and model delivery/offline behavior |
| Secure session/draft storage               | `flutter_secure_storage` and a reviewed draft-storage approach | Configure auth session storage deliberately; limit retained photos              |

These packages are not dependencies of the web repository. Check their current platform/minimum SDK requirements and licenses before selecting versions. ML Kit Flutter text output may not expose calibrated confidence. Do not promise a confidence value or first-launch offline OCR without testing model availability.

Example package selection commands (for the new client, not this repository):

```sh
flutter pub add dio cookie_jar dio_cookie_manager image_picker google_mlkit_text_recognition
# Secure-auth mode only:
flutter pub add supabase_flutter flutter_secure_storage
```

Suggested client-only module structure:

```text
lib/
  config/                 API origin and explicit authentication mode
  models/                 Dart equivalents of the documented JSON types
  services/               HTTP, auth, foreground polling, on-device OCR
  repositories/           Authoritative snapshot and draft lifecycle
  features/login/         Secure login or clearly labeled demo role setup
  features/yard/          Yard/block/row/bay/tier selection and occupancy
  features/search/        Snapshot search and container detail
  features/register/      Camera, editable number, metadata, initial placement
  features/operations/    Place, relocate, dispatch, location verification
  features/history/       Recent recorded movements
```

This is an organizational proposal, not server routing. Avoid a mobile-side SQL schema for authoritative yard records. Local drafts/cached snapshots must be explicitly non-authoritative.

## 4. Configure the origin and establish authentication

Recommended client settings, supplied through the new project's configuration:

```text
YARDLINE_API_BASE_URL=https://<BACKEND_HOST>
YARDLINE_AUTH_MODE=supabase
SUPABASE_URL=https://<EXISTING_PROJECT>.supabase.co
SUPABASE_ANON_KEY=<PUBLIC_ANON_OR_PUBLISHABLE_KEY>
```

These are proposed Flutter setting names, not exact copies of backend env names. `--dart-define` values are compiled into the client and are **not secret storage**. It is acceptable for public API origin/project URL/public key. Do not pass passwords or server keys with it.

Example launch:

```sh
flutter run --dart-define=YARDLINE_API_BASE_URL=http://<CONTROL_LAPTOP_LAN_IP>:3000 --dart-define=YARDLINE_AUTH_MODE=demo
```

### Trusted demo flow

1. Create a native HTTP client with a cookie jar.
2. POST `/api/session` body `{"role":"operator"}`. Require 200 and keep returned cookie.
3. GET `/api/state` using that same client. Require `authMode == 'demo'` and `actor.role == 'operator'` before permitting writes.
4. Select accessible yard and use `/api/state?yard=<selected-id>` for subsequent reads.
5. On cold restart with an in-memory jar, repeat role selection. If cookie disappears, backend defaults to administrator: detect that mismatch and reestablish operator mode before continuing.

Do not add a fake password screen that gives the impression these shared demo personas are individual worker accounts.

### Secure worker flow

1. Initialize Supabase Auth for the backend's existing identity project.
2. Sign in the provisioned worker with email/password through the SDK. Persist/refresh the session using reviewed platform-secure storage configuration; do not persist the password.
3. Attach its current access token to every Yardline request. The backend independently verifies it and looks up membership.
4. GET state. Reject a backend/config mismatch if it reports demo mode when secure mode was expected.
5. On 401, refresh/re-login; on 403, show provisioning/yard-role problem. A user may sign in successfully yet have no yard membership.
6. Logout clears auth state, cookie jar, cached protected images/state, and sensitive drafts according to the client's explicit retention policy.

No Yardline `/api/login`, `/api/auth/refresh`, or `/api/logout` routes exist. The server's secure mode disables `/api/session` demo switching. Do not pass role or user ID in JSON to impersonate workers.

## 5. Implement the HTTP client and models first

Port the interfaces from `MOBILE_API_CONTRACT.md` before building screens:

- `boundary` is a JSON-encoded **string**, so decode it to a point list separately.
- `identity_verified`, `has_photo`, `is_demo` are integer flags, not booleans.
- Use a name such as `YardContainer`, avoiding collision with Flutter's `Container` widget.
- Keep `current_slot_id`, `verified_at`, movement from/to fields, and `entityId` nullable.
- Use `num` conversion for numeric fields, since an integral coordinate can arrive as an integer and another as fractional.
- Keep `expectedSlotId` present even when null. Omit `photo` if absent; `photo:null` is invalid.
- `/api/state` returns a bare Snapshot; actions wrap it as `{state,entityId}`. Photo GET returns bytes. These need separate parsers.

Recommended request handling:

1. Construct paths against one configured origin, URL-encode query/path IDs, attach JSON Content-Type and current auth/cookie.
2. Apply bounded connect/read timeouts; preserve HTTP status plus server error code/message in a typed client exception.
3. Decode documented JSON envelopes; handle unexpected content types and proxy errors gracefully.
4. Treat connection loss after a POST as **unknown outcome**, not a safe retry.
5. Serialize writes and protect snapshot replacement from older in-flight reads. Apply each successful action's full returned state.
6. For secure photos, use an authenticated bytes request and display the bytes, or a verified image widget with the proper headers. Do not put access tokens in query strings or logs.

Illustrative Dart JSON construction for relocation, with IDs taken from parsed state:

```dart
final request = <String, dynamic>{
  'yardId': snapshot.yard.id,
  'containerId': container.id,
  'slotId': selectedDestination.id,
  'expectedSlotId': container.currentSlotId, // keep this key even when null
  'physicalConfirmed': true, // only after explicit worker confirmation
  'notes': workerNotes.trim(),
};
// POST this object to /api/actions/move using the authenticated client.
// Parse ActionResult and replace the authoritative snapshot only on success.
```

Do not create a generic endpoint like `PATCH /containers/:id/location`; the only existing move contract is the action above.

## 6. Build online read-only screens

Build/test in this order:

1. Authentication/connection screen with clear error states.
2. Yard selector from `state.yards`; active yard from `state.yard`.
3. Search `state.containers` locally by normalized number, display location/status, select the real container ID.
4. Block/row/bay/tier browser from the actual arrays and their parent IDs. Irregular blocks can have different bay counts per row; never reconstruct a uniform grid from assumptions.
5. Occupancy from `container.current_slot_id` joins. An `available` slot can be occupied. Render reserved/blocked/restricted with text/symbols as well as color.
6. Recent history from `state.movements`, clearly limited to latest 1,000 yard events. Do not label it a complete historical export.

If using existing design language, consult the web repository's `figma.md`: white/black chrome, pill actions, variable-weight sans, uppercase mono labels, pastel sections, lime yard surface `#dceeb1`, navy occupied cells. Use readable native touch targets and responsive layouts; do not apply the desktop's 80% CSS zoom to a Flutter UI.

Polling: foreground timer around 30 seconds plus refresh on resume, yard change, reconnect, and before commit review. Pause background polling. No realtime subscription is available. `generatedAt` can show snapshot age but is not an event cursor.

## 7. Implement camera OCR and human review

1. Configure and test native camera/photo-picker permissions, cancellation, permanently denied states, and manual fallback. Explain permission use through appropriate platform text. Android camera picker/plugin requirements and iOS usage-description requirements differ; follow chosen package documentation rather than requesting broad unnecessary permissions.
2. Capture the printed container number close up. Crop/rotate/re-encode on device if needed.
3. Run on-device text recognition and extract candidate numbers. If OCR/model loading fails, retain manual entry.
4. Show the source image and editable suggestion. Do not mark OCR output as verified automatically or manufacture confidence values.
5. Normalize, validate, require explicit identity review, then proceed to metadata/location.
6. Prefer small JPEG attachment under 2 MB binary and keep encoded data URL under 2,800,000 characters and total request under 3,000,000 bytes. Compress further or omit optional attachment when needed. Base64 must have no line breaks.

Suggested Dart parity helper (recommended client code; not a repository backend change):

```dart
String normalizeContainerNumber(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

bool hasValidIso6346CheckDigit(String value) {
  final number = normalizeContainerNumber(value);
  if (!RegExp(r'^[A-Z]{3}[UJZ][0-9]{7}$').hasMatch(number)) return false;
  const values = '0123456789A?BCDEFGHIJK?LMNOPQRSTU?VWXYZ';
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += values.indexOf(number[i]) * (1 << i);
  }
  return (sum % 11) % 10 == int.parse(number[10]);
}
```

Add client tests for `MSCU1234566` and `MSCU 123456 6` valid, `MSCU1234567` invalid, and `TGHU7599330` valid. Also test format, zero-leading serials, category U/J/Z, and OCR numeric O/I/L substitutions only as reviewed suggestions. The backend revalidates; passing the client check never bypasses it.

No server OCR/confidence endpoint exists. Submit only final `number` and documented fields. Confidence/raw OCR/capture time may be kept in a local review draft, but are not structured server metadata. Do not change a check digit solely to pass validation without checking the physical identifier.

## 8. Implement operations in order

### Registration / new gate-in

1. Refresh and search selected yard snapshot; global duplicate protection still happens on server.
2. Review OCR/manual number, required length 20/40/45, and optional type/owner/notes.
3. Either register unassigned or select an actual eligible slot ID and physically confirm placement.
4. POST `/api/actions/register` with the documented camelCase keys. Operators must use valid ISO identifiers; do not expose administrator exception bypass as an operator feature.
5. On 200, use `entityId` to locate the new record in response `state`. Arrival plus optional placement events already exist; do not send a second arrival/history write.
6. A duplicate response should open the existing record if accessible; otherwise explain it may exist elsewhere and request administrator review.

### Placement and relocation

1. Open current stored/unassigned container, inspect source accessibility, and preserve current slot as expected old state.
2. Choose an existing destination in the same yard. Client hints reject unavailable/occupied/too-small positions, missing support, mismatched stacked length, or full block. For moving within a full block, exclude this container when counting occupants. Server remains authoritative.
3. Worker confirms actual physical destination.
4. POST `/api/actions/move` with explicit original `expectedSlotId` (null for unassigned).
5. Replace state after 200. On conflict, refresh and require a fresh decision; do not silently substitute a new expected slot and replay.

### Gate-out

1. Show current record and require departure confirmation.
2. POST `/api/actions/dispatch` with `confirmed:true` and expected current slot.
3. Success releases slot, marks dispatched, and records history. Retain old records in search/history.
4. Do not offer re-entry of a dispatched identifier; no supported contract exists.

### Location verification

1. Only offer for a record with a current slot.
2. Worker confirms container is actually at the recorded location.
3. POST `/api/actions/verify` with expected slot and `physicalConfirmed:true`.
4. Show updated location time. Do not claim invalid number identity has been corrected; this action does not change that flag.

## 9. Handle connectivity and ambiguous writes

For the first demonstration implement **online-only commits with recoverable local drafts**. Do not add automatic offline replay to this API.

- Cached state must show age/offline status; do not present cached free slots as reservations.
- Save a draft/photograph only under an explicit local retention policy. Never mark a drafted registration/move as committed occupancy.
- On explicit 4xx rejection, preserve draft and display server code/message. Refresh conflict cases and ask the worker to review.
- On POST timeout, connection loss, proxy failure, or app termination, mark operation pending reconciliation. A server commit may already have happened.
- After reconnect/session renewal, GET fresh state/history. Compare container number, slot/status, event type, actor, and recent times with intended operation. Another worker may have produced the same current state; require review rather than asserting ownership of the result.
- Do not blindly repeat verify: it can duplicate audit events. Repeated register/move/dispatch can conflict even if the original request succeeded.
- No pending-write replay is safe merely because a connectivity plugin says online. A robust replay feature requires an idempotency protocol added transactionally to the existing backend first.

## 10. Run a two-client acceptance demonstration

Use an agreed test window and recoverable demonstration records. Existing demo seed contains primary `MSCU1234566` and known free positions initially, but a used working yard may have changed. Always resolve and validate from fresh state.

| Check                                                        | Expected result                                                               |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| Connect with demo operator cookie / provisioned bearer       | Correct `authMode`, actor and accessible yard                                 |
| Search primary number                                        | Same ID and recorded position as web                                          |
| Read existing block/row/bay/tier layout                      | No fabricated positions or assumptions about uniform rows                     |
| Scan/correct a valid new number                              | Editable suggestion; client and server check-digit agreement                  |
| Register new container in eligible empty slot                | 200, created ID, one container, arrival + placement; web sees it on next poll |
| Register same normalized number again                        | 409 duplicate, no extra record                                                |
| Place an unassigned record                                   | `move` with expected null, placement event                                    |
| Relocate accessible stored record                            | Source becomes free, destination occupied, occupancy count unchanged          |
| Race two workers for same destination                        | One succeeds, other conflicts; no double occupancy                            |
| Use stale old slot                                           | 409 stale, no silent overwrite                                                |
| Choose reserved/blocked/restricted or unsupported upper tier | Server rejects and original state/history preserved                           |
| Try removing container under occupied upper tier             | 409 stack blocked                                                             |
| Dispatch                                                     | Slot released, history retained, no re-registration allowed                   |
| Verify                                                       | Timestamp/event updated; identity flag unchanged                              |
| Fetch attachment with worker auth                            | Correct image bytes; absent photo returns JSON 404                            |
| Viewer attempts write                                        | 403 at server, not only disabled UI                                           |
| Operator attempts configuration                              | 403                                                                           |
| Secure account outside yard / expired bearer                 | 403 / 401 respectively                                                        |
| Kill connectivity before save                                | No false success, draft retained                                              |
| Lose response after save                                     | Reconciliation without duplicate automatic write                              |
| Background/resume app                                        | Foreground refetch; no old response overwrites fresh mutation                 |
| Restart client/server                                        | Shared persisted state remains, app reestablishes session                     |

Secure bearer/membership tests require actual Supabase/PostgreSQL setup. Do not mark them passing based on demo role tests. Test physical camera/OCR on a real device; emulator fixtures do not establish weathered-container recognition accuracy.

## 11. Backend-owner follow-up requests

Ask for changes only if a required feature is absent. All such changes belong to this **existing** service, with explicit contracts reviewed before the Flutter client depends on them:

1. Verified HTTPS hosting and real worker provisioning if remote access is required.
2. Transaction-safe idempotency before automated offline retries.
3. Typed OCR provenance/client-observed timestamp if scan auditing is required.
4. Paginated search/history if snapshot volume or 1,000-event limit is insufficient.
5. Authenticated invalidation stream if 30-second polling is too slow.
6. Controlled container re-entry/transfer and metadata editing if workflows demand them.
7. Narrow CORS allowlist only if separately hosted Flutter Web is an actual target.

No new endpoint names or proposed data fields in this list are available today. First connect the native client to the tested existing operations.

## 12. Prompt for the separate Codex account

> Build a native Flutter worker client using MOBILE_API_CONTRACT.md, MOBILE_INTEGRATION.md, and this guide as the backend contract. Use the one existing Yardline API origin supplied by the owner. Implement explicit configured authentication (trusted demo operator cookie or provisioned Supabase bearer), yard snapshot/search, layout and occupancy, on-device OCR with editable human review and ISO 6346 validation, registration/placement/relocation/dispatch/location verification, protected photo reads, foreground polling, and recoverable drafts. Use actual IDs from snapshots and enforce physical confirmations. Preserve camelCase request keys, snake_case response keys, integer flags, nullability, and required expectedSlotId. Do not create a backend or authoritative database, access Supabase application tables, invent routes, claim realtime support, or blindly retry mutations. Ask the backend owner for the API origin/auth configuration and privately supplied worker credentials. Clearly distinguish unimplemented backend capabilities from client work. Verify with the web client against the same shared state.
