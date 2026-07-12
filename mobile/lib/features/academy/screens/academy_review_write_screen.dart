import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';

class AcademyReviewWriteScreen extends ConsumerStatefulWidget {
  final int academyId;
  final Map<String, dynamic>? editingReview;
  const AcademyReviewWriteScreen({super.key, required this.academyId, this.editingReview});

  @override
  ConsumerState<AcademyReviewWriteScreen> createState() => _AcademyReviewWriteScreenState();
}

class _AcademyReviewWriteScreenState extends ConsumerState<AcademyReviewWriteScreen> {
  final _textCtrl = TextEditingController();
  final _adminReviewCtrl = TextEditingController();
  int _rating = 0;
  int _adminRating = 0;
  final Set<String> _selectedSubjects = {};     // 다중 과목 선택
  final Set<String> _selectedTeacherStyles = {}; // 다중 선생님 스타일 (최대 3)
  String _homeworkLevel = '';
  String _scoreImprovement = '';
  String _nicknameType = 'nickname';
  String? _nickname;
  bool _isAdmin = false;
  final Set<String> _adminSubjects = {};
  bool _submitting = false;

  // 학원 추천 매칭용 — 후기 작성 시점 기준 수강생 성향/성적대 (선택 입력)
  final Set<String> _studentTraits = {};  // 최대 2개
  String _scoreLevel = '';
  String _feedbackFrequency = '';
  bool? _recommendToSimilar;

  static const _teacherStyleOptions = [
    '꼼꼼해요', '친절해요', '엄격해요', '열정적이에요', '설명이 쉬워요',
    '재미있어요', '칭찬을 잘해요', '질문에 잘 답해줘요', '학생 맞춤형이에요',
    '숙제 피드백이 빨라요', '이해 중심으로 가르쳐요', '반복 학습을 강조해요',
  ];
  static const _homeworkOptions = ['없음', '적음', '보통', '많음', '매우 많음'];
  static const _scoreOptions = ['크게 올랐어요', '조금 올랐어요', '유지됐어요', '변화 없음', '오히려 내려갔어요'];
  static const _subjects = ['수학', '영어', '과학', '국어', '음악', '미술', '체육', '코딩', '기타'];
  static const _studentTraitOptions = [
    '자기주도형', '가끔관리필요', '밀착관리필요', '칭찬에_약해요', '승부욕이_강해요',
    '내향적이에요', '외향적이에요', '꼼꼼해요', '감성적이에요', '논리적이에요',
  ];
  static const _scoreLevelOptions = ['최상위권', '상위권', '중위권', '기초가_필요해요'];
  static const _feedbackFrequencyOptions = ['일간', '주간', '월간', '분기', '반기'];

  bool get _isEditing => widget.editingReview != null;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    final r = widget.editingReview;
    if (r != null) {
      _rating = (r['rating'] as num?)?.toInt() ?? 0;
      _selectedSubjects.addAll((r['subjects'] as List?)?.cast<String>() ?? []);
      _selectedTeacherStyles.addAll((r['teacher_styles'] as List?)?.cast<String>() ?? []);
      _homeworkLevel = r['homework_level'] as String? ?? '';
      _scoreImprovement = r['score_improvement'] as String? ?? '';
      _studentTraits.addAll((r['student_traits'] as List?)?.cast<String>() ?? []);
      _scoreLevel = r['score_level'] as String? ?? '';
      _feedbackFrequency = r['feedback_frequency'] as String? ?? '';
      _recommendToSimilar = r['recommend_to_similar'] as bool?;
      _nicknameType = (r['is_anonymous'] as bool? ?? true) ? 'anon' : 'nickname';
      _textCtrl.text = r['review_text'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _adminReviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/me');
      final p = resp.data as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _nickname = p['nickname'] as String?;
          _isAdmin = p['is_admin'] as bool? ?? false;
        });
      }
    } catch (_) {}
  }

  // 관리자: 과목 PATCH + 선택적으로 별점 리뷰 POST
  Future<void> _submitAdmin() async {
    if (_adminSubjects.isEmpty && _adminRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('과목을 선택하거나 별점을 부여해주세요.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final dio = ref.read(dioProvider);
      if (_adminSubjects.isNotEmpty) {
        await dio.patch('/academies/${widget.academyId}/subjects', data: {
          'subjects': _adminSubjects.toList(),
        });
      }
      if (_adminRating > 0) {
        await dio.post('/academies/${widget.academyId}/reviews', data: {
          'rating': _adminRating,
          'subjects': [],
          'teacher_styles': [],
          'homework_level': '',
          'score_improvement': '',
          'review_text': _adminReviewCtrl.text.trim().isEmpty
              ? '관리자가 직접 평가한 후기입니다.'
              : _adminReviewCtrl.text.trim(),
          'nickname_type': 'anon',
          'is_anonymous': true,
        });
      }
      if (mounted) {
        final msgs = <String>[];
        if (_adminSubjects.isNotEmpty) msgs.add('과목 저장');
        if (_adminRating > 0) msgs.add('별점 등록');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${msgs.join(' · ')}되었습니다.')));
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
      final data = {
        'rating': _rating,
        'subjects': _selectedSubjects.toList(),
        'teacher_styles': _selectedTeacherStyles.toList(),
        'homework_level': _homeworkLevel,
        'score_improvement': _scoreImprovement,
        'student_traits': _studentTraits.toList(),
        'score_level': _scoreLevel.isEmpty ? null : _scoreLevel,
        'feedback_frequency': _feedbackFrequency.isEmpty ? null : _feedbackFrequency,
        'recommend_to_similar': _recommendToSimilar,
        'review_text': _textCtrl.text.trim(),
        'nickname_type': _nicknameType,
        'is_anonymous': _nicknameType == 'anon',
      };
      if (_isEditing) {
        final reviewId = widget.editingReview!['id'];
        await dio.patch('/academies/${widget.academyId}/reviews/$reviewId', data: data);
      } else {
        await dio.post('/academies/${widget.academyId}/reviews', data: data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isEditing ? '후기가 수정되었습니다.' : '후기가 등록되었습니다.')));
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
        title: Text(_isAdmin ? '학원 정보 설정 (관리자)' : (_isEditing ? '후기 수정' : '후기 작성')),
        actions: [
          TextButton(
            onPressed: _submitting ? null : (_isAdmin ? _submitAdmin : _submitReview),
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

  // ── 관리자 전용 UI ──────────────────────────────────────────
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
                '관리자 모드: 과목 설정과 별점 부여를 각각 또는 함께 할 수 있습니다.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        _SectionTitle('과목 설정 (복수 선택 가능 · 선택 시 기존 목록 교체)'),
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
          const SizedBox(height: 8),
          Text(
            '선택됨: ${_adminSubjects.join(', ')}',
            style: TextStyle(fontSize: 13, color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
          ),
        ],

        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),

        _SectionTitle('별점 부여 (선택)'),
        const SizedBox(height: 8),
        Row(
          children: List.generate(5, (i) => GestureDetector(
            onTap: () => setState(() => _adminRating = _adminRating == i + 1 ? 0 : i + 1),
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                i < _adminRating ? Icons.star : Icons.star_border,
                size: 36,
                color: Colors.amber.shade600,
              ),
            ),
          )),
        ),
        if (_adminRating > 0) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _adminReviewCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '평가 내용 (선택 · 비워두면 기본 문구로 등록)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
          ),
        ],

        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitting ? null : _submitAdmin,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('저장', style: TextStyle(fontSize: 15)),
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

        // ── 과목 (복수 선택) ─────────────────────────────────
        _SectionTitle('과목 (복수 선택 가능)'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _subjects.map((s) {
            final selected = _selectedSubjects.contains(s);
            return FilterChip(
              label: Text(s),
              selected: selected,
              onSelected: (_) => setState(() {
                selected ? _selectedSubjects.remove(s) : _selectedSubjects.add(s);
              }),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // ── 선생님 스타일 (최대 3개) ──────────────────────────
        Row(
          children: [
            _SectionTitle('선생님 스타일'),
            const SizedBox(width: 6),
            Text(
              '(최대 3개, 선택됨: ${_selectedTeacherStyles.length}/3)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _teacherStyleOptions.map((o) {
            final selected = _selectedTeacherStyles.contains(o);
            final maxReached = _selectedTeacherStyles.length >= 3 && !selected;
            return FilterChip(
              label: Text(o),
              selected: selected,
              onSelected: maxReached ? null : (_) => setState(() {
                selected ? _selectedTeacherStyles.remove(o) : _selectedTeacherStyles.add(o);
              }),
              visualDensity: VisualDensity.compact,
              disabledColor: Colors.grey.shade100,
            );
          }).toList(),
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

        // ── 학원 추천 매칭용 (선택 입력) ─────────────────────
        Row(children: [
          _SectionTitle('수강생 성향'),
          const SizedBox(width: 6),
          Text('(선택, 최대 2개, 추천 매칭에 활용돼요)', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6, runSpacing: 4,
          children: _studentTraitOptions.map((t) {
            final selected = _studentTraits.contains(t);
            final maxReached = _studentTraits.length >= 2 && !selected;
            return FilterChip(
              label: Text(t),
              selected: selected,
              onSelected: maxReached ? null : (_) => setState(() {
                selected ? _studentTraits.remove(t) : _studentTraits.add(t);
              }),
              visualDensity: VisualDensity.compact,
              disabledColor: Colors.grey.shade100,
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        _SectionTitle('수강 당시 성적대 (선택)'),
        const SizedBox(height: 8),
        _ChipSelector(
          options: _scoreLevelOptions,
          selected: _scoreLevel,
          onSelect: (v) => setState(() => _scoreLevel = _scoreLevel == v ? '' : v),
        ),
        const SizedBox(height: 16),

        _SectionTitle('선생님 피드백 주기 (선택)'),
        const SizedBox(height: 8),
        _ChipSelector(
          options: _feedbackFrequencyOptions,
          selected: _feedbackFrequency,
          onSelect: (v) => setState(() => _feedbackFrequency = _feedbackFrequency == v ? '' : v),
        ),
        const SizedBox(height: 16),

        _SectionTitle('비슷한 성향의 아이에게 추천하시겠어요? (선택)'),
        const SizedBox(height: 8),
        Row(children: [
          ChoiceChip(
            label: const Text('추천해요'),
            selected: _recommendToSimilar == true,
            onSelected: (_) => setState(() => _recommendToSimilar = _recommendToSimilar == true ? null : true),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('비추천해요'),
            selected: _recommendToSimilar == false,
            onSelected: (_) => setState(() => _recommendToSimilar = _recommendToSimilar == false ? null : false),
          ),
        ]),
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

        // ── 공개 방식 (익명 / 닉네임 / 인증 닉네임) ────────────
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
            const SizedBox(width: 8),
            Expanded(
              child: _TypeCard(
                selected: _nicknameType == 'nickname',
                icon: Icons.person_outline,
                title: _nickname ?? '닉네임',
                color: Colors.teal.shade600,
                onTap: () => setState(() => _nicknameType = 'nickname'),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : Colors.grey.shade300, width: selected ? 2 : 1),
          color: selected ? color.withOpacity(0.06) : (disabled ? Colors.grey.shade50 : null),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: disabled ? Colors.grey.shade400 : color),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: disabled ? Colors.grey.shade400 : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (selected)
              Icon(Icons.check_circle, size: 12, color: color),
          ],
        ),
      ),
    );
  }
}
