import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/main_bottom_nav.dart';
import '../../../core/refresh_bus.dart';

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
  static const _schoolTypeLabel = {'elementary': '초', 'middle': '중', 'high': '고'};

  String _nicknameType = 'nickname';
  String? _nickname;
  bool _submitting = false;

  List<Map<String, dynamic>> _children = [];
  final Set<int> _selectedChildIds = {};

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
      final childrenResp = await dio.get('/auth/me/children');
      final children = (childrenResp.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final activeChildId = p['active_child_id'] as int?;
      if (mounted) {
        setState(() {
          _nickname = p['nickname'] as String?;
          _children = children;
          if (activeChildId != null) _selectedChildIds.add(activeChildId);
        });
      }
    } catch (_) {}
  }

  String _childLabel(Map<String, dynamic> c) {
    final schoolType = c['school_type'] as String?;
    if (schoolType == 'preschool') return '미취학';
    final grade = c['grade'] as int?;
    final level = _schoolTypeLabel[schoolType];
    if (level != null && grade != null) return '$level$grade';
    final name = c['school_name'] as String?;
    return (name != null && name.isNotEmpty) ? name : '자녀 ${c['id']}';
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
        // 서버는 nickname_type을 "anon"/"certified"(인증 닉네임 표시 여부)로만 받는다.
        // 화면의 "익명"/"닉네임" 선택은 별개 축인 is_anonymous로 이미 전달되므로
        // nickname_type은 항상 유효값인 "anon"으로 고정 전송한다.
        'nickname_type': 'anon',
        if (_children.length > 1 && _selectedChildIds.isNotEmpty) 'child_ids': _selectedChildIds.toList(),
      };
      final resp = await dio.post('/posts', data: body);
      final postId = resp.data['id'];
      bumpBoardRefresh(ref); // 목록으로 돌아왔을 때 방금 쓴 글이 바로 보이도록
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
      backgroundColor: Colors.grey.shade50,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('글쓰기'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 16, width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('등록'),
            ),
          ),
        ],
      ),
      // 공개 방식·자녀 선택 — 키보드 위에 고정
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_anonAllowed || _children.length > 1)
            Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_anonAllowed) ...[
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
                    if (_anonAllowed && _children.length > 1) const SizedBox(height: 14),
                    if (_children.length > 1) ...[
                      Text('어떤 자녀 이야기인가요?',
                          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('닉네임 옆에 표시될 자녀 정보예요. 복수 선택 가능',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6, runSpacing: 6,
                        children: _children.map((c) {
                          final id = c['id'] as int;
                          final sel = _selectedChildIds.contains(id);
                          return FilterChip(
                            label: Text(_childLabel(c)),
                            selected: sel,
                            onSelected: (_) => setState(() {
                              sel ? _selectedChildIds.remove(id) : _selectedChildIds.add(id);
                            }),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            const MainBottomNav(),
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      hintText: '제목',
                      hintStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey),
                      border: InputBorder.none,
                      isDense: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 20, color: Colors.grey.shade200),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: TextField(
                      controller: _contentCtrl,
                      decoration: const InputDecoration(
                        hintText: '내용을 입력해주세요.',
                        hintStyle: TextStyle(fontSize: 15, color: Colors.grey),
                        border: InputBorder.none,
                        isDense: false,
                        contentPadding: EdgeInsets.zero,
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
