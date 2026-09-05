# Campus Autocomplete Flutter Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect Flutter destination search to the Fastify campus API with debounced, stale-safe state, truthful navigation metadata, housing classification, and preserved recent searches.

**Architecture:** A screen-scoped `CampusSearchController` coordinates input, location, and a typed `CampusSearchGateway`. The gateway is the only Flutter component that understands Fastify JSON; selected API places become enriched `NaviDestination` values consumed by the existing Mapbox and indoor flows. The backend receives one additive public `housing` type mapping while retaining canonical database records as buildings.

**Tech Stack:** Dart 3.12, Flutter, Provider/ChangeNotifier, package:http, Geolocator, SharedPreferences, Fastify 5, TypeBox, TypeScript 6, Vitest.

**Spec:** `docs/superpowers/specs/2026-09-05-campus-autocomplete-flutter-design.md`

## Global Constraints

- Debounce accepted input for 275 milliseconds.
- Never query fewer than two meaningful alphanumeric characters.
- Ignore every response whose generation no longer matches the current query.
- Request and display at most ten results.
- Use backend stable UUIDs for local places and reload local selection by ID.
- Route Mapbox only to `navigation.outdoorDestination` supplied by the API.
- Offer indoor navigation only for a nonblank `navigation.indoorDestinationId`.
- Keep `SUPABASE_SERVICE_ROLE_KEY` and all other service credentials out of Flutter.
- Keep the existing recent-search storage key and three-item limit.
- Do not modify the user's existing iOS project/workspace changes.
- Follow `/Users/kaydee/Developer/NaviPetBackend/AGENTS.md` before backend edits: refresh a stale GitNexus index, run upstream impact before editing a symbol, warn on HIGH/CRITICAL risk, and run `detect_changes` before a backend commit.

---

### Task 1: Repair the Committed Authentication Conflict Markers

**Files:**
- Modify: `lib/data/app_state.dart`
- Modify: `lib/data/registration_gateway.dart`
- Modify: `lib/router/app_router.dart`
- Modify: `lib/screens/register_screen.dart`
- Modify: `lib/screens/sign_in_screen.dart`
- Modify: `test/register_screen_test.dart`
- Modify: `test/registration_gateway_test.dart`

**Interfaces:**
- Consumes: backend auth endpoints already used by both sides of commit `f615bf7`.
- Produces: one compileable OTP/password-recovery API used by existing screens and tests; no conflict-marker text remains under `lib/` or `test/`.

- [ ] **Step 1: Reproduce the parser failure**

Run:

```bash
flutter analyze
```

Expected: nonzero exit with parser errors at committed `<<<<<<< Updated upstream` markers.

- [ ] **Step 2: Record the intended combined gateway contract in existing tests**

Keep the existing assertions for `/auth/login`, `/auth/register`,
`/auth/verify-otp`, `/auth/forgot-password`, and `/auth/reset-password`.
Ensure the tests exercise this single interface:

```dart
abstract interface class RegistrationGateway {
  Future<RegistrationVerificationSuccess> signIn({
    required String email,
    required String password,
  });
  Future<RegistrationSuccess> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  });
  Future<RegistrationVerificationSuccess> verifyRegistrationCode({
    required String email,
    required String code,
  });
  Future<PasswordResetRequestSuccess> requestPasswordReset({
    required String email,
  });
  Future<RegistrationVerificationSuccess> verifyPasswordRecoveryCode({
    required String email,
    required String code,
  });
  Future<void> resetPassword({
    required String accessToken,
    required String newPassword,
    required String confirmPassword,
  });
}
```

- [ ] **Step 3: Verify the focused tests fail before repair**

Run:

```bash
flutter test test/registration_gateway_test.dart test/register_screen_test.dart test/app_state_password_reset_test.dart test/authentication_flow_test.dart test/app_router_test.dart
```

Expected: nonzero exit caused by conflict-marker syntax and inconsistent duplicate interfaces.

- [ ] **Step 4: Merge the two behaviors without choosing one side wholesale**

Retain the newer OTP screen method names shown above. Retain the upstream
recovery-session guarantees: recovery tokens stay outside the normal Supabase
session, `/new-password` remains reachable while signed out, reset consumes
the scoped access token, and normal authenticated redirects remain intact.
Normalize the base URL once in `HttpRegistrationGateway`:

```dart
HttpRegistrationGateway({required String baseUrl, http.Client? client})
  : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
    _client = client ?? http.Client();
```

Delete all marker lines and duplicate branches. Do not change search files in
this task.

- [ ] **Step 5: Verify conflict repair**

Run:

```bash
rg -n '^(<<<<<<<|=======|>>>>>>>)' lib test
flutter test test/registration_gateway_test.dart test/register_screen_test.dart test/app_state_password_reset_test.dart test/authentication_flow_test.dart test/app_router_test.dart
```

Expected: `rg` returns no matches; focused auth tests pass.

- [ ] **Step 6: Commit the isolated repair**

```bash
git add lib/data/app_state.dart lib/data/registration_gateway.dart lib/router/app_router.dart lib/screens/register_screen.dart lib/screens/sign_in_screen.dart test/register_screen_test.dart test/registration_gateway_test.dart
git commit -m "fix: resolve committed authentication conflicts"
```

---

### Task 2: Expose Verified Housing as a Public Destination Type

**Files:**
- Modify: `/Users/kaydee/Developer/NaviPetBackend/src/modules/campus/campus.types.ts`
- Modify: `/Users/kaydee/Developer/NaviPetBackend/src/modules/campus/campus.schema.ts`
- Modify: `/Users/kaydee/Developer/NaviPetBackend/src/modules/campus/campus.service.ts`
- Modify: `/Users/kaydee/Developer/NaviPetBackend/tests/unit/campus-service.test.ts`
- Modify: `/Users/kaydee/Developer/NaviPetBackend/tests/integration/campus.test.ts`

**Interfaces:**
- Consumes: canonical records with `type: 'building'` and `metadata.categories` containing `housing`.
- Produces: `PublicCampusResult.type` including `'housing'`, accepted by Fastify response validation.

- [ ] **Step 1: Refresh graph and check blast radius before editing**

Run from the backend repository:

```bash
npx gitnexus analyze
```

Then run GitNexus upstream impact for `toPublicCampusResult`. If risk is HIGH
or CRITICAL, stop and report it before editing.

- [ ] **Step 2: Write failing service and route tests**

Add a service assertion using a verified building record:

```ts
const housing = destination({
  type: 'building',
  name: 'Parkside North',
  code: 'PN',
  buildingCode: 'PN',
  metadata: { categories: ['housing'] },
});
const result = await createCampusService(gateways([housing])).autocomplete('Parkside North', 10);
expect(result.results[0]).toMatchObject({ id: housing.id, type: 'housing' });
```

Add an integration assertion that `/autocomplete?q=Parkside%20North` returns
HTTP 200 and `results[0].type === 'housing'`.

- [ ] **Step 3: Verify tests fail for the expected type mismatch**

Run:

```bash
npm test -- tests/unit/campus-service.test.ts tests/integration/campus.test.ts
```

Expected: housing assertion fails because current output is `building`.

- [ ] **Step 4: Implement the additive public mapping**

Add `'housing'` only to the public result union and TypeBox schema. In
`toPublicCampusResult`, derive the public type without mutating the record:

```ts
const categories = stringArray(destination.metadata.categories);
const publicType = categories.includes('housing')
  ? 'housing'
  : destination.type;
```

Return `type: publicType`. Keep stored `CampusDestinationType` unchanged so
database imports and parent/child behavior continue treating residences as
buildings.

- [ ] **Step 5: Verify backend behavior and affected graph**

Run:

```bash
npm test -- tests/unit/campus-service.test.ts tests/integration/campus.test.ts
npm run typecheck
```

Expected: targeted tests and typecheck pass. Run GitNexus `detect_changes`
against `main` and confirm only public campus-result serialization flows are
affected.

- [ ] **Step 6: Commit backend change**

```bash
git add src/modules/campus/campus.types.ts src/modules/campus/campus.schema.ts src/modules/campus/campus.service.ts tests/unit/campus-service.test.ts tests/integration/campus.test.ts
git commit -m "feat(campus): expose housing destination type"
```

---

### Task 3: Add Typed Campus Place Models and HTTP Gateway

**Files:**
- Create: `lib/data/campus_place.dart`
- Create: `lib/data/campus_search_gateway.dart`
- Create: `test/campus_place_test.dart`
- Create: `test/campus_search_gateway_test.dart`
- Modify: `lib/data/navigation_models.dart`

**Interfaces:**
- Consumes: `GET /autocomplete` and `GET /places/:placeId` JSON from the backend.
- Produces: `CampusPlace.fromJson`, `CampusSearchGateway.autocomplete`, `CampusSearchGateway.place`, and `CampusPlace.toDestination`.

- [ ] **Step 1: Write failing model tests**

Test parsing all public fields, including `housing`, and conversion using only
verified outdoor coordinates:

```dart
final place = CampusPlace.fromJson({
  'id': '00000000-0000-4000-8000-000000000001',
  'type': 'room',
  'title': 'COB 140',
  'subtitle': 'College of Business · Floor 1',
  'source': 'csulb',
  'buildingCode': 'COB',
  'roomNumber': '140',
  'floorNumber': '1',
  'navigation': {
    'outdoorDestination': {'latitude': 33.7832, 'longitude': -118.1147},
    'indoorDestinationId': 'multiset-cob-140',
  },
});
expect(place.type, CampusDestinationType.room);
expect(place.hasIndoorNavigation, isTrue);
expect(place.toDestination().coordinate.latitude, 33.7832);
```

Also assert missing outdoor coordinates make `toDestination()` throw a typed
`CampusSearchException` rather than synthesizing a coordinate.

- [ ] **Step 2: Write failing HTTP gateway tests**

Inject `MockClient` and assert:

```dart
expect(request.url.path, '/autocomplete');
expect(request.url.queryParameters['q'], 'COB 140');
expect(request.url.queryParameters['limit'], '10');
```

Cover paired location parameters, ten-item defensive truncation, standard
error-envelope parsing, malformed JSON, client/network failure, and
`GET /places/<uuid>` parsing from `{ "place": ... }`.

- [ ] **Step 3: Run model/gateway tests to verify RED**

Run:

```bash
flutter test test/campus_place_test.dart test/campus_search_gateway_test.dart
```

Expected: compile failure because the new types do not exist.

- [ ] **Step 4: Implement destination model**

Define:

```dart
enum CampusDestinationType {
  building, room, entrance, parking, dining, service, amenity,
  transit, housing, landmark, external,
}

class CampusPlace {
  const CampusPlace({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.source,
    this.buildingCode,
    this.roomNumber,
    this.floorNumber,
    this.outdoorDestination,
    this.indoorDestinationId,
    this.external = false,
  });

  bool get hasIndoorNavigation =>
      indoorDestinationId?.trim().isNotEmpty == true;
  bool get isBuildingAlternative =>
      subtitle.startsWith('Building-level alternative');
}
```

Extend `NaviDestination` with optional corresponding fields while preserving
the current required `name`, `address`, and `coordinate` parameters.

- [ ] **Step 5: Implement gateway and typed errors**

Define:

```dart
abstract interface class CampusSearchGateway {
  Future<List<CampusPlace>> autocomplete(
    String query, {
    NavigationCoordinate? proximity,
    int limit = 10,
  });
  Future<CampusPlace> place(String stableId);
}

class HttpCampusSearchGateway implements CampusSearchGateway {
  HttpCampusSearchGateway({required String baseUrl, http.Client? client});
}
```

Clamp `limit` to `1..10`, encode paths with `Uri`, close only an internally
created client, and classify `http.ClientException`, `SocketException`, and
timeouts as `CampusSearchFailure.offline`. Classify non-2xx responses and
invalid JSON as `CampusSearchFailure.api`.

- [ ] **Step 6: Verify GREEN and commit**

Run:

```bash
dart format lib/data/campus_place.dart lib/data/campus_search_gateway.dart lib/data/navigation_models.dart test/campus_place_test.dart test/campus_search_gateway_test.dart
flutter test test/campus_place_test.dart test/campus_search_gateway_test.dart
```

Expected: all model/gateway tests pass.

```bash
git add lib/data/campus_place.dart lib/data/campus_search_gateway.dart lib/data/navigation_models.dart test/campus_place_test.dart test/campus_search_gateway_test.dart
git commit -m "feat: add campus search gateway"
```

---

### Task 4: Add Debounced Search State and Location Handling

**Files:**
- Create: `lib/data/campus_search_controller.dart`
- Create: `lib/data/search_location_provider.dart`
- Create: `test/campus_search_controller_test.dart`

**Interfaces:**
- Consumes: `CampusSearchGateway`, `SearchLocationProvider`.
- Produces: `CampusSearchController.queryChanged`, `select`, `retry`, and immutable observable search state.

- [ ] **Step 1: Write failing debounce and minimum-length tests**

Use a 20-millisecond injected debounce in tests. Assert zero gateway calls for
`''`, `'x'`, and `'---x---'`; assert one call after the debounce for `'CO'`.
Assert state changes from `typing` to `loading` to `results`.

- [ ] **Step 2: Write failing stale-response test**

Use two completers:

```dart
controller.queryChanged('CO');
await debounceElapsed();
controller.queryChanged('COB');
await debounceElapsed();
second.complete([cob]);
first.complete([obsolete]);
expect(controller.results, [cob]);
```

Also clear the query while a request is active and assert its later completion
cannot leave `initial`.

- [ ] **Step 3: Write failing state/error/location tests**

Cover empty response to `noResults`, offline exception to `offline`, API
exception to `apiError`, denied proximity permission to `permissionRequired`,
disabled location to `locationUnavailable`, and paired valid coordinates sent
for `nearest parking`. Assert ordinary `COB` never asks for permission.

- [ ] **Step 4: Run controller tests to verify RED**

Run:

```bash
flutter test test/campus_search_controller_test.dart
```

Expected: compile failure because controller and location abstraction do not exist.

- [ ] **Step 5: Implement explicit state machine**

Define:

```dart
enum CampusSearchStatus {
  initial, typing, loading, results, noResults, offline,
  permissionRequired, locationUnavailable, apiError,
}

class CampusSearchController extends ChangeNotifier {
  CampusSearchController({
    required CampusSearchGateway gateway,
    required SearchLocationProvider location,
    Duration debounce = const Duration(milliseconds: 275),
  });

  CampusSearchStatus get status;
  List<CampusPlace> get results;
  String? get message;
  void queryChanged(String value);
  Future<NaviDestination?> select(CampusPlace place);
  Future<void> retry();
}
```

Increment `_generation` synchronously on every query change and capture it
before every async search/selection. Before each mutation after `await`, require
`capturedGeneration == _generation && !_disposed`.

- [ ] **Step 6: Implement Geolocator adapter**

Define `SearchLocationProvider.locationFor(String normalizedQuery)` returning
no coordinate for ordinary queries and a typed permission/unavailable result
for the five exact proximity phrases. The real adapter checks permission,
requests only when denied, checks service availability, then requests the
current position.

- [ ] **Step 7: Verify GREEN and commit**

Run:

```bash
dart format lib/data/campus_search_controller.dart lib/data/search_location_provider.dart test/campus_search_controller_test.dart
flutter test test/campus_search_controller_test.dart
```

Expected: all controller tests pass.

```bash
git add lib/data/campus_search_controller.dart lib/data/search_location_provider.dart test/campus_search_controller_test.dart
git commit -m "feat: add debounced campus search state"
```

---

### Task 5: Preserve and Enrich Recent Searches

**Files:**
- Modify: `lib/data/search_history_store.dart`
- Create: `test/search_history_store_test.dart`

**Interfaces:**
- Consumes: old v1 JSON and enriched `NaviDestination`.
- Produces: backward-compatible load/add/clear behavior with stable-ID deduplication.

- [ ] **Step 1: Write failing persistence tests**

Seed `SharedPreferences.setMockInitialValues` with old JSON containing only
name, address, latitude, and longitude. Assert it loads. Add an enriched room,
reload, and assert stable ID, type, code, floor, indoor ID, and alternative flag
survive. Add the same stable ID with changed title and assert one updated item
remains. Assert old destinations still deduplicate by name/address.

- [ ] **Step 2: Run history tests to verify RED**

Run:

```bash
flutter test test/search_history_store_test.dart
```

Expected: enriched-field round trip and stable-ID deduplication fail.

- [ ] **Step 3: Implement optional JSON fields without changing the key**

Continue using `recent_mapbox_destinations_v1`. Encode optional fields only
when nonnull. Decode absent fields to null/false. Compare records with:

```dart
bool sameDestination(NaviDestination left, NaviDestination right) =>
    left.id != null && right.id != null
        ? left.id == right.id
        : left.name == right.name && left.address == right.address;
```

- [ ] **Step 4: Verify GREEN and commit**

Run:

```bash
dart format lib/data/search_history_store.dart test/search_history_store_test.dart
flutter test test/search_history_store_test.dart
```

Expected: all history tests pass.

```bash
git add lib/data/search_history_store.dart test/search_history_store_test.dart
git commit -m "feat: preserve campus search metadata in history"
```

---

### Task 6: Connect and Render the Search Screen

**Files:**
- Modify: `lib/screens/search_screen.dart`
- Create: `lib/widgets/campus_search_result_tile.dart`
- Create: `test/search_screen_test.dart`

**Interfaces:**
- Consumes: `CampusSearchController`, `CampusPlace`, `SearchHistoryStore`, `AppConfig.backendBaseUrl`.
- Produces: existing `/search` route returning an enriched `NaviDestination`.

- [ ] **Step 1: Write failing widget-state tests**

Inject a fake controller/gateway and test initial discovery, typing, loading,
results, no results, offline, permission required, location unavailable, and
API error copy. Verify loading is visible before completion and result count
never exceeds ten.

- [ ] **Step 2: Write failing rendering tests**

Pump one place of each public type and assert the expected icon key and visible
type label. For a room, assert title, subtitle, `COB`, `Floor 1`, and `Indoor
navigation available`. For external, assert `External Mapbox result`. For a
building alternative, assert `Navigation ends at the building` and no room
navigation claim.

- [ ] **Step 3: Write failing selection tests**

Tap a local building and room; assert the gateway reloads each stable UUID and
the navigator receives the refreshed destination. For external, assert no
local place reload occurs. For missing indoor data, assert the selected
destination has `indoorDestinationId == null` and the UI says `Outdoor
navigation only`.

- [ ] **Step 4: Run screen tests to verify RED**

Run:

```bash
flutter test test/search_screen_test.dart
```

Expected: tests fail because the screen still calls Mapbox Search Box directly.

- [ ] **Step 5: Replace direct Mapbox autocomplete with injected campus search**

Give `SearchScreen` optional test dependencies while retaining a zero-argument
route constructor:

```dart
const SearchScreen({
  super.key,
  this.gateway,
  this.locationProvider,
  this.historyStore,
  this.debounce = const Duration(milliseconds: 275),
});
```

When dependencies are absent, create `HttpCampusSearchGateway(baseUrl:
AppConfig.backendBaseUrl)`, `GeolocatorSearchLocationProvider`, and
`SearchHistoryStore`. Dispose only objects owned by the screen.

- [ ] **Step 6: Render explicit states and result tiles**

Keep `_discovery()` and recent/popular/class cards structurally unchanged.
Map status to precise UI copy:

```dart
CampusSearchStatus.noResults => 'No destinations found.',
CampusSearchStatus.offline => 'You’re offline. Check your connection and retry.',
CampusSearchStatus.permissionRequired =>
  'Location permission is required for nearby searches.',
CampusSearchStatus.locationUnavailable =>
  'Location is unavailable. Turn on Location Services and retry.',
CampusSearchStatus.apiError =>
  'Campus search is unavailable. Please retry.',
```

Use destination-specific Material icons and semantic keys in the focused tile
widget. Do not change unrelated screen composition.

- [ ] **Step 7: Verify GREEN and commit**

Run:

```bash
dart format lib/screens/search_screen.dart lib/widgets/campus_search_result_tile.dart test/search_screen_test.dart
flutter test test/search_screen_test.dart
```

Expected: all search widget and selection tests pass.

```bash
git add lib/screens/search_screen.dart lib/widgets/campus_search_result_tile.dart test/search_screen_test.dart
git commit -m "feat: connect search screen to campus API"
```

---

### Task 7: Make Navigation Handoff Truthful

**Files:**
- Modify: `lib/screens/navigation_flow_screens.dart`
- Modify: `lib/screens/map_screen.dart`
- Modify: `lib/router/app_router.dart`
- Create: `test/destination_details_screen_test.dart`
- Create: `test/map_destination_selection_test.dart`

**Interfaces:**
- Consumes: enriched `NaviDestination` with verified outdoor coordinate and optional Multiset ID.
- Produces: outdoor Mapbox routing plus conditional handoff into the existing indoor flow.

- [ ] **Step 1: Write failing destination-details tests**

Assert real building code, room, floor, and building-alternative copy replace
hard-coded `CBA • Room 234`. Assert `Continue indoors` is absent without an
indoor ID and present for `indoorDestinationId: 'multiset-cob-140'`.

- [ ] **Step 2: Write failing Mapbox/indoor selection tests**

Inject a fake route service into the narrow selection/preview seam. Assert the
destination coordinate passed to `getRoute` equals the API outdoor coordinate.
Assert room indoor ID is carried into `/navigation/localize`; assert a building
or room without the ID never offers that route. Assert a building-level
alternative says arrival ends at the building.

- [ ] **Step 3: Run navigation tests to verify RED**

Run:

```bash
flutter test test/destination_details_screen_test.dart test/map_destination_selection_test.dart
```

Expected: hard-coded details and unconditional prototype flow fail assertions.

- [ ] **Step 4: Render real details and condition indoor actions**

Build metadata from nonblank destination fields. Use:

```dart
final canNavigateIndoors =
    destination.indoorDestinationId?.trim().isNotEmpty == true;
```

The primary Directions result continues outdoor routing. At campus arrival,
show `Continue indoors` only when `canNavigateIndoors`; pass the complete
destination as route `extra`. Otherwise show `Navigation ends outdoors`, or
`Navigation ends at the building` for a building alternative.

- [ ] **Step 5: Carry destination through indoor routes**

Update `/navigation/localize` and `/navigation/indoor` builders to accept a
`NaviDestination` extra. Forward that same extra through
`pushReplacement('/navigation/indoor', extra: destination)`. The existing
prototype screen remains visually unchanged apart from using the real title
and holding the validated Multiset ID.

- [ ] **Step 6: Verify GREEN and commit**

Run:

```bash
dart format lib/screens/navigation_flow_screens.dart lib/screens/map_screen.dart lib/router/app_router.dart test/destination_details_screen_test.dart test/map_destination_selection_test.dart
flutter test test/destination_details_screen_test.dart test/map_destination_selection_test.dart
```

Expected: navigation handoff tests pass.

```bash
git add lib/screens/navigation_flow_screens.dart lib/screens/map_screen.dart lib/router/app_router.dart test/destination_details_screen_test.dart test/map_destination_selection_test.dart
git commit -m "feat: preserve verified navigation destinations"
```

---

### Task 8: Full Verification and Requirement Audit

**Files:**
- Modify only if a verification failure receives its own reproducing test first.

**Interfaces:**
- Consumes: all prior task outputs.
- Produces: fresh evidence for formatting, analysis, Flutter tests, and backend checks.

- [ ] **Step 1: Verify no credentials or conflict markers leaked**

Run:

```bash
rg -n 'SUPABASE_SERVICE_ROLE|service[_-]?role|^(<<<<<<<|=======|>>>>>>>)' lib test
```

Expected: no matches.

- [ ] **Step 2: Format and verify Flutter sources**

Run:

```bash
dart format lib test
dart format --output=none --set-exit-if-changed lib test
```

Expected: second command exits 0 with no changed files.

- [ ] **Step 3: Run Flutter static analysis and full tests**

Run:

```bash
flutter analyze
flutter test
```

Expected: analysis exits 0; full suite exits 0 with zero failed tests.

- [ ] **Step 4: Run full backend verification**

Run from `/Users/kaydee/Developer/NaviPetBackend`:

```bash
npm test
npm run lint
npm run typecheck
npm run build
```

Expected: every command exits 0.

- [ ] **Step 5: Audit every requested behavior against tests**

Confirm named passing tests exist for debounce, stale response, loading, empty
results, API errors, result rendering, building alternatives, building
selection, room selection, missing indoor data, and location permissions.
Confirm manually from the diff that the maximum is ten, stable IDs are
preserved, ordinary one-character input makes no request, and only API outdoor
coordinates reach Mapbox routing.

- [ ] **Step 6: Inspect final scope**

Run:

```bash
git status --short
git diff --stat HEAD~7..HEAD
```

Expected: only planned Flutter files plus the user's pre-existing iOS changes
appear. In the backend, only the five planned campus files differ from its
starting commit.
