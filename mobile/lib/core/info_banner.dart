import 'package:flutter/material.dart';

/// 앱 전체에서 공통으로 쓰는 안내 배너 톤 — 파란(정보)/주황(주의, 폴백 등)
/// 두 가지 색만 쓰고 아이콘+본문 레이아웃을 통일한다. 예전엔 화면마다
/// 배경색·아이콘·폰트 크기가 조금씩 달라서 "공지"·"안내"가 서로 다른
/// 톤으로 보였다.
enum InfoBannerTone { info, notice }

class InfoBanner extends StatelessWidget {
  final String text;
  final InfoBannerTone tone;
  final EdgeInsetsGeometry margin;

  const InfoBanner({
    super.key,
    required this.text,
    this.tone = InfoBannerTone.info,
    this.margin = const EdgeInsets.fromLTRB(12, 12, 12, 0),
  });

  @override
  Widget build(BuildContext context) {
    final isNotice = tone == InfoBannerTone.notice;
    final bg = isNotice ? Colors.amber.shade50 : const Color(0xFFEAF2FB);
    final border = isNotice ? Colors.amber.shade200 : const Color(0xFFBBD6F0);
    final fg = isNotice ? Colors.amber.shade900 : const Color(0xFF2E5F8A);
    final iconColor = isNotice ? Colors.amber.shade800 : const Color(0xFF4A90D9);

    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12.5, color: fg, height: 1.4)),
        ),
      ]),
    );
  }
}
