import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// Represents a place suggestion from Nominatim
class PlaceSuggestion {
  final String displayName; // Short label for dropdown
  final String fullAddress; // Full address to fill the field
  final double lat;
  final double lng;

  const PlaceSuggestion({
    required this.displayName,
    required this.fullAddress,
    required this.lat,
    required this.lng,
  });
}

/// Handles reverse geocoding and place search via OpenStreetMap Nominatim API
/// All results are filtered to within ~10–12 km of Melapalayam, Tirunelveli
class LocationService {
  // Center of Melapalayam, Tirunelveli
  static const double melapalayamLat = 8.7235;
  static const double melapalayamLng = 77.6910;

  // ~10 km radius in degrees (≈ 0.09°)
  static const double radiusDeg = 0.09;

  static const String _userAgent = 'MPM-Express-App/1.0 (mpm@local.dev)';

  // Viewbox for biasing Nominatim search toward Melapalayam
  // Format: left,top,right,bottom
  static final String _viewbox =
      '${(melapalayamLng - radiusDeg).toStringAsFixed(6)},'
      '${(melapalayamLat + radiusDeg).toStringAsFixed(6)},'
      '${(melapalayamLng + radiusDeg).toStringAsFixed(6)},'
      '${(melapalayamLat - radiusDeg).toStringAsFixed(6)}';

  /// Reverse geocode a GPS position to a full readable address string.
  /// Returns a fallback coordinate string if the API fails.
  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        if (address == null) {
          return data['display_name'] as String? ?? _fallbackCoords(lat, lng);
        }
        return _buildFullAddress(address, data['display_name'] as String? ?? '');
      }
    } catch (_) {
      // Fallback on any network/timeout error
    }
    return _fallbackCoords(lat, lng);
  }

  static String _fallbackCoords(double lat, double lng) =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)} (GPS)';

  /// Search for places matching [query], biased toward Melapalayam's 10km area.
  /// Returns an empty list if query is shorter than 3 characters.
  static Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    if (query.trim().length < 3) return [];

    try {
      final encoded = Uri.encodeQueryComponent('$query, Tirunelveli');
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=$encoded'
        '&format=jsonv2'
        '&addressdetails=1'
        '&limit=10'
        '&countrycodes=in'
        '&viewbox=$_viewbox'
        '&bounded=0', // not strictly bounded so short queries still return results
      );

      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> results = jsonDecode(response.body) as List<dynamic>;
        final suggestions = <PlaceSuggestion>[];

        for (final item in results) {
          final double itemLat =
              double.tryParse(item['lat'].toString()) ?? 0.0;
          final double itemLng =
              double.tryParse(item['lon'].toString()) ?? 0.0;

          // Distance filter: skip places farther than 12 km (slight buffer over 10 km)
          final distKm = _haversineKm(
            itemLat, itemLng, melapalayamLat, melapalayamLng,
          );
          if (distKm > 12.0) continue;

          final address = item['address'] as Map<String, dynamic>?;
          final rawDisplay = item['display_name'] as String? ?? '';

          suggestions.add(PlaceSuggestion(
            displayName: _buildShortDisplay(address, rawDisplay),
            fullAddress: _buildFullAddress(address, rawDisplay),
            lat: itemLat,
            lng: itemLng,
          ));
        }
        return suggestions;
      }
    } catch (_) {
      // Return empty list on error
    }
    return [];
  }

  // ─── Address formatting helpers ───────────────────────────────────────────

  static String _buildShortDisplay(
      Map<String, dynamic>? address, String rawDisplay) {
    if (address == null) {
      final parts = rawDisplay.split(',');
      return parts.take(3).join(',').trim();
    }

    final parts = <String>[];
    final name = address['amenity'] as String? ??
        address['shop'] as String? ??
        address['leisure'] as String? ??
        address['tourism'] as String? ??
        address['road'] as String?;
    if (name != null) parts.add(name);

    final area = address['suburb'] as String? ??
        address['neighbourhood'] as String? ??
        address['quarter'] as String?;
    if (area != null) parts.add(area);

    final city =
        address['town'] as String? ?? address['city'] as String?;
    if (city != null) parts.add(city);

    if (parts.isEmpty) {
      final fallback = rawDisplay.split(',');
      return fallback.take(3).join(',').trim();
    }
    return parts.join(', ');
  }

  static String _buildFullAddress(
      Map<String, dynamic>? address, String rawDisplay) {
    if (address == null) return rawDisplay;

    final parts = <String>[];

    final houseNumber = address['house_number'] as String?;
    final road = address['road'] as String?;
    if (houseNumber != null && road != null) {
      parts.add('$houseNumber, $road');
    } else if (road != null) {
      parts.add(road);
    }

    final area = address['suburb'] as String? ??
        address['neighbourhood'] as String? ??
        address['quarter'] as String?;
    if (area != null) parts.add(area);

    final town = address['town'] as String? ?? address['city'] as String?;
    if (town != null) parts.add(town);

    final state = address['state'] as String?;
    if (state != null) parts.add(state);

    if (parts.isEmpty) return rawDisplay;
    return parts.join(', ');
  }

  // ─── Haversine distance ────────────────────────────────────────────────────

  static double _haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLng / 2), 2) *
            math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2));
    final c = 2 * math.asin(math.sqrt(a));
    return r * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}
