import 'package:PiliPlus/models/common/reply/reply_sort_type.dart';
import 'package:PiliPlus/models/common/search/search_filter_mode.dart';
import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:PiliPlus/utils/reply_quality_filter.dart';
import 'package:PiliPlus/utils/search_quality_filter.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get qualitySettings => [
  SwitchModel(
    title: '启用搜索过滤',
    subtitle: '完全本地判断，不额外请求视频详情；关闭后搜索结果保持原样',
    leading: const Icon(Icons.manage_search_outlined),
    setKey: SettingBoxKey.searchFilterEnabled,
    defaultVal: Pref.searchFilterEnabled,
    onChanged: (value) {
      SearchQualityFilter.enabled = value;
      if (value && SearchQualityFilter.mode == SearchFilterMode.off) {
        SearchQualityFilter.mode = SearchFilterMode.dim;
        GStorage.setting.put(
          SettingBoxKey.searchFilterMode,
          SearchFilterMode.dim.index,
        );
      }
    },
  ),
  PopupModel(
    title: '不相关搜索结果处理',
    leading: const Icon(Icons.filter_alt_outlined),
    value: () => SearchQualityFilter.mode == SearchFilterMode.off
        ? SearchFilterMode.dim
        : SearchQualityFilter.mode,
    items: SearchFilterMode.values.where(
      (item) => item != SearchFilterMode.off,
    ),
    onSelected: (value, setState) {
      SearchQualityFilter.mode = value;
      GStorage.setting
          .put(SettingBoxKey.searchFilterMode, value.index)
          .whenComplete(setState);
    },
  ),
  NormalModel(
    title: '搜索结果淡化程度',
    leading: const Icon(Icons.opacity_outlined),
    getSubtitle: () =>
        '当前保留 ${(SearchQualityFilter.dimOpacity * 100).round()}% 可见度；点击手动输入 1–100',
    onTap: _showSearchOpacityDialog,
  ),
  NormalModel(
    title: '搜索最低播放量',
    leading: const Icon(Icons.play_circle_outline),
    getSubtitle: () => SearchQualityFilter.minPlay == 0
        ? '当前不按播放量过滤；点击手动输入'
        : '当前 ${SearchQualityFilter.minPlay} 次；强相关结果不会被直接隐藏',
    onTap: _showSearchMinPlayDialog,
  ),
  NormalModel(
    title: '搜索最低点赞播放比',
    leading: const Icon(Icons.thumb_up_alt_outlined),
    getSubtitle: () => SearchQualityFilter.minLikePermille == 0
        ? '当前不按点赞播放比过滤；点击手动输入'
        : '当前 ${SearchQualityFilter.minLikePermille}‰（${SearchQualityFilter.minLikePermille / 10}%）；至少 1000 播放后才判断',
    onTap: _showSearchLikeRatioDialog,
  ),
  const SwitchModel(
    title: '默认启用评论点赞排序',
    subtitle: '首批按点赞降序；后加载批次只在自身内部排序并追加，避免阅读位置跳动',
    leading: Icon(Icons.thumb_up_alt_outlined),
    setKey: SettingBoxKey.replySortByLikes,
    defaultVal: true,
  ),
  PopupModel(
    title: '未启用点赞排序时',
    leading: const Icon(Icons.sort_outlined),
    value: () => Pref.replySortType,
    items: ReplySortType.values.take(2),
    onSelected: (value, setState) => GStorage.setting
        .put(SettingBoxKey.replySortType, value.index)
        .whenComplete(setState),
  ),
  SwitchModel(
    title: '淡化低赞评论',
    subtitle: '置顶评论不会被淡化；仅依据点赞数，不检测图片或用户等级',
    leading: const Icon(Icons.comments_disabled_outlined),
    setKey: SettingBoxKey.replyDimEnabled,
    defaultVal: Pref.replyDimEnabled,
    onChanged: (value) => ReplyQualityFilter.enabled = value,
  ),
  NormalModel(
    title: '低赞评论阈值',
    leading: const Icon(Icons.low_priority_outlined),
    getSubtitle: () => '点赞数小于或等于 ${ReplyQualityFilter.maxLikes} 时淡化；点击手动输入',
    onTap: _showReplyLikeThresholdDialog,
  ),
  NormalModel(
    title: '评论淡化程度',
    leading: const Icon(Icons.opacity_outlined),
    getSubtitle: () =>
        '当前保留 ${(ReplyQualityFilter.opacity * 100).round()}% 可见度；点击手动输入 1–100',
    onTap: _showReplyOpacityDialog,
  ),
];

Future<void> _showSearchOpacityDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final percent = await _showIntegerInputDialog(
    context: context,
    title: '搜索结果淡化后的可见度',
    initialValue: (SearchQualityFilter.dimOpacity * 100).round(),
    suffix: '%',
    min: 1,
    max: 100,
    hint: '数值越小越淡',
  );
  if (percent == null) return;
  final value = percent / 100;
  SearchQualityFilter.dimOpacity = value;
  await GStorage.setting.put(SettingBoxKey.searchDimOpacity, value);
  setState();
  SmartDialog.showToast('设置成功');
}

Future<void> _showSearchMinPlayDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final value = await _showIntegerInputDialog(
    context: context,
    title: '搜索最低播放量',
    initialValue: SearchQualityFilter.minPlay,
    suffix: '次',
    min: 0,
    max: 2000000000,
    hint: '输入 0 表示不按播放量过滤',
  );
  if (value == null) return;
  SearchQualityFilter.minPlay = value;
  await GStorage.setting.put(SettingBoxKey.searchFilterMinPlay, value);
  setState();
  SmartDialog.showToast('设置成功');
}

Future<void> _showSearchLikeRatioDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final value = await _showIntegerInputDialog(
    context: context,
    title: '搜索最低点赞播放比',
    initialValue: SearchQualityFilter.minLikePermille,
    suffix: '‰',
    min: 0,
    max: 1000,
    hint: '输入 5 表示 5‰（即 0.5%）；0 表示不过滤',
  );
  if (value == null) return;
  SearchQualityFilter.minLikePermille = value;
  await GStorage.setting.put(SettingBoxKey.searchFilterMinLikePermille, value);
  setState();
  SmartDialog.showToast('设置成功');
}

Future<void> _showReplyLikeThresholdDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final value = await _showIntegerInputDialog(
    context: context,
    title: '低赞评论阈值',
    initialValue: ReplyQualityFilter.maxLikes,
    suffix: '赞',
    min: 0,
    max: 2000000000,
    hint: '小于或等于该点赞数的评论会被淡化',
  );
  if (value == null) return;
  ReplyQualityFilter.maxLikes = value;
  await GStorage.setting.put(SettingBoxKey.replyDimMaxLikes, value);
  setState();
}

Future<void> _showReplyOpacityDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final percent = await _showIntegerInputDialog(
    context: context,
    title: '评论淡化后的可见度',
    initialValue: (ReplyQualityFilter.opacity * 100).round(),
    suffix: '%',
    min: 1,
    max: 100,
    hint: '数值越小越淡',
  );
  if (percent == null) return;
  final value = percent / 100;
  ReplyQualityFilter.opacity = value;
  await GStorage.setting.put(SettingBoxKey.replyDimOpacity, value);
  setState();
  SmartDialog.showToast('设置成功');
}

Future<int?> _showIntegerInputDialog({
  required BuildContext context,
  required String title,
  required int initialValue,
  required String suffix,
  required int min,
  required int max,
  required String hint,
}) async {
  final controller = TextEditingController(text: initialValue.toString());
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
  final result = await showDialog<int>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            autofocus: true,
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(suffixText: suffix, helperText: hint),
            onFieldSubmitted: (_) => _submitIntegerInput(
              dialogContext: dialogContext,
              input: controller.text,
              min: min,
              max: max,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(dialogContext).outline),
          ),
        ),
        TextButton(
          onPressed: () => _submitIntegerInput(
            dialogContext: dialogContext,
            input: controller.text,
            min: min,
            max: max,
          ),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

void _submitIntegerInput({
  required BuildContext dialogContext,
  required String input,
  required int min,
  required int max,
}) {
  final value = int.tryParse(input.trim());
  if (value == null || value < min || value > max) {
    SmartDialog.showToast('请输入 $min 到 $max 之间的整数');
    return;
  }
  Navigator.of(dialogContext).pop(value);
}
