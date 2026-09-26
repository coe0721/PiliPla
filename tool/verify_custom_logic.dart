import 'dart:io';

import 'package:PiliPlus/models/common/search/search_filter_mode.dart';
import 'package:PiliPlus/utils/reply_sort_utils.dart';
import 'package:PiliPlus/utils/search_quality_engine.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  SearchQualityAssessment assess({
    String keyword = '原神',
    required String title,
    String? tags,
    String? description,
    int view = 10000,
    int like = 200,
  }) => SearchQualityEngine.evaluate(
    keyword: keyword,
    title: title,
    tags: tags,
    description: description,
    view: view,
    like: like,
    minPlay: 500,
    minLikePermille: 5,
  );

  final tagRescue = assess(
    title: '胡桃生日手书',
    tags: '原神,胡桃,二创,手书',
    view: 120,
    like: 18,
  );
  check(tagRescue.relevance == SearchRelevance.related, '标签应挽救二创');
  check(!tagRescue.shouldHide(SearchFilterMode.hide), '强相关低播放项不应隐藏');

  final titleOnly = assess(
    title: '原神震撼消息',
    tags: '社会,生活',
    description: '与游戏无关的日常记录',
  );
  check(titleOnly.relevance == SearchRelevance.related, '标题完整命中应放行');
  check(!titleOnly.shouldDim(SearchFilterMode.dim), '标题完整命中不应淡化');

  final unrelated = assess(
    title: '今日汽车资讯',
    tags: '汽车,新闻',
    description: '新车试驾',
  );
  check(!unrelated.shouldHide(SearchFilterMode.hide), '任何搜索结果都不应隐藏');
  check(unrelated.shouldDim(SearchFilterMode.dim), '无搜索证据时应淡化');

  final lowRatio = assess(
    title: '原神攻略',
    tags: '原神,攻略',
    view: 2000,
    like: 2,
  );
  check(lowRatio.reasonText.contains('点赞播放比'), '足够样本时应判断点赞比');

  final separated = assess(
    keyword: '原神深渊',
    title: '原神 5.8版本：12层深渊攻略',
    tags: '游戏,攻略',
  );
  check(separated.relevance == SearchRelevance.related, '分开的查询词应匹配');

  final typo = assess(
    keyword: '薇丝纳',
    title: '薇斯纳角色攻略与配队',
    tags: '游戏,攻略',
  );
  check(typo.relevance == SearchRelevance.related, '三字角色名应容许中间字写错');

  final firstBatch = [
    (id: 'first-high', likes: 20),
    (id: 'first-low', likes: 1),
  ];
  final nextBatch = [
    (id: 'next-low', likes: 2),
    (id: 'next-high', likes: 100),
  ];
  ReplySortUtils.stableSortBatchByLikes(
    firstBatch,
    likes: (item) => item.likes,
  );
  ReplySortUtils.stableSortBatchByLikes(
    nextBatch,
    likes: (item) => item.likes,
  );
  final displayed = [...firstBatch, ...nextBatch].map((e) => e.id).toList();
  check(
    displayed.join(',') == 'first-high,first-low,next-high,next-low',
    '后加载高赞评论不应跳到首批前',
  );

  stdout.writeln('custom logic checks passed');
}
