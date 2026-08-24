import 'package:flutter/material.dart';

import '../screens/about_risk_screen.dart';
import '../screens/home_screen.dart';
import '../screens/route_comparison_screen.dart';
import '../screens/splash_screen.dart';

/// Named routes for the app.
///
/// The experience stays centred on the map, so there are only a few screens:
/// splash, the map itself, full route comparison and the risk explainer.
class AppRoutes {
  const AppRoutes._();

  static const String splash = '/';
  static const String home = '/home';
  static const String comparison = '/routes/compare';
  static const String aboutRisk = '/about-risk';

  static Map<String, WidgetBuilder> get routes => <String, WidgetBuilder>{
        splash: (_) => const SplashScreen(),
        home: (_) => const HomeScreen(),
        comparison: (_) => const RouteComparisonScreen(),
        aboutRisk: (_) => const AboutRiskScreen(),
      };
}
