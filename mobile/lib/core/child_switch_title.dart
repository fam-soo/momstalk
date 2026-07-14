import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'refresh_bus.dart';
import 'school_display.dart';

/// AppBar 타이틀 자리에 들어가는 "탭하면 자녀 전환" 위젯 — school_board_screen.dart의
/// _SchoolDropdownTitle과 같은 상호작용 패턴을 지역/학원 게시판에도 통일 적용한다.
/// (예전엔 지역/학원은 별도 아이콘 버튼으로 전환했는데, 학교만 다른 방식이라
/// 헷갈린다는 피드백 — 자녀가 1명뿐이면 눌러도 의미가 없으니 그냥 라벨만 보여준다.)
class ChildSwitchTitle extends ConsumerStatefulWidget {
  /// 활성 자녀 기준 타이틀 문구를 만드는 함수 (예: (region) => '$region 게시판').
  final String Function(Map<String, dynamic>? activeChild) labelBuilder;

  const ChildSwitchTitle({super.key, required this.labelBuilder});

  @override
  ConsumerState<ChildSwitchTitle> createState() => _ChildSwitchTitleState();
}

class _ChildSwitchTitleState extends ConsumerState<ChildSwitchTitle> {
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

  Map<String, dynamic>? get _activeChild {
    for (final c in _children) {
      if (c['id'] == _activeChildId) return c;
    }
    return null;
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
    final title = widget.labelBuilder(_activeChild);
    final textWidget = Text(title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis);

    if (!_loaded || _children.length < 2) return textWidget;

    return PopupMenuButton<int>(
      tooltip: '자녀 전환',
      onSelected: _switchTo,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: textWidget),
        const Icon(Icons.arrow_drop_down),
      ]),
    );
  }
}
