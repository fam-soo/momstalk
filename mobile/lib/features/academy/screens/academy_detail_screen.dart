import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/academies/${widget.academyId}'),
        dio.get('/academies/${widget.academyId}/reviews'),
      ]);
      if (mounted) {
        setState(() {
          _academy = Map<String, dynamic>.from(results[0].data);
          _reviews = List<Map<String, dynamic>>.from(results[1].data);
        });
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
        actions: [
          FilledButton.tonal(
            onPressed: () => context
                .push('/academy/${widget.academyId}/review/write')
                .then((_) => _load()),
            child: const Text('후기 작성'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        children: [
          // ── 학원 프로필 ─────────────────────────────────
          Container(
            color: isB2b ? theme.colorScheme.primaryContainer.withOpacity(0.2) : null,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _academy!['name'] as String? ?? '',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isB2b)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('공식 파트너', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
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

          // ── 후기 목록 ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('후기', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          if (_reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.rate_review_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text('아직 후기가 없습니다', style: TextStyle(color: Colors.grey.shade500)),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => context
                          .push('/academy/${widget.academyId}/review/write')
                          .then((_) => _load()),
                      child: const Text('첫 번째 후기를 작성해보세요'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_reviews.length, (i) => _ReviewCard(review: _reviews[i])),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final isAnon = review['is_anonymous'] as bool? ?? true;
    final authorName = isAnon ? '익명' : (review['author_display_name'] as String? ?? '학부모');
    final subject = review['subject'] as String? ?? '';
    final text = review['review_text'] as String? ?? '';
    final schoolName = review['author_school_name'] as String?;
    final grade = review['author_grade'] as int?;
    final schoolInfo = [
      if (schoolName != null && schoolName.isNotEmpty) schoolName,
      if (grade != null) '$grade학년',
    ].join(' ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(authorName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    if (schoolInfo.isNotEmpty)
                      Text(schoolInfo, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
                if (subject.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(subject, style: const TextStyle(fontSize: 11, color: Colors.blue)),
                  ),
                ],
                const Spacer(),
                Row(
                  children: List.generate(5, (i) => Icon(
                    i < rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: Colors.amber.shade600,
                  )),
                ),
              ],
            ),
            if (text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(text, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
            const SizedBox(height: 6),
            // 구조화된 평가 항목
            _ReviewDetail(label: '선생님 스타일', value: review['teacher_style'] as String?),
            _ReviewDetail(label: '숙제량', value: review['homework_level'] as String?),
            _ReviewDetail(label: '성적 향상', value: review['score_improvement'] as String?),
            const SizedBox(height: 4),
            Text(
              review['created_at'] as String? ?? '',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 4),
            Text(
              '이 후기는 작성자 개인 경험을 바탕으로 한 의견입니다.',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
            ),
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
