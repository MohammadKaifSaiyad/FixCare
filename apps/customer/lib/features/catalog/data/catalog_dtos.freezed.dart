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
mixin _$CategoryDto {

 String get id; String get name; String get status;
/// Create a copy of CategoryDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CategoryDtoCopyWith<CategoryDto> get copyWith => _$CategoryDtoCopyWithImpl<CategoryDto>(this as CategoryDto, _$identity);

  /// Serializes this CategoryDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as CategoryDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CategoryDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.status, _this.status) || other.status == _this.status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as CategoryDto;
  return Object.hash(runtimeType,_this.id,_this.name,_this.status);
}

@override
String toString() {
  final _this = this as CategoryDto;
  return 'CategoryDto(id: ${_this.id}, name: ${_this.name}, status: ${_this.status})';
}


}

/// @nodoc
abstract mixin class $CategoryDtoCopyWith<$Res>  {
  factory $CategoryDtoCopyWith(CategoryDto value, $Res Function(CategoryDto) _then) = _$CategoryDtoCopyWithImpl;
@useResult
$Res call({
 String id, String name, String status
});




}
/// @nodoc
class _$CategoryDtoCopyWithImpl<$Res>
    implements $CategoryDtoCopyWith<$Res> {
  _$CategoryDtoCopyWithImpl(this._self, this._then);

  final CategoryDto _self;
  final $Res Function(CategoryDto) _then;

/// Create a copy of CategoryDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? status = null,}) {
  return _then(CategoryDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CategoryDto].
extension CategoryDtoPatterns on CategoryDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CategoryDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CategoryDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CategoryDto value)  $default,){
final _that = this;
switch (_that) {
case _CategoryDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CategoryDto value)?  $default,){
final _that = this;
switch (_that) {
case _CategoryDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CategoryDto() when $default != null:
return $default(_that.id,_that.name,_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String status)  $default,) {final _that = this;
switch (_that) {
case _CategoryDto():
return $default(_that.id,_that.name,_that.status);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String status)?  $default,) {final _that = this;
switch (_that) {
case _CategoryDto() when $default != null:
return $default(_that.id,_that.name,_that.status);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CategoryDto implements CategoryDto {
  const _CategoryDto({required this.id, required this.name, required this.status});
  factory _CategoryDto.fromJson(Map<String, dynamic> json) => _$CategoryDtoFromJson(json);

@override final  String id;
@override final  String name;
@override final  String status;

/// Create a copy of CategoryDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CategoryDtoCopyWith<_CategoryDto> get copyWith => __$CategoryDtoCopyWithImpl<_CategoryDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CategoryDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CategoryDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,status);
}

@override
String toString() {
    return 'CategoryDto(id: $id, name: $name, status: $status)';
}


}

/// @nodoc
abstract mixin class _$CategoryDtoCopyWith<$Res> implements $CategoryDtoCopyWith<$Res> {
  factory _$CategoryDtoCopyWith(_CategoryDto value, $Res Function(_CategoryDto) _then) = __$CategoryDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String status
});




}
/// @nodoc
class __$CategoryDtoCopyWithImpl<$Res>
    implements _$CategoryDtoCopyWith<$Res> {
  __$CategoryDtoCopyWithImpl(this._self, this._then);

  final _CategoryDto _self;
  final $Res Function(_CategoryDto) _then;

/// Create a copy of CategoryDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? status = null,}) {
  return _then(_CategoryDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ServiceDto {

 String get id; String get name; String get tier; String get categoryId; int? get laborPaise; int get visitFeePaise;
/// Create a copy of ServiceDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ServiceDtoCopyWith<ServiceDto> get copyWith => _$ServiceDtoCopyWithImpl<ServiceDto>(this as ServiceDto, _$identity);

  /// Serializes this ServiceDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ServiceDto;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ServiceDto&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.tier, _this.tier) || other.tier == _this.tier)&&(identical(other.categoryId, _this.categoryId) || other.categoryId == _this.categoryId)&&(identical(other.laborPaise, _this.laborPaise) || other.laborPaise == _this.laborPaise)&&(identical(other.visitFeePaise, _this.visitFeePaise) || other.visitFeePaise == _this.visitFeePaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ServiceDto;
  return Object.hash(runtimeType,_this.id,_this.name,_this.tier,_this.categoryId,_this.laborPaise,_this.visitFeePaise);
}

@override
String toString() {
  final _this = this as ServiceDto;
  return 'ServiceDto(id: ${_this.id}, name: ${_this.name}, tier: ${_this.tier}, categoryId: ${_this.categoryId}, laborPaise: ${_this.laborPaise}, visitFeePaise: ${_this.visitFeePaise})';
}


}

/// @nodoc
abstract mixin class $ServiceDtoCopyWith<$Res>  {
  factory $ServiceDtoCopyWith(ServiceDto value, $Res Function(ServiceDto) _then) = _$ServiceDtoCopyWithImpl;
@useResult
$Res call({
 String id, String name, String tier, String categoryId, int? laborPaise, int visitFeePaise
});




}
/// @nodoc
class _$ServiceDtoCopyWithImpl<$Res>
    implements $ServiceDtoCopyWith<$Res> {
  _$ServiceDtoCopyWithImpl(this._self, this._then);

  final ServiceDto _self;
  final $Res Function(ServiceDto) _then;

/// Create a copy of ServiceDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? tier = null,Object? categoryId = null,Object? laborPaise = freezed,Object? visitFeePaise = null,}) {
  return _then(ServiceDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,tier: null == tier ? _self.tier : tier // ignore: cast_nullable_to_non_nullable
as String,categoryId: null == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String,laborPaise: freezed == laborPaise ? _self.laborPaise : laborPaise // ignore: cast_nullable_to_non_nullable
as int?,visitFeePaise: null == visitFeePaise ? _self.visitFeePaise : visitFeePaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ServiceDto].
extension ServiceDtoPatterns on ServiceDto {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ServiceDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ServiceDto() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ServiceDto value)  $default,){
final _that = this;
switch (_that) {
case _ServiceDto():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ServiceDto value)?  $default,){
final _that = this;
switch (_that) {
case _ServiceDto() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String tier,  String categoryId,  int? laborPaise,  int visitFeePaise)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ServiceDto() when $default != null:
return $default(_that.id,_that.name,_that.tier,_that.categoryId,_that.laborPaise,_that.visitFeePaise);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String tier,  String categoryId,  int? laborPaise,  int visitFeePaise)  $default,) {final _that = this;
switch (_that) {
case _ServiceDto():
return $default(_that.id,_that.name,_that.tier,_that.categoryId,_that.laborPaise,_that.visitFeePaise);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String tier,  String categoryId,  int? laborPaise,  int visitFeePaise)?  $default,) {final _that = this;
switch (_that) {
case _ServiceDto() when $default != null:
return $default(_that.id,_that.name,_that.tier,_that.categoryId,_that.laborPaise,_that.visitFeePaise);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ServiceDto implements ServiceDto {
  const _ServiceDto({required this.id, required this.name, required this.tier, required this.categoryId, this.laborPaise, required this.visitFeePaise});
  factory _ServiceDto.fromJson(Map<String, dynamic> json) => _$ServiceDtoFromJson(json);

@override final  String id;
@override final  String name;
@override final  String tier;
@override final  String categoryId;
@override final  int? laborPaise;
@override final  int visitFeePaise;

/// Create a copy of ServiceDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ServiceDtoCopyWith<_ServiceDto> get copyWith => __$ServiceDtoCopyWithImpl<_ServiceDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ServiceDtoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ServiceDto&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.tier, tier) || other.tier == tier)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.laborPaise, laborPaise) || other.laborPaise == laborPaise)&&(identical(other.visitFeePaise, visitFeePaise) || other.visitFeePaise == visitFeePaise));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,tier,categoryId,laborPaise,visitFeePaise);
}

@override
String toString() {
    return 'ServiceDto(id: $id, name: $name, tier: $tier, categoryId: $categoryId, laborPaise: $laborPaise, visitFeePaise: $visitFeePaise)';
}


}

/// @nodoc
abstract mixin class _$ServiceDtoCopyWith<$Res> implements $ServiceDtoCopyWith<$Res> {
  factory _$ServiceDtoCopyWith(_ServiceDto value, $Res Function(_ServiceDto) _then) = __$ServiceDtoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String tier, String categoryId, int? laborPaise, int visitFeePaise
});




}
/// @nodoc
class __$ServiceDtoCopyWithImpl<$Res>
    implements _$ServiceDtoCopyWith<$Res> {
  __$ServiceDtoCopyWithImpl(this._self, this._then);

  final _ServiceDto _self;
  final $Res Function(_ServiceDto) _then;

/// Create a copy of ServiceDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? tier = null,Object? categoryId = null,Object? laborPaise = freezed,Object? visitFeePaise = null,}) {
  return _then(_ServiceDto(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,tier: null == tier ? _self.tier : tier // ignore: cast_nullable_to_non_nullable
as String,categoryId: null == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String,laborPaise: freezed == laborPaise ? _self.laborPaise : laborPaise // ignore: cast_nullable_to_non_nullable
as int?,visitFeePaise: null == visitFeePaise ? _self.visitFeePaise : visitFeePaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
