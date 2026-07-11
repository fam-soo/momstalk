import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';
import '../../../core/kakao_login_helper.dart';
import '../../../core/router.dart';
import '../../../core/saved_accounts.dart';

/// 초대 링크(/invite/{token}) 진입 화면.
/// 비로그인 상태라면 카카오 로그인 후 바로 가입 처리.
class InviteJoinScreen extends ConsumerStatefulWidget {
  final String token;
  const InviteJoinScreen({super.key, required this.token});

  @override
  ConsumerState<InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends ConsumerState<InviteJoinScreen> {
  Map<String, dynamic>? _inviteInfo;
  bool _loading = true;
  String? _error;
  int _grade = 1;
  int? _classNum;
  bool _joining = false;
  bool _loggingIn = false;
  bool _isLoggedIn = false;
  bool _wasAlreadyMember = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final token = await ref.read(tokenStorageProvider).read(AppConstants.tokenKey);
    _isLoggedIn = token != null;
    if (_isLoggedIn) {
      try {
        final dio = ref.read(dioProvider);
        final me = await dio.get('/auth/me');
        _wasAlreadyMember = (me.data['member_grade'] as String?) == 'member';
      } catch (_) {}
    }
    await _loadInvite();
  }

  Future<void> _loadInvite() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/invite/${widget.token}');
      setState(() => _inviteInfo = Map<String, dynamic>.from(resp.data));
    } catch (e) {
      setState(() => _error = '유효하지 않은 초대 링크입니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _kakaoLoginThenJoin() async {
    setState(() => _loggingIn = true);
    try {
      OAuthToken kakaoToken;
      if (!kIsWeb && await isKakaoTalkInstalled()) {
        kakaoToken = await UserApi.instance.loginWithKakaoTalk();
      } else {
        // login_screen.dart와 동일한 정책: 이 기기에서 처음 로그인하는 경우에만
        // Prompt.login으로 계정 선택 화면을 강제하고, 그 외에는 prompts를 생략해
        // 기존 세션을 재사용(2단계 인증 재요구 방지)한다.
        final hasLoggedInBefore = await SavedAccountsStorage.hasLoggedInBefore();
        kakaoToken = await UserApi.instance.loginWithKakaoAccount(
          prompts: hasLoggedInBefore ? null : [Prompt.login],
        );
      }
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/auth/kakao', data: {'kakao_access_token': kakaoToken.accessToken});
      final storage = ref.read(tokenStorageProvider);
      await storage.write(AppConstants.tokenKey, resp.data['access_token'] as String);
      await storage.write(AppConstants.refreshTokenKey, resp.data['refresh_token'] as String);
      await SavedAccountsStorage.markLoggedIn();

      final meResp = await dio.get('/auth/me');
      _wasAlreadyMember = (meResp.data['member_grade'] as String?) == 'member';
      setState(() { _isLoggedIn = true; _loggingIn = false; });
      await _join();
    } on DioException catch (e) {
      // login_screen.dart의 계정 상태(403 정지/차단)·요청 제한(429) 처리와
      // 동일하게 맞춤 — 예전엔 이 화면만 raw DioException.toString()을 그대로
      // 스낵바에 보여줘서 초대 링크로 가입하는 사람에게 유독 알아보기 어려운
      // 오류 문구가 노출됐다.
      if (mounted) {
        setState(() => _loggingIn = false);
        final statusCode = e.response?.statusCode;
        if (statusCode == 403) {
          final detail = e.response?.data?['detail'] as String? ?? '가입이 제한된 계정입니다.';
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('로그인 불가'),
              content: Text(detail),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인'))],
            ),
          );
        } else if (statusCode == 429) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('잠시 후 다시 시도해주세요. (요청 횟수 초과)')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('로그인에 실패했습니다. 잠시 후 다시 시도해주세요.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mapKakaoSdkError(e.toString()))));
        setState(() => _loggingIn = false);
      }
    }
  }

  Future<void> _join() async {
    if (!_isLoggedIn) {
      await _kakaoLoginThenJoin();
      return;
    }

    setState(() => _joining = true);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/auth/invite/use', data: {
        'token': widget.token,
        'grade': _grade,
        'class_num': _classNum,
      });
      if (mounted) {
        final msg = _wasAlreadyMember
            ? '자녀 학교가 추가되었습니다!'
            : '정회원 가입이 완료되었습니다!';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        ref.read(routerProvider).go(_wasAlreadyMember ? '/my' : '/region');
      }
    } catch (e) {
      final detail = _extractDetail(e.toString());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $detail')));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  String _extractDetail(String err) {
    // DioException message에서 백엔드 detail 추출
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(err);
    return match?.group(1) ?? err;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    if (_error != null) {
      return Scaffold(
        body: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.link_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => ref.read(routerProvider).go('/region'),
              child: const Text('홈으로'),
            ),
          ]),
        )),
      );
    }

    final schoolName = _inviteInfo?['school_name'] as String? ?? '';
    final schoolType = _inviteInfo?['school_type'] as String? ?? 'elementary';
    final isFull = _inviteInfo?['is_full'] as bool? ?? (_inviteInfo?['is_used'] as bool? ?? false);
    final useCount = _inviteInfo?['use_count'] as int?;
    final maxUses = _inviteInfo?['max_uses'] as int?;
    final maxGrade = schoolType == 'elementary' ? 6 : 3;
    final schoolTypeLabel = switch (schoolType) {
      'elementary' => '초등학교',
      'middle' => '중학교',
      'high' => '고등학교',
      _ => '',
    };
    // 이미 사용된 링크는 기존 정회원(자녀 추가 목적)만 허용
    final isBlocked = isFull && !_wasAlreadyMember;
    final isBusy = _joining || _loggingIn;

    // 학년이 범위를 벗어나면 리셋
    if (_grade > maxGrade) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _grade = 1);
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(_wasAlreadyMember ? '자녀 학교 추가' : '초대 링크로 가입')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const Icon(Icons.school_outlined, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    schoolName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  if (schoolTypeLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(schoolTypeLabel,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _wasAlreadyMember ? '이 학교를 자녀 학교로 추가합니다' : '학부모 커뮤니티 초대',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  if (!_wasAlreadyMember && useCount != null && maxUses != null) ...[
                    const SizedBox(height: 6),
                    Text('지금까지 $useCount / $maxUses명 참여',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 24),
            const Text('자녀 학년', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: List.generate(maxGrade, (i) {
                final g = i + 1;
                final selected = _grade.clamp(1, maxGrade) == g;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < maxGrade - 1 ? 6 : 0),
                    child: GestureDetector(
                      onTap: isBusy ? null : () => setState(() => _grade = g),
                      child: Container(
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                          border: Border.all(
                            color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$g학년',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                            color: selected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            const Text('반 (선택)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: _classNum,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '반 선택 안함'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('선택 안함')),
                ...List.generate(15, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}반'))),
              ],
              onChanged: isBusy ? null : (v) => setState(() => _classNum = v),
            ),
            const Spacer(),
            if (isBlocked) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Text(
                  '이 초대 링크는 참여 인원이 가득 찼습니다.\n새 초대 링크를 받아 다시 시도해주세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.red),
                ),
              ),
              const SizedBox(height: 12),
            ] else if (!_isLoggedIn) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Text(
                  '가입하려면 카카오 로그인이 필요합니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: isBusy || isBlocked ? null : _join,
              icon: isBusy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_isLoggedIn ? Icons.check : Icons.login),
              label: Text(
                _loggingIn
                    ? '카카오 로그인 중...'
                    : _joining
                        ? '가입 중...'
                        : _isLoggedIn
                            ? (_wasAlreadyMember ? '자녀 추가하기' : '가입하기')
                            : '카카오 로그인 후 가입하기',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
