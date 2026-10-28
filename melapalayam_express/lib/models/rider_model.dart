class RiderModel {
  final String id;
  final String name;
  final String phone;
  final bool isOnline;
  final int totalDeliveries;
  final int totalEarnings;

  RiderModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.isOnline,
    required this.totalDeliveries,
    required this.totalEarnings,
  });

  factory RiderModel.fromJson(Map<String, dynamic> json) {
    return RiderModel(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      isOnline: json['isOnline'] ?? false,
      totalDeliveries: json['totalDeliveries'] ?? 0,
      totalEarnings: json['totalEarnings'] ?? 0,
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
    };
  }
}
