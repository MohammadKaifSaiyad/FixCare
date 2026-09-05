import 'package:freezed_annotation/freezed_annotation.dart';
part 'profile_dtos.freezed.dart';
part 'profile_dtos.g.dart';

@freezed
abstract class CustomerProfileDto with _$CustomerProfileDto {
  const factory CustomerProfileDto({
    required String id,
    required String role,
    required String name,
    required String status,
  }) = _CustomerProfileDto;
  factory CustomerProfileDto.fromJson(Map<String, dynamic> j) => _$CustomerProfileDtoFromJson(j);
}
