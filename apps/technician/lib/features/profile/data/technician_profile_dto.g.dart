// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'technician_profile_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ZoneRefDto _$ZoneRefDtoFromJson(Map<String, dynamic> json) =>
    _ZoneRefDto(id: json['id'] as String, name: json['name'] as String);

Map<String, dynamic> _$ZoneRefDtoToJson(_ZoneRefDto instance) =>
    <String, dynamic>{'id': instance.id, 'name': instance.name};

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
  zones:
      (json['zones'] as List<dynamic>?)
          ?.map((e) => ZoneRefDto.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ZoneRefDto>[],
  reviewNote: json['reviewNote'] as String?,
  submittedAt: json['submittedAt'] as String?,
);

Map<String, dynamic> _$TechnicianProfileDtoToJson(
  _TechnicianProfileDto instance,
) => <String, dynamic>{
  'id': instance.id,
  'role': instance.role,
  'name': instance.name,
  'skills': instance.skills,
  'status': instance.status,
  'zones': instance.zones,
  'reviewNote': instance.reviewNote,
  'submittedAt': instance.submittedAt,
};
