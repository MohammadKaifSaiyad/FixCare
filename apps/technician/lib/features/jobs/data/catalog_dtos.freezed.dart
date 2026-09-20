// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog_dtos.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DiagnosedIssueDto {

 String get id; String get name; String get categoryId; String get status;
/// Create a copy of DiagnosedIssueDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosedIssueDtoCopyWith<DiagnosedIssueDto> get copyWith => _$DiagnosedIssueDtoCopyWithImpl<DiagnosedIssueDto>(this as DiagnosedIssueDto, _$identity);

  /// Serializes this DiagnosedIssueDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DiagnosedIssueDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosedIssueDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.categoryId, _this.categoryId) || other.categoryId == _this.categoryId)&&(identical(other.status, _this.status) || other.status == _this.status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DiagnosedIssueDto;
  return Object.hash(runtimeType,_this.id,_this.name,_this.categoryId,_this.status);
}

@override
String toString() {
  final _this = this as DiagnosedIssueDto;
  return 'DiagnosedIssueDto(id: ${_this.id}, name: ${_this.name}, categoryId: ${_this.categoryId}, status: ${_this.status})';
}


}

/// @nodoc
abstract mixin class $DiagnosedIssueDtoCopyWith<$Res>  {
  factory $DiagnosedIssueDtoCopyWith(DiagnosedIssueDto value, $Res Function(DiagnosedIssueDto) _then) = _$DiagnosedIssueDtoCopyWithImpl;
@useResult
$Res call({
 String id, String name, String categoryId, String status
});




}
/// @nodoc
class _$DiagnosedIssueDtoCopyWithImpl<$Res>
    implements $DiagnosedIssueDtoCopyWith<$Res> {
  _$DiagnosedIssueDtoCopyWithImpl(this._self, this._then);

  final DiagnosedIssueDto _self;
  final $Res Function(DiagnosedIssueDto) _then;

/// Create a copy of DiagnosedIssueDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? categoryId = null,Object? status = null,}) {
  return _then(DiagnosedIssueDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,categoryId: null == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DiagnosedIssueDto].
extension DiagnosedIssueDtoPatterns on DiagnosedIssueDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DiagnosedIssueDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DiagnosedIssueDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DiagnosedIssueDto value)  $default,){
final _that = this;
switch (_that) {
case _DiagnosedIssueDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DiagnosedIssueDto value)?  $default,){
final _that = this;
switch (_that) {
case _DiagnosedIssueDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String categoryId,  String status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DiagnosedIssueDto() when $default != null:
return $default(_that.id,_that.name,_that.categoryId,_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String categoryId,  String status)  $default,) {final _that = this;
switch (_that) {
case _DiagnosedIssueDto():
return $default(_that.id,_that.name,_that.categoryId,_that.status);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String categoryId,  String status)?  $default,) {final _that = this;
switch (_that) {
case _DiagnosedIssueDto() when $default != null:
return $default(_that.id,_that.name,_that.categoryId,_that.status);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DiagnosedIssueDto implements DiagnosedIssueDto {
  const _DiagnosedIssueDto({required this.id, required this.name, required this.categoryId, required this.status});
  factory _DiagnosedIssueDto.fromJson(Map<String, dynamic> json) => _$DiagnosedIssueDtoFromJson(json);

@override final  String id;
@override final  String name;
@override final  String categoryId;
@override final  String status;

/// Create a copy of DiagnosedIssueDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DiagnosedIssueDtoCopyWith<_DiagnosedIssueDto> get copyWith => __$DiagnosedIssueDtoCopyWithImpl<_DiagnosedIssueDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DiagnosedIssueDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DiagnosedIssueDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,categoryId,status);
}

@override
String toString() {
    return 'DiagnosedIssueDto(id: $id, name: $name, categoryId: $categoryId, status: $status)';
}


}

/// @nodoc
abstract mixin class _$DiagnosedIssueDtoCopyWith<$Res> implements $DiagnosedIssueDtoCopyWith<$Res> {
  factory _$DiagnosedIssueDtoCopyWith(_DiagnosedIssueDto value, $Res Function(_DiagnosedIssueDto) _then) = __$DiagnosedIssueDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String categoryId, String status
});




}
/// @nodoc
class __$DiagnosedIssueDtoCopyWithImpl<$Res>
    implements _$DiagnosedIssueDtoCopyWith<$Res> {
  __$DiagnosedIssueDtoCopyWithImpl(this._self, this._then);

  final _DiagnosedIssueDto _self;
  final $Res Function(_DiagnosedIssueDto) _then;

/// Create a copy of DiagnosedIssueDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? categoryId = null,Object? status = null,}) {
  return _then(_DiagnosedIssueDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,categoryId: null == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$PartCatalogDto {

 String get id; String get sku; String get name; String? get categoryId; int get ceilingPricePaise; String get status;
/// Create a copy of PartCatalogDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PartCatalogDtoCopyWith<PartCatalogDto> get copyWith => _$PartCatalogDtoCopyWithImpl<PartCatalogDto>(this as PartCatalogDto, _$identity);

  /// Serializes this PartCatalogDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PartCatalogDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PartCatalogDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sku, _this.sku) || other.sku == _this.sku)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.categoryId, _this.categoryId) || other.categoryId == _this.categoryId)&&(identical(other.ceilingPricePaise, _this.ceilingPricePaise) || other.ceilingPricePaise == _this.ceilingPricePaise)&&(identical(other.status, _this.status) || other.status == _this.status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PartCatalogDto;
  return Object.hash(runtimeType,_this.id,_this.sku,_this.name,_this.categoryId,_this.ceilingPricePaise,_this.status);
}

@override
String toString() {
  final _this = this as PartCatalogDto;
  return 'PartCatalogDto(id: ${_this.id}, sku: ${_this.sku}, name: ${_this.name}, categoryId: ${_this.categoryId}, ceilingPricePaise: ${_this.ceilingPricePaise}, status: ${_this.status})';
}


}

/// @nodoc
abstract mixin class $PartCatalogDtoCopyWith<$Res>  {
  factory $PartCatalogDtoCopyWith(PartCatalogDto value, $Res Function(PartCatalogDto) _then) = _$PartCatalogDtoCopyWithImpl;
@useResult
$Res call({
 String id, String sku, String name, String? categoryId, int ceilingPricePaise, String status
});




}
/// @nodoc
class _$PartCatalogDtoCopyWithImpl<$Res>
    implements $PartCatalogDtoCopyWith<$Res> {
  _$PartCatalogDtoCopyWithImpl(this._self, this._then);

  final PartCatalogDto _self;
  final $Res Function(PartCatalogDto) _then;

/// Create a copy of PartCatalogDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sku = null,Object? name = null,Object? categoryId = freezed,Object? ceilingPricePaise = null,Object? status = null,}) {
  return _then(PartCatalogDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sku: null == sku ? _self.sku : sku // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,ceilingPricePaise: null == ceilingPricePaise ? _self.ceilingPricePaise : ceilingPricePaise // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PartCatalogDto].
extension PartCatalogDtoPatterns on PartCatalogDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PartCatalogDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PartCatalogDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PartCatalogDto value)  $default,){
final _that = this;
switch (_that) {
case _PartCatalogDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PartCatalogDto value)?  $default,){
final _that = this;
switch (_that) {
case _PartCatalogDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String sku,  String name,  String? categoryId,  int ceilingPricePaise,  String status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PartCatalogDto() when $default != null:
return $default(_that.id,_that.sku,_that.name,_that.categoryId,_that.ceilingPricePaise,_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String sku,  String name,  String? categoryId,  int ceilingPricePaise,  String status)  $default,) {final _that = this;
switch (_that) {
case _PartCatalogDto():
return $default(_that.id,_that.sku,_that.name,_that.categoryId,_that.ceilingPricePaise,_that.status);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String sku,  String name,  String? categoryId,  int ceilingPricePaise,  String status)?  $default,) {final _that = this;
switch (_that) {
case _PartCatalogDto() when $default != null:
return $default(_that.id,_that.sku,_that.name,_that.categoryId,_that.ceilingPricePaise,_that.status);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PartCatalogDto implements PartCatalogDto {
  const _PartCatalogDto({required this.id, required this.sku, required this.name, this.categoryId, required this.ceilingPricePaise, required this.status});
  factory _PartCatalogDto.fromJson(Map<String, dynamic> json) => _$PartCatalogDtoFromJson(json);

@override final  String id;
@override final  String sku;
@override final  String name;
@override final  String? categoryId;
@override final  int ceilingPricePaise;
@override final  String status;

/// Create a copy of PartCatalogDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PartCatalogDtoCopyWith<_PartCatalogDto> get copyWith => __$PartCatalogDtoCopyWithImpl<_PartCatalogDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PartCatalogDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PartCatalogDto&&(identical(other.id, id) || other.id == id)&&(identical(other.sku, sku) || other.sku == sku)&&(identical(other.name, name) || other.name == name)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.ceilingPricePaise, ceilingPricePaise) || other.ceilingPricePaise == ceilingPricePaise)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,sku,name,categoryId,ceilingPricePaise,status);
}

@override
String toString() {
    return 'PartCatalogDto(id: $id, sku: $sku, name: $name, categoryId: $categoryId, ceilingPricePaise: $ceilingPricePaise, status: $status)';
}


}

/// @nodoc
abstract mixin class _$PartCatalogDtoCopyWith<$Res> implements $PartCatalogDtoCopyWith<$Res> {
  factory _$PartCatalogDtoCopyWith(_PartCatalogDto value, $Res Function(_PartCatalogDto) _then) = __$PartCatalogDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String sku, String name, String? categoryId, int ceilingPricePaise, String status
});




}
/// @nodoc
class __$PartCatalogDtoCopyWithImpl<$Res>
    implements _$PartCatalogDtoCopyWith<$Res> {
  __$PartCatalogDtoCopyWithImpl(this._self, this._then);

  final _PartCatalogDto _self;
  final $Res Function(_PartCatalogDto) _then;

/// Create a copy of PartCatalogDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sku = null,Object? name = null,Object? categoryId = freezed,Object? ceilingPricePaise = null,Object? status = null,}) {
  return _then(_PartCatalogDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sku: null == sku ? _self.sku : sku // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,ceilingPricePaise: null == ceilingPricePaise ? _self.ceilingPricePaise : ceilingPricePaise // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
