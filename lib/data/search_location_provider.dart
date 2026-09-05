import 'package:geolocator/geolocator.dart';

import 'navigation_models.dart';

enum SearchLocationStatus {
  notRequired,
  available,
  permissionRequired,
  unavailable,
}

class SearchLocationResult {
  const SearchLocationResult._(this.status, [this.coordinate]);

  const SearchLocationResult.notRequired()
    : this._(SearchLocationStatus.notRequired);

  const SearchLocationResult.available(NavigationCoordinate coordinate)
    : this._(SearchLocationStatus.available, coordinate);

  const SearchLocationResult.permissionRequired()
    : this._(SearchLocationStatus.permissionRequired);

  const SearchLocationResult.unavailable()
    : this._(SearchLocationStatus.unavailable);

  final SearchLocationStatus status;
  final NavigationCoordinate? coordinate;
}

abstract interface class SearchLocationProvider {
  Future<SearchLocationResult> locationFor(String normalizedQuery);
}

class GeolocatorSearchLocationProvider implements SearchLocationProvider {
  static const proximityQueries = {
    'nearest restroom',
    'food near me',
    'nearest parking',
    'closest bus stop',
    'coffee near me',
  };

  @override
  Future<SearchLocationResult> locationFor(String normalizedQuery) async {
    if (!proximityQueries.contains(normalizedQuery)) {
      return const SearchLocationResult.notRequired();
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const SearchLocationResult.unavailable();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const SearchLocationResult.permissionRequired();
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return SearchLocationResult.available(
        NavigationCoordinate(
          latitude: position.latitude,
          longitude: position.longitude,
        ),
      );
    } on Object {
      return const SearchLocationResult.unavailable();
    }
  }
}
