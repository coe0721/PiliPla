import 'package:PiliPlus/models/common/search/search_filter_mode.dart';
import 'package:PiliPlus/utils/search_quality_engine.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('标签能挽救标题未出现关键词的二创', () {
    final result = assess(
      title: '胡桃生日手书',
      tags: '原神,胡桃,二创,手书',
      view: 120,
      like: 18,
    );

    expect(result.relevance, SearchRelevance.related);
    expect(result.lowQuality, isTrue);
    expect(result.shouldHide(SearchFilterMode.hide), isFalse);
    expect(result.shouldDim(SearchFilterMode.hide), isTrue);
  });

  test('标题命中时直接放行，不强制标签和简介重复关键词', () {
    final result = assess(
      title: '原神震撼消息',
      tags: '社会,生活',
      description: '与游戏无关的日常记录',
    );

    expect(result.relevance, SearchRelevance.related);
    expect(result.shouldHide(SearchFilterMode.hide), isFalse);
    expect(result.shouldDim(SearchFilterMode.dim), isFalse);
  });

  test('无文字命中但质量正常的结果保守保留并淡化', () {
    final result = assess(
      title: '今日汽车资讯',
      tags: '汽车,新闻',
      description: '新车试驾',
    );

    expect(result.relevance, SearchRelevance.unrelated);
    expect(result.shouldHide(SearchFilterMode.hide), isFalse);
    expect(result.shouldDim(SearchFilterMode.hide), isTrue);
  });

  test('无文字命中且明显低质量也只淡化', () {
    final result = assess(
      title: '今日汽车资讯',
      tags: '汽车,新闻',
      description: '新车试驾',
      view: 100,
      like: 0,
    );

    expect(result.relevance, SearchRelevance.unrelated);
    expect(result.lowQuality, isTrue);
    expect(result.shouldHide(SearchFilterMode.hide), isFalse);
    expect(result.shouldDim(SearchFilterMode.hide), isTrue);
  });

  test('点赞播放比只在足够样本时参与判断', () {
    final smallSample = assess(
      title: '原神攻略',
      tags: '原神,攻略',
      view: 800,
      like: 0,
    );
    final largeSample = assess(
      title: '原神攻略',
      tags: '原神,攻略',
      view: 2000,
      like: 2,
    );

    expect(smallSample.reasonText, isNot(contains('点赞播放比')));
    expect(largeSample.reasonText, contains('点赞播放比'));
  });

  test('连续查询词可在标题中近距离分开出现', () {
    final result = assess(
      keyword: '原神深渊',
      title: '原神 5.8版本：12层深渊攻略',
      tags: '游戏,攻略',
    );

    expect(result.relevance, SearchRelevance.related);
    expect(result.shouldDim(SearchFilterMode.dim), isFalse);
  });

  test('三字角色名允许中间字写错一次', () {
    final result = assess(
      keyword: '薇丝纳',
      title: '薇斯纳角色攻略与配队',
      tags: '游戏,攻略',
    );

    expect(result.relevance, SearchRelevance.related);
    expect(result.shouldDim(SearchFilterMode.dim), isFalse);
  });

  test('两字词不启用模糊纠错以避免误杀', () {
    final result = assess(
      keyword: '原神',
      title: '原声音乐合集',
      tags: '音乐,原声',
    );

    expect(result.relevance, SearchRelevance.unrelated);
  });

  test('空格和标点不影响完整查询词匹配', () {
    final result = assess(
      keyword: '原神：深渊',
      title: '原神 深渊 满星教学',
      tags: '原神,深渊,攻略',
    );

    expect(result.relevance, SearchRelevance.related);
  });

  test('长查询命中有意义片段时作为弱证据保留', () {
    final result = assess(
      keyword: '原神深渊',
      title: '胡桃配队与输出手法',
      tags: '原神,胡桃,攻略',
      view: 8000,
      like: 300,
    );

    expect(result.relevance, SearchRelevance.uncertain);
    expect(result.shouldHide(SearchFilterMode.hide), isFalse);
    expect(result.shouldDim(SearchFilterMode.dim), isTrue);
  });

  test('三处均无搜索证据时只淡化而不隐藏', () {
    final result = assess(
      keyword: '原神',
      title: '胡桃新队伍实战演示',
      tags: '火系,配队,攻略',
      description: '测试多种输出循环',
      view: 50000,
      like: 2500,
    );

    expect(result.relevance, SearchRelevance.unrelated);
    expect(result.lowQuality, isFalse);
    expect(result.shouldHide(SearchFilterMode.hide), isFalse);
    expect(result.shouldDim(SearchFilterMode.dim), isTrue);
  });

  test('关键词之间插入较长版本文字仍视为相关', () {
    final result = assess(
      keyword: '原神剧情',
      title: '原神 5.8 版本挪德卡莱主线任务完整剧情流程',
      tags: '游戏,主线,攻略',
    );

    expect(result.relevance, SearchRelevance.related);
    expect(result.shouldHide(SearchFilterMode.hide), isFalse);
  });

  test('标题和标签中的片段合起来覆盖搜索词时正常显示', () {
    final result = assess(
      keyword: '原神深渊',
      title: '本期深渊满星阵容与手法',
      tags: '原神,攻略,配队',
    );

    expect(result.relevance, SearchRelevance.related);
    expect(result.shouldDim(SearchFilterMode.dim), isFalse);
  });

  test('简介完整命中搜索词时正常显示', () {
    final result = assess(
      keyword: '原神剧情',
      title: '空月之歌间奏解析',
      tags: '游戏,解析',
      description: '本期完整梳理原神剧情与角色关系',
    );

    expect(result.relevance, SearchRelevance.related);
    expect(result.shouldDim(SearchFilterMode.dim), isFalse);
  });
}
