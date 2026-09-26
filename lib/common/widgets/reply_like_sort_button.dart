import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/models/common/reply/reply_sort_type.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 所有主评论区和楼中楼共用的“点赞 / 最热 / 最新”排序栏。
class ReplyLikeSortButton extends StatelessWidget {
  const ReplyLikeSortButton({
    super.key,
    required this.controller,
    required this.colorScheme,
  });

  final ReplyController controller;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final byLikes = controller.sortByLikes.value;
      final serverSort = controller.sortType.value;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(
            label: '点赞',
            selected: byLikes,
            onPressed: controller.selectLikeSort,
          ),
          _button(
            label: '最热',
            selected: !byLikes && serverSort != ReplySortType.time,
            onPressed: () => controller.selectServerSort(ReplySortType.hot),
          ),
          _button(
            label: '最新',
            selected: !byLikes && serverSort == ReplySortType.time,
            onPressed: () => controller.selectServerSort(ReplySortType.time),
          ),
        ],
      );
    });
  }

  Widget _button({
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final color = selected ? colorScheme.primary : colorScheme.outline;
    return TextButton(
      style: Style.buttonStyle,
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: color,
        ),
      ),
    );
  }
}
