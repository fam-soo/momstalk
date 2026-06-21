import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';

/// 캡처 제출 후 관리자 심사 대기 화면.
class AuthPendingScreen extends ConsumerStatefulWidget {
  const AuthPendingScreen({super.key});

  @override
  ConsumerState<AuthPendingScreen> createState() => _AuthPendingScreenState();
}

class _AuthPendingScreenState extends ConsumerState<AuthPendingScreen> {
  bool _checking = false;

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/me');
      final memberGrade = resp.data['member_grade'] as String? ?? 'lurker';
      final authPending = resp.data['auth_pending'] as bool? ?? false;

      if (!mounted) return;

      if (memberGrade == 'member') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('정회원 승인이 완료되었습니다!')));
        context.go('/board');
      } else if (!authPending) {
        // 반려된 경우 — 다시 제출 가능
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('심사가 반려되었습니다. 다시 시도해주세요.')));
        context.go('/auth/school-select');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('아직 심사 중입니다. 조금만 기다려주세요.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.hourglass_top_rounded, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                '심사 중',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '제출하신 알림장 캡처를 검토하고 있습니다.\n보통 영업일 기준 1~2일 내에 완료됩니다.\n\n승인 시 푸시 알림으로 안내드립니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.6),
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: _checking ? null : _checkStatus,
                child: _checking
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('승인 여부 확인'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/board'),
                child: const Text('게시판 둘러보기 (전체글)'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/auth/school-select'),
                child: const Text('캡처 다시 제출', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
