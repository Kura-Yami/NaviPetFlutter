import 'package:flutter_test/flutter_test.dart';
import 'package:navipet/data/navigation_models.dart';
import 'package:navipet/data/outdoor_route_gateway.dart';

class FakeRouteGateway implements OutdoorRouteGateway {
  NavigationCoordinate? receivedDestination;

  @override
  Future<NavigationRoute> getRoute({
    required NavigationCoordinate origin,
    required NavigationCoordinate destination,
    String profile = 'walking',
  }) async {
    receivedDestination = destination;
    return const NavigationRoute(
      coordinates: [],
      steps: [],
      distanceMeters: 0,
      durationSeconds: 0,
    );
  }
}

void main() {
  test(
    'routes to the verified outdoor destination carried by selection',
    () async {
      final gateway = FakeRouteGateway();
      const selected = NaviDestination(
        id: '00000000-0000-4000-8000-000000000001',
        type: CampusDestinationType.room,
        name: 'COB 140',
        address: 'College of Business · Floor 1',
        coordinate: NavigationCoordinate(
          latitude: 33.7832,
          longitude: -118.1147,
        ),
        indoorDestinationId: 'multiset-cob-140',
      );

      await loadOutdoorRoute(
        gateway: gateway,
        origin: const NavigationCoordinate(latitude: 33.78, longitude: -118.11),
        destination: selected,
      );

      expect(gateway.receivedDestination, same(selected.coordinate));
    },
  );

  test('indoor eligibility requires a nonblank Multiset destination ID', () {
    const missing = NaviDestination(
      name: 'COB 140',
      address: 'COB',
      coordinate: NavigationCoordinate(latitude: 1, longitude: 2),
      indoorDestinationId: '  ',
    );
    const valid = NaviDestination(
      name: 'COB 140',
      address: 'COB',
      coordinate: NavigationCoordinate(latitude: 1, longitude: 2),
      indoorDestinationId: 'multiset-cob-140',
    );

    expect(missing.hasIndoorNavigation, isFalse);
    expect(valid.hasIndoorNavigation, isTrue);
  });
}
