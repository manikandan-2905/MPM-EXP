import 'package:flutter/material.dart';

class AppConstants {
  // Network Config
  // static const String apiBaseUrl = 'http://10.0.2.2:5000/api'; // Local Development
  static const String apiBaseUrl = 'https://mpm-exp.onrender.com/api'; // Live Production (Render)

  // Brand Identity
  static const String appName = 'ZIPPO';
  static const String appTagline = 'Trusted Local Goods Connection';
  static const String appDownloadUrl = 'https://zippo-mpm.onrender.com';

  // Regional Dispatch
  static const String melapalayamRegionName = 'Melapalayam, Tirunelveli';
  static const String defaultWhatsAppGroupUrl = 'https://chat.whatsapp.com/EXAMPLE_MELAPALAYAM_DISPATCH';

  // ZIPPO Support & Help Desk (zippompm@gmail.com | 7639483476 / 6379329930)
  static const String supportDeskTitle = 'ZIPPO Customer Support Desk';
  static const String supportEmail = 'zippompm@gmail.com';
  static const String supportPhone1 = '7639483476';
  static const String supportPhone2 = '6379329930';
  static const String supportPhone = '7639483476';
  static const String supportWhatsApp = '7639483476';

  // Fare Engine Constants
  static const int baseFare = 30; // ₹30 for first 2 km
  static const double baseKm = 2.0;
  static const int perKmRate = 10; // ₹10/km beyond 2 km
  static const int urgentSurcharge = 15; // +₹15

  // Theme Colors (Exact match with MPM Express #76C457 Prototype)
  static const Color mpm50 = Color(0xFFF4FBF0);
  static const Color mpm100 = Color(0xFFE5F6DE);
  static const Color mpm200 = Color(0xFFCBEDBC);
  static const Color mpm300 = Color(0xFFA7DF92);
  static const Color mpm400 = Color(0xFF86CF69);
  static const Color mpm500 = Color(0xFF76C457); // Exact user brand color #76C457
  static const Color mpm600 = Color(0xFF5DA441);
  static const Color mpm700 = Color(0xFF467D32);
  static const Color mpm800 = Color(0xFF3A642B);
  static const Color mpm900 = Color(0xFF325327);
  static const Color mpm950 = Color(0xFF172E12);

  static const Color emerald950 = Color(0xFF172E12);
  static const Color emerald900 = Color(0xFF325327);
  static const Color emerald800 = Color(0xFF3A642B);
  static const Color emerald700 = Color(0xFF467D32);
  static const Color emerald600 = Color(0xFF5DA441);
  static const Color emerald500 = Color(0xFF76C457);
  static const Color emerald200 = Color(0xFFCBEDBC);
  static const Color emerald50 = Color(0xFFF4FBF0);

  static const Color slate950 = Color(0xFF020617);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate50 = Color(0xFFF8FAFC);

  // Pick and Deliver Categories (Fresh Meat removed as requested)
  static const List<Map<String, String>> prototypeCategories = [
    {'id': 'Medicines', 'label': 'Medicine', 'emoji': '💊', 'title': 'Medicines & Pharmacy'},
    {'id': 'Documents', 'label': 'Keys / Docs', 'emoji': '🔑', 'title': 'Keys / Urgent Documents'},
    {'id': 'Grocery', 'label': 'Grocery', 'emoji': '🛒', 'title': 'Grocery & Shop Items'},
    {'id': 'Tailoring', 'label': 'Tailoring', 'emoji': '🧵', 'title': 'Tailoring / Clothes'},
    {'id': 'Food', 'label': 'Lunch / Food', 'emoji': '🍱', 'title': 'Lunch / Any Food'},
    {'id': 'Custom', 'label': 'Other / தனி', 'emoji': '✍️', 'title': 'Any Legal Item / Custom'},
  ];

  // Flat category list for Pick and Deliver form ChoiceChips
  static const List<String> pickupCategories = [
    'Medicines',
    'Documents',
    'Grocery',
    'Tailoring',
    'Lunch / Any Food',
    'Custom (Any Legal Item)',
  ];

  // Buy For Me Categories (6 Categories: Fresh Meat, Veg/Fruits, Grocery, Stationary, Food, Others)
  static const List<Map<String, String>> buyForMeCategories = [
    {'id': 'Meat', 'label': 'Fresh Meat', 'emoji': '🥩', 'title': 'Fresh Mutton / Meat / Chicken', 'placeholder': 'e.g. 1/2 Kg Fresh Mutton (curry cut), 1/2 Kg Chicken'},
    {'id': 'VegFruits', 'label': 'Veg / Fruits', 'emoji': '🥦', 'title': 'Fresh Veg & Fruits', 'placeholder': 'e.g. 1kg Big Onion, 1/2kg Tomato, 2 Lemons, Greens'},
    {'id': 'Grocery', 'label': 'Grocery', 'emoji': '🛒', 'title': 'Grocery & Provisions', 'placeholder': 'e.g. 1kg Sugar, 1/2kg Dhal, 1 Tea packet, Cooking Oil'},
    {'id': 'Stationary', 'label': 'Stationary', 'emoji': '📚', 'title': 'Stationary & Books', 'placeholder': 'e.g. 2 Long Ruled Notebooks, 2 Blue pens, A4 Sheets'},
    {'id': 'Food', 'label': 'Food / Meals', 'emoji': '🍱', 'title': 'Lunch / Hotel Meals', 'placeholder': 'e.g. 2 Chicken Biryani, 4 Parotta, Salna, Tea'},
    {'id': 'Others', 'label': 'Others', 'emoji': '🛍️', 'title': 'Others / Any Legal Items', 'placeholder': 'e.g. Specific items needed from local market stall'},
  ];

  // Prohibited Items Warning (Tamil & English)
  static const String legalWarningText =
      'பாதுகாப்பு விதிமுறைகள்: பணம் (Cash), மதுபானம், போதைப்பொருட்கள், அல்லது பில் இல்லாத மருந்துகள் கொண்டு செல்லப்பட மாட்டாது.';
}
