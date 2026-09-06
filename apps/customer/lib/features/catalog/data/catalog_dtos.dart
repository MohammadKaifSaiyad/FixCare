import 'package:freezed_annotation/freezed_annotation.dart';
part 'catalog_dtos.freezed.dart';
part 'catalog_dtos.g.dart';

@freezed
abstract class CategoryDto with _$CategoryDto {
  const factory CategoryDto({required String id, required String name, required String status}) = _CategoryDto;
  factory CategoryDto.fromJson(Map<String, dynamic> j) => _$CategoryDtoFromJson(j);
}

@freezed
abstract class ServiceDto with _$ServiceDto {
  const factory ServiceDto({
    required String id,
    required String name,
    required String tier, // 'T1' | 'T2' | 'T3'
    required String categoryId,
    int? laborPaise, // null = unpriced in the requested zone
    required int visitFeePaise,
  }) = _ServiceDto;
  factory ServiceDto.fromJson(Map<String, dynamic> j) => _$ServiceDtoFromJson(j);
}
