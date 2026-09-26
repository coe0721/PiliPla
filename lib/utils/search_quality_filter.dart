import 'package:PiliPlus/models/common/search/search_filter_mode.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/utils/search_quality_engine.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// 快速、完全本地的搜索质量判断。
///
/// 标签、简介、播放量和点赞数都来自搜索响应。这里不会调用视频详情接口，
/// 因而不会出现滚动很久后才完成判断，也不会增加账号或网络风险。
abstract final class SearchQualityFilter {
  static bool enabled = Pref.searchFilterEnabled;
  static SearchFilterMode mode = Pref.searchFilterMode;
  static int minPlay = Pref.searchFilterMinPlay;
  static int minLikePermille = Pref.searchFilterMinLikePermille;
  static double dimOpacity = Pref.searchDimOpacity;

  static SearchFilterMode get effectiveMode =>
      enabled ? mode : SearchFilterMode.off;

  static SearchQualityAssessment evaluate(
    SearchVideoItemModel item,
    String keyword,
  ) => evaluateFields(
    keyword: keyword,
    title: item.title,
    author: item.owner.name,
    description: item.desc,
    tags: item.tag,
    view: item.stat.view,
    like: item.stat.like,
  );

  static SearchQualityAssessment evaluateFields({
    required String keyword,
    required String title,
    String? author,
    String? description,
    String? tags,
    int? view,
    int? like,
    int? minPlayOverride,
    int? minLikePermilleOverride,
  }) => SearchQualityEngine.evaluate(
    keyword: keyword,
    title: title,
    author: author,
    description: description,
    tags: tags,
    view: view,
    like: like,
    minPlay: minPlayOverride ?? minPlay,
    minLikePermille: minLikePermilleOverride ?? minLikePermille,
  );
}
