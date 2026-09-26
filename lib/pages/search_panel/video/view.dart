import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/models/common/search/search_filter_mode.dart';
import 'package:PiliPlus/models/common/search/video_search_type.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/search/widgets/search_text.dart';
import 'package:PiliPlus/pages/search_panel/video/controller.dart';
import 'package:PiliPlus/pages/search_panel/view.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/search_quality_filter.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class SearchVideoPanel extends CommonSearchPanel {
  const SearchVideoPanel({
    super.key,
    required super.keyword,
    required super.tag,
    required super.searchType,
  });

  @override
  State<SearchVideoPanel> createState() => _SearchVideoPanelState();
}

class _SearchVideoPanelState
    extends
        CommonSearchPanelState<
          SearchVideoPanel,
          SearchVideoData,
          SearchVideoItemModel
        >
    with GridMixin, SearchVideoPanelMixin<SearchVideoPanel> {
  @override
  late final SearchVideoController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      SearchVideoController(
        keyword: widget.keyword,
        searchType: widget.searchType,
        tag: widget.tag,
      ),
      tag: widget.searchType.name + widget.tag,
    );
  }
}

mixin SearchVideoPanelMixin<S extends SearchVideoPanel>
    on
        CommonSearchPanelState<S, SearchVideoData, SearchVideoItemModel>,
        GridMixin {
  @override
  SearchVideoController get controller;

  @override
  Widget buildHeader() {
    return SliverFloatingHeaderWidget(
      backgroundColor: colorScheme.surface,
      child: Padding(
        padding: const .fromLTRB(12, 0, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 3,
                  children: [
                    for (final e in ArchiveFilterType.values)
                      Obx(
                        () => SearchText(
                          fontSize: 13,
                          text: e.desc,
                          bgColor: Colors.transparent,
                          textColor: controller.selectedType.value == e
                              ? colorScheme.primary
                              : colorScheme.outline,
                          onTap: (_) => controller
                            ..order = e == .totalrank ? '' : e.name
                            ..selectedType.value = e
                            ..onSortSearch(getBack: false),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const VerticalDivider(indent: 7, endIndent: 8),
            Obx(() {
              final enabled =
                  controller.filterMode.value != SearchFilterMode.off;
              return Tooltip(
                message: enabled ? '关闭本页搜索过滤' : '开启本页搜索过滤',
                child: SearchText(
                  text: enabled ? '过滤开' : '过滤关',
                  fontSize: 12,
                  padding: const .symmetric(horizontal: 7, vertical: 5),
                  bgColor: enabled
                      ? colorScheme.secondaryContainer
                      : Colors.transparent,
                  textColor: enabled
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.outline,
                  onTap: (_) => controller.toggleQualityFilter(),
                ),
              );
            }),
            const SizedBox(width: 3),
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                tooltip: '筛选',
                style: const ButtonStyle(
                  padding: WidgetStatePropertyAll(EdgeInsets.zero),
                ),
                onPressed: () => controller.onShowFilterDialog(context),
                icon: Icon(
                  Icons.filter_list_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildList(List<SearchVideoItemModel> list) {
    final displayList = controller.visibleItems(list);
    if (displayList.isEmpty) {
      if (!controller.isEnd) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          controller.onLoadMore();
        });
      }
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 160,
          child: Center(
            child: Text(
              controller.isEnd ? '结果均已被过滤' : '正在跳过低相关结果…',
              style: TextStyle(color: colorScheme.outline),
            ),
          ),
        ),
      );
    }
    return SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemBuilder: (context, index) {
        if (index == displayList.length - 1) {
          controller.onLoadMore();
        }
        final item = displayList[index];
        final mode = controller.filterMode.value;
        final assessment = controller.assessment(item);
        final shouldDim = assessment.shouldDim(mode);
        return Stack(
          children: [
            Opacity(
              opacity: shouldDim ? SearchQualityFilter.dimOpacity : 1,
              child: VideoCardH(
                videoItem: item,
                onRemove: () => controller.loadingState
                  ..value.data!.remove(item)
                  ..refresh(),
              ),
            ),
            if (shouldDim)
              Positioned(
                top: 7,
                left: 7,
                child: Tooltip(
                  message: assessment.reasonText,
                  triggerMode: TooltipTriggerMode.tap,
                  child: GestureDetector(
                    onTap: () => SmartDialog.showToast(assessment.reasonText),
                    child: Container(
                      padding: const .symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: const .all(.circular(5)),
                      ),
                      child: Text(
                        '已淡化',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      itemCount: displayList.length,
    );
  }

  @override
  Widget get buildLoading => gridSkeleton;
}
