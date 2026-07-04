import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import '../../../core/api_client.dart';
import '../../../core/constants.dart';
import '../../../core/router.dart';

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
        kakaoToken = await UserApi.instance.loginWithKakaoAccount(
          prompts: [Prompt.selectAccount],
        );
      }
      final dio = ref.read(dioProvider);
      final resp = await dio.post('/auth/kakao', data: {'kakao_access_token': kakaoToken.accessToken});
      final storage = ref.read(tokenStorageProvider);
      await storage.write(AppConstants.tokenKey, resp.data['access_token'] as String);
      await storage.write(AppConstants.refreshTokenKey, resp.data['refresh_token'] as String);

      final meResp = await dio.get('/auth/me');
      _wasAlreadyMember = (meResp.data['member_grade'] as String?) == 'member';
      setState(() { _isLoggedIn = true; _loggingIn = false; });
      await _join();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('로그인 실패: $e')));
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
    final isUsed = _inviteInfo?['is_used'] as bool? ?? false;
    final maxGrade = schoolType == 'elementary' ? 6 : 3;
    final schoolTypeLabel = switch (schoolType) {
      'elementary' => '초등학교',
      'middle' => '중학교',
      'high' => '고등학교',
      _ => '',
    };
    // 이미 사용된 링크는 기존 정회원(자녀 추가 목적)만 허용
    final isBlocked = isUsed && !_wasAlreadyMember;
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
                ]),
              ),
            ),
            const SizedBox(height: 24),
            const Text('자녀 학년', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _grade.clamp(1, maxGrade),
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: List.generate(maxGrade, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}학년'))),
              onChanged: isBusy ? null : (v) => setState(() => _grade = v ?? 1),
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
                  '이미 사용된 초대 링크입니다.\n새 초대 링크를 받아 다시 시도해주세요.',
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
