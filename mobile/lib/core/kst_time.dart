/// 백엔드는 항상 UTC 기준 naive datetime을 타임존 표시(Z, +00:00) 없이
/// ISO8601 문자열로 반환한다 (`datetime.utcnow()` 사용). Dart의
/// `DateTime.parse`/`tryParse`는 타임존 표시가 없는 문자열을 "로컬 시간"으로
/// 해석하므로, 그대로 파싱하면 실제 UTC 값을 로컬 시각인 것처럼 오인해
/// 한국(KST, UTC+9) 기준으로 정확히 9시간이 어긋난 값이 표시된다.
///
/// 이 파일의 함수들은 문자열을 명시적으로 UTC로 해석한 뒤 한국 표준시로
/// 변환한다. 기기의 로컬 타임존(`toLocal()`)에 의존하지 않고 항상 KST로
/// 고정 표시하므로, 관리자가 해외에서 접속해도 동일하게 한국 시간 기준으로
/// 보인다.
const kstOffset = Duration(hours: 9);

/// 서버가 내려준 ISO 문자열(UTC, 타임존 표시 없음)을 KST `DateTime`으로 변환.
DateTime? parseServerTimeToKst(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final hasOffset = iso.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(iso);
  final utcIso = hasOffset ? iso : '${iso}Z';
  final parsed = DateTime.tryParse(utcIso);
  if (parsed == null) return null;
  return parsed.toUtc().add(kstOffset);
}

/// "3분 전" / "2시간 전" / "5일 전" 형태의 상대 시간 표시 (KST 기준으로 계산).
String kstTimeAgo(String? iso) {
  final kst = parseServerTimeToKst(iso);
  if (kst == null) return '';
  final nowKst = DateTime.now().toUtc().add(kstOffset);
  final diff = nowKst.difference(kst);
  if (diff.inMinutes < 1) return '방금';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  return '${diff.inDays}일 전';
}

/// 절대 시각 표시 (KST). 같은 해면 "MM.dd HH:mm", 아니면 "yyyy.MM.dd" 형태.
String kstDateTimeLabel(String? iso, {bool withTime = true}) {
  final kst = parseServerTimeToKst(iso);
  if (kst == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  final datePart = '${two(kst.month)}.${two(kst.day)}';
  if (!withTime) return '${kst.year}.$datePart';
  return '$datePart ${two(kst.hour)}:${two(kst.minute)}';
}
