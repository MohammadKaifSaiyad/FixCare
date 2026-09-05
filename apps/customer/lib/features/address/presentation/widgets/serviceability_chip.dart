import 'package:flutter/material.dart';
import '../../../../core/theme.dart';

class ServiceabilityChip extends StatelessWidget {
  const ServiceabilityChip({super.key, required this.serviceable});
  final bool serviceable;

  @override
  Widget build(BuildContext context) {
    final ok = serviceable;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFE9F5EF) : FixCareColors.disabledFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ok ? Icons.check_circle : Icons.info_outline, size: 14,
            color: ok ? FixCareColors.success : FixCareColors.textMuted),
        const SizedBox(width: 5),
        Text(ok ? 'We serve this area' : 'Out of service area',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: ok ? FixCareColors.success : FixCareColors.textMuted)),
      ]),
    );
  }
}
