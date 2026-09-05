// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'address_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AddressController)
final addressControllerProvider = AddressControllerProvider._();

final class AddressControllerProvider
    extends $AsyncNotifierProvider<AddressController, List<AddressDto>> {
  AddressControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'addressControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$addressControllerHash();

  @$internal
  @override
  AddressController create() => AddressController();
}

String _$addressControllerHash() => r'0f2e308b43e6a12bef93260b09595a4f61ef37a5';

abstract class _$AddressController extends $AsyncNotifier<List<AddressDto>> {
  FutureOr<List<AddressDto>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<AddressDto>>, List<AddressDto>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<AddressDto>>, List<AddressDto>>,
              AsyncValue<List<AddressDto>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
