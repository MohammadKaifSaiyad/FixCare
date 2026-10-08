// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'earnings_dtos.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PendingReleaseDto _$PendingReleaseDtoFromJson(Map<String, dynamic> json) =>
    _PendingReleaseDto(
      bookingId: json['bookingId'] as String,
      bookingNumber: json['bookingNumber'] as String,
      serviceName: json['serviceName'] as String,
      amountPaise: (json['amountPaise'] as num).toInt(),
      releasesAt: json['releasesAt'] as String?,
      onHold: json['onHold'] as bool? ?? false,
    );

Map<String, dynamic> _$PendingReleaseDtoToJson(_PendingReleaseDto instance) =>
    <String, dynamic>{
      'bookingId': instance.bookingId,
      'bookingNumber': instance.bookingNumber,
      'serviceName': instance.serviceName,
      'amountPaise': instance.amountPaise,
      'releasesAt': instance.releasesAt,
      'onHold': instance.onHold,
    };

_PayoutRequestDto _$PayoutRequestDtoFromJson(Map<String, dynamic> json) =>
    _PayoutRequestDto(
      id: json['id'] as String,
      status: json['status'] as String,
      amountPaise: (json['amountPaise'] as num).toInt(),
      requestedAt: json['requestedAt'] as String,
      reviewedAt: json['reviewedAt'] as String?,
      reviewNote: json['reviewNote'] as String?,
      paidPaise: (json['paidPaise'] as num?)?.toInt(),
    );

Map<String, dynamic> _$PayoutRequestDtoToJson(_PayoutRequestDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'status': instance.status,
      'amountPaise': instance.amountPaise,
      'requestedAt': instance.requestedAt,
      'reviewedAt': instance.reviewedAt,
      'reviewNote': instance.reviewNote,
      'paidPaise': instance.paidPaise,
    };

_EarningsSummaryDto _$EarningsSummaryDtoFromJson(Map<String, dynamic> json) =>
    _EarningsSummaryDto(
      owedPaise: (json['owedPaise'] as num).toInt(),
      netPayoutPaise: (json['netPayoutPaise'] as num).toInt(),
      pendingPaise: (json['pendingPaise'] as num).toInt(),
      cashDebtPaise: (json['cashDebtPaise'] as num).toInt(),
      cashDebtLimitPaise: (json['cashDebtLimitPaise'] as num).toInt(),
      acceptBlocked: json['acceptBlocked'] as bool,
      payoutMinPaise: (json['payoutMinPaise'] as num).toInt(),
      pending:
          (json['pending'] as List<dynamic>?)
              ?.map(
                (e) => PendingReleaseDto.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const <PendingReleaseDto>[],
      latestPayoutRequest: json['latestPayoutRequest'] == null
          ? null
          : PayoutRequestDto.fromJson(
              json['latestPayoutRequest'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$EarningsSummaryDtoToJson(_EarningsSummaryDto instance) =>
    <String, dynamic>{
      'owedPaise': instance.owedPaise,
      'netPayoutPaise': instance.netPayoutPaise,
      'pendingPaise': instance.pendingPaise,
      'cashDebtPaise': instance.cashDebtPaise,
      'cashDebtLimitPaise': instance.cashDebtLimitPaise,
      'acceptBlocked': instance.acceptBlocked,
      'payoutMinPaise': instance.payoutMinPaise,
      'pending': instance.pending,
      'latestPayoutRequest': instance.latestPayoutRequest,
    };

_LedgerEntryDto _$LedgerEntryDtoFromJson(Map<String, dynamic> json) =>
    _LedgerEntryDto(
      id: json['id'] as String,
      type: json['type'] as String,
      amountPaise: (json['amountPaise'] as num).toInt(),
      bookingNumber: json['bookingNumber'] as String?,
      serviceName: json['serviceName'] as String?,
      createdAt: json['createdAt'] as String,
    );

Map<String, dynamic> _$LedgerEntryDtoToJson(_LedgerEntryDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'amountPaise': instance.amountPaise,
      'bookingNumber': instance.bookingNumber,
      'serviceName': instance.serviceName,
      'createdAt': instance.createdAt,
    };

_LedgerPageDto _$LedgerPageDtoFromJson(Map<String, dynamic> json) =>
    _LedgerPageDto(
      entries:
          (json['entries'] as List<dynamic>?)
              ?.map((e) => LedgerEntryDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <LedgerEntryDto>[],
      nextCursor: json['nextCursor'] as String?,
    );

Map<String, dynamic> _$LedgerPageDtoToJson(_LedgerPageDto instance) =>
    <String, dynamic>{
      'entries': instance.entries,
      'nextCursor': instance.nextCursor,
    };
