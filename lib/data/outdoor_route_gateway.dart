import 'navigation_models.dart';

abstract interface class OutdoorRouteGateway {
  Future<NavigationRoute> getRoute({
    required NavigationCoordinate origin,
    required NavigationCoordinate destination,
    String profile = 'walking',
  });
}

Future<NavigationRoute> loadOutdoorRoute({
  required OutdoorRouteGateway gateway,
  required NavigationCoordinate origin,
  required NaviDestination destination,
}) {
  return gateway.getRoute(origin: origin, destination: destination.coordinate);
}
