import 'package:flutter/material.dart';

class RiderCounterBadge extends StatelessWidget {
  final int count;
  final bool isLoading;

  const RiderCounterBadge({
    Key? key,
    required this.count,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool hasRiders = count > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasRiders ? const Color(0xFF34D399) : const Color(0xFFF87171),
          ),
        ),
        const SizedBox(width: 6),
        isLoading
            ? const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              )
            : Text(
                hasRiders
                    ? '🟢 $count Riders Active in Melapalayam'
                    : '🟡 All riders busy / offline',
                style: const TextStyle(
                  color: Color(0xFFD1FAE5), // emerald-100
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
      ],
    );
  }
}
