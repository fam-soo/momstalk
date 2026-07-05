import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'has_logged_in_before';

/// 이 기기에서 카카오 로그인을 완료한 적이 있는지만 기록한다.
/// (약관 동의 UI를 다시 보여줄지 판단하는 용도 — 특정 계정을 기억하거나
/// 닉네임으로 빠른 로그인을 제공하지 않는다. 재로그인 시에는 항상 카카오
/// 자체 계정 선택 화면에서 사용자가 직접 계정을 고른다.)
class SavedAccountsStorage {
  static Future<bool> hasLoggedInBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kKey) ?? false;
  }

  static Future<void> markLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKey, true);
  }
}
