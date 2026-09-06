// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CategoryDto _$CategoryDtoFromJson(Map<String, dynamic> json) => _CategoryDto(
  id: json['id'] as String,
  name: json['name'] as String,
  status: json['status'] as String,
);

Map<String, dynamic> _$CategoryDtoToJson(_CategoryDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'status': instance.status,
    };

_ServiceDto _$ServiceDtoFromJson(Map<String, dynamic> json) => _ServiceDto(
  id: json['id'] as String,
  name: json['name'] as String,
  tier: json['tier'] as String,
  categoryId: json['categoryId'] as String,
  laborPaise: (json['laborPaise'] as num?)?.toInt(),
  visitFeePaise: (json['visitFeePaise'] as num).toInt(),
);

Map<String, dynamic> _$ServiceDtoToJson(_ServiceDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'tier': instance.tier,
      'categoryId': instance.categoryId,
      'laborPaise': instance.laborPaise,
      'visitFeePaise': instance.visitFeePaise,
    };
