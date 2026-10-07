import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../profile/data/technician_profile_dto.dart';
import 'skills.dart';

/// Read-only recap of what the technician submitted (name, skills, zone names).
class SubmittedSummary extends StatelessWidget {
  const SubmittedSummary({super.key, required this.profile});
  final TechnicianProfileDto profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('submittedSummary'),
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FixCareColors.surface,
        border: Border.all(color: FixCareColors.border),
        borderRadius: BorderRadius.circular(FixCareRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Name', profile.name),
          _row('Skills', profile.skills.map(skillLabel).join(', ')),
          _row('Service zones', profile.zones.map((z) => z.name).join(', ')),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12.5, color: FixCareColors.textMuted)),
            Text(value, style: const TextStyle(fontSize: 15, color: FixCareColors.textPrimary)),
          ],
        ),
      );
}
