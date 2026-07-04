import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'saved_accounts';
const _kMax = 5;

class SavedAccount {
  final String nickname;
  final String schoolName;
  final String memberGrade;
  /// 연결된 카카오 user ID (로그인 후 자동 연결, 快速 로그인 계정 매칭용)
  final String? kakaoUserId;

  const SavedAccount({
    required this.nickname,
    required this.schoolName,
    required this.memberGrade,
    this.kakaoUserId,
  });

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'schoolName': schoolName,
    'memberGrade': memberGrade,
    if (kakaoUserId != null) 'kakaoUserId': kakaoUserId,
  };

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
    nickname: j['nickname'] as String? ?? '',
    schoolName: j['schoolName'] as String? ?? '',
    memberGrade: j['memberGrade'] as String? ?? 'lurker',
    kakaoUserId: j['kakaoUserId'] as String?,
  );

  SavedAccount copyWith({String? nickname, String? schoolName, String? memberGrade, String? kakaoUserId}) =>
      SavedAccount(
        nickname: nickname ?? this.nickname,
        schoolName: schoolName ?? this.schoolName,
        memberGrade: memberGrade ?? this.memberGrade,
        kakaoUserId: kakaoUserId ?? this.kakaoUserId,
      );

  String get displaySchool =>
      schoolName.isEmpty ? '학교 미인증' : schoolName;
}

class SavedAccountsStorage {
  static Future<List<SavedAccount>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? [];
    return raw
        .map((s) => SavedAccount.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  /// 로그인 성공 시 호출 — 동일 닉네임이 있으면 맨 앞으로 이동, 없으면 추가.
  static Future<void> upsert(SavedAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    var list = await load();
    list.removeWhere((a) => a.nickname == account.nickname);
    list.insert(0, account);
    if (list.length > _kMax) list = list.sublist(0, _kMax);
    await prefs.setStringList(_kKey, list.map((a) => jsonEncode(a.toJson())).toList());
  }

  static Future<void> remove(String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    list.removeWhere((a) => a.nickname == nickname);
    await prefs.setStringList(_kKey, list.map((a) => jsonEncode(a.toJson())).toList());
  }

  /// 같은 kakaoUserId를 가진 저장 계정의 닉네임을 최신값으로 갱신
  static Future<void> updateByKakaoId(String kakaoUserId, String newNickname) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final updated = list.map((a) {
      if (a.kakaoUserId == kakaoUserId && a.nickname != newNickname) {
        return a.copyWith(nickname: newNickname);
      }
      return a;
    }).toList();
    await prefs.setStringList(_kKey, updated.map((a) => jsonEncode(a.toJson())).toList());
  }
}
