/// The backend's ServiceSkill values with their display labels, in display (and submit) order.
const kSkills = <(String, String)>[
  ('AC', 'AC'),
  ('FAN', 'Fan'),
  ('ELECTRICAL', 'Electrical'),
  ('WIRING', 'Wiring'),
  ('APPLIANCE', 'Appliance'),
];

String skillLabel(String code) => kSkills.firstWhere((s) => s.$1 == code, orElse: () => (code, code)).$2;
