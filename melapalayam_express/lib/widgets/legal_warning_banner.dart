import 'package:flutter/material.dart';

class LegalWarningBanner extends StatelessWidget {
  const LegalWarningBanner({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7).withOpacity(0.4), // amber-500/10
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(
            Icons.shield_outlined,
            color: Color(0xFFD97706), // amber-600
            size: 16,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'பாதுகாப்பு விதிமுறைகள்: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF78350F), // amber-900
                      fontSize: 10.5,
                    ),
                  ),
                  TextSpan(
                    text:
                        'பணம் (Cash), மதுபானம், போதைப்பொருட்கள், அல்லது பில் இல்லாத மருந்துகள் கொண்டு செல்லப்பட மாட்டாது.',
                    style: TextStyle(
                      color: Color(0xFF78350F),
                      fontSize: 10.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
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
