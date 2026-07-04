import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';

class AcademyScreen extends ConsumerStatefulWidget {
  const AcademyScreen({super.key});

  @override
  ConsumerState<AcademyScreen> createState() => _AcademyScreenState();
}

class _AcademyScreenState extends ConsumerState<AcademyScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchActive = false;

  // 필터 상태
  final Set<String> _selectedSubjects = {};
  String _selectedLevel = '';           // 초등|중등|고등|''
  String _reviewerSchool = '';          // 후기 작성자 아이 학교명
  final Set<int> _reviewerGrades = {};  // 후기 작성자 아이 학년
  final Set<String> _selectedRegions = {}; // 추가 지역 (기본 지역 외)

  // 사용자 프로필 (필터 기본값 제공용)
  String _userRegion = '';
  String _userSchoolName = '';
  int _userGrade = 0;
  bool _isAdmin = false;
  int _userReviewCount = 0;
  String _memberGrade = '';

  List<Map<String, dynamic>> _results = [];
  bool _loading = true;
  bool _searched = false;
  String? _error;

  static const _subjects = ['수학', '영어', '과학', '국어', '음악', '미술', '체육', '코딩', '기타'];
  static const _levels = ['초등', '중등', '고등'];
  static const _grades = [1, 2, 3, 4, 5, 6];
  static const _seoulDistricts = [
    '강남구', '강동구', '강북구', '강서구', '관악구', '광진구', '구로구', '금천구',
    '노원구', '도봉구', '동대문구', '동작구', '마포구', '서대문구', '서초구',
    '성동구', '성북구', '송파구', '양천구', '영등포구', '용산구', '은평구',
    '종로구', '중구', '중랑구',
  ];

  bool get _hasFilter =>
      _selectedSubjects.isNotEmpty ||
      _selectedLevel.isNotEmpty ||
      _reviewerSchool.isNotEmpty ||
      _reviewerGrades.isNotEmpty ||
      _selectedRegions.isNotEmpty;

  // 실제 검색에 사용할 지역 목록 (기본 + 추가 선택)
  Set<String> get _activeRegions {
    final base = <String>{if (_userRegion.isNotEmpty) _userRegion};
    return {...base, ..._selectedRegions};
  }

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _initLoad() async {
    try {
      final dio = ref.read(dioProvider);
      String region = '';
      final token = await ref.read(tokenStorageProvider).read(AppConstants.tokenKey);
      if (token != null) {
        try {
          final resp = await dio.get('/auth/me');
          final p = resp.data as Map<String, dynamic>;
          final r = p['region'] as String? ?? '';
          final adminFlag = p['is_admin'] as bool? ?? false;
          region = adminFlag ? '' : (r.isNotEmpty ? r : '양천구');
          final schoolName = p['school_name'] as String? ?? '';
          final grade = p['grade'] as int? ?? 0;
          final reviewCount = p['academy_review_count'] as int? ?? 0;
          final memberGrade = p['member_grade'] as String? ?? '';
          if (mounted) {
            setState(() {
              _userSchoolName = schoolName;
              _userGrade = grade;
              _isAdmin = adminFlag;
              _userReviewCount = reviewCount;
              _memberGrade = memberGrade;
            });
          }
        } catch (_) {}
      }
      if (region.isEmpty) region = '양천구';
      if (mounted) setState(() => _userRegion = region);
      await _search(regionOverride: region);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _search({String? regionOverride}) async {
    final q = _searchCtrl.text.trim();
    // regionOverride: 초기 로딩 시 사용자 지역. 이후엔 _activeRegions 사용
    final regions = regionOverride != null
        ? {regionOverride}
        : _activeRegions;

    if (mounted) setState(() { _loading = true; _searched = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      final params = <String, dynamic>{};
      if (q.isNotEmpty) params['name'] = q;
      if (regions.isNotEmpty) params['region'] = regions.join(',');
      if (_selectedSubjects.isNotEmpty) params['subjects'] = _selectedSubjects.join(',');
      if (_selectedLevel.isNotEmpty) params['school_level'] = _selectedLevel;
      if (_reviewerSchool.isNotEmpty) params['reviewer_school'] = _reviewerSchool;
      if (_reviewerGrades.isNotEmpty) params['reviewer_grades'] = _reviewerGrades.join(',');

      final resp = await dio.get('/academies', queryParameters: params);
      final list = resp.data as List;
      if (mounted) {
        setState(() {
          _results = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _searchActive = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        final detail = e.response?.data;
        setState(() => _error = detail is Map ? detail['detail'] as String? ?? '오류 발생' : '오류 발생');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openSearch() {
    setState(() => _searchActive = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  void _cancelSearch() {
    _searchCtrl.clear();
    setState(() => _searchActive = false);
    _searchFocus.unfocus();
  }

  // 필터 bottom sheet
  Future<void> _openFilter() async {
    final tempSubjects = Set<String>.from(_selectedSubjects);
    var tempLevel = _selectedLevel;
    var tempSchool = _reviewerSchool.isNotEmpty ? _reviewerSchool : _userSchoolName;
    final tempGrades = Set<int>.from(_reviewerGrades);
    final tempRegions = Set<String>.from(_selectedRegions);
    final schoolCtrl = TextEditingController(text: tempSchool);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setBS) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) => Column(
              children: [
                // 핸들
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
                  child: Row(children: [
                    const Text('검색 필터', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setBS(() {
                          tempSubjects.clear();
                          tempLevel = '';
                          tempGrades.clear();
                          tempRegions.clear();
                          schoolCtrl.clear();
                        });
                      },
                      child: const Text('초기화'),
                    ),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    children: [
                      // ── 지역 추가 선택 ────────────────────
                      Row(children: [
                        const Text('타 지역 추가', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        if (_userRegion.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(ctx).colorScheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('기본: $_userRegion',
                              style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.w600)),
                          ),
                        if (tempRegions.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text('+${tempRegions.length}개 선택',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _seoulDistricts.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (_, idx) {
                            final district = _seoulDistricts[idx];
                            final isBase = district == _userRegion;
                            final sel = tempRegions.contains(district);
                            return FilterChip(
                              label: Text(district, style: const TextStyle(fontSize: 12)),
                              selected: isBase || sel,
                              onSelected: isBase ? null : (_) => setBS(() {
                                sel ? tempRegions.remove(district) : tempRegions.add(district);
                              }),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: isBase
                                  ? Theme.of(ctx).colorScheme.primary.withOpacity(0.08)
                                  : null,
                              selectedColor: isBase
                                  ? Theme.of(ctx).colorScheme.primary.withOpacity(0.2)
                                  : null,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      // ── 과목 (복수 선택, 3개씩) ──────────
                      const Text('과목', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _subjects.map((s) {
                          final sel = tempSubjects.contains(s);
                          return FilterChip(
                            label: Text(s),
                            selected: sel,
                            onSelected: (_) => setBS(() {
                              sel ? tempSubjects.remove(s) : tempSubjects.add(s);
                            }),
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      // ── 학교급 (단일 선택, 한 줄) ────────
                      const Text('학교급', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('전체'),
                            selected: tempLevel.isEmpty,
                            onSelected: (_) => setBS(() => tempLevel = ''),
                            visualDensity: VisualDensity.compact,
                          ),
                          ..._levels.map((l) => ChoiceChip(
                            label: Text(l),
                            selected: tempLevel == l,
                            onSelected: (_) => setBS(() => tempLevel = l),
                            visualDensity: VisualDensity.compact,
                          )),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      // ── 후기 작성자 아이 정보 ────────────
                      const Text('후기 작성자 아이 정보', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        '해당 학교·학년 아이를 가진 학부모의 후기가 있는 학원만 표시됩니다.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: schoolCtrl,
                        onChanged: (_) => setBS(() {}),
                        decoration: InputDecoration(
                          labelText: '학교명',
                          hintText: _userSchoolName.isNotEmpty ? _userSchoolName : '예: 양천초등학교',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          suffixIcon: schoolCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () => setBS(() => schoolCtrl.clear()),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('학년', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: _grades.map((g) {
                          final sel = tempGrades.contains(g);
                          return FilterChip(
                            label: Text('$g학년'),
                            selected: sel,
                            onSelected: (_) => setBS(() {
                              sel ? tempGrades.remove(g) : tempGrades.add(g);
                            }),
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                // 적용 버튼
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          final school = schoolCtrl.text.trim();
                          Navigator.pop(ctx);
                          setState(() {
                            _selectedSubjects..clear()..addAll(tempSubjects);
                            _selectedLevel = tempLevel;
                            _reviewerSchool = school;
                            _reviewerGrades..clear()..addAll(tempGrades);
                            _selectedRegions..clear()..addAll(tempRegions);
                          });
                          _search();
                        },
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: Text(
                          _buildFilterLabel(tempSubjects, tempLevel, schoolCtrl.text.trim(), tempGrades, tempRegions),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
    schoolCtrl.dispose();
  }

  String _buildFilterLabel(Set<String> subjects, String level, String school, Set<int> grades, [Set<String>? regions]) {
    final parts = <String>[
      if ((regions ?? {}).isNotEmpty) '지역 ${(regions ?? {}).length}개 추가',
      if (subjects.isNotEmpty) '과목 ${subjects.length}개',
      if (level.isNotEmpty) level,
      if (school.isNotEmpty) school,
      if (grades.isNotEmpty) '${grades.toList()..sort()}학년'.replaceAll('[', '').replaceAll(']', ''),
    ];
    return parts.isEmpty ? '전체 조회' : '필터 적용 (${parts.join(', ')})';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _searchActive ? _buildSearchAppBar(theme) : _buildNormalAppBar(theme),
      body: Column(
        children: [
          // ── 활성 필터 요약 바 ──────────────────────────
          if (_hasFilter)
            Container(
              width: double.infinity,
              color: theme.colorScheme.primaryContainer.withOpacity(0.25),
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  Icon(Icons.filter_list, size: 15, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        if (_selectedRegions.isNotEmpty) '+지역: ${_selectedRegions.join(', ')}',
                        if (_selectedSubjects.isNotEmpty) '과목: ${_selectedSubjects.join(', ')}',
                        if (_selectedLevel.isNotEmpty) '학교급: $_selectedLevel',
                        if (_reviewerSchool.isNotEmpty) '학교: $_reviewerSchool',
                        if (_reviewerGrades.isNotEmpty) '${(_reviewerGrades.toList()..sort()).join('·')}학년',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      setState(() {
                        _selectedSubjects.clear();
                        _selectedLevel = '';
                        _reviewerSchool = '';
                        _reviewerGrades.clear();
                        _selectedRegions.clear();
                      });
                      _search();
                    },
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          if (_hasFilter) const Divider(height: 1),

          // ── 결과 영역 ─────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.error_outline, size: 40, color: Colors.red.shade300),
                          const SizedBox(height: 8),
                          Text(_error!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: _initLoad, child: const Text('다시 시도')),
                        ]),
                      )
                    : !_searched
                        ? Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.school_outlined, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text('학원명이나 지역으로 검색해보세요',
                                  style: TextStyle(color: Colors.grey.shade500)),
                            ]),
                          )
                        : _results.isEmpty
                            ? Center(
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
                                  const SizedBox(height: 8),
                                  Text(
                                    _hasFilter
                                        ? '해당 조건의 학원이 없습니다'
                                        : _userRegion.isNotEmpty
                                            ? '$_userRegion 주변 학원 정보가 없습니다'
                                            : '검색 결과가 없습니다',
                                    style: TextStyle(color: Colors.grey.shade500),
                                  ),
                                ]),
                              )
                            : RefreshIndicator(
                                onRefresh: () => _search(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                                      child: Text(
                                        () {
                                          final regionLabel = _activeRegions.length > 1
                                              ? _activeRegions.join(', ')
                                              : _userRegion;
                                          return '학원 ${_results.length}곳 · $regionLabel';
                                        }(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: ListView.separated(
                                        padding: const EdgeInsets.only(bottom: 20),
                                        itemCount: _results.length,
                                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                                        itemBuilder: (_, i) => _AcademyTile(
                                          academy: _results[i],
                                          isQuotaLimited: !_isAdmin &&
                                              _memberGrade != 'lurker' &&
                                              _userReviewCount < 5 &&
                                              (_results[i]['review_count'] as int? ?? 0) > 0,
                                          userReviewCount: _userReviewCount,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar(ThemeData theme) {
    return AppBar(
      title: Text(
        _isAdmin
            ? '전지역 학원 후기'
            : _selectedRegions.isNotEmpty
                ? '${_activeRegions.length}개 지역 학원 후기'
                : (_userRegion.isNotEmpty ? '$_userRegion 학원 후기' : '학원 후기'),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      centerTitle: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: '학원명 검색',
          onPressed: _openSearch,
        ),
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '필터',
              onPressed: _openFilter,
            ),
            if (_hasFilter)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSearchAppBar(ThemeData theme) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _cancelSearch,
      ),
      title: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.search,
        autofocus: true,
        decoration: InputDecoration(
          hintText: '학원명 검색',
          border: InputBorder.none,
          hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
        ),
        style: const TextStyle(fontSize: 16),
        onSubmitted: (_) => _search(),
      ),
      actions: [
        if (_searchCtrl.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () { _searchCtrl.clear(); setState(() {}); },
          ),
        TextButton(onPressed: _search, child: const Text('검색')),
      ],
    );
  }
}

class _AcademyTile extends StatelessWidget {
  final Map<String, dynamic> academy;
  final bool isQuotaLimited;
  final int userReviewCount;
  const _AcademyTile({required this.academy, this.isQuotaLimited = false, this.userReviewCount = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = (academy['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final reviewCount = academy['review_count'] as int? ?? 0;
    final readableCount = isQuotaLimited
        ? (userReviewCount == 0 ? 1 : (userReviewCount * 5)).clamp(0, reviewCount)
        : reviewCount;
    final rawSubjects = (academy['subjects'] as List?)?.cast<String>() ?? [];
    const knownSubjects = ['수학', '영어', '과학', '국어', '음악', '미술', '체육', '코딩', '기타'];
    final subjects = rawSubjects.where((s) => knownSubjects.contains(s)).toList();
    final isB2b = academy['is_b2b'] as bool? ?? false;
    final name = academy['name'] as String? ?? '';
    final address = academy['address'] as String? ?? '';

    return ListTile(
      onTap: () => context.push('/academy/${academy['id']}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          name.isNotEmpty ? name[0] : '학',
          style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(children: [
        Expanded(
          child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        ),
        if (isB2b)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('공식', style: TextStyle(
              fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
          ),
      ]),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (address.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(address,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          const SizedBox(height: 4),
          Row(children: [
            ...List.generate(5, (i) => Icon(
              i < rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 14,
              color: Colors.amber.shade600,
            )),
            const SizedBox(width: 4),
            Text(
              rating > 0 ? rating.toStringAsFixed(1) : '-',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Text('후기 $reviewCount개', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (isQuotaLimited && reviewCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock_outline, size: 11, color: Colors.orange.shade700),
                  const SizedBox(width: 2),
                  Text('$readableCount개 열람 가능',
                    style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            if (subjects.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subjects.join(' · '),
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ]),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
    );
  }
}
