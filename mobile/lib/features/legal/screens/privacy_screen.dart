import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('개인정보처리방침')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: _PrivacyContent(),
      ),
    );
  }
}

class _PrivacyContent extends StatelessWidget {
  const _PrivacyContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headStyle = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold);
    const bodyStyle = TextStyle(height: 1.7, fontSize: 14);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('개인정보처리방침', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('시행일: 2026년 7월 1일', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.security, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'MomsTalk은 전화번호를 복호화 불가능한 방식으로 변환하여 저장하며, 신원 역추적이 수학적으로 불가능한 구조로 설계되어 있습니다.',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Text('1. 수집하는 개인정보', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '서비스 이용 과정에서 다음의 정보를 수집합니다:\n\n'
          '【인증 DB — 신원 정보】\n'
          '• 전화번호: SMS 인증 목적으로만 사용, 인증 완료 후 익명 식별자(anon_id)로 변환\n'
          '• SMS 인증 코드: 5분간 임시 보관 후 자동 삭제\n'
          '• anon_id: HMAC-SHA256 해시값 (원본 전화번호 역추적 불가)\n\n'
          '【서비스 DB — 활동 정보】\n'
          '• anon_id (익명 식별자만 저장, 전화번호 없음)\n'
          '• 학교명, 학년, 지역 (공개 교육 정보)\n'
          '• 작성 게시글, 댓글, 학원 후기\n'
          '• 앱 사용 기록 (좋아요, 스크랩, 차단)',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),

        Text('2. 이중 DB 분리 구조', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          'MomsTalk은 신원 정보(인증 DB)와 활동 정보(서비스 DB)를 물리적으로 완전히 분리하여 운영합니다.\n\n'
          '• 인증 DB: 전화번호 ↔ anon_id 매핑만 보관 (서비스 운영팀 접근 불가)\n'
          '• 서비스 DB: anon_id만 저장. 전화번호 없음. 신원 역추적 수학적 불가능\n\n'
          '이 구조로 인해 법원의 영장이 있더라도 서비스 DB만으로는 특정 게시물의 실제 작성자를 알 수 없습니다.',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),

        Text('3. 개인정보 보유 및 이용 기간', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '• SMS 인증 코드: 5분 (만료 즉시 삭제)\n'
          '• 전화번호 (인증 DB): 회원 탈퇴 시 즉시 삭제\n'
          '• 서비스 활동 정보: 회원 탈퇴 요청 후 30일 이내 삭제\n'
          '• 법령에 따라 보관이 필요한 정보: 관련 법령에서 정한 기간',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),

        Text('4. 개인정보 제3자 제공', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '서비스는 원칙적으로 개인정보를 제3자에게 제공하지 않습니다.\n'
          '단, 다음의 경우 예외적으로 제공될 수 있습니다:\n'
          '• 이용자가 사전에 동의한 경우\n'
          '• 법령의 규정 또는 수사기관의 적법한 요청이 있는 경우',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),

        Text('5. 이용자의 권리', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '이용자는 언제든지 다음의 권리를 행사할 수 있습니다:\n'
          '• 개인정보 열람 요청\n'
          '• 개인정보 정정·삭제 요청\n'
          '• 회원 탈퇴 (앱 내 프로필 → 탈퇴하기)',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),

        Text('6. 개인정보 보호책임자', style: headStyle),
        const SizedBox(height: 8),
        const Text(
          '• 이메일: privacy@momstalk.kr\n'
          '• 응답 기한: 7영업일 이내',
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
            '본 방침은 법령 변경 또는 서비스 정책 변경에 따라 개정될 수 있습니다.\n'
            '변경 시 앱 내 공지 또는 이메일로 사전 고지합니다.',
            style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.6),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
