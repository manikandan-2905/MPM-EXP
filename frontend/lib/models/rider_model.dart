class RiderModel {
  final String id;
  final String name;
  final String phone;
  final bool isOnline;
  final int totalDeliveries;
  final int totalEarnings;
  final int totalOrders;
  final int todayOrders;
  final int todayEarnings;
  final int cashEarnings;
  final int upiEarnings;

  RiderModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.isOnline,
    required this.totalDeliveries,
    required this.totalEarnings,
    this.totalOrders = 0,
    this.todayOrders = 0,
    this.todayEarnings = 0,
    this.cashEarnings = 0,
    this.upiEarnings = 0,
  });

  factory RiderModel.fromJson(Map<String, dynamic> json) {
    return RiderModel(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      isOnline: json['isOnline'] ?? false,
      totalDeliveries: json['totalDeliveries'] ?? json['totalOrders'] ?? 0,
      totalEarnings: json['totalEarnings'] ?? 0,
      totalOrders: json['totalOrders'] ?? json['totalDeliveries'] ?? 0,
      todayOrders: json['todayOrders'] ?? 0,
      todayEarnings: json['todayEarnings'] ?? 0,
      cashEarnings: json['cashEarnings'] ?? 0,
      upiEarnings: json['upiEarnings'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'isOnline': isOnline,
      'totalDeliveries': totalDeliveries,
      'totalEarnings': totalEarnings,
      'totalOrders': totalOrders,
      'todayOrders': todayOrders,
      'todayEarnings': todayEarnings,
      'cashEarnings': cashEarnings,
      'upiEarnings': upiEarnings,
    };
  }
}
