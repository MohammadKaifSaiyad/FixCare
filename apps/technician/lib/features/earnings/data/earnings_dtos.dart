import 'package:freezed_annotation/freezed_annotation.dart';
part 'earnings_dtos.freezed.dart';
part 'earnings_dtos.g.dart';

@freezed
abstract class PendingReleaseDto with _$PendingReleaseDto {
  const factory PendingReleaseDto({
    required String bookingId,
    required String bookingNumber,
    required String serviceName,
    required int amountPaise,
    String? releasesAt,
    @Default(false) bool onHold,
  }) = _PendingReleaseDto;
  factory PendingReleaseDto.fromJson(Map<String, dynamic> j) => _$PendingReleaseDtoFromJson(j);
}

@freezed
abstract class PayoutRequestDto with _$PayoutRequestDto {
  const factory PayoutRequestDto({
    required String id,
    required String status, // REQUESTED | PAID | REJECTED
    required int amountPaise,
    required String requestedAt,
    String? reviewedAt,
    String? reviewNote,
    int? paidPaise, // amount actually paid when PAID; can differ from amountPaise
  }) = _PayoutRequestDto;
  factory PayoutRequestDto.fromJson(Map<String, dynamic> j) => _$PayoutRequestDtoFromJson(j);
}

@freezed
abstract class EarningsSummaryDto with _$EarningsSummaryDto {
  const factory EarningsSummaryDto({
    required int owedPaise,
    required int netPayoutPaise,
    required int pendingPaise,
    required int cashDebtPaise,
    required int cashDebtLimitPaise,
    required bool acceptBlocked,
    required int payoutMinPaise,
    @Default(<PendingReleaseDto>[]) List<PendingReleaseDto> pending,
    PayoutRequestDto? latestPayoutRequest,
  }) = _EarningsSummaryDto;
  factory EarningsSummaryDto.fromJson(Map<String, dynamic> j) => _$EarningsSummaryDtoFromJson(j);
}

@freezed
abstract class LedgerEntryDto with _$LedgerEntryDto {
  const factory LedgerEntryDto({
    required String id,
    required String type,
    required int amountPaise,
    String? bookingNumber,
    String? serviceName,
    required String createdAt,
  }) = _LedgerEntryDto;
  factory LedgerEntryDto.fromJson(Map<String, dynamic> j) => _$LedgerEntryDtoFromJson(j);
}

@freezed
abstract class LedgerPageDto with _$LedgerPageDto {
  const factory LedgerPageDto({
    @Default(<LedgerEntryDto>[]) List<LedgerEntryDto> entries,
    String? nextCursor,
  }) = _LedgerPageDto;
  factory LedgerPageDto.fromJson(Map<String, dynamic> j) => _$LedgerPageDtoFromJson(j);
}
