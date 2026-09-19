// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'technician_profile_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TechnicianProfileDto _$TechnicianProfileDtoFromJson(
  Map<String, dynamic> json,
) => _TechnicianProfileDto(
  id: json['id'] as String,
  role: json['role'] as String,
  name: json['name'] as String,
  skills:
      (json['skills'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const <String>[],
  status: json['status'] as String,
);

Map<String, dynamic> _$TechnicianProfileDtoToJson(
  _TechnicianProfileDto instance,
) => <String, dynamic>{
  'id': instance.id,
  'role': instance.role,
  'name': instance.name,
  'skills': instance.skills,
  'status': instance.status,
};
