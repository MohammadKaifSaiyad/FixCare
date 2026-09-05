import 'package:freezed_annotation/freezed_annotation.dart';
part 'auth_dtos.freezed.dart';
part 'auth_dtos.g.dart';

@freezed
abstract class UserDto with _$UserDto {
  const factory UserDto({required String id, required String role, required String status}) = _UserDto;
  factory UserDto.fromJson(Map<String, dynamic> j) => _$UserDtoFromJson(j);
}

@freezed
abstract class VerifyResponse with _$VerifyResponse {
  const factory VerifyResponse({required String accessToken, required String refreshToken, required UserDto user}) = _VerifyResponse;
  factory VerifyResponse.fromJson(Map<String, dynamic> j) => _$VerifyResponseFromJson(j);
}

@freezed
abstract class RefreshResponse with _$RefreshResponse {
  const factory RefreshResponse({required String accessToken, required String refreshToken}) = _RefreshResponse;
  factory RefreshResponse.fromJson(Map<String, dynamic> j) => _$RefreshResponseFromJson(j);
}

@freezed
abstract class SendOtpResponse with _$SendOtpResponse {
  const factory SendOtpResponse({required bool ok, String? devOtp}) = _SendOtpResponse;
  factory SendOtpResponse.fromJson(Map<String, dynamic> j) => _$SendOtpResponseFromJson(j);
}
