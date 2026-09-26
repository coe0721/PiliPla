import 'package:PiliPlus/models/common/enum_with_label.dart';

/// 搜索结果的本地处理方式。
///
/// 本地过滤只使用搜索接口已经返回的数据，不会为每个视频额外发请求。
enum SearchFilterMode implements EnumWithLabel {
  off('关闭'),
  dim('淡化'),
  hide('隐藏');

  @override
  final String label;

  const SearchFilterMode(this.label);

  SearchFilterMode get next => values[(index + 1) % values.length];
}

enum SearchRelevance { related, uncertain, unrelated }

class SearchQualityAssessment {
  const SearchQualityAssessment({
    required this.relevance,
    required this.reasons,
    required this.score,
    required this.lowQuality,
  });

  final SearchRelevance relevance;
  final List<String> reasons;
  final int score;
  final bool lowQuality;

  bool get hasIssue => relevance != SearchRelevance.related || lowQuality;

  bool shouldHide(SearchFilterMode mode) {
    // 搜索判断只能提供辅助证据，不能可靠确认视频内容无关。
    // 所有可疑结果都保留在列表中，仅通过淡化提示用户。
    return false;
  }

  bool shouldDim(SearchFilterMode mode) {
    if (mode == SearchFilterMode.off || shouldHide(mode)) return false;
    return hasIssue;
  }

  double opacity(SearchFilterMode mode) {
    if (!shouldDim(mode)) return 1;
    return relevance == SearchRelevance.unrelated ? 0.28 : 0.52;
  }

  String get reasonText => reasons.isEmpty ? '未发现异常' : reasons.join('；');
}
