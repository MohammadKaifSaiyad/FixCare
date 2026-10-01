// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalog_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DiagnosedIssueDto _$DiagnosedIssueDtoFromJson(Map<String, dynamic> json) =>
    _DiagnosedIssueDto(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String,
      status: json['status'] as String,
    );

Map<String, dynamic> _$DiagnosedIssueDtoToJson(_DiagnosedIssueDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'categoryId': instance.categoryId,
      'status': instance.status,
    };

_PartCatalogDto _$PartCatalogDtoFromJson(Map<String, dynamic> json) =>
    _PartCatalogDto(
      id: json['id'] as String,
      sku: json['sku'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String?,
      ceilingPricePaise: (json['ceilingPricePaise'] as num).toInt(),
      status: json['status'] as String,
    );

Map<String, dynamic> _$PartCatalogDtoToJson(_PartCatalogDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'sku': instance.sku,
      'name': instance.name,
      'categoryId': instance.categoryId,
      'ceilingPricePaise': instance.ceilingPricePaise,
      'status': instance.status,
    };
