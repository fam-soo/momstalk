import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// 별도 관리자 로그인 폐지 — 일반 카카오 로그인 후 is_admin 계정에서 관리자 버튼으로 진입
class AdminLoginScreen extends StatelessWidget {
  const AdminLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/auth/login');
    });
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
