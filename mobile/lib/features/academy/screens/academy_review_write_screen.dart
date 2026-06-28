import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';

class AcademyReviewWriteScreen extends ConsumerStatefulWidget {
  final int academyId;
  const AcademyReviewWriteScreen({super.key, required this.academyId});

  @override
  ConsumerState<AcademyReviewWriteScreen> createState() => _AcademyReviewWriteScreenState();
}

class _AcademyReviewWriteScreenState extends ConsumerState<AcademyReviewWriteScreen> {
  final _textCtrl = TextEditingController();
  int _rating = 0;
  String _subject = '';
  String _teacherStyle = '';
  String _homeworkLevel = '';
  String _scoreImprovement = '';
  String _nicknameType = 'anon';
  String? _certifiedNickname;
  bool _isAdmin = false;
  // 관리자 과목 멀티셀렉트
  final Set<String> _adminSubjects = {};
  bool _submitting = false;

  static const _teacherStyleOptions = ['꼼꼼해요', '친절해요', '엄격해요', '열정적이에요', '설명이 쉬워요'];
  static const _homeworkOptions = ['없음', '적음', '보통', '많음', '매우 많음'];
  static const _scoreOptions = ['크게 올랐어요', '조금 올랐어요', '유지됐어요', '변화 없음', '오히려 내려갔어요'];
  static const _subjects = ['수학', '영어', '과학', '국어', '음악', '미술', '체육', '코딩', '기타'];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/me');
      final p = resp.data as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _certifiedNickname = p['certified_nickname'] as String?;
          _isAdmin = p['is_admin'] as bool? ?? false;
        });
      }
    } catch (_) {}
  }

  // 관리자: 과목만 PATCH
  Future<void> _submitAdminSubjects() async {
    if (_adminSubjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('과목을 1개 이상 선택해주세요.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('/academies/${widget.academyId}/subjects', data: {
        'subjects': _adminSubjects.toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('과목이 저장되었습니다.')));
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        final detail = e.response?.data['detail'];
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(detail is String ? detail : '오류가 발생했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // 일반 사용자: 후기 작성
  Future<void> _submitReview() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('별점을 선택해주세요.')));
      return;
    }
    if (_textCtrl.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('후기를 10자 이상 입력해주세요.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/academies/${widget.academyId}/reviews', data: {
        'rating': _rating,
        'subject': _subject,
        'teacher_style': _teacherStyle,
        'homework_level': _homeworkLevel,
        'score_improvement': _scoreImprovement,
        'review_text': _textCtrl.text.trim(),
        'nickname_type': _nicknameType,
        'is_anonymous': _nicknameType == 'anon',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('후기가 등록되었습니다.')));
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        final detail = e.response?.data['detail'];
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(detail is String ? detail : '오류가 발생했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? '과목 설정 (관리자)' : '후기 작성'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : (_isAdmin ? _submitAdminSubjects : _submitReview),
            child: _submitting
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('저장'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _isAdmin ? _buildAdminBody(theme) : _buildReviewBody(theme),
      ),
    );
  }

  // ── 관리자 전용 UI: 과목 멀티셀렉트만 ──────────────────────────
  Widget _buildAdminBody(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(Icons.admin_panel_settings, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '관리자 모드: 필수 항목 없이 과목만 선택·저장합니다.\n기존 과목 목록은 선택한 항목으로 교체됩니다.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        _SectionTitle('과목 선택 (복수 선택 가능)'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _subjects.map((s) {
            final selected = _adminSubjects.contains(s);
            return FilterChip(
              label: Text(s),
              selected: selected,
              onSelected: (_) => setState(() {
                selected ? _adminSubjects.remove(s) : _adminSubjects.add(s);
              }),
              selectedColor: theme.colorScheme.primaryContainer,
              checkmarkColor: theme.colorScheme.primary,
            );
          }).toList(),
        ),
        if (_adminSubjects.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '선택됨: ${_adminSubjects.join(', ')}',
            style: TextStyle(fontSize: 13, color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
          ),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submitAdminSubjects,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('과목 저장', style: TextStyle(fontSize: 15)),
          ),
        ),
      ],
    );
  }

  // ── 일반 사용자 후기 작성 UI ──────────────────────────────────
  Widget _buildReviewBody(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('종합 평점'),
        const SizedBox(height: 8),
        Row(
          children: List.generate(5, (i) => GestureDetector(
            onTap: () => setState(() => _rating = i + 1),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                i < _rating ? Icons.star : Icons.star_border,
                size: 36,
                color: Colors.amber.shade600,
              ),
            ),
          )),
        ),
        const SizedBox(height: 20),

        _SectionTitle('과목'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _subjects.map((s) => FilterChip(
            label: Text(s),
            selected: _subject == s,
            onSelected: (_) => setState(() => _subject = _subject == s ? '' : s),
            visualDensity: VisualDensity.compact,
          )).toList(),
        ),
        const SizedBox(height: 20),

        _SectionTitle('선생님 스타일'),
        const SizedBox(height: 8),
        _ChipSelector(
          options: _teacherStyleOptions,
          selected: _teacherStyle,
          onSelect: (v) => setState(() => _teacherStyle = _teacherStyle == v ? '' : v),
        ),
        const SizedBox(height: 16),

        _SectionTitle('숙제량'),
        const SizedBox(height: 8),
        _ChipSelector(
          options: _homeworkOptions,
          selected: _homeworkLevel,
          onSelect: (v) => setState(() => _homeworkLevel = _homeworkLevel == v ? '' : v),
        ),
        const SizedBox(height: 16),

        _SectionTitle('성적 향상'),
        const SizedBox(height: 8),
        _ChipSelector(
          options: _scoreOptions,
          selected: _scoreImprovement,
          onSelect: (v) => setState(() => _scoreImprovement = _scoreImprovement == v ? '' : v),
        ),
        const SizedBox(height: 20),

        _SectionTitle('상세 후기 (10자 이상)'),
        const SizedBox(height: 8),
        TextField(
          controller: _textCtrl,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: '이 학원에 대한 경험을 자유롭게 적어주세요.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 20),

        _SectionTitle('공개 방식'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TypeCard(
                selected: _nicknameType == 'anon',
                icon: Icons.visibility_off_outlined,
                title: '익명',
                color: Colors.grey.shade600,
                onTap: () => setState(() => _nicknameType = 'anon'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TypeCard(
                selected: _nicknameType == 'certified',
                icon: Icons.verified_outlined,
                title: _certifiedNickname ?? '인증 닉네임',
                color: theme.colorScheme.primary,
                onTap: _certifiedNickname != null
                    ? () => setState(() => _nicknameType = 'certified')
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.orange),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  '이 후기는 작성자 개인 경험을 바탕으로 한 의견입니다. 허위 사실 게재 시 법적 책임을 질 수 있습니다.',
                  style: TextStyle(fontSize: 12, color: Colors.orange, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _ChipSelector extends StatelessWidget {
  final List<String> options;
  final String selected;
  final void Function(String) onSelect;
  const _ChipSelector({required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: options.map((o) => FilterChip(
        label: Text(o),
        selected: selected == o,
        onSelected: (_) => onSelect(o),
        visualDensity: VisualDensity.compact,
      )).toList(),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback? onTap;
  const _TypeCard({required this.selected, required this.icon, required this.title, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : Colors.grey.shade300, width: selected ? 2 : 1),
          color: selected ? color.withOpacity(0.06) : (disabled ? Colors.grey.shade50 : null),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: disabled ? Colors.grey.shade400 : color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: disabled ? Colors.grey.shade400 : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected) Icon(Icons.check_circle, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}
