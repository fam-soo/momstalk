import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../../core/api_client.dart';
import '../../../core/router.dart';
import '../../../core/school_display.dart';
import '../../../core/user_profile_provider.dart';
import 'post_list_widget.dart';

export '../../../core/user_profile_provider.dart' show userProfileProvider;

class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentTab = _tabController.index);
      }
    });
    _registerFcmToken();
  }

  Future<void> _registerFcmToken() async {
    try {
      final messaging = _tryGetMessaging();
      if (messaging == null) return;
      final token = await messaging.getToken();
      if (token == null || !mounted) return;
      final dio = ref.read(dioProvider);
      await dio.post('/auth/me/fcm-token', data: {'token': token});
    } catch (_) {}
  }

  FirebaseMessaging? _tryGetMessaging() {
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<(String label, String boardType, bool locked)> _buildTabs(Map<String, dynamic> profile) {
    final isAdmin = (profile['is_admin'] as bool? ?? false) ||
        (profile['member_grade'] as String? ?? '') == 'admin';
    final isMember = isAdmin || (profile['member_grade'] as String? ?? 'lurker') == 'member';
    final region = profile['region'] as String? ?? '';
    final school = shortSchoolName(profile['school_name'] as String?);
    final grade = profile['grade'] as int? ?? 1;

    if (isAdmin) {
      return [
        ('전체', 'free', false),
        ('전지역 게시판', 'region', false),
        ('전학교 게시판', 'school', false),
        ('전학년', 'grade', false),
      ];
    }
    if (isMember) {
      return [
        ('전체', 'free', false),
        (region.isNotEmpty ? region : '지역', 'region', false),
        (school.isNotEmpty ? school : '학교', 'school', false),
        ('$grade학년', 'grade', false),
      ];
    }
    return [
      ('전체', 'free', false),
      ('지역', 'region', true),
      ('학교', 'school', true),
      ('학년', 'grade', true),
    ];
  }

  void _showAuthBottomSheet({bool isPending = false}) {
    if (isPending) {
      context.push('/auth/pending');
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AuthPromptSheet(
        onStart: () {
          Navigator.pop(ctx);
          context.push('/auth/school-select');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) {
        final isAuthError = err is DioException && err.response?.statusCode == 401;
        if (isAuthError) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => ref.read(routerProvider).go('/auth/login'),
          );
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(body: Center(child: Text('오류: $err')));
      },
      data: (profile) {
        final tabs = _buildTabs(profile);
        final isAdmin = (profile['is_admin'] as bool? ?? false) ||
            (profile['member_grade'] as String? ?? '') == 'admin';
        final isMember = isAdmin || (profile['member_grade'] as String? ?? 'lurker') == 'member';
        final isPending = !isAdmin && (profile['auth_pending'] as bool? ?? false);

        return Scaffold(
          appBar: AppBar(
            title: const Text('MomsTalk', style: TextStyle(fontWeight: FontWeight.bold)),
            bottom: TabBar(
              controller: _tabController,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: tabs.map((t) {
                if (t.$3) {
                  return Tab(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(isPending ? Icons.hourglass_top_rounded : Icons.lock_outline, size: 13),
                      const SizedBox(width: 4),
                      Text(t.$1),
                    ]),
                  );
                }
                return Tab(text: t.$1);
              }).toList(),
              onTap: (index) {
                if (tabs[index].$3) {
                  _tabController.index = _currentTab;
                  _showAuthBottomSheet(isPending: isPending);
                }
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => context.push('/search'),
              ),
              if (!isMember)
                TextButton.icon(
                  onPressed: () => _showAuthBottomSheet(isPending: isPending),
                  icon: Icon(isPending ? Icons.hourglass_top_rounded : Icons.verified_outlined, size: 16),
                  label: Text(isPending ? '심사 중' : '인증'),
                  style: TextButton.styleFrom(
                    foregroundColor: isPending ? Colors.orange : Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
          body: TabBarView(
            controller: _tabController,
            // 지역/학교/학년 변경 시 프로필의 식별값이 바뀌므로 key도 함께 바뀌어
            // Flutter가 새 위젯으로 인식하고 다시 마운트해 최신 데이터를 가져온다.
            // key 없이는 같은 위치의 같은 위젯 타입으로 취급되어 학교를 바꾼 뒤에도
            // 이전 학교의 목록(또는 빈 상태)이 그대로 남아있는 문제가 있었다.
            children: tabs.map((t) {
              if (t.$3) {
                return _LockedBoardPlaceholder(
                  key: ValueKey('locked-${t.$2}'),
                  isPending: isPending,
                  onCertify: () => _showAuthBottomSheet(isPending: isPending),
                );
              }
              final identity = '${profile['school_code']}-${profile['region']}-${profile['grade']}';
              return PostListWidget(
                key: ValueKey('${t.$2}-$identity'),
                boardType: t.$2,
                isAdmin: isAdmin,
              );
            }).toList(),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              if (!isMember) {
                _showAuthBottomSheet(isPending: isPending);
                return;
              }
              context.push('/board/write?board_type=${tabs[_currentTab].$2}');
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('글쓰기'),
          ),
        );
      },
    );
  }
}

// ── 인증 유도 Bottom Sheet ─────────────────────────────

class _AuthPromptSheet extends StatelessWidget {
  final VoidCallback onStart;
  const _AuthPromptSheet({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.school_outlined, color: Theme.of(context).colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('내 지역과 학교 소식을 보려면', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  SizedBox(height: 2),
                  Text('학부모 인증이 필요해요!', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            const _BenefitRow(icon: Icons.location_on_outlined, text: '우리 지역 학부모들의 생생한 이야기'),
            const SizedBox(height: 10),
            const _BenefitRow(icon: Icons.school_outlined, text: '우리 학교 · 학년 전용 게시판'),
            const SizedBox(height: 10),
            const _BenefitRow(icon: Icons.edit_outlined, text: '글쓰기 · 댓글 · DM 전체 기능'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('학교 검색으로 인증 시작하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BenefitRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Text(text, style: const TextStyle(fontSize: 13)),
    ]);
  }
}

// ── 잠긴 게시판 플레이스홀더 ─────────────────────────

class _LockedBoardPlaceholder extends StatelessWidget {
  final VoidCallback onCertify;
  final bool isPending;
  const _LockedBoardPlaceholder({super.key, required this.onCertify, required this.isPending});

  @override
  Widget build(BuildContext context) {
    if (isPending) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.hourglass_top_rounded, size: 56, color: Colors.orange.shade300),
            const SizedBox(height: 16),
            const Text('심사 진행 중', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('알림장 캡처를 검토하고 있어요.\n승인되면 이 게시판을 이용할 수 있습니다.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, height: 1.5)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onCertify,
              icon: const Icon(Icons.hourglass_top_rounded),
              label: const Text('심사 현황 확인'),
            ),
          ]),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('학부모 인증 후 이용 가능', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('내 지역 · 학교 · 학년 게시판은\n학부모 인증을 완료해야 열립니다.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, height: 1.5)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCertify,
            icon: const Icon(Icons.search),
            label: const Text('학교 검색으로 인증하기'),
          ),
        ]),
      ),
    );
  }
}
