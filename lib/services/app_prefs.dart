import 'package:shared_preferences/shared_preferences.dart';

/// 입금 계좌처럼 간단한 설정값 저장
class AppPrefs {
  static const _accountKey = 'account_info';

  static Future<String> loadAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accountKey) ?? '';
  }

  static Future<void> saveAccount(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountKey, value);
  }
}
