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
  String _selectedLevel = ''; // 초등|중등|고등|''

  String _userRegion = '';
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;
  bool _searched = false;
  String? _error;

  static const _subjects = ['수학', '영어', '과학', '국어', '음악', '미술', '체육', '코딩', '기타'];
  static const _levels = ['초등', '중등', '고등'];

  bool get _hasFilter => _selectedSubjects.isNotEmpty || _selectedLevel.isNotEmpty;

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
      if (_selectedSubjects.isNotEmpty) params['subjects'] = _selectedSubjects.join(',');
      if (_selectedLevel.isNotEmpty) params['school_level'] = _selectedLevel;

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
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.9,
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
                        setBS(() { tempSubjects.clear(); tempLevel = ''; });
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
                      // ── 과목 (복수 선택) ────────────────
                      const Text('과목', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      ..._subjects.map((s) {
                        final sel = tempSubjects.contains(s);
                        return CheckboxListTile(
                          value: sel,
                          onChanged: (_) => setBS(() {
                            sel ? tempSubjects.remove(s) : tempSubjects.add(s);
                          }),
                          title: Text(s),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      }),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      // ── 학교급 (단일 선택) ──────────────
                      const Text('학교급', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      RadioListTile<String>(
                        value: '',
                        groupValue: tempLevel,
                        onChanged: (v) => setBS(() => tempLevel = v ?? ''),
                        title: const Text('전체'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      ..._levels.map((l) => RadioListTile<String>(
                        value: l,
                        groupValue: tempLevel,
                        onChanged: (v) => setBS(() => tempLevel = v ?? ''),
                        title: Text(l),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      )),
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
                          Navigator.pop(ctx);
                          setState(() {
                            _selectedSubjects
                              ..clear()
                              ..addAll(tempSubjects);
                            _selectedLevel = tempLevel;
                          });
                          _search();
                        },
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: Text(
                          tempSubjects.isEmpty && tempLevel.isEmpty
                              ? '전체 조회'
                              : '필터 적용 (${[
                                  if (tempSubjects.isNotEmpty) '과목 ${tempSubjects.length}개',
                                  if (tempLevel.isNotEmpty) tempLevel,
                                ].join(', ')})',
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
                        if (_selectedSubjects.isNotEmpty) '과목: ${_selectedSubjects.join(', ')}',
                        if (_selectedLevel.isNotEmpty) '학교급: $_selectedLevel',
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      setState(() { _selectedSubjects.clear(); _selectedLevel = ''; });
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
                                        '학원 ${_results.length}곳'
                                        '${_userRegion.isNotEmpty && !_hasFilter ? " · $_userRegion" : ""}',
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
                                        itemBuilder: (_, i) => _AcademyTile(academy: _results[i]),
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
        _userRegion.isNotEmpty ? '$_userRegion 학원 후기' : '학원 후기',
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
  const _AcademyTile({required this.academy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = (academy['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final reviewCount = academy['review_count'] as int? ?? 0;
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
