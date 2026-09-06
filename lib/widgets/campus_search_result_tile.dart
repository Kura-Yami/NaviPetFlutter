import 'package:flutter/material.dart';

import '../data/campus_place.dart';
import '../theme/app_theme.dart';

class CampusSearchResultTile extends StatelessWidget {
  const CampusSearchResultTile({
    super.key,
    required this.place,
    required this.onTap,
    this.enabled = true,
  });

  final CampusPlace place;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      _typeLabel(place.type),
      if (place.buildingCode != null) place.buildingCode!,
      if (place.floorNumber != null) 'Floor ${place.floorNumber}',
    ];
    final navigationLabel = place.isBuildingAlternative
        ? 'Navigation ends at the building'
        : place.hasIndoorNavigation
        ? 'Indoor navigation available'
        : 'Outdoor navigation only';

    return ListTile(
      enabled: enabled,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFFFF1C2),
        child: Icon(
          _icon(place.type),
          key: ValueKey('campus-result-icon-${place.type.name}'),
          color: AppColors.amberInk,
        ),
      ),
      title: Text(place.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(place.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              for (final detail in details)
                Text(
                  detail,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          Text(
            place.external ? 'External Mapbox result' : navigationLabel,
            style: TextStyle(
              color: place.hasIndoorNavigation
                  ? AppColors.green
                  : AppColors.muted,
              fontSize: 11,
            ),
          ),
          if (place.external)
            Text(
              navigationLabel,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
        ],
      ),
      trailing: const Icon(Icons.north_west, size: 18),
    );
  }

  static String _typeLabel(CampusDestinationType type) => switch (type) {
    CampusDestinationType.building => 'Building',
    CampusDestinationType.room => 'Room',
    CampusDestinationType.entrance => 'Entrance',
    CampusDestinationType.parking => 'Parking',
    CampusDestinationType.dining => 'Dining',
    CampusDestinationType.service => 'Service',
    CampusDestinationType.amenity => 'Amenity',
    CampusDestinationType.transit => 'Transit',
    CampusDestinationType.housing => 'Housing',
    CampusDestinationType.landmark => 'Landmark',
    CampusDestinationType.external => 'External',
  };

  static IconData _icon(CampusDestinationType type) => switch (type) {
    CampusDestinationType.building => Icons.business_outlined,
    CampusDestinationType.room => Icons.meeting_room_outlined,
    CampusDestinationType.entrance => Icons.sensor_door_outlined,
    CampusDestinationType.parking => Icons.local_parking,
    CampusDestinationType.dining => Icons.restaurant_outlined,
    CampusDestinationType.service => Icons.support_agent_outlined,
    CampusDestinationType.amenity => Icons.accessible_outlined,
    CampusDestinationType.transit => Icons.directions_bus_outlined,
    CampusDestinationType.housing => Icons.home_outlined,
    CampusDestinationType.landmark => Icons.place_outlined,
    CampusDestinationType.external => Icons.public,
  };
}
