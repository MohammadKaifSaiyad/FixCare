// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'booking_wizard_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BookingWizardState {

 String get serviceId; String? get addressId; String? get scheduledSlot;
/// Create a copy of BookingWizardState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BookingWizardStateCopyWith<BookingWizardState> get copyWith => _$BookingWizardStateCopyWithImpl<BookingWizardState>(this as BookingWizardState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BookingWizardState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BookingWizardState&&(identical(other.serviceId, _this.serviceId) || other.serviceId == _this.serviceId)&&(identical(other.addressId, _this.addressId) || other.addressId == _this.addressId)&&(identical(other.scheduledSlot, _this.scheduledSlot) || other.scheduledSlot == _this.scheduledSlot));
}


@override
int get hashCode {
  final _this = this as BookingWizardState;
  return Object.hash(runtimeType,_this.serviceId,_this.addressId,_this.scheduledSlot);
}

@override
String toString() {
  final _this = this as BookingWizardState;
  return 'BookingWizardState(serviceId: ${_this.serviceId}, addressId: ${_this.addressId}, scheduledSlot: ${_this.scheduledSlot})';
}


}

/// @nodoc
abstract mixin class $BookingWizardStateCopyWith<$Res>  {
  factory $BookingWizardStateCopyWith(BookingWizardState value, $Res Function(BookingWizardState) _then) = _$BookingWizardStateCopyWithImpl;
@useResult
$Res call({
 String serviceId, String? addressId, String? scheduledSlot
});




}
/// @nodoc
class _$BookingWizardStateCopyWithImpl<$Res>
    implements $BookingWizardStateCopyWith<$Res> {
  _$BookingWizardStateCopyWithImpl(this._self, this._then);

  final BookingWizardState _self;
  final $Res Function(BookingWizardState) _then;

/// Create a copy of BookingWizardState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? serviceId = null,Object? addressId = freezed,Object? scheduledSlot = freezed,}) {
  return _then(BookingWizardState(
serviceId: null == serviceId ? _self.serviceId : serviceId // ignore: cast_nullable_to_non_nullable
as String,addressId: freezed == addressId ? _self.addressId : addressId // ignore: cast_nullable_to_non_nullable
as String?,scheduledSlot: freezed == scheduledSlot ? _self.scheduledSlot : scheduledSlot // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BookingWizardState].
extension BookingWizardStatePatterns on BookingWizardState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BookingWizardState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BookingWizardState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BookingWizardState value)  $default,){
final _that = this;
switch (_that) {
case _BookingWizardState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BookingWizardState value)?  $default,){
final _that = this;
switch (_that) {
case _BookingWizardState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String serviceId,  String? addressId,  String? scheduledSlot)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BookingWizardState() when $default != null:
return $default(_that.serviceId,_that.addressId,_that.scheduledSlot);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String serviceId,  String? addressId,  String? scheduledSlot)  $default,) {final _that = this;
switch (_that) {
case _BookingWizardState():
return $default(_that.serviceId,_that.addressId,_that.scheduledSlot);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String serviceId,  String? addressId,  String? scheduledSlot)?  $default,) {final _that = this;
switch (_that) {
case _BookingWizardState() when $default != null:
return $default(_that.serviceId,_that.addressId,_that.scheduledSlot);case _:
  return null;

}
}

}

/// @nodoc


class _BookingWizardState implements BookingWizardState {
  const _BookingWizardState({required this.serviceId, this.addressId, this.scheduledSlot});
  

@override final  String serviceId;
@override final  String? addressId;
@override final  String? scheduledSlot;

/// Create a copy of BookingWizardState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BookingWizardStateCopyWith<_BookingWizardState> get copyWith => __$BookingWizardStateCopyWithImpl<_BookingWizardState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BookingWizardState&&(identical(other.serviceId, serviceId) || other.serviceId == serviceId)&&(identical(other.addressId, addressId) || other.addressId == addressId)&&(identical(other.scheduledSlot, scheduledSlot) || other.scheduledSlot == scheduledSlot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,serviceId,addressId,scheduledSlot);
}

@override
String toString() {
    return 'BookingWizardState(serviceId: $serviceId, addressId: $addressId, scheduledSlot: $scheduledSlot)';
}


}

/// @nodoc
abstract mixin class _$BookingWizardStateCopyWith<$Res> implements $BookingWizardStateCopyWith<$Res> {
  factory _$BookingWizardStateCopyWith(_BookingWizardState value, $Res Function(_BookingWizardState) _then) = __$BookingWizardStateCopyWithImpl;
@override @useResult
$Res call({
 String serviceId, String? addressId, String? scheduledSlot
});




}
/// @nodoc
class __$BookingWizardStateCopyWithImpl<$Res>
    implements _$BookingWizardStateCopyWith<$Res> {
  __$BookingWizardStateCopyWithImpl(this._self, this._then);

  final _BookingWizardState _self;
  final $Res Function(_BookingWizardState) _then;

/// Create a copy of BookingWizardState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? serviceId = null,Object? addressId = freezed,Object? scheduledSlot = freezed,}) {
  return _then(_BookingWizardState(
serviceId: null == serviceId ? _self.serviceId : serviceId // ignore: cast_nullable_to_non_nullable
as String,addressId: freezed == addressId ? _self.addressId : addressId // ignore: cast_nullable_to_non_nullable
as String?,scheduledSlot: freezed == scheduledSlot ? _self.scheduledSlot : scheduledSlot // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
