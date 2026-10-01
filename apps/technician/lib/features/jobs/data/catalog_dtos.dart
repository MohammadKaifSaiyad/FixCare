import 'package:freezed_annotation/freezed_annotation.dart';
part 'catalog_dtos.freezed.dart';
part 'catalog_dtos.g.dart';

@freezed
abstract class DiagnosedIssueDto with _$DiagnosedIssueDto {
  const factory DiagnosedIssueDto({
    required String id,
    required String name,
    required String categoryId,
    required String status,
  }) = _DiagnosedIssueDto;
  factory DiagnosedIssueDto.fromJson(Map<String, dynamic> j) => _$DiagnosedIssueDtoFromJson(j);
}

@freezed
abstract class PartCatalogDto with _$PartCatalogDto {
  const factory PartCatalogDto({
    required String id,
    required String sku,
    required String name,
    String? categoryId,
    required int ceilingPricePaise,
    required String status,
  }) = _PartCatalogDto;
  factory PartCatalogDto.fromJson(Map<String, dynamic> j) => _$PartCatalogDtoFromJson(j);
}
