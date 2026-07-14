/// 학교명을 화면에 표시할 때 쓰는 약칭 변환.
/// 예: "서울계남초등학교" → "계남초", "신서중학교" → "신서중"
/// (백엔드 auth_service.py의 _make_school_short_name과 동일한 규칙)
String shortSchoolName(String? full) {
  if (full == null || full.isEmpty) return full ?? '';
  const suffixes = ['초등학교', '중학교', '고등학교', '초', '중', '고'];
  for (final suffix in suffixes) {
    final idx = full.indexOf(suffix);
    if (idx > 0) {
      final label = (suffix == '초등학교' || suffix == '중학교' || suffix == '고등학교')
          ? suffix.substring(0, 1)
          : suffix;
      var raw = full.substring(0, idx).trim();
      raw = raw.replaceAll(RegExp(r'[\s()（）]'), '');
      final short = raw.length > 4 ? raw.substring(raw.length - 4) : raw;
      return '$short$label';
    }
  }
  return full.length > 5 ? full.substring(0, 5) : full;
}
