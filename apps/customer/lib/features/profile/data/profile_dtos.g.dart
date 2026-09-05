// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CustomerProfileDto _$CustomerProfileDtoFromJson(Map<String, dynamic> json) =>
    _CustomerProfileDto(
      id: json['id'] as String,
      role: json['role'] as String,
      name: json['name'] as String,
      status: json['status'] as String,
    );

Map<String, dynamic> _$CustomerProfileDtoToJson(_CustomerProfileDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'role': instance.role,
      'name': instance.name,
      'status': instance.status,
    };
