import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('이용약관')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: _TermsContent(),
      ),
    );
  }
}

class _TermsContent extends StatelessWidget {
  const _TermsContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headStyle = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);
    const bodyStyle = TextStyle(height: 1.7, fontSize: 14);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MomsTalk 서비스 이용약관', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('시행일: 2026년 7월 1일', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
        const SizedBox(height: 24),

        Text('제1조 (목적)', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '본 약관은 MomsTalk(맘스톡크, 이하 "서비스")가 제공하는 학부모 교육 정보 커뮤니티 플랫폼 서비스의 이용에 관한 조건 및 절차, 회사와 이용자의 권리·의무 및 책임 사항을 규정하는 것을 목적으로 합니다.',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),

        Text('제2조 (정의)', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '"서비스"란 MomsTalk이 제공하는 학부모 전용 커뮤니티, 학원 후기, 실시간 대화 등 모든 기능을 의미합니다.\n'
          '"회원"이란 본 약관에 동의하고 서비스를 이용하는 자를 의미합니다.\n'
          '"익명 식별자(anon_id)"란 전화번호를 복호화 불가능한 방식으로 변환한 고유 값으로, 신원 역추적이 수학적으로 불가능합니다.',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),

        Text('제3조 (서비스 이용)', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '① 서비스는 NEIS(교육부 나이스 API) 기반의 학교 인증을 통해 가입할 수 있습니다.\n'
          '② 회원은 1인 1계정만 생성할 수 있으며, 동일한 전화번호로 중복 가입이 불가합니다.\n'
          '③ 회원은 서비스 이용 시 타인의 권리를 침해하거나 법령을 위반하는 행위를 하여서는 안 됩니다.\n'
          '④ 학원 후기는 작성자 개인의 경험을 바탕으로 한 의견이며, 서비스는 후기 내용의 정확성을 보증하지 않습니다.',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),

        Text('제4조 (금지 행위)', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '회원은 다음 각 호의 행위를 하여서는 안 됩니다:\n'
          '• 타인을 비방하거나 명예를 훼손하는 행위\n'
          '• 허위 정보 유포 또는 광고성 게시물 작성\n'
          '• 개인정보 수집 또는 유포\n'
          '• 불법 정보 유통 (마약, 도박 등)\n'
          '• 서비스 운영을 방해하는 행위\n'
          '• 특정 학원에 대한 근거 없는 허위 비방',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),

        Text('제5조 (제재 조치)', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '서비스는 이용약관 위반 시 다음 조치를 취할 수 있습니다:\n'
          '• 게시물 블라인드 또는 삭제\n'
          '• 경고 부여 (누적 경고에 따라 이용 제한)\n'
          '• 7일 또는 30일 이용 정지\n'
          '• 영구 이용 정지',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),

        Text('제6조 (면책 조항)', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '① 서비스는 회원이 게시한 콘텐츠에 대한 법적 책임을 지지 않습니다.\n'
          '② 학원 후기는 작성자 개인의 주관적 경험입니다. 서비스는 후기의 정확성에 대한 책임을 지지 않으며, 학원은 이의 신청 절차를 통해 검토를 요청할 수 있습니다.\n'
          '③ 서비스는 천재지변, 시스템 장애 등 불가항력적 사유로 인한 서비스 중단에 대해 책임을 지지 않습니다.',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),

        Text('제7조 (준거법 및 관할)', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '본 약관은 대한민국 법령에 따라 해석되며, 서비스 이용과 관련한 분쟁은 대한민국 법원을 관할 법원으로 합니다.',
          style: bodyStyle,
        ),
        const SizedBox(height: 32),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '문의: support@momstalk.kr\n운영사: MomsTalk',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
