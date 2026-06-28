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
  String _selectedSubject = '';
  String _userRegion = '';
  List<Map<String, dynamic>> _allResults = [];  // 전체 로드 결과
  List<Map<String, dynamic>> _results = [];     // 표시 결과 (클라이언트 필터)
  bool _loading = true;
  bool _searched = false;
  String? _error;

  static const _subjects = ['수학', '영어', '과학', '국어', '음악', '미술', '체육', '코딩'];

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

  // 과목별 학원 수 (전체 결과 기준)
  Map<String, int> get _subjectCounts {
    final counts = <String, int>{};
    for (final a in _allResults) {
      final subjects = (a['subjects'] as List?)?.cast<String>() ?? [];
      for (final s in subjects) {
        if (_subjects.contains(s)) {
          counts[s] = (counts[s] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  void _applySubjectFilter() {
    if (_selectedSubject.isEmpty) {
      _results = List.from(_allResults);
    } else {
      _results = _allResults.where((a) {
        final subjects = (a['subjects'] as List?)?.cast<String>() ?? [];
        return subjects.contains(_selectedSubject);
      }).toList();
    }
  }

  Future<void> _initLoad() async {
    try {
      final dio = ref.read(dioProvider);
      String region = '';
      final token = await ref.read(tokenStorageProvider).read(AppConstants.tokenKey);
      if (token != null) {
        try {
          final resp = await dio.get('/auth/me');
          final r = (resp.data as Map<String, dynamic>)['region'] as String? ?? '';
          region = r.isNotEmpty ? r : '양천구';
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
    final searchRegion = regionOverride ?? _userRegion;

    if (mounted) setState(() { _loading = true; _searched = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      final params = <String, dynamic>{};
      if (q.isNotEmpty) params['name'] = q;
      if (searchRegion.isNotEmpty) params['region'] = searchRegion;
      // subject 필터는 서버에 보내지 않고 클라이언트에서 처리

      final resp = await dio.get('/academies', queryParameters: params);
      final list = resp.data as List;
      final all = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) {
        setState(() {
          _allResults = all;
          _applySubjectFilter();
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

  void _onChipTap(String subject) {
    setState(() {
      _selectedSubject = _selectedSubject == subject ? '' : subject;
      _applySubjectFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = _subjectCounts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('학원 후기'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // ── 검색 영역 ─────────────────────────────────
          // Material 대신 ColoredBox 사용 — Flutter Web에서 Material이 포인터 이벤트 차단하는 버그 회피
          ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          focusNode: _searchFocus,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.search,
                          enableInteractiveSelection: true,
                          decoration: InputDecoration(
                            hintText: _userRegion.isNotEmpty
                                ? '$_userRegion 학원명 검색'
                                : '학원명 검색',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onSubmitted: (_) => _search(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _search(),
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('검색'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 과목 필터 칩 — 카운트 표시, 토글 가능
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // 전체 칩
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(
                              '전체${_allResults.isNotEmpty ? " ${_allResults.length}" : ""}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: _selectedSubject.isEmpty,
                            onSelected: (_) {
                              setState(() {
                                _selectedSubject = '';
                                _applySubjectFilter();
                              });
                            },
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        ..._subjects.map((s) {
                          final count = counts[s] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(
                                count > 0 ? '$s $count' : s,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: _selectedSubject == s,
                              onSelected: count > 0 ? (_) => _onChipTap(s) : null,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              disabledColor: theme.colorScheme.surfaceContainerHighest,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

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
                                    _selectedSubject.isNotEmpty
                                        ? '\'$_selectedSubject\' 과목 학원이 없습니다'
                                        : _userRegion.isNotEmpty
                                            ? '$_userRegion 주변 학원 정보가 없습니다'
                                            : '검색 결과가 없습니다',
                                    style: TextStyle(color: Colors.grey.shade500),
                                  ),
                                  if (_selectedSubject.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text('후기 작성 시 과목을 선택하면 검색에 반영됩니다',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
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
                                        '학원 ${_results.length}곳'
                                        '${_selectedSubject.isNotEmpty ? " · $_selectedSubject" : (_userRegion.isNotEmpty ? " · $_userRegion" : "")}',
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
                                        separatorBuilder: (_, __) => const Divider(
                                            height: 1, indent: 16, endIndent: 16),
                                        itemBuilder: (_, i) =>
                                            _AcademyTile(academy: _results[i]),
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
}

class _AcademyTile extends StatelessWidget {
  final Map<String, dynamic> academy;
  const _AcademyTile({required this.academy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = (academy['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final reviewCount = academy['review_count'] as int? ?? 0;
    final rawSubjects = (academy['subjects'] as List?)?.cast<String>() ?? [];
    // NEIS 계열명("보통교과" 등)은 표시하지 않고 실제 과목만 표시
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
          style: TextStyle(
              color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(children: [
        Expanded(
          child: Text(name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        ),
        if (isB2b)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('공식',
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600)),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          const SizedBox(height: 4),
          Row(children: [
            // 별점
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
            Text('후기 $reviewCount개',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (subjects.isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subjects.join(' · '),
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
