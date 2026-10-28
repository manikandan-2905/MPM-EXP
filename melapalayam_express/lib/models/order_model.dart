class OrderCoordinates {
  final double? lat;
  final double? lng;

  OrderCoordinates({this.lat, this.lng});

  factory OrderCoordinates.fromJson(Map<String, dynamic>? json) {
    if (json == null) return OrderCoordinates();
    return OrderCoordinates(
      lat: (json['lat'] != null) ? (json['lat'] as num).toDouble() : null,
      lng: (json['lng'] != null) ? (json['lng'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
    };
  }
}

class OrderModel {
  final String id;
  final String orderNumber;
  final String customerName;
  final String customerPhone;
  final String? pickupPhone;
  final String? dropPhone;
  final String orderType; // 'PICKUP_DROP' | 'BUY_FOR_ME'
  final String category;
  final List<String> itemsList;
  final String? shopName;
  final double budget;
  final bool isUrgent;
  final String pickupAddress;
  final OrderCoordinates? pickupCoords;
  final String dropAddress;
  final OrderCoordinates? dropCoords;
  final String status; // 'ORDER_PLACED', 'RIDER_ASSIGNED', 'ITEM_PURCHASED', 'ON_THE_WAY', 'DELIVERED', 'CANCELLED'
  final Map<String, dynamic>? assignedRider;
  final String deliveryPin;
  final bool isOtpBypassed;
  final int fare;
  final double estimatedDistanceKm;
  final DateTime createdAt;

  OrderModel({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.customerPhone,
    this.pickupPhone,
    this.dropPhone,
    required this.orderType,
    required this.category,
    required this.itemsList,
    this.shopName,
    required this.budget,
    required this.isUrgent,
    required this.pickupAddress,
    this.pickupCoords,
    required this.dropAddress,
    this.dropCoords,
    required this.status,
    this.assignedRider,
    required this.deliveryPin,
    required this.isOtpBypassed,
    required this.fare,
    required this.estimatedDistanceKm,
    required this.createdAt,
  });

  bool get isPlaced => status == 'ORDER_PLACED';
  bool get isAssigned => status == 'RIDER_ASSIGNED';
  bool get isItemPurchased => status == 'ITEM_PURCHASED';
  bool get isOnTheWay => status == 'ON_THE_WAY';
  bool get isDelivered => status == 'DELIVERED';
  bool get isCancelled => status == 'CANCELLED';

  // Locked Cancellation: customer cannot cancel once items are bought/picked up
  bool get canCancel => status == 'ORDER_PLACED' || status == 'RIDER_ASSIGNED';

  String? get riderName => assignedRider != null ? assignedRider!['name'] : null;
  String? get riderPhone => assignedRider != null ? assignedRider!['phone'] : null;

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['_id'] ?? json['id'] ?? '',
      orderNumber: json['orderNumber'] ?? '',
      customerName: json['customerName'] ?? '',
      customerPhone: json['customerPhone'] ?? '',
      pickupPhone: json['pickupPhone'],
      dropPhone: json['dropPhone'],
      orderType: json['orderType'] ?? 'PICKUP_DROP',
      category: json['category'] ?? 'Custom',
      itemsList: (json['itemsList'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      shopName: json['shopName'],
      budget: (json['budget'] != null) ? (json['budget'] as num).toDouble() : 0.0,
      isUrgent: json['isUrgent'] ?? false,
      pickupAddress: json['pickupAddress'] ?? '',
      pickupCoords: OrderCoordinates.fromJson(json['pickupCoords']),
      dropAddress: json['dropAddress'] ?? '',
      dropCoords: OrderCoordinates.fromJson(json['dropCoords']),
      status: json['status'] ?? 'ORDER_PLACED',
      assignedRider: json['assignedRider'] is Map<String, dynamic>
          ? json['assignedRider']
          : null,
      deliveryPin: json['deliveryPin'] ?? '----',
      isOtpBypassed: json['isOtpBypassed'] ?? false,
      fare: json['fare'] != null ? (json['fare'] as num).toInt() : 30,
      estimatedDistanceKm: (json['estimatedDistanceKm'] != null)
          ? (json['estimatedDistanceKm'] as num).toDouble()
          : 2.0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
