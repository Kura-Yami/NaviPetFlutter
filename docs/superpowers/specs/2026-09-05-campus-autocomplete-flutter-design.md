# Campus Autocomplete Flutter Integration Design

## Goal

Connect NaviPet's existing Flutter destination search to the Fastify campus
autocomplete API while preserving recent searches and the current screen's
visual structure. Search results must accurately communicate destination type
and available outdoor and indoor navigation capabilities.

## Scope

This change covers the Flutter search models, HTTP gateway, search state,
result presentation, destination selection, recent-search persistence, and the
existing route handoff. It also makes the smallest backend contract extension
needed to expose verified housing destinations as `housing` results.

The change repairs conflict markers already committed in the Flutter main
branch because they currently prevent formatting, analysis, and tests. The
repair combines the backend-based OTP flow with the existing scoped password
recovery behavior. It does not redesign authentication.

Unrelated screens and the user's existing iOS project/workspace changes remain
untouched.

## Existing Architecture

The search screen currently owns transient state with `StatefulWidget` and
`setState`, debounces Mapbox Search Box calls, retrieves a selected Mapbox
suggestion, stores a `NaviDestination` in `SharedPreferences`, and pops it to
`MapScreen`. `MapScreen` previews a walking route through
`MapboxNavigationService`, then the existing destination-details and prototype
indoor screens continue the navigation flow. App-wide account and class data
uses `Provider` with `ChangeNotifier`.

The backend exposes:

- `GET /autocomplete?q=<query>&limit=10`
- optional paired `latitude` and `longitude` for supported proximity intents
- `GET /places/:placeId` for a current local destination by stable UUID

Autocomplete results already include stable IDs, titles, subtitles, building
and floor data, verified outdoor coordinates, and optional Multiset indoor
destination IDs. External Mapbox fallback results are returned by the backend
and are not persisted to Supabase.

## Backend Contract Extension

Add `housing` to the public destination-type schema and public TypeScript type.
When a verified destination has `metadata.categories` containing `housing`,
serialize its public type as `housing`; keep its stored canonical record type
as `building`. Add service and integration coverage for this mapping.

No credentials or raw metadata become public. Flutter receives only the same
public result shape with the additional type value.

## Flutter Models and Gateway

Introduce a typed campus place model with:

- stable `id`
- destination type
- title and subtitle
- source and external-result marker
- optional building code, room number, and floor
- optional verified outdoor coordinate
- optional nonblank indoor destination ID
- building-alternative marker derived from the backend's explicit subtitle

Extend `NaviDestination` with optional stable ID, destination type, building
code, room number, floor, indoor destination ID, external marker, and
building-level-alternative marker. Existing constructors remain source
compatible through optional fields.

Create an HTTP campus search gateway following the existing registration
gateway's injected `http.Client` pattern. It reads only `BACKEND_BASE_URL` and
calls `/autocomplete` with a hard maximum of ten. For local selections it calls
`/places/:id`; external Mapbox selections use the complete autocomplete result
because the UUID-only place endpoint does not accept external provider IDs.

The gateway distinguishes network/offline failures from backend or malformed
response failures. It never talks directly to Supabase and never needs a
Supabase service-role credential.

## Search State and Data Flow

Use a screen-scoped `ChangeNotifier` controller. This follows the app's
existing notifier convention while keeping search state out of global
`AppState`.

The controller exposes these states:

- `initial`: blank query; discovery and recent searches visible
- `typing`: a one-character query or a meaningful query waiting for debounce
- `loading`: the accepted debounced request is active
- `results`: one to ten results
- `noResults`: successful empty response
- `offline`: request failed because no network connection was available
- `permissionRequired`: a proximity query needs location permission
- `locationUnavailable`: location services or a usable position are unavailable
- `apiError`: non-network API, parsing, configuration, or selection failure

Input is normalized for its meaningful alphanumeric length. Empty and
one-character values never call the API. A 275-millisecond timer starts after
valid input. Each query change increments a generation counter; only the
latest generation may mutate state. Clearing or shortening the query also
invalidates in-flight work. The gateway result is defensively capped at ten.

Location is requested only for the backend's supported proximity phrases:
`nearest restroom`, `food near me`, `nearest parking`, `closest bus stop`, and
`coffee near me`. Ordinary searches remain available without location access.
Denied permission produces `permissionRequired`; disabled services or failed
position acquisition produce `locationUnavailable`. Valid location is sent as
a paired latitude/longitude query parameter.

## Result Presentation

Keep the existing search scaffold, search field, discovery content, colors,
and list layout. Replace the generic pin with icons for Building, Room,
Parking, Dining, Service, Amenity, Transit, Housing, Landmark, and External
Mapbox result.

Each result shows its title and helpful subtitle. Compact metadata labels show
building code and floor when present. A navigation label says either `Indoor
navigation available` or `Outdoor navigation only`. External fallback results
are explicitly labeled `External Mapbox result`.

A building returned for a nonexistent room retains the backend subtitle and
adds a prominent `Navigation ends at the building` label. It never displays
room-level or indoor-navigation claims unless the returned building itself has
a valid indoor destination ID.

## Selection and Navigation

Selecting a local result reloads it by stable UUID before navigation. Selecting
an external result uses its backend-returned autocomplete payload. Selection
fails visibly when no verified outdoor destination exists; canonical point
guessing is forbidden.

The selected result converts to `NaviDestination` using the verified outdoor
coordinate. `MapScreen` continues to pass that coordinate to Mapbox Directions.
Destination details render actual type, code, room, floor, and navigation
availability instead of hard-coded CBA metadata.

The existing indoor flow is offered only when `indoorDestinationId` is nonblank.
The stable Multiset ID is retained in the destination passed through the flow.
For all other places, the UI states that navigation ends outdoors. A
building-level room alternative says that the route ends at the building and
does not imply room arrival.

## Recent Searches

Keep the same storage key and three-item limit. Stored JSON gains optional
fields for stable ID and navigation metadata. Loading remains backward
compatible with old name/address/coordinate records. Deduplication uses stable
ID when present and falls back to the existing name/address identity.

Selecting a recent search keeps current behavior: it returns the stored
destination immediately. Recent-search load corruption remains recoverable by
clearing the malformed preference.

## Error Handling

User-facing messages remain concise and actionable:

- offline: check connection and retry
- permission required: allow location for proximity search, while ordinary
  search remains usable
- location unavailable: enable Location Services or retry after a GPS fix
- API error: campus search is unavailable and can be retried
- selection without outdoor coordinates: routing is unavailable for that place

Request errors never erase a previously successful result because of a stale
response. New current-query failures replace the current state with the
matching explicit error state.

## Testing

Controller unit tests use injected debounce duration, gateway, and location
provider to cover:

- debounce timing and minimum query length
- stale-response protection
- loading and successful empty states
- offline and API errors
- location permission and unavailable-location handling

Gateway/model tests cover request paths, the ten-result cap, JSON parsing,
stable IDs, full-place loading, external selection, and missing navigation
data.

Widget tests cover destination-type rendering, metadata labels, building-level
alternatives, and missing indoor-navigation data. Selection tests cover a
building, room, external result, and local place refresh by ID. Existing recent
search tests are extended for backward compatibility.

Backend tests cover the public `housing` mapping and schema acceptance.

## Verification

Run fresh commands after implementation:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Run targeted backend validation:

```bash
npm test -- tests/unit/campus-service.test.ts tests/integration/campus.test.ts
npm run lint
npm run typecheck
```

Report command, exit status, passing-test count where available, and any
remaining failure caused by external tooling or environment.
