import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
  int _readableReviews = 0;
  bool _isLimited = false;
  int _nextUnlockAt = 1;
  int _userReviewCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
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
            _readableReviews = quotaInfo['readable'] as int? ?? _totalReviews;
            _isLimited = quotaInfo['is_limited'] as bool? ?? false;
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
                if (_academy!['phone'] != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 15, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(_academy!['phone'] as String, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                if (subjects.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: subjects.map((s) => Chip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: theme.colorScheme.secondaryContainer.withOpacity(0.5),
                    )).toList(),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.star, size: 20, color: Colors.amber.shade600),
                    const SizedBox(width: 4),
                    Text(
                      rating > 0 ? rating.toStringAsFixed(1) : '-',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text('후기 $reviewCount개', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
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
            ..._seedReviews.map((r) => _ReviewCard(review: r)),
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
          if (!_reviewsLocked && _totalReviews > 0)
            _QuotaBanner(
              readable: _readableReviews,
              total: _totalReviews,
              isLimited: _isLimited,
              nextUnlockAt: _nextUnlockAt,
              userReviewCount: _userReviewCount,
              onWriteTap: () => context.push('/academy/${widget.academyId}/review/write').then((_) => _load()),
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
            ..._userReviews.map((r) => _ReviewCard(review: r)),
            // 하단 잠금 안내 (제한 중일 때)
            if (_isLimited)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/academy/${widget.academyId}/review/write').then((_) => _load()),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: Text('후기 $_nextUnlockAt건 작성하면 더 보기'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade600,
                    textStyle: const TextStyle(fontSize: 13),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ),
          ],

        ],
      ),
    );
  }
}

// ── 조회 쿼터 배너 ──────────────────────────────────────────────

class _QuotaBanner extends StatelessWidget {
  final int readable;
  final int total;
  final bool isLimited;
  final int nextUnlockAt;
  final int userReviewCount;
  final VoidCallback onWriteTap;

  const _QuotaBanner({
    required this.readable,
    required this.total,
    required this.isLimited,
    required this.nextUnlockAt,
    required this.userReviewCount,
    required this.onWriteTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!isLimited) {
      // 전체 열람 가능 — 간단히 상태만 표시
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
              '전체 $total개 후기 조회 가능',
              style: TextStyle(fontSize: 12, color: Colors.green.shade700),
            ),
          ],
        ),
      );
    }

    // 제한 중 — "N/M 조회 가능" 배너
    final limitLabel = userReviewCount == 0 ? '제목만 조회 가능' : '$readable/$total 조회 가능';
    final unlockMsg = nextUnlockAt > 0
        ? '후기 $nextUnlockAt건 더 작성하면 ${userReviewCount == 0 ? "내용" : "더 많이"} 열람'
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
          TextButton(
            onPressed: onWriteTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('후기 작성'),
          ),
        ],
      ),
    );
  }
}

// ── 후기 카드 ────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final isSeed = review['is_seed'] as bool? ?? false;
    final isViewLimited = review['is_view_limited'] as bool? ?? false;
    final isAnon = review['is_anonymous'] as bool? ?? true;
    final authorName = isSeed
        ? '맘스톡'
        : (isAnon ? '익명' : (review['author_display_name'] as String? ?? '학부모'));
    final subjects = (review['subjects'] as List?)?.cast<String>() ?? [];
    final teacherStyles = (review['teacher_styles'] as List?)?.cast<String>() ?? [];
    final text = review['review_text'] as String? ?? '';
    final schoolName = review['author_school_name'] as String?;
    final grade = review['author_grade'] as int?;
    final schoolInfo = isSeed
        ? ''
        : [
            if (schoolName != null && schoolName.isNotEmpty) schoolName,
            if (grade != null) '$grade학년',
          ].join(' ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!isViewLimited)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(authorName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isSeed ? theme.colorScheme.primary : null)),
                      if (schoolInfo.isNotEmpty)
                        Text(schoolInfo, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  )
                else
                  Row(
                    children: [
                      Icon(Icons.lock_outline, size: 13, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text('후기 열람 잠금', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                    ],
                  ),
                if (!isViewLimited && subjects.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Wrap(
                    spacing: 4,
                    children: subjects.map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(s, style: const TextStyle(fontSize: 11, color: Colors.blue)),
                    )).toList(),
                  ),
                ],
                const Spacer(),
                Row(
                  children: List.generate(5, (i) => Icon(
                    i < rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: isViewLimited ? Colors.grey.shade300 : Colors.amber.shade600,
                  )),
                ),
              ],
            ),
            if (isViewLimited) ...[
              const SizedBox(height: 6),
              Text('후기를 작성하면 내용을 볼 수 있습니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
            ],
            if (!isViewLimited && text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(text, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
            const SizedBox(height: 6),
            if (!isSeed && !isViewLimited) ...[
              if (teacherStyles.isNotEmpty)
                _ReviewDetail(label: '선생님 스타일', value: teacherStyles.join(' · ')),
              _ReviewDetail(label: '숙제량', value: review['homework_level'] as String?),
              _ReviewDetail(label: '성적 향상', value: review['score_improvement'] as String?),
            ],
            if (!isViewLimited) ...[
              const SizedBox(height: 4),
              Text(
                isSeed
                    ? '수강생 후기를 바탕으로 AI가 요약한 정보입니다.'
                    : '이 후기는 작성자 개인 경험을 바탕으로 한 의견입니다.',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReviewDetail extends StatelessWidget {
  final String label;
  final String? value;
  const _ReviewDetail({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Text(value!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
