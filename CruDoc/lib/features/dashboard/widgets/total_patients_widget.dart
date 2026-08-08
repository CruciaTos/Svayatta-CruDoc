import 'package:flutter/material.dart';

class TotalPatientsWidget extends StatelessWidget {
  const TotalPatientsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Patients',
                style: TextStyle(color: Color(0xFF1A1A1A), fontSize: 14, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '+16.2%',
                  style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: '1,024 ',
                  style: TextStyle(color: Color(0xFF1A1A1A), fontSize: 28, fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: 'active',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            value: 0.8,
            backgroundColor: Color(0xFFE0E0E0),
            color: Color(0xFF3F51B5),
          ),
        ],
      ),
    );
  }
}