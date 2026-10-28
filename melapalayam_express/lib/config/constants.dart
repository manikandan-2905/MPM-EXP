import 'package:flutter/material.dart';

class AppConstants {
  // Network Config
  // static const String apiBaseUrl = 'http://10.0.2.2:5000/api'; // Local Development
  static const String apiBaseUrl = 'https://mpm-exp.onrender.com/api'; // Live Production (Render)

  // Regional Dispatch
  static const String melapalayamRegionName = 'Melapalayam, Tirunelveli';
  static const String defaultWhatsAppGroupUrl = 'https://chat.whatsapp.com/EXAMPLE_MELAPALAYAM_DISPATCH';

  // Fare Engine Constants
  static const int baseFare = 30; // ₹30 for first 2 km
  static const double baseKm = 2.0;
  static const int perKmRate = 10; // ₹10/km beyond 2 km
  static const int urgentSurcharge = 15; // +₹15

  // Theme Colors (Exact match with MPMExpress Prototype)
  static const Color emerald950 = Color(0xFF022C22);
  static const Color emerald900 = Color(0xFF064E3B);
  static const Color emerald800 = Color(0xFF065F46);
  static const Color emerald700 = Color(0xFF047857);
  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald200 = Color(0xFFA7F3D0);
  static const Color emerald50 = Color(0xFFECFDF5);

  static const Color slate950 = Color(0xFF020617);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate50 = Color(0xFFF8FAFC);

  // Categories matching Prototype
  static const List<Map<String, String>> prototypeCategories = [
    {'id': 'Food', 'label': '🍱 Food / Tiffin'},
    {'id': 'Meat', 'label': '🥩 Fresh Meat'},
    {'id': 'Medicines', 'label': '💊 Medicine'},
    {'id': 'Documents', 'label': '🔑 Keys / Docs'},
    {'id': 'Tailoring', 'label': '🧵 Tailoring'},
    {'id': 'Custom', 'label': '✍️ பிற / Other'},
  ];

  // Prohibited Items Warning (Tamil & English)
  static const String legalWarningText =
      'தடைசெய்யப்பட்டவை: பணம், மதுபானம், போதைப்பொருட்கள், பில் இல்லாத மருந்துகள் அனுப்ப அனுமதி இல்லை. (Strictly No Cash/Alcohol/Illegal items).';
}
