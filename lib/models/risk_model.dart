import '../utils/json_parsing.dart';

/// Risk levels reported by the backend Risk Engine.
///
/// The frontend never calculates these — it only displays what the backend
/// sends. [unknown] covers missing or unrecognised values so the UI can say
/// "not available" instead of inventing a level.
enum RiskLevel { low, moderate, high, unknown }

extension RiskLevelDisplay on RiskLevel {
  /// Short uppercase label used inside badges, e.g. "LOW".
  String get badgeLabel {
    switch (this) {
      case RiskLevel.low:
        return 'LOW';
      case RiskLevel.moderate:
        return 'MEDIUM';
      case RiskLevel.high:
        return 'HIGH';
      case RiskLevel.unknown:
        return 'N/A';
    }
  }

  /// Sentence-case label used in body text, e.g. "Lower risk".
  String get description {
    switch (this) {
      case RiskLevel.low:
        return 'Lower risk';
      case RiskLevel.moderate:
        return 'Moderate risk';
      case RiskLevel.high:
        return 'Higher risk';
      case RiskLevel.unknown:
        return 'Not available';
    }
  }

  /// Ordering used when comparing routes. Unknown sorts last so a route with
  /// no risk data is never presented as the safer option.
  int get comparisonRank {
    switch (this) {
      case RiskLevel.low:
        return 0;
      case RiskLevel.moderate:
        return 1;
      case RiskLevel.high:
        return 2;
      case RiskLevel.unknown:
        return 3;
    }
  }

  bool get isKnown => this != RiskLevel.unknown;
}

/// Estimated risk for a route, as returned by `POST /api/v1/risk/route`.
class RiskModel {
  const RiskModel({
    required this.level,
    this.score,
    this.reason,
  });

  final RiskLevel level;

  /// Normalised risk score from the backend, when provided. Displayed only
  /// where it genuinely helps the user — never as false precision.
  final double? score;

  /// Short human-readable explanation written by the backend.
  final String? reason;

  static const RiskModel unavailable = RiskModel(level: RiskLevel.unknown);

  factory RiskModel.fromJson(Map<String, dynamic> json) {
    return RiskModel(
      level: parseLevel(json['risk'] ?? json['level']),
      score: asDouble(json['score']),
      reason: asText(json['reason']) ?? asText(json['explanation']),
    );
  }

  /// Maps the backend's risk string onto [RiskLevel]. Anything unexpected
  /// becomes [RiskLevel.unknown] rather than a guess.
  static RiskLevel parseLevel(Object? raw) {
    if (raw is! String) return RiskLevel.unknown;
    switch (raw.trim().toLowerCase()) {
      case 'low':
      case 'lower':
        return RiskLevel.low;
      case 'moderate':
      case 'medium':
        return RiskLevel.moderate;
      case 'high':
      case 'higher':
        return RiskLevel.high;
      default:
        return RiskLevel.unknown;
    }
  }

  /// Score as a whole-number percentage, or null when no score was sent.
  /// Avoids showing values like "73.48291".
  int? get scorePercent {
    final double? value = score;
    if (value == null) return null;
    final double normalised = value <= 1 ? value * 100 : value;
    return normalised.round().clamp(0, 100);
  }
}
