import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navipet/data/app_state.dart';
import 'package:navipet/data/campus_place.dart';
import 'package:navipet/data/campus_search_gateway.dart';
import 'package:navipet/data/navigation_models.dart';
import 'package:navipet/data/search_history_store.dart';
import 'package:navipet/data/search_location_provider.dart';
import 'package:navipet/screens/search_screen.dart';
import 'package:navipet/widgets/campus_search_result_tile.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

CampusPlace place(
  CampusDestinationType type, {
  String? id,
  String? title,
  String subtitle = 'Helpful subtitle',
  String? indoorId,
  bool external = false,
}) => CampusPlace(
  id: id ?? '00000000-0000-4000-8000-000000000001',
  type: type,
  title: title ?? type.name,
  subtitle: subtitle,
  source: external ? 'mapbox' : 'csulb',
  buildingCode: type == CampusDestinationType.room ? 'COB' : null,
  roomNumber: type == CampusDestinationType.room ? '140' : null,
  floorNumber: type == CampusDestinationType.room ? '1' : null,
  indoorDestinationId: indoorId,
  external: external,
  outdoorDestination: const NavigationCoordinate(
    latitude: 33.7832,
    longitude: -118.1147,
  ),
);

class FakeGateway implements CampusSearchGateway {
  Future<List<CampusPlace>> Function(String query)? onAutocomplete;
  CampusPlace? refreshed;
  final List<String> placeRequests = [];

  @override
  Future<List<CampusPlace>> autocomplete(
    String query, {
    NavigationCoordinate? proximity,
    int limit = 10,
  }) => onAutocomplete?.call(query) ?? Future.value(const []);

  @override
  Future<CampusPlace> place(String stableId) async {
    placeRequests.add(stableId);
    return refreshed!;
  }
}

class FakeLocation implements SearchLocationProvider {
  FakeLocation([this.result = const SearchLocationResult.notRequired()]);
  SearchLocationResult result;

  @override
  Future<SearchLocationResult> locationFor(String normalizedQuery) async =>
      result;
}

Widget harness(
  FakeGateway gateway, {
  FakeLocation? location,
  ValueChanged<NaviDestination>? onSelected,
}) => ChangeNotifierProvider(
  create: (_) => AppState(),
  child: MaterialApp(
    home: SearchScreen(
      gateway: gateway,
      locationProvider: location ?? FakeLocation(),
      historyStore: SearchHistoryStore(),
      debounce: const Duration(milliseconds: 20),
      onSelected: onSelected,
    ),
  ),
);

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 25));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'renders every destination type with a distinct label and icon key',
    (tester) async {
      const types = [
        CampusDestinationType.building,
        CampusDestinationType.room,
        CampusDestinationType.parking,
        CampusDestinationType.dining,
        CampusDestinationType.service,
        CampusDestinationType.amenity,
        CampusDestinationType.transit,
        CampusDestinationType.housing,
        CampusDestinationType.landmark,
        CampusDestinationType.external,
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final type in types)
                    CampusSearchResultTile(
                      place: place(
                        type,
                        external: type == CampusDestinationType.external,
                      ),
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      for (final type in types) {
        expect(
          find.byKey(ValueKey('campus-result-icon-${type.name}')),
          findsOneWidget,
        );
      }
      expect(find.text('External Mapbox result'), findsOneWidget);
      expect(find.text('Housing'), findsOneWidget);
    },
  );

  testWidgets(
    'renders room code, floor, subtitle, and valid indoor availability',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CampusSearchResultTile(
              place: place(
                CampusDestinationType.room,
                title: 'COB 140',
                subtitle: 'College of Business · Floor 1',
                indoorId: 'multiset-cob-140',
              ),
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('COB 140'), findsOneWidget);
      expect(find.text('College of Business · Floor 1'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CampusSearchResultTile),
          matching: find.text('COB'),
        ),
        findsOneWidget,
      );
      expect(find.text('Floor 1'), findsOneWidget);
      expect(find.text('Indoor navigation available'), findsOneWidget);
    },
  );

  testWidgets('labels building alternatives as ending at the building', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampusSearchResultTile(
            place: place(
              CampusDestinationType.building,
              subtitle: 'Building-level alternative · COB',
            ),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Navigation ends at the building'), findsOneWidget);
    expect(find.text('Indoor navigation available'), findsNothing);
  });

  testWidgets(
    'shows initial, typing, loading, results, and no-results states',
    (tester) async {
      final pending = Completer<List<CampusPlace>>();
      final gateway = FakeGateway()..onAutocomplete = (_) => pending.future;
      await tester.pumpWidget(harness(gateway));
      expect(find.text('Find your way,'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'C');
      await tester.pump();
      expect(find.text('Type at least two characters.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'COB');
      await tester.pump(const Duration(milliseconds: 25));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      pending.complete([place(CampusDestinationType.building, title: 'COB')]);
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(CampusSearchResultTile),
          matching: find.text('COB'),
        ),
        findsOneWidget,
      );

      gateway.onAutocomplete = (_) async => const [];
      await search(tester, 'HSCI');
      expect(find.text('No destinations found.'), findsOneWidget);
    },
  );

  testWidgets(
    'shows offline, API, permission, and unavailable-location states',
    (tester) async {
      final gateway = FakeGateway()
        ..onAutocomplete = (_) => Future.error(
          const CampusSearchException(
            failure: CampusSearchFailure.offline,
            message: 'offline',
          ),
        );
      final location = FakeLocation();
      await tester.pumpWidget(harness(gateway, location: location));

      await search(tester, 'COB');
      expect(
        find.text('You’re offline. Check your connection and retry.'),
        findsOneWidget,
      );

      gateway.onAutocomplete = (_) => Future.error(
        const CampusSearchException(
          failure: CampusSearchFailure.api,
          message: 'api',
        ),
      );
      await search(tester, 'HSCI');
      expect(
        find.text('Campus search is unavailable. Please retry.'),
        findsOneWidget,
      );

      location.result = const SearchLocationResult.permissionRequired();
      await search(tester, 'nearest parking');
      expect(
        find.text('Location permission is required for nearby searches.'),
        findsOneWidget,
      );

      location.result = const SearchLocationResult.unavailable();
      await search(tester, 'coffee near me');
      expect(
        find.text(
          'Location is unavailable. Turn on Location Services and retry.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('reloads local building and room selections by stable ID', (
    tester,
  ) async {
    final gateway = FakeGateway();
    NaviDestination? selected;
    final building = place(
      CampusDestinationType.building,
      id: '00000000-0000-4000-8000-000000000010',
      title: 'Library',
    );
    gateway.onAutocomplete = (_) async => [building];
    gateway.refreshed = building;
    await tester.pumpWidget(
      harness(gateway, onSelected: (value) => selected = value),
    );
    await search(tester, 'Library');
    await tester.tap(find.byType(CampusSearchResultTile));
    await tester.pump();
    expect(gateway.placeRequests, [building.id]);
    expect(selected?.type, CampusDestinationType.building);

    final room = place(
      CampusDestinationType.room,
      id: '00000000-0000-4000-8000-000000000011',
      title: 'COB 140',
      indoorId: 'multiset-cob-140',
    );
    gateway.onAutocomplete = (_) async => [room];
    gateway.refreshed = room;
    await search(tester, 'COB 140');
    await tester.tap(find.byType(CampusSearchResultTile));
    await tester.pump();
    expect(gateway.placeRequests.last, room.id);
    expect(selected?.indoorDestinationId, 'multiset-cob-140');
  });

  testWidgets('does not reload external selection or invent indoor data', (
    tester,
  ) async {
    final gateway = FakeGateway();
    NaviDestination? selected;
    final external = place(
      CampusDestinationType.external,
      id: 'mapbox.place.1',
      title: 'Long Beach',
      external: true,
    );
    gateway.onAutocomplete = (_) async => [external];
    await tester.pumpWidget(
      harness(gateway, onSelected: (value) => selected = value),
    );
    await search(tester, 'Long Beach');

    expect(find.text('Outdoor navigation only'), findsOneWidget);
    await tester.tap(find.byType(CampusSearchResultTile));
    await tester.pump();
    expect(gateway.placeRequests, isEmpty);
    expect(selected?.indoorDestinationId, isNull);
  });
}
