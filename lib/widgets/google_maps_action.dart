import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_model.dart';
import '../services/google_maps_launcher.dart';
import '../utils/app_theme.dart';

/// Explains what "Open in Google Maps" does and does not carry over.
const String googleMapsLimitationNote =
    'Open in Google Maps sends the start, destination and a few points along '
    'the route. Google Maps may still choose different roads, and SafeRoute\'s '
    'risk estimate applies only to the route shown here.';

/// Full-width "Open in Google Maps" action used under each route's details.
class GoogleMapsButton extends StatelessWidget {
  const GoogleMapsButton({
    super.key,
    required this.routeName,
    required this.onPressed,
  });

  final String routeName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Semantics(
        hint: 'Opens directions for $routeName in Google Maps',
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text(
            'Open in Google Maps',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            backgroundColor: AppColors.surface,
          ),
        ),
      ),
    );
  }
}

/// Opens [route] in Google Maps and tells the user when that is not possible.
Future<void> openRouteInGoogleMaps(
  BuildContext context, {
  required GoogleMapsLauncher launcher,
  required LatLng? origin,
  required LatLng? destination,
  required RouteModel route,
}) async {
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  final MapsLaunchResult result = await launcher.openDirections(
    origin: origin,
    destination: destination,
    routePoints: route.points,
  );

  final String? message = switch (result) {
    MapsLaunchResult.opened || MapsLaunchResult.openedFallback => null,
    MapsLaunchResult.missingCoordinates =>
      'The start or destination for ${route.name} is missing, so Google Maps '
          'cannot be opened. Search for the destination again.',
    MapsLaunchResult.failed =>
      "Couldn't open Google Maps. Install Google Maps or a web browser and try "
          'again.',
  };
  if (message != null) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}
