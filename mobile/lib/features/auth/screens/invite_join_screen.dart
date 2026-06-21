import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';

/// 딥링크 momstalk://invite/{token} 처리 화면.
class InviteJoinScreen extends ConsumerStatefulWidget {
  final String token;
  const InviteJoinScreen({super.key, required this.token});

  @override
  ConsumerState<InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends ConsumerState<InviteJoinScreen> {
  Map<String, dynamic>? _inviteInfo;
  bool _loading = true;
  String? _error;
  int _grade = 1;
  int? _classNum;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _loadInvite();
  }

  Future<void> _loadInvite() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/invite/${widget.token}');
      setState(() => _inviteInfo = Map<String, dynamic>.from(resp.data));
    } catch (e) {
      setState(() => _error = '유효하지 않은 초대 링크입니다.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/auth/invite/use', data: {
        'token': widget.token,
        'grade': _grade,
        'class_num': _classNum,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('정회원 가입이 완료되었습니다!')));
        context.go('/board');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('가입 실패: $e')));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        body: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.link_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => context.go('/'), child: const Text('홈으로')),
          ]),
        )),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('초대 링크로 가입')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.school_outlined, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      _inviteInfo?['school_name'] ?? '',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('에 자녀가 재학 중인 학부모 커뮤니티', style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('자녀 학년', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _grade,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: List.generate(6, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}학년'))),
              onChanged: (v) => setState(() => _grade = v ?? 1),
            ),
            const SizedBox(height: 16),
            const Text('반 (선택)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: _classNum,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '반 선택 안함'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('선택 안함')),
                ...List.generate(15, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}반'))),
              ],
              onChanged: (v) => setState(() => _classNum = v),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _joining ? null : _join,
              child: _joining
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('가입하기'),
            ),
          ],
        ),
      ),
    );
  }
}
