import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/order_model.dart';
import 'order_tracking_screen.dart';

class OrderSuccessShareScreen extends StatelessWidget {
  final OrderModel order;
  final String whatsappTicket;

  const OrderSuccessShareScreen({
    Key? key,
    required this.order,
    required this.whatsappTicket,
  }) : super(key: key);

  void _shareToWhatsApp(BuildContext context) {
    Share.share(
      whatsappTicket,
      subject: 'Melapalayam Express Order #${order.orderNumber}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Success Icon
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF064E3B),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 48,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Order Placed Successfully!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Order ID: ${order.orderNumber}',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),

              const SizedBox(height: 24),

              // Delivery PIN Card
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'YOUR 4-DIGIT DELIVERY PIN',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      order.deliveryPin,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 36,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Share this PIN with your rider only when receiving your package.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // WhatsApp Dispatch Share Action
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2E23),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF25D366).withOpacity(0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.chat, color: Color(0xFF25D366), size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Dispatch to Melapalayam WhatsApp Group',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Broadcast this formatted order ticket directly to local riders in the Melapalayam dispatch group for instant pickup.',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text(
                          'Share Ticket to WhatsApp Group',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _shareToWhatsApp(context),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Track Order Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderTrackingScreen(orderId: order.id),
                      ),
                    );
                  },
                  child: const Text(
                    'Track Live Milestones',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                child: const Text('Back to Home', style: TextStyle(color: Colors.white60)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
