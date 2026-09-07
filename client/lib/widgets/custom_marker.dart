import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class CustomMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool isPulsing;

  const CustomMarker({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    this.isPulsing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.8), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Stack(
          alignment: Alignment.center,
          children: [
            if (isPulsing)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(seconds: 2),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Container(
                    width: 36 + (value * 20),
                    height: 36 + (value * 20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(1.0 - value),
                    ),
                  );
                },
              ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
