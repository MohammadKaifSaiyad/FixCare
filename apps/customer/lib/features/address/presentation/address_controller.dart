import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../data/address_repository.dart';

part 'address_controller.g.dart';

@riverpod
class AddressController extends _$AddressController {
  @override
  Future<List<AddressDto>> build() async {
    final r = await ref.read(addressRepositoryProvider).list();
    return switch (r) {
      Ok(value: final list) => list,
      Failure(message: final m) => throw Exception(m),
    };
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final r = await ref.read(addressRepositoryProvider).list();
      return switch (r) {
        Ok(value: final list) => list,
        Failure(message: final m) => throw Exception(m),
      };
    });
  }

  Future<Result<void>> setDefault(String id) async {
    final r = await ref.read(addressRepositoryProvider).update(id, {'isDefault': true});
    if (r is Ok) { await refresh(); return const Ok(null); }
    final f = r as Failure;
    return Failure(f.kind, f.message);
  }

  Future<Result<void>> remove(String id) async {
    final r = await ref.read(addressRepositoryProvider).delete(id);
    if (r is Ok) { await refresh(); return const Ok(null); }
    final f = r as Failure;
    return Failure(f.kind, f.message);
  }
}
