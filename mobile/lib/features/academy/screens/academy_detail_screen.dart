import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/school_display.dart';

/// 수업당 평균 정원을 10/20/30/50/100명 단위 구간으로 표시 — 원본 숫자는
/// DB에 그대로 저장돼 있고(academies.avg_class_capacity), 구간 기준은
/// 여기서만 바꾸면 재수집 없이 라벨링을 조정할 수 있다.
String _capacityBucketLabel(double avgCapacity) {
  if (avgCapacity <= 10) return '10명 이하';
  if (avgCapacity <= 20) return '20명 이하';
  if (avgCapacity <= 30) return '30명 이하';
  if (avgCapacity <= 50) return '50명 이하';
  if (avgCapacity <= 100) return '100명 이하';
  return '100명 초과';
}

/// 접기/펼치기 토글을 보여줄지 판단 — 접을 내용이 아예 없으면 토글 자체를 숨긴다.
bool _hasExtraAcademyInfo(
  List<String> subjects,
  String? businessHours,
  bool? shuttleBus,
  double? avgClassCapacity,
  double? avgTuition, [
  List<String> facilities = const [],
  List<String> curriculumFocus = const [],
  List<String> classStyle = const [],
]) {
  return subjects.isNotEmpty ||
      (businessHours != null && businessHours.isNotEmpty) ||
      shuttleBus != null ||
      avgClassCapacity != null ||
      avgTuition != null ||
      facilities.isNotEmpty ||
      curriculumFocus.isNotEmpty ||
      classStyle.isNotEmpty;
}

class AcademyDetailScreen extends ConsumerStatefulWidget {
  final int academyId;
  const AcademyDetailScreen({super.key, required this.academyId});

  @override
  ConsumerState<AcademyDetailScreen> createState() => _AcademyDetailScreenState();
}

class _AcademyDetailScreenState extends ConsumerState<AcademyDetailScreen> {
  Map<String, dynamic>? _academy;
  List<Map<String, dynamic>> _reviews = [];
  List<Map<String, dynamic>> _seedReviews = [];
  List<Map<String, dynamic>> _userReviews = [];
  bool _loading = true;
  bool _reviewsLocked = false;  // 로그인 미인증
  int _totalReviews = 0;
  bool _academyLocked = false;   // 이 학원의 후기(기본 소개 + 사용자 후기) 전체 가림 처리 여부
  int _unlockedAcademyCount = 0;
  int? _unlockedAcademyLimit;    // null = 무제한
  int _nextUnlockAt = 1;
  int _userReviewCount = 0;
  bool _infoExpanded = true;  // 학원 기본정보 접기/펼치기 — 기본은 펼침
  bool _excludePreschool = false;  // 미취학 맘 후기 제외 토글

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      if (!await launchUrl(uri)) throw Exception();
    } catch (_) {
      // 데스크톱 브라우저 등 tel: 링크를 처리할 앱이 없는 환경 — 복사로 대체
      await _copyPhone(phone);
    }
  }

  Future<void> _copyPhone(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전화번호($phone)를 복사했어요.'), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final academyResp = await dio.get('/academies/${widget.academyId}');
      if (mounted) {
        setState(() => _academy = Map<String, dynamic>.from(academyResp.data));
      }

      // 리뷰 로드는 학원 정보와 분리 — 실패해도 학원 정보는 표시
      try {
        final reviewsResp = await dio.get(
          '/academies/${widget.academyId}/reviews',
          queryParameters: {'exclude_preschool': _excludePreschool},
        );
        final data = reviewsResp.data as Map<String, dynamic>;
        final quotaInfo = data['quota_info'] as Map<String, dynamic>? ?? {};
        if (mounted) {
          setState(() {
            _reviews = List<Map<String, dynamic>>.from(data['reviews'] as List? ?? []);
            _seedReviews = _reviews.where((r) => r['is_seed'] == true).toList();
            _userReviews = _reviews.where((r) => r['is_seed'] != true).toList();
            _totalReviews = quotaInfo['total'] as int? ?? 0;
            _academyLocked = quotaInfo['academy_locked'] as bool? ?? false;
            _unlockedAcademyCount = quotaInfo['unlocked_academy_count'] as int? ?? 0;
            _unlockedAcademyLimit = quotaInfo['unlocked_academy_limit'] as int?;
            _nextUnlockAt = quotaInfo['next_unlock_at'] as int? ?? 1;
            _userReviewCount = quotaInfo['user_review_count'] as int? ?? 0;
            _reviewsLocked = false;
          });
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
          if (mounted) setState(() => _reviewsLocked = true);
        }
      } catch (_) {
        // 기타 오류 — 빈 목록 유지
      }
    } catch (e) {
      // 학원 정보 자체 로드 실패
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('학원 정보를 불러오지 못했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_academy == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('학원 정보를 불러올 수 없습니다.')));
    }

    final theme = Theme.of(context);
    final rating = (_academy!['avg_rating'] as num?)?.toDouble() ?? 0.0;
    // review_count는 AI 요약(seed) 후기까지 포함된 수치라 아래 "후기" 목록에
    // 실제로 보이는 사용자 후기 개수와 어긋나 헷갈릴 수 있다(예: seed만 1건
    // 있어도 "후기 1개"로 보이는데 정작 목록엔 "아직 후기가 없습니다"만 뜸) —
    // 상단 표시는 user_review_count(사용자 작성분만)로 목록과 맞춘다.
    final reviewCount = _academy!['user_review_count'] as int? ?? 0;
    final subjects = (_academy!['subjects'] as List?)?.cast<String>() ?? [];
    final isB2b = _academy!['is_b2b'] as bool? ?? false;
    final businessHours = _academy!['business_hours'] as String?;
    final shuttleBus = _academy!['shuttle_bus'] as bool?;
    final avgClassCapacity = (_academy!['avg_class_capacity'] as num?)?.toDouble();
    final avgTuition = (_academy!['avg_tuition_10k_won'] as num?)?.toDouble();
    final facilities = (_academy!['facilities'] as List?)?.cast<String>() ?? [];
    final curriculumFocus = (_academy!['curriculum_focus'] as List?)?.cast<String>() ?? [];
    final classStyle = (_academy!['class_style'] as List?)?.cast<String>() ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(_academy!['name'] as String? ?? '학원 상세'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/academy'),
        ),
        actions: const [],
      ),
      body: ListView(
        children: [
          // ── 학원 프로필 ─────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isB2b)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('공식 파트너', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 15, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(child: Text(_academy!['address'] as String? ?? '', style: TextStyle(color: Colors.grey.shade700, fontSize: 13))),
                  ],
                ),
                if ((_academy!['phone'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _callPhone(_academy!['phone'] as String),
                    onLongPress: () => _copyPhone(_academy!['phone'] as String),
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Icon(Icons.phone_outlined, size: 15, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(_academy!['phone'] as String,
                            style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, decoration: TextDecoration.underline)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // 별점/후기수는 항상 한 줄 — 나머지 항목(과목/설립/영업시간/셔틀버스)은
                // 값이 있을 때만 각자 줄을 차지한다(예전엔 전부 한 줄에 이어붙여서
                // 정제 안 된 값이 섞이면 그대로 노출되던 문제가 있었음).
                Row(children: [
                  ...List.generate(5, (i) => Icon(
                    i < rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 15, color: Colors.amber.shade600)),
                  const SizedBox(width: 4),
                  Text(rating > 0 ? rating.toStringAsFixed(1) : '-',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text('후기 $reviewCount개', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  if (_hasExtraAcademyInfo(subjects, businessHours, shuttleBus, avgClassCapacity, avgTuition, facilities, curriculumFocus, classStyle)) ...[
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() => _infoExpanded = !_infoExpanded),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(_infoExpanded ? '접기' : '더보기', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          Icon(_infoExpanded ? Icons.expand_less : Icons.expand_more, size: 16, color: Colors.grey.shade600),
                        ]),
                      ),
                    ),
                  ],
                ]),
                if (_infoExpanded) ...[
                  if (subjects.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6, runSpacing: 4,
                      children: subjects.map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(s, style: TextStyle(fontSize: 11.5, color: theme.colorScheme.primary)),
                      )).toList(),
                    ),
                  ],
                  if (businessHours != null && businessHours.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.schedule_outlined, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(child: Text(businessHours.replaceAll(' / ', '\n'),
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.4))),
                    ]),
                  ],
                  if (shuttleBus != null) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.directions_bus_outlined, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(shuttleBus ? '셔틀버스 있음' : '셔틀버스 없음', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                    ]),
                  ],
                  if (avgClassCapacity != null) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.groups_outlined, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text('정원 ${_capacityBucketLabel(avgClassCapacity)}', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                    ]),
                  ],
                  if (avgTuition != null) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.payments_outlined, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text('학원비 평균 ${avgTuition.toStringAsFixed(0)}만원', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                    ]),
                  ],
                  if (facilities.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.check_circle_outline, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(child: Text(facilities.join(' · '),
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700))),
                    ]),
                  ],
                  if (curriculumFocus.isNotEmpty || classStyle.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6, runSpacing: 4,
                      children: [...curriculumFocus, ...classStyle].map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('#$s', style: TextStyle(fontSize: 11.5, color: Colors.purple.shade700)),
                      )).toList(),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const Divider(height: 1),

          // ── 조회 쿼터 배너 ─────────────────────────────
          // 학원 목록 화면과 동일하게 상단 요약 바로 아래에 배치한다.
          if (!_reviewsLocked && (_totalReviews > 0 || _seedReviews.isNotEmpty))
            _QuotaBanner(
              academyLocked: _academyLocked,
              unlockedCount: _unlockedAcademyCount,
              unlockedLimit: _unlockedAcademyLimit,
              nextUnlockAt: _nextUnlockAt,
              userReviewCount: _userReviewCount,
            ),

          // ── 학원 소개 (seed 후기) ────────────────────────
          if (_seedReviews.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('학원 소개', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text('AI 요약 정보', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
            ),
            ..._seedReviews.map((r) => _ReviewCard(review: r, academyId: widget.academyId, onChanged: _load)),
            const Divider(height: 1),
          ],

          // ── 후기 목록 ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Text('후기', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                if (_totalReviews > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text('$_totalReviews개', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    setState(() => _excludePreschool = !_excludePreschool);
                    _load();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _excludePreschool ? theme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _excludePreschool ? theme.colorScheme.primary : Colors.grey.shade400,
                      ),
                    ),
                    child: Text('미취학맘 제외',
                        style: TextStyle(
                          fontSize: 11,
                          color: _excludePreschool ? theme.colorScheme.primary : Colors.grey.shade600,
                          fontWeight: _excludePreschool ? FontWeight.bold : FontWeight.normal,
                        )),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context
                      .push('/academy/${widget.academyId}/review/write')
                      .then((_) => _load()),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('후기 작성'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
          ),

          if (_reviewsLocked)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.lock_outline, size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text('로그인 후 후기를 확인하세요', style: TextStyle(color: Colors.grey.shade500)),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => context.go('/auth/login'),
                      child: const Text('로그인'),
                    ),
                  ],
                ),
              ),
            )
          else if (_userReviews.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.rate_review_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text('아직 후기가 없습니다', style: TextStyle(color: Colors.grey.shade500)),
                    const SizedBox(height: 4),
                    Text('첫 번째 후기를 작성해보세요', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  ],
                ),
              ),
            )
          else ...[
            ..._userReviews.map((r) => _ReviewCard(review: r, academyId: widget.academyId, onChanged: _load)),
          ],

        ],
      ),
    );
  }
}

// ── 조회 쿼터 배너 ──────────────────────────────────────────────

class _QuotaBanner extends StatelessWidget {
  final bool academyLocked;
  final int unlockedCount;
  final int? unlockedLimit;   // null = 무제한
  final int nextUnlockAt;
  final int userReviewCount;

  const _QuotaBanner({
    required this.academyLocked,
    required this.unlockedCount,
    required this.unlockedLimit,
    required this.nextUnlockAt,
    required this.userReviewCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!academyLocked) {
      // 이 학원은 이미 열람 해금됨
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 14, color: Colors.green.shade600),
            const SizedBox(width: 6),
            Text(
              unlockedLimit == null ? '이 학원 후기 전체 조회 가능' : '이 학원 후기 전체 조회 가능 (열람 가능 학원 $unlockedCount/$unlockedLimit곳)',
              style: TextStyle(fontSize: 12, color: Colors.green.shade700),
            ),
          ],
        ),
      );
    }

    // 잠김 — 이 학원의 후기(기본 소개 + 사용자 후기)가 가림 처리됨
    final limitLabel = '이 학원 후기 가림 처리됨 (열람 가능 학원 $unlockedCount/$unlockedLimit곳)';
    final unlockMsg = nextUnlockAt > 0
        ? '후기 $nextUnlockAt건 더 작성하면 열람 가능한 학원 수가 늘어나요 (아래 \'후기 작성\' 버튼 이용)'
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 15, color: theme.colorScheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  limitLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                if (unlockMsg.isNotEmpty)
                  Text(unlockMsg, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 후기 카드 ────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.grey.shade600),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  final int academyId;
  final VoidCallback? onChanged;
  const _ReviewCard({required this.review, required this.academyId, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final isSeed = review['is_seed'] as bool? ?? false;
    final isViewLimited = review['is_view_limited'] as bool? ?? false;
    final isOwn = review['is_own'] as bool? ?? false;
    final isAnon = review['is_anonymous'] as bool? ?? true;
    final authorName = isSeed
        ? '맘스톡'
        : (isAnon ? '익명' : (review['author_display_name'] as String? ?? '학부모'));
    final subjects = (review['subjects'] as List?)?.cast<String>() ?? [];
    final teacherStyles = (review['teacher_styles'] as List?)?.cast<String>() ?? [];
    final text = review['review_text'] as String? ?? '';
    final homeworkLevel = review['homework_level'] as String? ?? '';
    final scoreImprovement = review['score_improvement'] as String? ?? '';
    final schoolName = shortSchoolName(review['author_school_name'] as String?);
    final grade = review['author_grade'] as int?;
    final schoolInfo = isSeed
        ? ''
        : [
            if (schoolName != null && schoolName.isNotEmpty) schoolName,
            if (grade != null) '$grade학년',
          ].join(' ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      color: isViewLimited
          ? Colors.grey.shade50
          : isSeed
              ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.4)
              : null,
      shape: isSeed
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1번째 줄 — 작성자·학교·과목/스타일 태그 + 별점
            Row(
              children: [
                if (!isViewLimited)
                  Flexible(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: authorName,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isSeed ? theme.colorScheme.primary : null),
                        ),
                        if (schoolInfo.isNotEmpty)
                          TextSpan(text: '  $schoolInfo', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, size: 13, color: Colors.grey),
                        SizedBox(width: 4),
                        Text('후기 열람 잠금', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                const Spacer(),
                Row(
                  children: List.generate(5, (i) => Icon(
                    i < rating ? Icons.star : Icons.star_border,
                    size: 13,
                    color: isViewLimited ? Colors.grey.shade300 : Colors.amber.shade600,
                  )),
                ),
                if (isOwn) ...[
                  const SizedBox(width: 2),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => context
                        .push('/academy/$academyId/review/write', extra: review)
                        .then((_) => onChanged?.call()),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.edit_outlined, size: 15, color: theme.colorScheme.primary),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            // 후기 본문 — 잠금 상태만 한 줄 미리보기, 잠금 해제 시 전체 내용 표시(줄 수 제한 없음)
            if (text.isNotEmpty)
              Text(text,
                  maxLines: isViewLimited ? 1 : null,
                  overflow: isViewLimited ? TextOverflow.ellipsis : null,
                  style: TextStyle(fontSize: 13, height: 1.4, color: isViewLimited ? Colors.grey.shade500 : null))
            else if (isViewLimited)
              Text('후기를 작성하면 전체 내용을 볼 수 있어요.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
            // 과목·선생님 스타일·숙제량·성적 향상 — 작성 시 선택한 항목을 잘림 없이 전부 칩으로 노출
            if (!isViewLimited && (subjects.isNotEmpty || teacherStyles.isNotEmpty || homeworkLevel.isNotEmpty || scoreImprovement.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ...subjects.map((s) => _InfoChip(icon: Icons.menu_book_outlined, label: s)),
                  ...teacherStyles.map((s) => _InfoChip(icon: Icons.psychology_outlined, label: s)),
                  if (homeworkLevel.isNotEmpty) _InfoChip(icon: Icons.assignment_outlined, label: '숙제량 $homeworkLevel'),
                  if (scoreImprovement.isNotEmpty) _InfoChip(icon: Icons.trending_up, label: scoreImprovement),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

