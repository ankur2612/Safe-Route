import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'navigation/app_routes.dart';
import 'providers/crime_data_provider.dart';
import 'providers/location_provider.dart';
import 'providers/route_provider.dart';
import 'utils/app_theme.dart';

void main() {
  runApp(const SafeRouteApp());
}

class SafeRouteApp extends StatelessWidget {
  const SafeRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<LocationProvider>(
          create: (_) => LocationProvider(),
        ),
        ChangeNotifierProvider<RouteProvider>(
          create: (_) => RouteProvider(),
        ),
        ChangeNotifierProvider<CrimeDataProvider>(
          create: (_) => CrimeDataProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'SafeRoute',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: AppRoutes.splash,
        routes: AppRoutes.routes,
      ),
    );
  }
}
