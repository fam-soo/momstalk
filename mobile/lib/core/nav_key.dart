import 'package:flutter/material.dart';

/// GoRouter의 rootNavigatorKey. api_client.dart(세션 만료 시 로그인 화면으로
/// 강제 이동)와 router.dart가 서로를 import하지 않고 공유하기 위해 별도
/// 파일로 분리했다.
final rootNavKey = GlobalKey<NavigatorState>();
