import 'package:flutter/material.dart';

/// 게시판 안에서 별도 화면으로 이동하지 않고 그 자리에서 검색하는 AppBar.
/// StatefulShellRoute의 하단 네비 안에 그대로 남아있으므로(별도 라우트로
/// push하지 않음) 검색 중에도 하단 탭이 사라지지 않는다.
/// academy_screen.dart의 인라인 검색 UI와 같은 패턴을 공용 위젯으로 뺐다.
class BoardSearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final VoidCallback onSubmitted;
  final VoidCallback onClose;

  const BoardSearchAppBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onClose,
    this.hintText = '게시글 검색',
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onClose),
      titleSpacing: 0,
      title: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
          hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
        ),
        style: const TextStyle(fontSize: 16),
        onSubmitted: (_) => onSubmitted(),
      ),
      actions: [
        if (controller.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '검색어 지우기',
            onPressed: () {
              controller.clear();
              onSubmitted();
            },
          ),
        TextButton(onPressed: onSubmitted, child: const Text('검색')),
      ],
    );
  }
}
