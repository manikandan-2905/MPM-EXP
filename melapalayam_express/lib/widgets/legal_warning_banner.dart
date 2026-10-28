import 'package:flutter/material.dart';
import '../config/constants.dart';

class LegalWarningBanner extends StatelessWidget {
  const LegalWarningBanner({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2), // rose-50
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECDD3)), // rose-200
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFE11D48), // rose-600
            size: 18,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'தடைசெய்யப்பட்டவை: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF881337), // rose-900
                      fontSize: 10.5,
                    ),
                  ),
                  TextSpan(
                    text:
                        'பணம், மதுபானம், போதைப்பொருட்கள், பில் இல்லாத மருந்துகள் அனுப்ப அனுமதி இல்லை. (Strictly No Cash/Alcohol/Illegal items).',
                    style: TextStyle(
                      color: Color(0xFF881337),
                      fontSize: 10.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
