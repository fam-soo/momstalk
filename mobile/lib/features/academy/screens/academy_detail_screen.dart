import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';

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
  bool _kakaoLoading = false;
  bool _reviewsLocked = false;  // 로그인 미인증
  int _totalReviews = 0;
  bool _academyLocked = false;   // 이 학원의 후기(기본 소개 + 사용자 후기) 전체 가림 처리 여부
  int _unlockedAcademyCount = 0;
  int? _unlockedAcademyLimit;    // null = 무제한
  int _nextUnlockAt = 1;
  int _userReviewCount = 0;

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
        final reviewsResp = await dio.get('/academies/${widget.academyId}/reviews');
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

  Future<void> _openKakaoMap() async {
    setState(() => _kakaoLoading = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/academies/${widget.academyId}/kakao-place');
      final data = resp.data as Map<String, dynamic>;
      final placeUrl = data['place_url'] as String?;
      final found = data['found'] as bool? ?? false;
      if (!mounted) return;
      if (!found || placeUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('카카오맵에서 해당 학원을 찾을 수 없습니다.')),
        );
        return;
      }
      final uri = Uri.parse(placeUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('카카오맵을 열 수 없습니다.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _kakaoLoading = false);
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
    final reviewCount = _academy!['review_count'] as int? ?? 0;
    final subjects = (_academy!['subjects'] as List?)?.cast<String>() ?? [];
    final isB2b = _academy!['is_b2b'] as bool? ?? false;

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
            color: isB2b ? theme.colorScheme.primaryContainer.withOpacity(0.2) : null,
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
                Row(children: [
                  ...List.generate(5, (i) => Icon(
                    i < rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 15, color: Colors.amber.shade600)),
                  const SizedBox(width: 4),
                  Text(rating > 0 ? rating.toStringAsFixed(1) : '-',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text('후기 $reviewCount개', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  if (subjects.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(child: Text(subjects.join(' · '),
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ]),
              ],
            ),
          ),
          const Divider(height: 1),

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

          // ── 조회 쿼터 배너 ─────────────────────────────
          if (!_reviewsLocked && (_totalReviews > 0 || _seedReviews.isNotEmpty))
            _QuotaBanner(
              academyLocked: _academyLocked,
              unlockedCount: _unlockedAcademyCount,
              unlockedLimit: _unlockedAcademyLimit,
              nextUnlockAt: _nextUnlockAt,
              userReviewCount: _userReviewCount,
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
        ? '후기 $nextUnlockAt건 더 작성하면 열람 가능한 학원 수가 늘어나요 (위 \'후기 작성\' 버튼 이용)'
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
    final schoolName = review['author_school_name'] as String?;
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

