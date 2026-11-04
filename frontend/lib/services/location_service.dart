import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// Represents a place suggestion for autocomplete and manual search
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

/// Handles reverse geocoding and place search
/// Focused primarily on Melapalayam and surrounding areas (within ~10 km:
/// Palayamkottai, Vannarpettai, Tirunelveli Town, New Bus Stand)
class LocationService {
  // Center of Melapalayam, Tirunelveli
  static const double melapalayamLat = 8.7235;
  static const double melapalayamLng = 77.6910;

  // ~10 km radius in degrees (≈ 0.09°)
  static const double radiusDeg = 0.09;

  static const String _userAgent = 'MPM-Express-App/2.0 (zippo@melapalayam.local)';

  // Viewbox for biasing Nominatim search toward Melapalayam
  static final String _viewbox =
      '${(melapalayamLng - radiusDeg).toStringAsFixed(6)},'
      '${(melapalayamLat + radiusDeg).toStringAsFixed(6)},'
      '${(melapalayamLng + radiusDeg).toStringAsFixed(6)},'
      '${(melapalayamLat - radiusDeg).toStringAsFixed(6)}';

  // ─── Curated Local Places & Streets in Melapalayam & Surrounding Area (10 km) ───
  static const List<Map<String, dynamic>> _localPlacesDb = [
    // Melapalayam Core Streets & Areas
    // ── Newly Added Melapalayam Local Streets & Sub-Localities ──
    {
      'name': 'Kodimaram (கொடிமரம்)',
      'area': 'Melapalayam',
      'full': 'Kodimaram Main Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7230,
      'lng': 77.6912,
    },
    {
      'name': 'Kodimaram North Street (கொடிமரம் வடக்கு தெரு)',
      'area': 'Melapalayam',
      'full': 'Kodimaram North Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7235,
      'lng': 77.6914,
    },
    {
      'name': 'Kodimaram South Street (கொடிமரம் தெற்கு தெரு)',
      'area': 'Melapalayam',
      'full': 'Kodimaram South Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7226,
      'lng': 77.6910,
    },
    {
      'name': 'Anna Street (அண்ணா தெரு)',
      'area': 'Melapalayam',
      'full': 'Anna Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7240,
      'lng': 77.6925,
    },
    {
      'name': 'Anna Nagar Main Road (அண்ணா நகர்)',
      'area': 'Melapalayam',
      'full': 'Anna Nagar Main Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7245,
      'lng': 77.6930,
    },
    {
      'name': 'Anna Nagar 1st Street',
      'area': 'Melapalayam',
      'full': 'Anna Nagar 1st Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7247,
      'lng': 77.6932,
    },
    {
      'name': 'Anna Nagar 2nd Street',
      'area': 'Melapalayam',
      'full': 'Anna Nagar 2nd Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7249,
      'lng': 77.6935,
    },
    {
      'name': 'Jinnah Nagar (ஜின்னா நகர்)',
      'area': 'Melapalayam',
      'full': 'Jinnah Nagar, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7262,
      'lng': 77.6948,
    },
    {
      'name': 'Madina Nagar (மதீனா நகர்)',
      'area': 'Melapalayam',
      'full': 'Madina Nagar, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7275,
      'lng': 77.6955,
    },
    {
      'name': 'Poolathevan Street (பூலத்தேவன் தெரு)',
      'area': 'Melapalayam',
      'full': 'Poolathevan Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7215,
      'lng': 77.6902,
    },
    {
      'name': 'Kulumani Street (குளுமணி தெரு)',
      'area': 'Melapalayam',
      'full': 'Kulumani Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7224,
      'lng': 77.6896,
    },
    {
      'name': 'Mela Kottai Street (மேல கோட்டை தெரு)',
      'area': 'Melapalayam',
      'full': 'Mela Kottai Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7218,
      'lng': 77.6888,
    },
    {
      'name': 'Keela Kottai Street (கீழ கோட்டை தெரு)',
      'area': 'Melapalayam',
      'full': 'Keela Kottai Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7216,
      'lng': 77.6894,
    },
    {
      'name': 'Pattapathu (பட்டப்பத்து)',
      'area': 'Melapalayam',
      'full': 'Pattapathu Main Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7205,
      'lng': 77.6870,
    },
    {
      'name': 'Chidambaram Nagar (சிதம்பரம் நகர்)',
      'area': 'Melapalayam',
      'full': 'Chidambaram Nagar, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7285,
      'lng': 77.6960,
    },
    {
      'name': 'Thiru Vi Ka Street (திரு வி க தெரு)',
      'area': 'Melapalayam',
      'full': 'Thiru Vi Ka Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7238,
      'lng': 77.6922,
    },
    {
      'name': 'Kamaraj Street (காமராஜ் தெரு)',
      'area': 'Melapalayam',
      'full': 'Kamaraj Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7242,
      'lng': 77.6928,
    },
    {
      'name': 'Netaji Street (நேதாஜி தெரு)',
      'area': 'Melapalayam',
      'full': 'Netaji Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7246,
      'lng': 77.6934,
    },
    {
      'name': 'Bharathiyar Street (பாரதியார் தெரு)',
      'area': 'Melapalayam',
      'full': 'Bharathiyar Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7250,
      'lng': 77.6938,
    },
    {
      'name': 'New Colony (நியூ காலனி)',
      'area': 'Melapalayam',
      'full': 'New Colony, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7270,
      'lng': 77.6920,
    },
    {
      'name': 'Hameempuram Main Road',
      'area': 'Melapalayam',
      'full': 'Hameempuram Main Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7220,
      'lng': 77.6905,
    },
    {
      'name': 'Hameempuram 1st Street',
      'area': 'Melapalayam',
      'full': 'Hameempuram 1st Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7222,
      'lng': 77.6908,
    },
    {
      'name': 'Hameempuram 2nd Street',
      'area': 'Melapalayam',
      'full': 'Hameempuram 2nd Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7225,
      'lng': 77.6912,
    },
    {
      'name': 'Hameempuram 3rd Street',
      'area': 'Melapalayam',
      'full': 'Hameempuram 3rd Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7228,
      'lng': 77.6915,
    },
    {
      'name': 'Hameempuram 4th Street',
      'area': 'Melapalayam',
      'full': 'Hameempuram 4th Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7231,
      'lng': 77.6918,
    },
    {
      'name': 'Hameempuram 5th Street',
      'area': 'Melapalayam',
      'full': 'Hameempuram 5th Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7234,
      'lng': 77.6920,
    },
    {
      'name': 'Bazaar Main Road (பஜார் மெயின் ரோடு)',
      'area': 'Melapalayam',
      'full': 'Bazaar Main Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7235,
      'lng': 77.6910,
    },
    {
      'name': 'Melapalayam Uzhavar Sandhai (உழவர் சந்தை)',
      'area': 'Melapalayam',
      'full': 'Uzhavar Sandhai, Market Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7250,
      'lng': 77.6930,
    },
    {
      'name': 'Melapalayam Police Station',
      'area': 'Melapalayam',
      'full': 'Police Station Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7245,
      'lng': 77.6900,
    },
    {
      'name': 'Melapalayam Post Office',
      'area': 'Melapalayam',
      'full': 'Head Post Office Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7238,
      'lng': 77.6908,
    },
    {
      'name': 'Melapalayam Railway Station',
      'area': 'Melapalayam',
      'full': 'Station Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7210,
      'lng': 77.6880,
    },
    {
      'name': 'Shifa Hospital',
      'area': 'Melapalayam',
      'full': 'Shifa Hospital, Main Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7255,
      'lng': 77.6940,
    },
    {
      'name': 'Periya Theru (Big Street / பெரிய தெரு)',
      'area': 'Melapalayam',
      'full': 'Periya Theru (Big Street), Melapalayam, Tirunelveli - 627005',
      'lat': 8.7230,
      'lng': 77.6900,
    },
    {
      'name': 'Chinna Theru (Small Street / சின்ன தெரு)',
      'area': 'Melapalayam',
      'full': 'Chinna Theru, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7228,
      'lng': 77.6895,
    },
    {
      'name': 'Santhaipettai (சந்தைப்பேட்டை)',
      'area': 'Melapalayam',
      'full': 'Santhaipettai, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7260,
      'lng': 77.6925,
    },
    {
      'name': 'Periya Thaikka Mosque',
      'area': 'Melapalayam',
      'full': 'Periya Thaikka Pallivasal, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7240,
      'lng': 77.6915,
    },
    {
      'name': 'Kattubawa Mosque',
      'area': 'Melapalayam',
      'full': 'Kattubawa Pallivasal Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7232,
      'lng': 77.6922,
    },
    {
      'name': 'VST Pallivasal Street',
      'area': 'Melapalayam',
      'full': 'VST Pallivasal Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7248,
      'lng': 77.6918,
    },
    {
      'name': 'Melapalayam Roundana / Junction',
      'area': 'Melapalayam',
      'full': 'Melapalayam Roundana, Main Road, Tirunelveli - 627005',
      'lat': 8.7252,
      'lng': 77.6950,
    },
    {
      'name': 'Kurichi (குறிச்சி)',
      'area': 'Melapalayam',
      'full': 'Kurichi Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7180,
      'lng': 77.6950,
    },
    {
      'name': 'Karivalam (கரிவலம்)',
      'area': 'Melapalayam',
      'full': 'Karivalam Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7195,
      'lng': 77.6890,
    },
    {
      'name': 'Al Ameen Nagar',
      'area': 'Melapalayam',
      'full': 'Al Ameen Nagar, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7270,
      'lng': 77.6890,
    },
    {
      'name': 'Rahmath Nagar',
      'area': 'Melapalayam',
      'full': 'Rahmath Nagar Main Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7280,
      'lng': 77.6935,
    },
    {
      'name': 'Azad Nagar',
      'area': 'Melapalayam',
      'full': 'Azad Nagar, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7265,
      'lng': 77.6945,
    },
    {
      'name': 'Muslim Higher Secondary School',
      'area': 'Melapalayam',
      'full': 'Muslim HSS Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7242,
      'lng': 77.6928,
    },
    {
      'name': 'Mount Zion School Road',
      'area': 'Melapalayam',
      'full': 'Mount Zion School Road, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7258,
      'lng': 77.6960,
    },
    {
      'name': 'Quaid-e-Millath Street',
      'area': 'Melapalayam',
      'full': 'Quaid-e-Millath Street, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7236,
      'lng': 77.6902,
    },
    {
      'name': 'Asura Mela Theru (அசுரா மேல தெரு)',
      'area': 'Melapalayam',
      'full': 'Asura Mela Theru, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7225,
      'lng': 77.6885,
    },
    {
      'name': 'Asura Keela Theru (அசுரா கீழ தெரு)',
      'area': 'Melapalayam',
      'full': 'Asura Keela Theru, Melapalayam, Tirunelveli - 627005',
      'lat': 8.7223,
      'lng': 77.6892,
    },

    // ── Surrounding Area: Palayamkottai (~3-5 km) ──
    {
      'name': 'Palayamkottai Market & Bus Stand',
      'area': 'Palayamkottai',
      'full': 'Market Road, Palayamkottai, Tirunelveli - 627002',
      'lat': 8.7180,
      'lng': 77.7280,
    },
    {
      'name': 'Palayamkottai High Ground',
      'area': 'Palayamkottai',
      'full': 'High Ground, Palayamkottai, Tirunelveli - 627011',
      'lat': 8.7120,
      'lng': 77.7420,
    },
    {
      'name': 'St. Xavier\'s College Road',
      'area': 'Palayamkottai',
      'full': 'St. Xavier\'s College Road, Palayamkottai, Tirunelveli - 627002',
      'lat': 8.7150,
      'lng': 77.7310,
    },
    {
      'name': 'Sarah Tucker College Road',
      'area': 'Palayamkottai',
      'full': 'Sarah Tucker College Road, Palayamkottai, Tirunelveli - 627007',
      'lat': 8.7200,
      'lng': 77.7350,
    },
    {
      'name': 'Palayamkottai Government Hospital (GH)',
      'area': 'Palayamkottai',
      'full': 'Tiruchendur Road, Palayamkottai, Tirunelveli - 627002',
      'lat': 8.7165,
      'lng': 77.7260,
    },

    // ── Surrounding Area: Vannarpettai (~5-6 km) ──
    {
      'name': 'Vannarpettai Chellapandian Circle',
      'area': 'Vannarpettai',
      'full': 'Chellapandian Circle, Vannarpettai, Tirunelveli - 627003',
      'lat': 8.7290,
      'lng': 77.7120,
    },
    {
      'name': 'South Bypass Road, Vannarpettai',
      'area': 'Vannarpettai',
      'full': 'South Bypass Road, Vannarpettai, Tirunelveli - 627003',
      'lat': 8.7275,
      'lng': 77.7160,
    },

    // ── Surrounding Area: Tirunelveli Town (~7-8 km) ──
    {
      'name': 'Tirunelveli Town Nellaiappar Temple',
      'area': 'Tirunelveli Town',
      'full': 'Car Street (ரத வீதி), Nellaiappar Temple, Tirunelveli Town - 627006',
      'lat': 8.7285,
      'lng': 77.6850,
    },
    {
      'name': 'Tirunelveli Town Railway Station Road',
      'area': 'Tirunelveli Town',
      'full': 'Station Road, Tirunelveli Town - 627006',
      'lat': 8.7300,
      'lng': 77.6820,
    },
    {
      'name': 'Tirunelveli Town Arch / Bazaar',
      'area': 'Tirunelveli Town',
      'full': 'Town Arch Bazaar Road, Tirunelveli Town - 627006',
      'lat': 8.7295,
      'lng': 77.6840,
    },

    // ── Surrounding Area: New Bus Stand (~8-10 km) ──
    {
      'name': 'New Bus Stand (MGR Bus Terminus)',
      'area': 'New Bus Stand',
      'full': 'MGR New Bus Terminus, Vepper Kulam, Tirunelveli - 627007',
      'lat': 8.7050,
      'lng': 77.7550,
    },
    {
      'name': 'Tirunelveli Railway Junction (Nellai Jn)',
      'area': 'Tirunelveli Junction',
      'full': 'Junction Main Road, Tirunelveli - 627001',
      'lat': 8.7310,
      'lng': 77.7050,
    },
  ];

  /// Reverse geocode a GPS position to a clean, readable text format.
  /// If Nominatim API fails or gives raw coordinates, finds closest Melapalayam
  /// landmark so riders and customers always have a human-readable address.
  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final formatted = _buildFullAddress(address, data['display_name'] as String? ?? '');
          if (formatted.isNotEmpty && !formatted.contains('null')) {
            return formatted;
          }
        }
        if (data['display_name'] != null && (data['display_name'] as String).isNotEmpty) {
          return _cleanDisplayName(data['display_name'] as String);
        }
      }
    } catch (_) {
      // Network or API failure handled by smart local fallback below
    }

    return _getClosestLocalAddressFallback(lat, lng);
  }

  /// Search for places matching [query], prioritizing Melapalayam and ~10 km surroundings.
  /// Matches local database instantly (zero lag) and merges with Nominatim search.
  static Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.length < 2) return [];

    final suggestions = <PlaceSuggestion>[];
    final seenAddresses = <String>{};

    // 1. Instant Match from Local Melapalayam & 10km Surrounding Database
    for (final place in _localPlacesDb) {
      final name = (place['name'] as String).toLowerCase();
      final area = (place['area'] as String).toLowerCase();
      final full = (place['full'] as String).toLowerCase();

      if (name.contains(cleanQuery) || area.contains(cleanQuery) || full.contains(cleanQuery)) {
        final fullAddr = place['full'] as String;
        if (!seenAddresses.contains(fullAddr)) {
          seenAddresses.add(fullAddr);
          suggestions.add(PlaceSuggestion(
            displayName: '${place['name']} (${place['area']})',
            fullAddress: fullAddr,
            lat: place['lat'] as double,
            lng: place['lng'] as double,
          ));
        }
      }
    }

    // 2. Fetch live OpenStreetMap Nominatim results biased to Melapalayam
    try {
      final encoded = Uri.encodeQueryComponent('$cleanQuery, Melapalayam, Tirunelveli');
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=$encoded'
        '&format=jsonv2'
        '&addressdetails=1'
        '&limit=8'
        '&countrycodes=in'
        '&viewbox=$_viewbox'
        '&bounded=0',
      );

      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final List<dynamic> results = jsonDecode(response.body) as List<dynamic>;

        for (final item in results) {
          final double itemLat = double.tryParse(item['lat'].toString()) ?? 0.0;
          final double itemLng = double.tryParse(item['lon'].toString()) ?? 0.0;

          // Distance filter: strictly limit to 11 km around Melapalayam
          final distKm = _haversineKm(itemLat, itemLng, melapalayamLat, melapalayamLng);
          if (distKm > 11.0) continue;

          final address = item['address'] as Map<String, dynamic>?;
          final rawDisplay = item['display_name'] as String? ?? '';
          final fullFormatted = _buildFullAddress(address, rawDisplay);
          final shortDisplay = _buildShortDisplay(address, rawDisplay);

          if (!seenAddresses.contains(fullFormatted) && fullFormatted.isNotEmpty) {
            seenAddresses.add(fullFormatted);
            suggestions.add(PlaceSuggestion(
              displayName: shortDisplay,
              fullAddress: fullFormatted,
              lat: itemLat,
              lng: itemLng,
            ));
          }
        }
      }
    } catch (_) {
      // Local suggestions already populated
    }

    // Prioritize Melapalayam results first, then surrounding areas
    suggestions.sort((a, b) {
      final aMpm = a.fullAddress.contains('Melapalayam');
      final bMpm = b.fullAddress.contains('Melapalayam');
      if (aMpm && !bMpm) return -1;
      if (!aMpm && bMpm) return 1;
      return 0;
    });

    return suggestions;
  }

  // ─── Address formatting helpers ───────────────────────────────────────────

  static String _buildShortDisplay(Map<String, dynamic>? address, String rawDisplay) {
    if (address == null) {
      return _cleanDisplayName(rawDisplay);
    }

    final parts = <String>[];
    final landmark = address['amenity'] as String? ??
        address['shop'] as String? ??
        address['building'] as String? ??
        address['leisure'] as String? ??
        address['road'] as String?;
    if (landmark != null && landmark.isNotEmpty) parts.add(landmark);

    final area = address['suburb'] as String? ??
        address['neighbourhood'] as String? ??
        address['residential'] as String? ??
        address['quarter'] as String?;
    if (area != null && area.isNotEmpty && !parts.contains(area)) parts.add(area);

    final city = address['town'] as String? ?? address['city'] as String?;
    if (city != null && city.isNotEmpty && !parts.contains(city)) parts.add(city);

    if (parts.isEmpty) {
      return _cleanDisplayName(rawDisplay);
    }
    return parts.join(', ');
  }

  static String _buildFullAddress(Map<String, dynamic>? address, String rawDisplay) {
    if (address == null) return _cleanDisplayName(rawDisplay);

    final parts = <String>[];

    // 1. Landmark / Shop / Building
    final landmark = address['amenity'] as String? ??
        address['shop'] as String? ??
        address['building'] as String? ??
        address['office'] as String?;
    if (landmark != null && landmark.isNotEmpty) {
      parts.add(landmark);
    }

    // 2. House number & Street/Road
    final houseNumber = address['house_number'] as String?;
    final road = address['road'] as String? ?? address['street'] as String? ?? address['pedestrian'] as String?;
    if (houseNumber != null && road != null) {
      parts.add('$houseNumber, $road');
    } else if (road != null && road.isNotEmpty && !parts.contains(road)) {
      parts.add(road);
    }

    // 3. Area / Suburb / Neighbourhood
    final suburb = address['suburb'] as String? ??
        address['neighbourhood'] as String? ??
        address['residential'] as String? ??
        address['hamlet'] as String? ??
        address['village'] as String?;
    if (suburb != null && suburb.isNotEmpty && !parts.contains(suburb)) {
      parts.add(suburb);
    }

    // 4. City / Town
    final city = address['town'] as String? ?? address['city'] as String? ?? 'Tirunelveli';
    if (!parts.contains(city)) {
      parts.add(city);
    }

    // 5. Postcode
    final postcode = address['postcode'] as String?;
    if (postcode != null && postcode.isNotEmpty) {
      return '${parts.join(', ')} - $postcode';
    }

    if (parts.isEmpty) return _cleanDisplayName(rawDisplay);
    return parts.join(', ');
  }

  static String _cleanDisplayName(String rawDisplay) {
    final segments = rawDisplay.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (segments.length <= 4) return segments.join(', ');
    return segments.take(4).join(', ');
  }

  static String _getClosestLocalAddressFallback(double lat, double lng) {
    double minDistance = double.infinity;
    Map<String, dynamic> closest = _localPlacesDb.first;

    for (final p in _localPlacesDb) {
      final d = _haversineKm(lat, lng, p['lat'] as double, p['lng'] as double);
      if (d < minDistance) {
        minDistance = d;
        closest = p;
      }
    }

    if (minDistance <= 1.5) {
      return 'Near ${closest['name']}, ${closest['full']} (GPS)';
    } else if (minDistance <= 12.0) {
      return '${closest['area']}, Tirunelveli (GPS: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
    }
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)} (Melapalayam GPS)';
  }

  // ─── Haversine distance ────────────────────────────────────────────────────

  static double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLng / 2), 2) * math.cos(_toRad(lat1)) * math.cos(_toRad(lat2));
    final c = 2 * math.asin(math.sqrt(a));
    return r * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}
