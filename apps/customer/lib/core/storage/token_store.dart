import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _kAccess = 'fixcare.access';
  static const _kRefresh = 'fixcare.refresh';
  static const _kPhone = 'fixcare.phone';

  Future<void> save({required String access, required String refresh}) async {
    await _s.write(key: _kAccess, value: access);
    await _s.write(key: _kRefresh, value: refresh);
  }
  Future<String?> readAccess() => _s.read(key: _kAccess);
  Future<String?> readRefresh() => _s.read(key: _kRefresh);
  Future<void> savePhone(String phone) => _s.write(key: _kPhone, value: phone);
  Future<String?> readPhone() => _s.read(key: _kPhone);
  Future<void> clear() async {
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
    await _s.delete(key: _kPhone);
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());
