import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/info_banner.dart';
import '../../../core/main_bottom_nav.dart';

/// 학원 추천받기 — 5단계 설문 후 규칙 기반 매칭 결과를 보여준다.
/// 매칭 점수(0~100%)는 서버(academy_service.recommend_academies)가 계산하며,
/// 30% 미만(완전 무관으로 판단)은 결과에서 이미 제외되어 내려온다.
class AcademyRecommendScreen extends ConsumerStatefulWidget {
  const AcademyRecommendScreen({super.key});

  @override
  ConsumerState<AcademyRecommendScreen> createState() => _AcademyRecommendScreenState();
}

class _AcademyRecommendScreenState extends ConsumerState<AcademyRecommendScreen> {
  int _step = 0;
  bool _loading = false;
  List<Map<String, dynamic>>? _results;
  bool _isFallback = false;

  // 0단계 — 추천 대상 자녀 (필수). 학교급 정보 없이 추천하면 초등학생
  // 자녀에게 고등부 학원이 섞여 나오는 등 결과가 부정확해질 수 있어,
  // 어떤 자녀를 위한 추천인지 반드시 먼저 선택하게 한다.
  List<Map<String, dynamic>> _children = [];
  bool _childrenLoading = true;
  int? _selectedChildId;

  static const _schoolTypeLabel = {'elementary': '초', 'middle': '중', 'high': '고'};

  String _childLabel(Map<String, dynamic> c) {
    final schoolType = c['school_type'] as String?;
    final name = c['school_name'] as String?;
    if (schoolType == 'preschool') return '미취학';
    final grade = c['grade'] as int?;
    if (name != null && name.isNotEmpty) {
      return grade != null ? '$name $grade학년' : name;
    }
    final level = _schoolTypeLabel[schoolType];
    if (level != null && grade != null) return '$level$grade';
    return '자녀 ${c['id']}';
  }

  // 1단계
  final Set<String> _subjects = {};
  static const _subjectOptions = ['국어', '영어', '수학'];

  // 검색 지역 — 기본은 내 지역, 추가로 다른 구를 더 선택할 수 있다.
  // (예전엔 지역 제한이 아예 없어서 추천 결과에 다른 지역 학원이 섞여 나왔음)
  String _userRegion = '';
  final Set<String> _extraRegions = {};
  static const _seoulDistricts = [
    '강남구', '강동구', '강북구', '강서구', '관악구', '광진구', '구로구', '금천구',
    '노원구', '도봉구', '동대문구', '동작구', '마포구', '서대문구', '서초구',
    '성동구', '성북구', '송파구', '양천구', '영등포구', '용산구', '은평구',
    '종로구', '중구', '중랑구',
  ];

  // 2단계 — 과목별 수준/성적
  final Map<String, String> _levelBySubject = {};
  final Map<String, String> _scoreBySubject = {};
  static const _levelOptions = ['학교 수준', '학교+심화', '1학기 선행', '1년 선행', '2년 이상 선행'];
  static const _scoreOptions = ['상', '중', '하'];

  // 3단계
  String? _homeworkTolerance;
  String? _managementNeed;
  String? _desiredStyle;
  static const _homeworkOptions = ['30분', '60분', '90분', '120분', '상관없음'];
  static const _managementOptions = {
    '자기주도형': '혼자 잘하는 편',
    '가끔관리필요': '가끔 관리가 필요해요',
    '밀착관리필요': '계속 관리가 필요해요',
  };
  static const _styleOptions = ['자유로운 분위기', '적당한 관리', '철저한 관리'];

  // 4단계
  final Set<String> _goals = {};
  final Set<String> _constraints = {};
  final Set<String> _learningGoals = {};
  static const _goalOptions = ['성적 향상', '꼼꼼한 관리', '선행 진도', '공부 습관', '아이와 잘 맞는 선생님', '즐겁게 다니는 분위기'];
  static const _constraintOptions = ['숙제가 너무 많은 곳은 싫어요', '아이를 혼내는 분위기는 싫어요', '너무 큰 학원은 부담돼요', '경쟁이 심한 곳은 부담돼요'];
  static const _learningGoalOptions = ['선행', '심화', '내신', '수능', '경시', '영재'];

  // 5단계
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    try {
      final dio = ref.read(dioProvider);
      final meResp = await dio.get('/auth/me');
      final me = meResp.data as Map<String, dynamic>;
      final childrenResp = await dio.get('/auth/me/children');
      final children = (childrenResp.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _children = children;
        _childrenLoading = false;
        if (children.length == 1) {
          _selectedChildId = children.first['id'] as int;
          _applyChildRegion(children.first);
        }
      });
      final region = me['region'] as String? ?? '';
      if (mounted && region.isNotEmpty && _userRegion.isEmpty) setState(() => _userRegion = region);
    } catch (_) {
      if (mounted) setState(() => _childrenLoading = false);
    }
  }

  void _applyChildRegion(Map<String, dynamic> child) {
    final region = child['region'] as String?;
    if (region != null && region.isNotEmpty) _userRegion = region;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _canProceed {
    switch (_step) {
      case 0:
        return _selectedChildId != null;
      case 1:
        return _subjects.isNotEmpty;
      default:
        return true;
    }
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/academies/recommendations', data: {
        'child_id': _selectedChildId,
        'subjects': _subjects.toList(),
        'subject_levels': {
          for (final s in _subjects)
            if (_levelBySubject[s] != null || _scoreBySubject[s] != null)
              s: {
                if (_levelBySubject[s] != null) '수준': _levelBySubject[s],
                if (_scoreBySubject[s] != null) '성적': _scoreBySubject[s],
              },
        },
        'homework_tolerance': _homeworkTolerance,
        'management_need': _managementNeed,
        'desired_style': _desiredStyle,
        'goals': _goals.toList(),
        'constraints': _constraints.toList(),
        'learning_goals': _learningGoals.toList(),
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        'regions': {if (_userRegion.isNotEmpty) _userRegion, ..._extraRegions}.toList(),
      });
      final data = resp.data as Map<String, dynamic>;
      final list = (data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final isFallback = data['is_fallback'] as bool? ?? false;
      if (mounted) setState(() { _results = list; _isFallback = isFallback; _step = 6; });
    } on DioException catch (e) {
      if (mounted) {
        final detail = e.response?.data is Map ? e.response?.data['detail'] as String? : null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail ?? '추천을 불러오지 못했어요.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _next() {
    if (_step == 4) {
      // 4단계(목표/제약) 다음은 선택 단계(5단계)를 건너뛸지 물을 필요 없이 바로 5단계로
      setState(() => _step = 5);
      return;
    }
    if (_step == 5) {
      _submit();
      return;
    }
    setState(() => _step += 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('학원 추천받기')),
      body: _step == 6 ? _buildResults() : _buildSurveyStep(),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_step != 6)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _loading ? null : () => setState(() => _step -= 1),
                        child: const Text('이전'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: (!_canProceed || _loading) ? null : _next,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _loading
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_step == 5 ? '추천받기' : '다음'),
                    ),
                  ),
                ]),
              ),
            const MainBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildSurveyStep() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        LinearProgressIndicator(value: (_step + 1) / 6),
        const SizedBox(height: 20),
        switch (_step) {
          0 => _stepChild(),
          1 => _stepSubjects(),
          2 => _stepLevels(),
          3 => _stepTraits(),
          4 => _stepGoals(),
          _ => _stepNote(),
        },
      ],
    );
  }

  Widget _stepChild() {
    if (_childrenLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_children.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('등록된 자녀 정보가 없어요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('학교급(초/중/고)에 맞는 학원만 추천해드리려면 자녀 등록이 필요해요.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => context.push('/profile/add-child'),
          child: const Text('자녀 등록하러 가기'),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('어떤 자녀를 위한 추천인가요?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text('자녀의 학교급에 맞는 학원만 골라서 추천해드려요.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      const SizedBox(height: 16),
      ..._children.map((c) {
        final id = c['id'] as int;
        final selected = _selectedChildId == id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() {
              _selectedChildId = id;
              _applyChildRegion(c);
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                  width: selected ? 2 : 1,
                ),
                color: selected ? Theme.of(context).colorScheme.primary.withOpacity(0.06) : null,
              ),
              child: Row(children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                ),
                const SizedBox(width: 10),
                Text(_childLabel(c), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ]),
            ),
          ),
        );
      }),
    ]);
  }

  Widget _stepSubjects() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const InfoBanner(
        margin: EdgeInsets.only(bottom: 16),
        text: '추천은 학부모님들이 남겨주신 실제 후기를 바탕으로 이뤄져요. '
            '후기가 많아질수록 추천 정확도가 올라가니, 이용해보신 학원 후기를 남겨주시면 '
            '다른 학부모님들께도 큰 도움이 돼요!',
      ),
      const Text('어떤 과목을 추천받고 싶으세요?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: _subjectOptions.map((s) {
        final sel = _subjects.contains(s);
        return FilterChip(
          label: Text(s),
          selected: sel,
          onSelected: (_) => setState(() => sel ? _subjects.remove(s) : _subjects.add(s)),
        );
      }).toList()),
      const SizedBox(height: 24),
      const Divider(),
      const SizedBox(height: 16),
      Row(children: [
        const Text('검색 지역', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        if (_userRegion.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('기본: $_userRegion',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
          ),
      ]),
      const SizedBox(height: 4),
      Text('다른 지역 학원도 함께 보고 싶다면 추가로 선택하세요', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6, runSpacing: 6,
        children: _seoulDistricts.map((district) {
          final isBase = district == _userRegion;
          final sel = _extraRegions.contains(district);
          return FilterChip(
            label: Text(district, style: const TextStyle(fontSize: 11)),
            selected: isBase || sel,
            onSelected: isBase ? null : (_) => setState(() {
              sel ? _extraRegions.remove(district) : _extraRegions.add(district);
            }),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        }).toList(),
      ),
    ]);
  }

  Widget _stepLevels() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('선택한 과목의 현재 수준을 알려주세요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      for (final s in _subjects) ...[
        Text(s, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 6),
        Text('현재 수준', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: _levelOptions.map((o) {
          final sel = _levelBySubject[s] == o;
          return ChoiceChip(label: Text(o, style: const TextStyle(fontSize: 12)), selected: sel,
              onSelected: (_) => setState(() => _levelBySubject[s] = sel ? '' : o));
        }).toList()),
        const SizedBox(height: 8),
        Text('학교 성적', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, children: _scoreOptions.map((o) {
          final sel = _scoreBySubject[s] == o;
          return ChoiceChip(label: Text(o), selected: sel,
              onSelected: (_) => setState(() => _scoreBySubject[s] = sel ? '' : o));
        }).toList()),
        const SizedBox(height: 20),
      ],
    ]);
  }

  Widget _stepTraits() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('학습 성향을 파악할게요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      Text('하루 숙제는 어느 정도까지 괜찮으세요?', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: _homeworkOptions.map((o) => ChoiceChip(
        label: Text(o), selected: _homeworkTolerance == o,
        onSelected: (_) => setState(() => _homeworkTolerance = _homeworkTolerance == o ? null : o),
      )).toList()),
      const SizedBox(height: 20),
      Text('아이의 성향은 어떤 편인가요?', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: _managementOptions.entries.map((e) => ChoiceChip(
        label: Text(e.value), selected: _managementNeed == e.key,
        onSelected: (_) => setState(() => _managementNeed = _managementNeed == e.key ? null : e.key),
      )).toList()),
      const SizedBox(height: 20),
      Text('어떤 스타일의 학원을 원하시나요?', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: _styleOptions.map((o) => ChoiceChip(
        label: Text(o), selected: _desiredStyle == o,
        onSelected: (_) => setState(() => _desiredStyle = _desiredStyle == o ? null : o),
      )).toList()),
    ]);
  }

  Widget _stepGoals() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('학습 목표를 선택해주세요', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: _learningGoalOptions.map((g) {
        final sel = _learningGoals.contains(g);
        return FilterChip(
          label: Text(g), selected: sel,
          onSelected: (_) => setState(() => sel ? _learningGoals.remove(g) : _learningGoals.add(g)),
        );
      }).toList()),
      const SizedBox(height: 24),
      const Text('이번 학원에서 기대하는 것은? (최대 3개)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: _goalOptions.map((g) {
        final sel = _goals.contains(g);
        final maxReached = _goals.length >= 3 && !sel;
        return FilterChip(
          label: Text(g), selected: sel,
          onSelected: maxReached ? null : (_) => setState(() => sel ? _goals.remove(g) : _goals.add(g)),
          disabledColor: Colors.grey.shade100,
        );
      }).toList()),
      const SizedBox(height: 24),
      const Text('꼭 피하고 싶은 학원이 있다면? (최대 3개)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: _constraintOptions.map((c) {
        final sel = _constraints.contains(c);
        final maxReached = _constraints.length >= 3 && !sel;
        return FilterChip(
          label: Text(c), selected: sel,
          onSelected: maxReached ? null : (_) => setState(() => sel ? _constraints.remove(c) : _constraints.add(c)),
          disabledColor: Colors.grey.shade100,
        );
      }).toList()),
    ]);
  }

  Widget _stepNote() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('우리 아이에 대해 한 줄로 적어주세요 (선택)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text('추천 결과에는 반영되지 않고, 참고용으로만 표시돼요', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(height: 16),
      TextField(
        controller: _noteCtrl,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: '예) 계산은 잘하는데 응용문제를 어려워해요, 낯을 많이 가려요',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ]);
  }

  Widget _buildResults() {
    final results = _results ?? [];
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('조건에 맞는 학원을 찾지 못했어요.\n조건을 조금 완화해서 다시 시도해보세요.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => setState(() => _step = 0), child: const Text('설문 다시 하기')),
          ]),
        ),
      );
    }
    return Column(children: [
      if (_isFallback)
        const InfoBanner(
          tone: InfoBannerTone.notice,
          text: '조건에 딱 맞는 학원은 없었어요. 같은 과목을 가르치는 학원을 평점 높은 순으로 보여드릴게요 — 아래 후기를 참고해서 직접 골라보세요.',
        )
      else
        const InfoBanner(
          text: '이 추천은 학부모님들의 후기를 바탕으로 계산돼요. 마음에 드는 학원을 이용해보셨다면 후기를 남겨주세요 — 다음 추천이 더 정확해져요!',
        ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _MatchCard(match: results[i], isFallback: _isFallback),
        ),
      ),
    ]);
  }
}

class _MatchCard extends StatelessWidget {
  final Map<String, dynamic> match;
  final bool isFallback;
  const _MatchCard({required this.match, this.isFallback = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final academy = Map<String, dynamic>.from(match['academy'] as Map);
    final score = match['match_score'] as int? ?? 0;
    final reasons = (match['match_reasons'] as List?)?.cast<String>() ?? [];
    final name = academy['name'] as String? ?? '';
    final address = academy['address'] as String? ?? '';

    final rating = (academy['avg_rating'] as num?)?.toDouble();
    final scoreColor = score >= 80
        ? Colors.green.shade600
        : score >= 50
            ? Colors.amber.shade700
            : Colors.grey.shade500;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.push('/academy/${academy['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 폴백(조건 매칭 없음) 모드에서는 의미 없는 "0%" 대신 별점을 보여준다.
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: (isFallback ? Colors.amber.shade700 : scoreColor).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: isFallback
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.star_rounded, size: 16, color: Colors.amber.shade700),
                      Text(rating != null ? rating.toStringAsFixed(1) : '-',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800, fontSize: 12)),
                    ])
                  : Text('$score%', style: TextStyle(fontWeight: FontWeight.bold, color: scoreColor, fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (address.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(address, style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                if (!isFallback && reasons.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...reasons.take(2).map((r) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(children: [
                      Icon(Icons.check_circle, size: 12, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Expanded(child: Text(r, style: TextStyle(fontSize: 11.5, color: theme.colorScheme.primary))),
                    ]),
                  )),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
