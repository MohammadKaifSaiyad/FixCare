// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'earnings_dtos.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PendingReleaseDto {

 String get bookingId; String get bookingNumber; String get serviceName; int get amountPaise; String? get releasesAt; bool get onHold;
/// Create a copy of PendingReleaseDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PendingReleaseDtoCopyWith<PendingReleaseDto> get copyWith => _$PendingReleaseDtoCopyWithImpl<PendingReleaseDto>(this as PendingReleaseDto, _$identity);

  /// Serializes this PendingReleaseDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PendingReleaseDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PendingReleaseDto&&(identical(other.bookingId, _this.bookingId) || other.bookingId == _this.bookingId)&&(identical(other.bookingNumber, _this.bookingNumber) || other.bookingNumber == _this.bookingNumber)&&(identical(other.serviceName, _this.serviceName) || other.serviceName == _this.serviceName)&&(identical(other.amountPaise, _this.amountPaise) || other.amountPaise == _this.amountPaise)&&(identical(other.releasesAt, _this.releasesAt) || other.releasesAt == _this.releasesAt)&&(identical(other.onHold, _this.onHold) || other.onHold == _this.onHold));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PendingReleaseDto;
  return Object.hash(runtimeType,_this.bookingId,_this.bookingNumber,_this.serviceName,_this.amountPaise,_this.releasesAt,_this.onHold);
}

@override
String toString() {
  final _this = this as PendingReleaseDto;
  return 'PendingReleaseDto(bookingId: ${_this.bookingId}, bookingNumber: ${_this.bookingNumber}, serviceName: ${_this.serviceName}, amountPaise: ${_this.amountPaise}, releasesAt: ${_this.releasesAt}, onHold: ${_this.onHold})';
}


}

/// @nodoc
abstract mixin class $PendingReleaseDtoCopyWith<$Res>  {
  factory $PendingReleaseDtoCopyWith(PendingReleaseDto value, $Res Function(PendingReleaseDto) _then) = _$PendingReleaseDtoCopyWithImpl;
@useResult
$Res call({
 String bookingId, String bookingNumber, String serviceName, int amountPaise, String? releasesAt, bool onHold
});




}
/// @nodoc
class _$PendingReleaseDtoCopyWithImpl<$Res>
    implements $PendingReleaseDtoCopyWith<$Res> {
  _$PendingReleaseDtoCopyWithImpl(this._self, this._then);

  final PendingReleaseDto _self;
  final $Res Function(PendingReleaseDto) _then;

/// Create a copy of PendingReleaseDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? bookingId = null,Object? bookingNumber = null,Object? serviceName = null,Object? amountPaise = null,Object? releasesAt = freezed,Object? onHold = null,}) {
  return _then(PendingReleaseDto(
bookingId: null == bookingId ? _self.bookingId : bookingId // ignore: cast_nullable_to_non_nullable
as String,bookingNumber: null == bookingNumber ? _self.bookingNumber : bookingNumber // ignore: cast_nullable_to_non_nullable
as String,serviceName: null == serviceName ? _self.serviceName : serviceName // ignore: cast_nullable_to_non_nullable
as String,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,releasesAt: freezed == releasesAt ? _self.releasesAt : releasesAt // ignore: cast_nullable_to_non_nullable
as String?,onHold: null == onHold ? _self.onHold : onHold // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [PendingReleaseDto].
extension PendingReleaseDtoPatterns on PendingReleaseDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PendingReleaseDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PendingReleaseDto() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PendingReleaseDto value)  $default,){
final _that = this;
switch (_that) {
case _PendingReleaseDto():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PendingReleaseDto value)?  $default,){
final _that = this;
switch (_that) {
case _PendingReleaseDto() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String bookingId,  String bookingNumber,  String serviceName,  int amountPaise,  String? releasesAt,  bool onHold)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PendingReleaseDto() when $default != null:
return $default(_that.bookingId,_that.bookingNumber,_that.serviceName,_that.amountPaise,_that.releasesAt,_that.onHold);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String bookingId,  String bookingNumber,  String serviceName,  int amountPaise,  String? releasesAt,  bool onHold)  $default,) {final _that = this;
switch (_that) {
case _PendingReleaseDto():
return $default(_that.bookingId,_that.bookingNumber,_that.serviceName,_that.amountPaise,_that.releasesAt,_that.onHold);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String bookingId,  String bookingNumber,  String serviceName,  int amountPaise,  String? releasesAt,  bool onHold)?  $default,) {final _that = this;
switch (_that) {
case _PendingReleaseDto() when $default != null:
return $default(_that.bookingId,_that.bookingNumber,_that.serviceName,_that.amountPaise,_that.releasesAt,_that.onHold);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PendingReleaseDto implements PendingReleaseDto {
  const _PendingReleaseDto({required this.bookingId, required this.bookingNumber, required this.serviceName, required this.amountPaise, this.releasesAt, this.onHold = false});
  factory _PendingReleaseDto.fromJson(Map<String, dynamic> json) => _$PendingReleaseDtoFromJson(json);

@override final  String bookingId;
@override final  String bookingNumber;
@override final  String serviceName;
@override final  int amountPaise;
@override final  String? releasesAt;
@override@JsonKey() final  bool onHold;

/// Create a copy of PendingReleaseDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PendingReleaseDtoCopyWith<_PendingReleaseDto> get copyWith => __$PendingReleaseDtoCopyWithImpl<_PendingReleaseDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PendingReleaseDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PendingReleaseDto&&(identical(other.bookingId, bookingId) || other.bookingId == bookingId)&&(identical(other.bookingNumber, bookingNumber) || other.bookingNumber == bookingNumber)&&(identical(other.serviceName, serviceName) || other.serviceName == serviceName)&&(identical(other.amountPaise, amountPaise) || other.amountPaise == amountPaise)&&(identical(other.releasesAt, releasesAt) || other.releasesAt == releasesAt)&&(identical(other.onHold, onHold) || other.onHold == onHold));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,bookingId,bookingNumber,serviceName,amountPaise,releasesAt,onHold);
}

@override
String toString() {
    return 'PendingReleaseDto(bookingId: $bookingId, bookingNumber: $bookingNumber, serviceName: $serviceName, amountPaise: $amountPaise, releasesAt: $releasesAt, onHold: $onHold)';
}


}

/// @nodoc
abstract mixin class _$PendingReleaseDtoCopyWith<$Res> implements $PendingReleaseDtoCopyWith<$Res> {
  factory _$PendingReleaseDtoCopyWith(_PendingReleaseDto value, $Res Function(_PendingReleaseDto) _then) = __$PendingReleaseDtoCopyWithImpl;
@override @useResult
$Res call({
 String bookingId, String bookingNumber, String serviceName, int amountPaise, String? releasesAt, bool onHold
});




}
/// @nodoc
class __$PendingReleaseDtoCopyWithImpl<$Res>
    implements _$PendingReleaseDtoCopyWith<$Res> {
  __$PendingReleaseDtoCopyWithImpl(this._self, this._then);

  final _PendingReleaseDto _self;
  final $Res Function(_PendingReleaseDto) _then;

/// Create a copy of PendingReleaseDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? bookingId = null,Object? bookingNumber = null,Object? serviceName = null,Object? amountPaise = null,Object? releasesAt = freezed,Object? onHold = null,}) {
  return _then(_PendingReleaseDto(
bookingId: null == bookingId ? _self.bookingId : bookingId // ignore: cast_nullable_to_non_nullable
as String,bookingNumber: null == bookingNumber ? _self.bookingNumber : bookingNumber // ignore: cast_nullable_to_non_nullable
as String,serviceName: null == serviceName ? _self.serviceName : serviceName // ignore: cast_nullable_to_non_nullable
as String,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,releasesAt: freezed == releasesAt ? _self.releasesAt : releasesAt // ignore: cast_nullable_to_non_nullable
as String?,onHold: null == onHold ? _self.onHold : onHold // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$PayoutRequestDto {

 String get id; String get status; int get amountPaise; String get requestedAt; String? get reviewedAt; String? get reviewNote;
/// Create a copy of PayoutRequestDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PayoutRequestDtoCopyWith<PayoutRequestDto> get copyWith => _$PayoutRequestDtoCopyWithImpl<PayoutRequestDto>(this as PayoutRequestDto, _$identity);

  /// Serializes this PayoutRequestDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PayoutRequestDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PayoutRequestDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.amountPaise, _this.amountPaise) || other.amountPaise == _this.amountPaise)&&(identical(other.requestedAt, _this.requestedAt) || other.requestedAt == _this.requestedAt)&&(identical(other.reviewedAt, _this.reviewedAt) || other.reviewedAt == _this.reviewedAt)&&(identical(other.reviewNote, _this.reviewNote) || other.reviewNote == _this.reviewNote));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PayoutRequestDto;
  return Object.hash(runtimeType,_this.id,_this.status,_this.amountPaise,_this.requestedAt,_this.reviewedAt,_this.reviewNote);
}

@override
String toString() {
  final _this = this as PayoutRequestDto;
  return 'PayoutRequestDto(id: ${_this.id}, status: ${_this.status}, amountPaise: ${_this.amountPaise}, requestedAt: ${_this.requestedAt}, reviewedAt: ${_this.reviewedAt}, reviewNote: ${_this.reviewNote})';
}


}

/// @nodoc
abstract mixin class $PayoutRequestDtoCopyWith<$Res>  {
  factory $PayoutRequestDtoCopyWith(PayoutRequestDto value, $Res Function(PayoutRequestDto) _then) = _$PayoutRequestDtoCopyWithImpl;
@useResult
$Res call({
 String id, String status, int amountPaise, String requestedAt, String? reviewedAt, String? reviewNote
});




}
/// @nodoc
class _$PayoutRequestDtoCopyWithImpl<$Res>
    implements $PayoutRequestDtoCopyWith<$Res> {
  _$PayoutRequestDtoCopyWithImpl(this._self, this._then);

  final PayoutRequestDto _self;
  final $Res Function(PayoutRequestDto) _then;

/// Create a copy of PayoutRequestDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? status = null,Object? amountPaise = null,Object? requestedAt = null,Object? reviewedAt = freezed,Object? reviewNote = freezed,}) {
  return _then(PayoutRequestDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,requestedAt: null == requestedAt ? _self.requestedAt : requestedAt // ignore: cast_nullable_to_non_nullable
as String,reviewedAt: freezed == reviewedAt ? _self.reviewedAt : reviewedAt // ignore: cast_nullable_to_non_nullable
as String?,reviewNote: freezed == reviewNote ? _self.reviewNote : reviewNote // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PayoutRequestDto].
extension PayoutRequestDtoPatterns on PayoutRequestDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PayoutRequestDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PayoutRequestDto() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PayoutRequestDto value)  $default,){
final _that = this;
switch (_that) {
case _PayoutRequestDto():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PayoutRequestDto value)?  $default,){
final _that = this;
switch (_that) {
case _PayoutRequestDto() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String status,  int amountPaise,  String requestedAt,  String? reviewedAt,  String? reviewNote)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PayoutRequestDto() when $default != null:
return $default(_that.id,_that.status,_that.amountPaise,_that.requestedAt,_that.reviewedAt,_that.reviewNote);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String status,  int amountPaise,  String requestedAt,  String? reviewedAt,  String? reviewNote)  $default,) {final _that = this;
switch (_that) {
case _PayoutRequestDto():
return $default(_that.id,_that.status,_that.amountPaise,_that.requestedAt,_that.reviewedAt,_that.reviewNote);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String status,  int amountPaise,  String requestedAt,  String? reviewedAt,  String? reviewNote)?  $default,) {final _that = this;
switch (_that) {
case _PayoutRequestDto() when $default != null:
return $default(_that.id,_that.status,_that.amountPaise,_that.requestedAt,_that.reviewedAt,_that.reviewNote);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PayoutRequestDto implements PayoutRequestDto {
  const _PayoutRequestDto({required this.id, required this.status, required this.amountPaise, required this.requestedAt, this.reviewedAt, this.reviewNote});
  factory _PayoutRequestDto.fromJson(Map<String, dynamic> json) => _$PayoutRequestDtoFromJson(json);

@override final  String id;
@override final  String status;
@override final  int amountPaise;
@override final  String requestedAt;
@override final  String? reviewedAt;
@override final  String? reviewNote;

/// Create a copy of PayoutRequestDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PayoutRequestDtoCopyWith<_PayoutRequestDto> get copyWith => __$PayoutRequestDtoCopyWithImpl<_PayoutRequestDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PayoutRequestDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PayoutRequestDto&&(identical(other.id, id) || other.id == id)&&(identical(other.status, status) || other.status == status)&&(identical(other.amountPaise, amountPaise) || other.amountPaise == amountPaise)&&(identical(other.requestedAt, requestedAt) || other.requestedAt == requestedAt)&&(identical(other.reviewedAt, reviewedAt) || other.reviewedAt == reviewedAt)&&(identical(other.reviewNote, reviewNote) || other.reviewNote == reviewNote));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,status,amountPaise,requestedAt,reviewedAt,reviewNote);
}

@override
String toString() {
    return 'PayoutRequestDto(id: $id, status: $status, amountPaise: $amountPaise, requestedAt: $requestedAt, reviewedAt: $reviewedAt, reviewNote: $reviewNote)';
}


}

/// @nodoc
abstract mixin class _$PayoutRequestDtoCopyWith<$Res> implements $PayoutRequestDtoCopyWith<$Res> {
  factory _$PayoutRequestDtoCopyWith(_PayoutRequestDto value, $Res Function(_PayoutRequestDto) _then) = __$PayoutRequestDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String status, int amountPaise, String requestedAt, String? reviewedAt, String? reviewNote
});




}
/// @nodoc
class __$PayoutRequestDtoCopyWithImpl<$Res>
    implements _$PayoutRequestDtoCopyWith<$Res> {
  __$PayoutRequestDtoCopyWithImpl(this._self, this._then);

  final _PayoutRequestDto _self;
  final $Res Function(_PayoutRequestDto) _then;

/// Create a copy of PayoutRequestDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? status = null,Object? amountPaise = null,Object? requestedAt = null,Object? reviewedAt = freezed,Object? reviewNote = freezed,}) {
  return _then(_PayoutRequestDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,requestedAt: null == requestedAt ? _self.requestedAt : requestedAt // ignore: cast_nullable_to_non_nullable
as String,reviewedAt: freezed == reviewedAt ? _self.reviewedAt : reviewedAt // ignore: cast_nullable_to_non_nullable
as String?,reviewNote: freezed == reviewNote ? _self.reviewNote : reviewNote // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$EarningsSummaryDto {

 int get owedPaise; int get netPayoutPaise; int get pendingPaise; int get cashDebtPaise; int get cashDebtLimitPaise; bool get acceptBlocked; int get payoutMinPaise; List<PendingReleaseDto> get pending; PayoutRequestDto? get latestPayoutRequest;
/// Create a copy of EarningsSummaryDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EarningsSummaryDtoCopyWith<EarningsSummaryDto> get copyWith => _$EarningsSummaryDtoCopyWithImpl<EarningsSummaryDto>(this as EarningsSummaryDto, _$identity);

  /// Serializes this EarningsSummaryDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as EarningsSummaryDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EarningsSummaryDto&&(identical(other.owedPaise, _this.owedPaise) || other.owedPaise == _this.owedPaise)&&(identical(other.netPayoutPaise, _this.netPayoutPaise) || other.netPayoutPaise == _this.netPayoutPaise)&&(identical(other.pendingPaise, _this.pendingPaise) || other.pendingPaise == _this.pendingPaise)&&(identical(other.cashDebtPaise, _this.cashDebtPaise) || other.cashDebtPaise == _this.cashDebtPaise)&&(identical(other.cashDebtLimitPaise, _this.cashDebtLimitPaise) || other.cashDebtLimitPaise == _this.cashDebtLimitPaise)&&(identical(other.acceptBlocked, _this.acceptBlocked) || other.acceptBlocked == _this.acceptBlocked)&&(identical(other.payoutMinPaise, _this.payoutMinPaise) || other.payoutMinPaise == _this.payoutMinPaise)&&const DeepCollectionEquality().equals(other.pending, _this.pending)&&(identical(other.latestPayoutRequest, _this.latestPayoutRequest) || other.latestPayoutRequest == _this.latestPayoutRequest));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as EarningsSummaryDto;
  return Object.hash(runtimeType,_this.owedPaise,_this.netPayoutPaise,_this.pendingPaise,_this.cashDebtPaise,_this.cashDebtLimitPaise,_this.acceptBlocked,_this.payoutMinPaise,const DeepCollectionEquality().hash(_this.pending),_this.latestPayoutRequest);
}

@override
String toString() {
  final _this = this as EarningsSummaryDto;
  return 'EarningsSummaryDto(owedPaise: ${_this.owedPaise}, netPayoutPaise: ${_this.netPayoutPaise}, pendingPaise: ${_this.pendingPaise}, cashDebtPaise: ${_this.cashDebtPaise}, cashDebtLimitPaise: ${_this.cashDebtLimitPaise}, acceptBlocked: ${_this.acceptBlocked}, payoutMinPaise: ${_this.payoutMinPaise}, pending: ${_this.pending}, latestPayoutRequest: ${_this.latestPayoutRequest})';
}


}

/// @nodoc
abstract mixin class $EarningsSummaryDtoCopyWith<$Res>  {
  factory $EarningsSummaryDtoCopyWith(EarningsSummaryDto value, $Res Function(EarningsSummaryDto) _then) = _$EarningsSummaryDtoCopyWithImpl;
@useResult
$Res call({
 int owedPaise, int netPayoutPaise, int pendingPaise, int cashDebtPaise, int cashDebtLimitPaise, bool acceptBlocked, int payoutMinPaise, List<PendingReleaseDto> pending, PayoutRequestDto? latestPayoutRequest
});


$PayoutRequestDtoCopyWith<$Res>? get latestPayoutRequest;

}
/// @nodoc
class _$EarningsSummaryDtoCopyWithImpl<$Res>
    implements $EarningsSummaryDtoCopyWith<$Res> {
  _$EarningsSummaryDtoCopyWithImpl(this._self, this._then);

  final EarningsSummaryDto _self;
  final $Res Function(EarningsSummaryDto) _then;

/// Create a copy of EarningsSummaryDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? owedPaise = null,Object? netPayoutPaise = null,Object? pendingPaise = null,Object? cashDebtPaise = null,Object? cashDebtLimitPaise = null,Object? acceptBlocked = null,Object? payoutMinPaise = null,Object? pending = null,Object? latestPayoutRequest = freezed,}) {
  return _then(EarningsSummaryDto(
owedPaise: null == owedPaise ? _self.owedPaise : owedPaise // ignore: cast_nullable_to_non_nullable
as int,netPayoutPaise: null == netPayoutPaise ? _self.netPayoutPaise : netPayoutPaise // ignore: cast_nullable_to_non_nullable
as int,pendingPaise: null == pendingPaise ? _self.pendingPaise : pendingPaise // ignore: cast_nullable_to_non_nullable
as int,cashDebtPaise: null == cashDebtPaise ? _self.cashDebtPaise : cashDebtPaise // ignore: cast_nullable_to_non_nullable
as int,cashDebtLimitPaise: null == cashDebtLimitPaise ? _self.cashDebtLimitPaise : cashDebtLimitPaise // ignore: cast_nullable_to_non_nullable
as int,acceptBlocked: null == acceptBlocked ? _self.acceptBlocked : acceptBlocked // ignore: cast_nullable_to_non_nullable
as bool,payoutMinPaise: null == payoutMinPaise ? _self.payoutMinPaise : payoutMinPaise // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as List<PendingReleaseDto>,latestPayoutRequest: freezed == latestPayoutRequest ? _self.latestPayoutRequest : latestPayoutRequest // ignore: cast_nullable_to_non_nullable
as PayoutRequestDto?,
  ));
}
/// Create a copy of EarningsSummaryDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PayoutRequestDtoCopyWith<$Res>? get latestPayoutRequest {
    if (_self.latestPayoutRequest == null) {
    return null;
  }

  return $PayoutRequestDtoCopyWith<$Res>(_self.latestPayoutRequest!, (value) {
    return _then(_self.copyWith(latestPayoutRequest: value));
  });
}
}


/// Adds pattern-matching-related methods to [EarningsSummaryDto].
extension EarningsSummaryDtoPatterns on EarningsSummaryDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EarningsSummaryDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EarningsSummaryDto() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EarningsSummaryDto value)  $default,){
final _that = this;
switch (_that) {
case _EarningsSummaryDto():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EarningsSummaryDto value)?  $default,){
final _that = this;
switch (_that) {
case _EarningsSummaryDto() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int owedPaise,  int netPayoutPaise,  int pendingPaise,  int cashDebtPaise,  int cashDebtLimitPaise,  bool acceptBlocked,  int payoutMinPaise,  List<PendingReleaseDto> pending,  PayoutRequestDto? latestPayoutRequest)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EarningsSummaryDto() when $default != null:
return $default(_that.owedPaise,_that.netPayoutPaise,_that.pendingPaise,_that.cashDebtPaise,_that.cashDebtLimitPaise,_that.acceptBlocked,_that.payoutMinPaise,_that.pending,_that.latestPayoutRequest);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int owedPaise,  int netPayoutPaise,  int pendingPaise,  int cashDebtPaise,  int cashDebtLimitPaise,  bool acceptBlocked,  int payoutMinPaise,  List<PendingReleaseDto> pending,  PayoutRequestDto? latestPayoutRequest)  $default,) {final _that = this;
switch (_that) {
case _EarningsSummaryDto():
return $default(_that.owedPaise,_that.netPayoutPaise,_that.pendingPaise,_that.cashDebtPaise,_that.cashDebtLimitPaise,_that.acceptBlocked,_that.payoutMinPaise,_that.pending,_that.latestPayoutRequest);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int owedPaise,  int netPayoutPaise,  int pendingPaise,  int cashDebtPaise,  int cashDebtLimitPaise,  bool acceptBlocked,  int payoutMinPaise,  List<PendingReleaseDto> pending,  PayoutRequestDto? latestPayoutRequest)?  $default,) {final _that = this;
switch (_that) {
case _EarningsSummaryDto() when $default != null:
return $default(_that.owedPaise,_that.netPayoutPaise,_that.pendingPaise,_that.cashDebtPaise,_that.cashDebtLimitPaise,_that.acceptBlocked,_that.payoutMinPaise,_that.pending,_that.latestPayoutRequest);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _EarningsSummaryDto implements EarningsSummaryDto {
  const _EarningsSummaryDto({required this.owedPaise, required this.netPayoutPaise, required this.pendingPaise, required this.cashDebtPaise, required this.cashDebtLimitPaise, required this.acceptBlocked, required this.payoutMinPaise,  List<PendingReleaseDto> pending = const <PendingReleaseDto>[], this.latestPayoutRequest}): _pending = pending;
  factory _EarningsSummaryDto.fromJson(Map<String, dynamic> json) => _$EarningsSummaryDtoFromJson(json);

@override final  int owedPaise;
@override final  int netPayoutPaise;
@override final  int pendingPaise;
@override final  int cashDebtPaise;
@override final  int cashDebtLimitPaise;
@override final  bool acceptBlocked;
@override final  int payoutMinPaise;
 final  List<PendingReleaseDto> _pending;
@override@JsonKey() List<PendingReleaseDto> get pending {
  if (_pending is EqualUnmodifiableListView) return _pending;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_pending);
}

@override final  PayoutRequestDto? latestPayoutRequest;

/// Create a copy of EarningsSummaryDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EarningsSummaryDtoCopyWith<_EarningsSummaryDto> get copyWith => __$EarningsSummaryDtoCopyWithImpl<_EarningsSummaryDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$EarningsSummaryDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _EarningsSummaryDto&&(identical(other.owedPaise, owedPaise) || other.owedPaise == owedPaise)&&(identical(other.netPayoutPaise, netPayoutPaise) || other.netPayoutPaise == netPayoutPaise)&&(identical(other.pendingPaise, pendingPaise) || other.pendingPaise == pendingPaise)&&(identical(other.cashDebtPaise, cashDebtPaise) || other.cashDebtPaise == cashDebtPaise)&&(identical(other.cashDebtLimitPaise, cashDebtLimitPaise) || other.cashDebtLimitPaise == cashDebtLimitPaise)&&(identical(other.acceptBlocked, acceptBlocked) || other.acceptBlocked == acceptBlocked)&&(identical(other.payoutMinPaise, payoutMinPaise) || other.payoutMinPaise == payoutMinPaise)&&const DeepCollectionEquality().equals(other.pending, _pending)&&(identical(other.latestPayoutRequest, latestPayoutRequest) || other.latestPayoutRequest == latestPayoutRequest));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,owedPaise,netPayoutPaise,pendingPaise,cashDebtPaise,cashDebtLimitPaise,acceptBlocked,payoutMinPaise,const DeepCollectionEquality().hash(_pending),latestPayoutRequest);
}

@override
String toString() {
    return 'EarningsSummaryDto(owedPaise: $owedPaise, netPayoutPaise: $netPayoutPaise, pendingPaise: $pendingPaise, cashDebtPaise: $cashDebtPaise, cashDebtLimitPaise: $cashDebtLimitPaise, acceptBlocked: $acceptBlocked, payoutMinPaise: $payoutMinPaise, pending: $pending, latestPayoutRequest: $latestPayoutRequest)';
}


}

/// @nodoc
abstract mixin class _$EarningsSummaryDtoCopyWith<$Res> implements $EarningsSummaryDtoCopyWith<$Res> {
  factory _$EarningsSummaryDtoCopyWith(_EarningsSummaryDto value, $Res Function(_EarningsSummaryDto) _then) = __$EarningsSummaryDtoCopyWithImpl;
@override @useResult
$Res call({
 int owedPaise, int netPayoutPaise, int pendingPaise, int cashDebtPaise, int cashDebtLimitPaise, bool acceptBlocked, int payoutMinPaise, List<PendingReleaseDto> pending, PayoutRequestDto? latestPayoutRequest
});


@override $PayoutRequestDtoCopyWith<$Res>? get latestPayoutRequest;

}
/// @nodoc
class __$EarningsSummaryDtoCopyWithImpl<$Res>
    implements _$EarningsSummaryDtoCopyWith<$Res> {
  __$EarningsSummaryDtoCopyWithImpl(this._self, this._then);

  final _EarningsSummaryDto _self;
  final $Res Function(_EarningsSummaryDto) _then;

/// Create a copy of EarningsSummaryDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? owedPaise = null,Object? netPayoutPaise = null,Object? pendingPaise = null,Object? cashDebtPaise = null,Object? cashDebtLimitPaise = null,Object? acceptBlocked = null,Object? payoutMinPaise = null,Object? pending = null,Object? latestPayoutRequest = freezed,}) {
  return _then(_EarningsSummaryDto(
owedPaise: null == owedPaise ? _self.owedPaise : owedPaise // ignore: cast_nullable_to_non_nullable
as int,netPayoutPaise: null == netPayoutPaise ? _self.netPayoutPaise : netPayoutPaise // ignore: cast_nullable_to_non_nullable
as int,pendingPaise: null == pendingPaise ? _self.pendingPaise : pendingPaise // ignore: cast_nullable_to_non_nullable
as int,cashDebtPaise: null == cashDebtPaise ? _self.cashDebtPaise : cashDebtPaise // ignore: cast_nullable_to_non_nullable
as int,cashDebtLimitPaise: null == cashDebtLimitPaise ? _self.cashDebtLimitPaise : cashDebtLimitPaise // ignore: cast_nullable_to_non_nullable
as int,acceptBlocked: null == acceptBlocked ? _self.acceptBlocked : acceptBlocked // ignore: cast_nullable_to_non_nullable
as bool,payoutMinPaise: null == payoutMinPaise ? _self.payoutMinPaise : payoutMinPaise // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self._pending : pending // ignore: cast_nullable_to_non_nullable
as List<PendingReleaseDto>,latestPayoutRequest: freezed == latestPayoutRequest ? _self.latestPayoutRequest : latestPayoutRequest // ignore: cast_nullable_to_non_nullable
as PayoutRequestDto?,
  ));
}

/// Create a copy of EarningsSummaryDto
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PayoutRequestDtoCopyWith<$Res>? get latestPayoutRequest {
    if (_self.latestPayoutRequest == null) {
    return null;
  }

  return $PayoutRequestDtoCopyWith<$Res>(_self.latestPayoutRequest!, (value) {
    return _then(_self.copyWith(latestPayoutRequest: value));
  });
}
}


/// @nodoc
mixin _$LedgerEntryDto {

 String get id; String get type; int get amountPaise; String? get bookingNumber; String? get serviceName; String get createdAt;
/// Create a copy of LedgerEntryDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LedgerEntryDtoCopyWith<LedgerEntryDto> get copyWith => _$LedgerEntryDtoCopyWithImpl<LedgerEntryDto>(this as LedgerEntryDto, _$identity);

  /// Serializes this LedgerEntryDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as LedgerEntryDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LedgerEntryDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.amountPaise, _this.amountPaise) || other.amountPaise == _this.amountPaise)&&(identical(other.bookingNumber, _this.bookingNumber) || other.bookingNumber == _this.bookingNumber)&&(identical(other.serviceName, _this.serviceName) || other.serviceName == _this.serviceName)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as LedgerEntryDto;
  return Object.hash(runtimeType,_this.id,_this.type,_this.amountPaise,_this.bookingNumber,_this.serviceName,_this.createdAt);
}

@override
String toString() {
  final _this = this as LedgerEntryDto;
  return 'LedgerEntryDto(id: ${_this.id}, type: ${_this.type}, amountPaise: ${_this.amountPaise}, bookingNumber: ${_this.bookingNumber}, serviceName: ${_this.serviceName}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $LedgerEntryDtoCopyWith<$Res>  {
  factory $LedgerEntryDtoCopyWith(LedgerEntryDto value, $Res Function(LedgerEntryDto) _then) = _$LedgerEntryDtoCopyWithImpl;
@useResult
$Res call({
 String id, String type, int amountPaise, String? bookingNumber, String? serviceName, String createdAt
});




}
/// @nodoc
class _$LedgerEntryDtoCopyWithImpl<$Res>
    implements $LedgerEntryDtoCopyWith<$Res> {
  _$LedgerEntryDtoCopyWithImpl(this._self, this._then);

  final LedgerEntryDto _self;
  final $Res Function(LedgerEntryDto) _then;

/// Create a copy of LedgerEntryDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? type = null,Object? amountPaise = null,Object? bookingNumber = freezed,Object? serviceName = freezed,Object? createdAt = null,}) {
  return _then(LedgerEntryDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,bookingNumber: freezed == bookingNumber ? _self.bookingNumber : bookingNumber // ignore: cast_nullable_to_non_nullable
as String?,serviceName: freezed == serviceName ? _self.serviceName : serviceName // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [LedgerEntryDto].
extension LedgerEntryDtoPatterns on LedgerEntryDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LedgerEntryDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LedgerEntryDto() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LedgerEntryDto value)  $default,){
final _that = this;
switch (_that) {
case _LedgerEntryDto():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LedgerEntryDto value)?  $default,){
final _that = this;
switch (_that) {
case _LedgerEntryDto() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String type,  int amountPaise,  String? bookingNumber,  String? serviceName,  String createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LedgerEntryDto() when $default != null:
return $default(_that.id,_that.type,_that.amountPaise,_that.bookingNumber,_that.serviceName,_that.createdAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String type,  int amountPaise,  String? bookingNumber,  String? serviceName,  String createdAt)  $default,) {final _that = this;
switch (_that) {
case _LedgerEntryDto():
return $default(_that.id,_that.type,_that.amountPaise,_that.bookingNumber,_that.serviceName,_that.createdAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String type,  int amountPaise,  String? bookingNumber,  String? serviceName,  String createdAt)?  $default,) {final _that = this;
switch (_that) {
case _LedgerEntryDto() when $default != null:
return $default(_that.id,_that.type,_that.amountPaise,_that.bookingNumber,_that.serviceName,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LedgerEntryDto implements LedgerEntryDto {
  const _LedgerEntryDto({required this.id, required this.type, required this.amountPaise, this.bookingNumber, this.serviceName, required this.createdAt});
  factory _LedgerEntryDto.fromJson(Map<String, dynamic> json) => _$LedgerEntryDtoFromJson(json);

@override final  String id;
@override final  String type;
@override final  int amountPaise;
@override final  String? bookingNumber;
@override final  String? serviceName;
@override final  String createdAt;

/// Create a copy of LedgerEntryDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LedgerEntryDtoCopyWith<_LedgerEntryDto> get copyWith => __$LedgerEntryDtoCopyWithImpl<_LedgerEntryDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LedgerEntryDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LedgerEntryDto&&(identical(other.id, id) || other.id == id)&&(identical(other.type, type) || other.type == type)&&(identical(other.amountPaise, amountPaise) || other.amountPaise == amountPaise)&&(identical(other.bookingNumber, bookingNumber) || other.bookingNumber == bookingNumber)&&(identical(other.serviceName, serviceName) || other.serviceName == serviceName)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,type,amountPaise,bookingNumber,serviceName,createdAt);
}

@override
String toString() {
    return 'LedgerEntryDto(id: $id, type: $type, amountPaise: $amountPaise, bookingNumber: $bookingNumber, serviceName: $serviceName, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$LedgerEntryDtoCopyWith<$Res> implements $LedgerEntryDtoCopyWith<$Res> {
  factory _$LedgerEntryDtoCopyWith(_LedgerEntryDto value, $Res Function(_LedgerEntryDto) _then) = __$LedgerEntryDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String type, int amountPaise, String? bookingNumber, String? serviceName, String createdAt
});




}
/// @nodoc
class __$LedgerEntryDtoCopyWithImpl<$Res>
    implements _$LedgerEntryDtoCopyWith<$Res> {
  __$LedgerEntryDtoCopyWithImpl(this._self, this._then);

  final _LedgerEntryDto _self;
  final $Res Function(_LedgerEntryDto) _then;

/// Create a copy of LedgerEntryDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? type = null,Object? amountPaise = null,Object? bookingNumber = freezed,Object? serviceName = freezed,Object? createdAt = null,}) {
  return _then(_LedgerEntryDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,bookingNumber: freezed == bookingNumber ? _self.bookingNumber : bookingNumber // ignore: cast_nullable_to_non_nullable
as String?,serviceName: freezed == serviceName ? _self.serviceName : serviceName // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$LedgerPageDto {

 List<LedgerEntryDto> get entries; String? get nextCursor;
/// Create a copy of LedgerPageDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LedgerPageDtoCopyWith<LedgerPageDto> get copyWith => _$LedgerPageDtoCopyWithImpl<LedgerPageDto>(this as LedgerPageDto, _$identity);

  /// Serializes this LedgerPageDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as LedgerPageDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LedgerPageDto&&const DeepCollectionEquality().equals(other.entries, _this.entries)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as LedgerPageDto;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.entries),_this.nextCursor);
}

@override
String toString() {
  final _this = this as LedgerPageDto;
  return 'LedgerPageDto(entries: ${_this.entries}, nextCursor: ${_this.nextCursor})';
}


}

/// @nodoc
abstract mixin class $LedgerPageDtoCopyWith<$Res>  {
  factory $LedgerPageDtoCopyWith(LedgerPageDto value, $Res Function(LedgerPageDto) _then) = _$LedgerPageDtoCopyWithImpl;
@useResult
$Res call({
 List<LedgerEntryDto> entries, String? nextCursor
});




}
/// @nodoc
class _$LedgerPageDtoCopyWithImpl<$Res>
    implements $LedgerPageDtoCopyWith<$Res> {
  _$LedgerPageDtoCopyWithImpl(this._self, this._then);

  final LedgerPageDto _self;
  final $Res Function(LedgerPageDto) _then;

/// Create a copy of LedgerPageDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entries = null,Object? nextCursor = freezed,}) {
  return _then(LedgerPageDto(
entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<LedgerEntryDto>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [LedgerPageDto].
extension LedgerPageDtoPatterns on LedgerPageDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LedgerPageDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LedgerPageDto() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LedgerPageDto value)  $default,){
final _that = this;
switch (_that) {
case _LedgerPageDto():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LedgerPageDto value)?  $default,){
final _that = this;
switch (_that) {
case _LedgerPageDto() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<LedgerEntryDto> entries,  String? nextCursor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LedgerPageDto() when $default != null:
return $default(_that.entries,_that.nextCursor);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<LedgerEntryDto> entries,  String? nextCursor)  $default,) {final _that = this;
switch (_that) {
case _LedgerPageDto():
return $default(_that.entries,_that.nextCursor);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<LedgerEntryDto> entries,  String? nextCursor)?  $default,) {final _that = this;
switch (_that) {
case _LedgerPageDto() when $default != null:
return $default(_that.entries,_that.nextCursor);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LedgerPageDto implements LedgerPageDto {
  const _LedgerPageDto({ List<LedgerEntryDto> entries = const <LedgerEntryDto>[], this.nextCursor}): _entries = entries;
  factory _LedgerPageDto.fromJson(Map<String, dynamic> json) => _$LedgerPageDtoFromJson(json);

 final  List<LedgerEntryDto> _entries;
@override@JsonKey() List<LedgerEntryDto> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}

@override final  String? nextCursor;

/// Create a copy of LedgerPageDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LedgerPageDtoCopyWith<_LedgerPageDto> get copyWith => __$LedgerPageDtoCopyWithImpl<_LedgerPageDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LedgerPageDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LedgerPageDto&&const DeepCollectionEquality().equals(other.entries, _entries)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_entries),nextCursor);
}

@override
String toString() {
    return 'LedgerPageDto(entries: $entries, nextCursor: $nextCursor)';
}


}

/// @nodoc
abstract mixin class _$LedgerPageDtoCopyWith<$Res> implements $LedgerPageDtoCopyWith<$Res> {
  factory _$LedgerPageDtoCopyWith(_LedgerPageDto value, $Res Function(_LedgerPageDto) _then) = __$LedgerPageDtoCopyWithImpl;
@override @useResult
$Res call({
 List<LedgerEntryDto> entries, String? nextCursor
});




}
/// @nodoc
class __$LedgerPageDtoCopyWithImpl<$Res>
    implements _$LedgerPageDtoCopyWith<$Res> {
  __$LedgerPageDtoCopyWithImpl(this._self, this._then);

  final _LedgerPageDto _self;
  final $Res Function(_LedgerPageDto) _then;

/// Create a copy of LedgerPageDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entries = null,Object? nextCursor = freezed,}) {
  return _then(_LedgerPageDto(
entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<LedgerEntryDto>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
