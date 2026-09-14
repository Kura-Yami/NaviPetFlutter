import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navipet/data/navigation_models.dart';
import 'package:navipet/screens/navigation_flow_screens.dart';

Widget harness(NaviDestination destination) =>
    MaterialApp(home: DestinationDetailsScreen(destination: destination));

const outdoor = NavigationCoordinate(latitude: 33.7832, longitude: -118.1147);

void main() {
  testWidgets('shows real building, room, and floor metadata', (tester) async {
    await tester.pumpWidget(
      harness(
        const NaviDestination(
          id: '00000000-0000-4000-8000-000000000001',
          type: CampusDestinationType.room,
          name: 'COB 140',
          address: 'College of Business · Floor 1',
          coordinate: outdoor,
          buildingCode: 'COB',
          roomNumber: '140',
          floorNumber: '1',
          indoorDestinationId: 'multiset-cob-140',
        ),
      ),
    );

    expect(find.text('COB 140'), findsOneWidget);
    expect(find.textContaining('Building COB'), findsOneWidget);
    expect(find.textContaining('Room 140'), findsOneWidget);
    expect(find.textContaining('Floor 1'), findsOneWidget);
    expect(
      find.text('Indoor navigation available after outdoor arrival'),
      findsOneWidget,
    );
    expect(find.textContaining('Room 234'), findsNothing);
  });

  testWidgets('does not offer indoor navigation without a valid indoor ID', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const NaviDestination(
          type: CampusDestinationType.building,
          name: 'Library',
          address: 'LIB',
          coordinate: outdoor,
          buildingCode: 'LIB',
        ),
      ),
    );

    expect(find.text('Outdoor navigation only'), findsOneWidget);
    expect(find.textContaining('Indoor navigation available'), findsNothing);
  });

  testWidgets('states that a building alternative ends at the building', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const NaviDestination(
          type: CampusDestinationType.building,
          name: 'College of Business',
          address: 'Building-level alternative · COB',
          coordinate: outdoor,
          buildingCode: 'COB',
          isBuildingAlternative: true,
        ),
      ),
    );

    expect(find.text('Navigation ends at the building'), findsOneWidget);
    expect(find.textContaining('room-level'), findsNothing);
  });
}
