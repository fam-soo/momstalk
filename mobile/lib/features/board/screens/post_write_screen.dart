import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';

class PostWriteScreen extends ConsumerStatefulWidget {
  final String boardType;
  const PostWriteScreen({super.key, required this.boardType});

  @override
  ConsumerState<PostWriteScreen> createState() => _PostWriteScreenState();
}

class _PostWriteScreenState extends ConsumerState<PostWriteScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();

  static const _anonAllowedBoards = {'school', 'free', 'region'};

  String _nicknameType = 'nickname';
  String? _nickname;
  bool _submitting = false;

  bool get _anonAllowed => _anonAllowedBoards.contains(widget.boardType);

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMyProfile() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/me');
      final p = resp.data as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _nickname = p['nickname'] as String?;
        });
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty || _contentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 입력해주세요.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final dio = ref.read(dioProvider);
      final body = {
        'board_type': widget.boardType,
        'title': _titleCtrl.text.trim(),
        'content': _contentCtrl.text.trim(),
        'is_anonymous': _nicknameType == 'anon',
        'nickname_type': _nicknameType,
      };
      final resp = await dio.post('/posts', data: body);
      final postId = resp.data['id'];
      if (mounted) context.pushReplacement('/board/$postId');
    } on DioException catch (e) {
      if (mounted) {
        final data = e.response?.data;
        String msg = '';
        if (data is Map) {
          final raw = data['detail'];
          if (raw is String) {
            msg = raw;
          } else if (raw is List && raw.isNotEmpty) {
            msg = (raw as List).map((item) => (item as Map<dynamic, dynamic>)['msg'] as String? ?? '').join('\n');
          }
        }
        if (msg.isEmpty) msg = '오류 ${e.response?.statusCode ?? ''}: ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('글쓰기'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('등록'),
          ),
        ],
      ),
      // 닉네임 유형 선택 — 키보드 위에 고정
      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1),
            if (_anonAllowed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('공개 방식',
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _NicknameTypeCard(
                          selected: _nicknameType == 'anon',
                          icon: Icons.visibility_off_outlined,
                          title: '익명',
                          subtitle: '이름 없이 게시',
                          color: Colors.grey.shade600,
                          onTap: () => setState(() => _nicknameType = 'anon'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _NicknameTypeCard(
                          selected: _nicknameType == 'nickname',
                          icon: Icons.person_outline,
                          title: '닉네임',
                          subtitle: _nickname ?? '로딩 중...',
                          color: theme.colorScheme.primary,
                          onTap: () => setState(() => _nicknameType = 'nickname'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  hintText: '제목',
                  hintStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey),
                  border: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _contentCtrl,
                  decoration: const InputDecoration(
                    hintText: '내용을 입력해주세요.',
                    hintStyle: TextStyle(fontSize: 15, color: Colors.grey),
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 15, height: 1.6),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _NicknameTypeCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _NicknameTypeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onTap == null;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          color: selected ? color.withValues(alpha: 0.06) : (disabled ? Colors.grey.shade50 : null),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: disabled ? Colors.grey.shade400 : color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: disabled ? Colors.grey.shade400 : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: disabled ? Colors.grey.shade400 : color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}
