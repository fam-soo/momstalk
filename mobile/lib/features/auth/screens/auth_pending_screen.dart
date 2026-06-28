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
  bool _loading = true;
  bool _checking = false;
  // null = 초기 로딩 중 / 'new' = 미제출 / 'pending' = 심사 중 / 'rejected' = 반려
  String _state = 'new';
  String? _rejectReason;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/me');
      final memberGrade = resp.data['member_grade'] as String? ?? 'lurker';
      final authPending = resp.data['auth_pending'] as bool? ?? false;
      final rejectReason = resp.data['reject_reason'] as String?;

      if (!mounted) return;

      if (memberGrade == 'member') {
        context.go('/region');
        return;
      }

      String newState;
      if (authPending) {
        newState = 'pending';
      } else if (rejectReason != null) {
        newState = 'rejected';
      } else {
        newState = 'new'; // 캡처 미제출 상태
      }
      setState(() {
        _state = newState;
        _rejectReason = rejectReason;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _state = 'new'; _loading = false; });
    }
  }

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/me');
      final memberGrade = resp.data['member_grade'] as String? ?? 'lurker';
      final authPending = resp.data['auth_pending'] as bool? ?? false;
      final rejectReason = resp.data['reject_reason'] as String?;

      if (!mounted) return;

      if (memberGrade == 'member') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('정회원 승인이 완료되었습니다!')));
        context.go('/region');
        return;
      }
      if (authPending) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('아직 심사 중입니다. 조금만 기다려주세요.')));
      } else if (rejectReason != null) {
        setState(() { _state = 'rejected'; _rejectReason = rejectReason; });
      } else {
        setState(() => _state = 'new');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                _state == 'rejected'
                    ? Icons.cancel_outlined
                    : _state == 'pending'
                        ? Icons.hourglass_top_rounded
                        : Icons.family_restroom,
                size: 72,
                color: _state == 'rejected'
                    ? Colors.red
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                _state == 'rejected'
                    ? '심사 반려'
                    : _state == 'pending'
                        ? '심사 중'
                        : 'MomsTalk에 오신 것을 환영해요!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (_state == 'rejected') ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('반려 사유', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    const SizedBox(height: 6),
                    Text(_rejectReason!, style: const TextStyle(height: 1.5)),
                  ]),
                ),
                const SizedBox(height: 16),
                const Text(
                  '아래 버튼을 눌러 캡처를 다시 제출해주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, height: 1.6),
                ),
              ] else if (_state == 'pending')
                const Text(
                  '제출하신 알림장 캡처를 검토하고 있습니다.\n보통 영업일 기준 1~2일 내에 완료됩니다.\n\n승인 시 푸시 알림으로 안내드립니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, height: 1.6),
                )
              else
                const Text(
                  '학부모 인증이 필요해요.\n알림장이나 가정통신문 캡처를 제출하면\n관리자 확인 후 정회원으로 승인됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, height: 1.6),
                ),
              const SizedBox(height: 40),
              if (_state == 'rejected' || _state == 'new')
                FilledButton.icon(
                  onPressed: () => context.go('/auth/school-select'),
                  icon: const Icon(Icons.upload_outlined),
                  label: Text(_state == 'rejected' ? '캡처 다시 제출' : '캡처 제출하기'),
                )
              else
                FilledButton(
                  onPressed: _checking ? null : _checkStatus,
                  child: _checking
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('승인 여부 확인'),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/region'),
                child: const Text('게시판 둘러보기'),
              ),
              if (_state == 'pending') ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go('/auth/school-select'),
                  child: const Text('캡처 다시 제출', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
