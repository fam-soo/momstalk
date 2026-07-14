import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'refresh_bus.dart';
import 'school_display.dart';

/// 지역/학원 게시판 상단에 붙는 "빠른 지역 전환" 버튼.
///
/// 다자녀 유저가 지금 활성 자녀와 다른 지역의 자녀로 바로 전환하고 싶을 때,
/// 매번 내정보 화면까지 가지 않고 여기서 바로 고를 수 있게 한다
/// (school_board_screen.dart의 자녀 드롭다운과 같은 발상 — active-child API
/// 재사용). 자녀가 1명뿐이면 눌러도 의미가 없으니 숨긴다.
class RegionSwitchButton extends ConsumerStatefulWidget {
  const RegionSwitchButton({super.key});

  @override
  ConsumerState<RegionSwitchButton> createState() => _RegionSwitchButtonState();
}

class _RegionSwitchButtonState extends ConsumerState<RegionSwitchButton> {
  List<Map<String, dynamic>> _children = [];
  int? _activeChildId;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/auth/me');
      final profile = Map<String, dynamic>.from(resp.data as Map);
      final children = (profile['children'] as List? ?? [])
          .map((c) => Map<String, dynamic>.from(c as Map))
          .toList();
      if (mounted) {
        setState(() {
          _children = children;
          _activeChildId = profile['active_child_id'] as int?;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _switchTo(int childId) async {
    if (childId == _activeChildId) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/auth/me/active-child/$childId');
      bumpBoardRefresh(ref);
      if (mounted) setState(() => _activeChildId = childId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('전환 실패: $e')));
      }
    }
  }

  String _childLabel(Map<String, dynamic> c) {
    if (c['school_type'] == 'preschool') {
      final region = c['region'] as String?;
      return (region != null && region.isNotEmpty) ? '$region · 미취학' : '미취학';
    }
    final school = shortSchoolName(c['school_name'] as String?);
    final grade = c['grade'] as int?;
    return grade != null ? '$school $grade학년' : school;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _children.length < 2) return const SizedBox.shrink();
    return PopupMenuButton<int>(
      tooltip: '자녀 전환으로 지역 바꾸기',
      icon: const Icon(Icons.sync_alt),
      onSelected: _switchTo,
      itemBuilder: (_) => _children.map((c) {
        final id = c['id'] as int;
        return PopupMenuItem<int>(
          value: id,
          child: Row(children: [
            if (id == _activeChildId) const Icon(Icons.check, size: 16, color: Colors.blue)
            else const SizedBox(width: 16),
            const SizedBox(width: 8),
            Text(_childLabel(c)),
          ]),
        );
      }).toList(),
    );
  }
}
