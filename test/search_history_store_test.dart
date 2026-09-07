import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:navipet/data/navigation_models.dart';
import 'package:navipet/data/search_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const storageKey = 'recent_mapbox_destinations_v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('loads legacy recent-search JSON without campus metadata', () async {
    SharedPreferences.setMockInitialValues({
      storageKey: [
        jsonEncode({
          'name': 'Library',
          'address': 'Long Beach, CA',
          'latitude': 33.77,
          'longitude': -118.11,
        }),
      ],
    });

    final loaded = await SearchHistoryStore().load();

    expect(loaded.single.name, 'Library');
    expect(loaded.single.id, isNull);
    expect(loaded.single.type, isNull);
  });

  test('round-trips enriched room and navigation metadata', () async {
    const room = NaviDestination(
      id: '00000000-0000-4000-8000-000000000001',
      type: CampusDestinationType.room,
      name: 'COB 140',
      address: 'College of Business · Floor 1',
      coordinate: NavigationCoordinate(latitude: 33.7832, longitude: -118.1147),
      buildingCode: 'COB',
      roomNumber: '140',
      floorNumber: '1',
      indoorDestinationId: 'multiset-cob-140',
      isBuildingAlternative: true,
    );

    await SearchHistoryStore().add(room);
    final loaded = (await SearchHistoryStore().load()).single;

    expect(loaded.id, room.id);
    expect(loaded.type, CampusDestinationType.room);
    expect(loaded.buildingCode, 'COB');
    expect(loaded.roomNumber, '140');
    expect(loaded.floorNumber, '1');
    expect(loaded.indoorDestinationId, 'multiset-cob-140');
    expect(loaded.isBuildingAlternative, isTrue);
  });

  test('updates one item when the same stable ID is selected again', () async {
    const first = NaviDestination(
      id: '00000000-0000-4000-8000-000000000001',
      name: 'Old title',
      address: 'COB',
      coordinate: NavigationCoordinate(latitude: 1, longitude: 2),
    );
    const refreshed = NaviDestination(
      id: '00000000-0000-4000-8000-000000000001',
      name: 'College of Business',
      address: 'COB',
      coordinate: NavigationCoordinate(latitude: 3, longitude: 4),
    );

    await SearchHistoryStore().add(first);
    final current = await SearchHistoryStore().add(refreshed);

    expect(current, hasLength(1));
    expect(current.single.name, 'College of Business');
  });

  test('legacy items still deduplicate by name and address', () async {
    const destination = NaviDestination(
      name: 'Library',
      address: 'Long Beach, CA',
      coordinate: NavigationCoordinate(latitude: 1, longitude: 2),
    );

    await SearchHistoryStore().add(destination);
    final current = await SearchHistoryStore().add(destination);

    expect(current, hasLength(1));
  });
}
