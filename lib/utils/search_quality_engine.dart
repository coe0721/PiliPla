import 'package:PiliPlus/models/common/search/search_filter_mode.dart';

/// 与网络、存储、UI 无关的搜索相关性判断核心。
abstract final class SearchQualityEngine {
  static const int ratioSampleFloor = 1000;
  static final RegExp _htmlTag = RegExp(r'<[^>]*>');
  static final RegExp _separator = RegExp(
    r'''[\s\u3000,，。.!！?？、|/\\:：;；_\-—·•~～`'"“”‘’()（）\[\]【】{}<>《》]+''',
  );
  static SearchQualityAssessment evaluate({
    required String keyword,
    required String title,
    String? description,
    String? tags,
    int? view,
    int? like,
    required int minPlay,
    required int minLikePermille,
  }) {
    final query = _normalize(keyword);
    if (query.isEmpty) {
      return const SearchQualityAssessment(
        relevance: SearchRelevance.related,
        reasons: [],
        score: 0,
        lowQuality: false,
      );
    }

    final titleMatch = _match(title, query, allowFuzzy: true);
    final tagMatch = _match(tags, query, allowFuzzy: true);
    final descMatch = _match(description, query, allowFuzzy: false);
    final matches = [titleMatch, tagMatch, descMatch];
    final hasDirectMatch = matches.any(
      (match) =>
          match != _MatchStrength.none && match != _MatchStrength.partial,
    );
    final hasPartialMatch = matches.any(
      (match) => match == _MatchStrength.partial,
    );
    final coveredByFragments = _coveredByFieldFragments(
      query,
      [title, tags, description],
    );

    // 相关性的判断只分三档，不再叠加来源权重：任一字段直接命中，或者
    // 标题、标签、简介中的若干片段合起来覆盖完整查询词，都正常显示。
    final relevance = hasDirectMatch || coveredByFragments
        ? SearchRelevance.related
        : hasPartialMatch
        ? SearchRelevance.uncertain
        : SearchRelevance.unrelated;
    final score = switch (relevance) {
      SearchRelevance.related => 5,
      SearchRelevance.uncertain => 2,
      SearchRelevance.unrelated => 0,
    };

    final reasons = <String>[];
    switch (relevance) {
      case SearchRelevance.related:
        break;
      case SearchRelevance.uncertain:
        reasons.add('有部分关联证据，已保守保留');
      case SearchRelevance.unrelated:
        reasons.add('标题、标签和简介未找到直接文字证据');
    }

    var lowQuality = false;
    if (minPlay > 0 && view != null && view >= 0 && view < minPlay) {
      lowQuality = true;
      reasons.add('播放量 $view 低于 $minPlay');
    }
    if (minLikePermille > 0 &&
        view != null &&
        like != null &&
        view >= ratioSampleFloor &&
        like >= 0 &&
        like * 1000 < minLikePermille * view) {
      lowQuality = true;
      final ratio = view == 0 ? 0 : like * 100 / view;
      reasons.add(
        '点赞播放比 ${ratio.toStringAsFixed(2)}% 低于 '
        '${(minLikePermille / 10).toStringAsFixed(1)}%',
      );
    }

    return SearchQualityAssessment(
      relevance: relevance,
      reasons: reasons,
      score: score,
      lowQuality: lowQuality,
    );
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(_htmlTag, '')
        .replaceAll(_separator, '');
  }

  static _MatchStrength _match(
    String? text,
    String query, {
    required bool allowFuzzy,
  }) {
    if (text == null || text.isEmpty) return _MatchStrength.none;
    final normalized = _normalize(text);
    if (normalized.contains(query)) return _MatchStrength.exact;

    // 四字及以上允许在较短范围内顺序出现，例如“原神…深渊”。
    // 这是线性扫描，不需要额外请求，也不会等待 AI。
    if (query.length >= 4 && _orderedNear(normalized, query)) {
      return _MatchStrength.ordered;
    }

    // 标题、标签和 UP 名允许一次输入错误。三字词只容许中间字写错，
    // 避免两字词或任意两个相同字造成大范围误判。
    if (allowFuzzy &&
        query.length >= 3 &&
        query.length <= 12 &&
        _containsWithinOneEdit(normalized, query)) {
      return _MatchStrength.fuzzy;
    }

    // 只命中长查询中的一小段时仅作为弱证据；是否完整覆盖
    // 查询词由 _coveredByFieldFragments 统一判断。
    if (query.length >= 4 && _hasQueryFragment(normalized, query)) {
      return _MatchStrength.partial;
    }
    return _MatchStrength.none;
  }

  static bool _hasQueryFragment(String text, String query) {
    for (var start = 0; start + 2 <= query.length; start++) {
      if (text.contains(query.substring(start, start + 2))) {
        return true;
      }
    }
    return false;
  }

  /// 判断完整查询词能否由标题、标签、简介中的连续片段共同覆盖。
  ///
  /// 每段至少两个字，并且最多允许一个三字以上片段出现一次输入错误。
  /// 例如“原神薇斯纳剧情”可以由标签“原神”和标题中的“薇斯纳”、
  /// “剧情”共同覆盖。查询通常很短；限制为 24 字可避免极端输入拖慢列表。
  static bool _coveredByFieldFragments(
    String query,
    List<String?> rawFields,
  ) {
    if (query.length < 4 || query.length > 24) return false;
    final fields = rawFields
        .whereType<String>()
        .map(_normalize)
        .where((field) => field.isNotEmpty)
        .toList(growable: false);
    if (fields.isEmpty) return false;

    final reachable = List.generate(
      query.length + 1,
      (_) => List<bool>.filled(2, false),
    );
    reachable[0][0] = true;

    for (var start = 0; start < query.length; start++) {
      for (var editsUsed = 0; editsUsed <= 1; editsUsed++) {
        if (!reachable[start][editsUsed]) continue;
        for (var end = start + 2; end <= query.length; end++) {
          final fragment = query.substring(start, end);
          if (fields.any((field) => field.contains(fragment))) {
            reachable[end][editsUsed] = true;
            continue;
          }
          if (editsUsed == 0 &&
              fragment.length >= 3 &&
              fragment.length <= 12 &&
              fields.any(
                (field) => _containsWithinOneEdit(field, fragment),
              )) {
            reachable[end][1] = true;
          }
        }
      }
    }
    return reachable[query.length][0] || reachable[query.length][1];
  }

  static bool _orderedNear(String text, String query) {
    // 标题常在关键词之间插入版本号、角色名或活动名。旧的 4 倍长度窗口
    // 会误杀“原神 5.8 版本主线剧情”这类结果；扩大窗口仍保持线性扫描。
    final maxSpan = query.length * 12;
    for (var start = 0; start < text.length; start++) {
      if (text.codeUnitAt(start) != query.codeUnitAt(0)) continue;
      var queryIndex = 1;
      final end = (start + maxSpan).clamp(0, text.length);
      for (
        var textIndex = start + 1;
        textIndex < end && queryIndex < query.length;
        textIndex++
      ) {
        if (text.codeUnitAt(textIndex) == query.codeUnitAt(queryIndex)) {
          queryIndex++;
        }
      }
      if (queryIndex == query.length) return true;
    }
    return false;
  }

  static bool _containsWithinOneEdit(String text, String query) {
    if (text.isEmpty) return false;

    if (query.length == 3) {
      for (var start = 0; start + 3 <= text.length; start++) {
        if (text.codeUnitAt(start) == query.codeUnitAt(0) &&
            text.codeUnitAt(start + 2) == query.codeUnitAt(2) &&
            text.codeUnitAt(start + 1) != query.codeUnitAt(1)) {
          return true;
        }
      }
      return false;
    }

    for (final windowLength in {
      query.length - 1,
      query.length,
      query.length + 1,
    }) {
      if (windowLength <= 0 || windowLength > text.length) continue;
      for (var start = 0; start + windowLength <= text.length; start++) {
        if (_isWithinOneEditAt(text, start, windowLength, query)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _isWithinOneEditAt(
    String text,
    int start,
    int windowLength,
    String query,
  ) {
    final lengthDiff = windowLength - query.length;
    if (lengthDiff.abs() > 1) return false;
    if (lengthDiff == 0) {
      var mismatch = 0;
      for (var i = 0; i < query.length; i++) {
        if (text.codeUnitAt(start + i) != query.codeUnitAt(i) &&
            ++mismatch > 1) {
          return false;
        }
      }
      return mismatch == 1;
    }

    final textIsLonger = lengthDiff > 0;
    final longerLength = textIsLonger ? windowLength : query.length;
    final shorterLength = textIsLonger ? query.length : windowLength;
    var longIndex = 0;
    var shortIndex = 0;
    var skipped = false;
    while (longIndex < longerLength && shortIndex < shorterLength) {
      final longUnit = textIsLonger
          ? text.codeUnitAt(start + longIndex)
          : query.codeUnitAt(longIndex);
      final shortUnit = textIsLonger
          ? query.codeUnitAt(shortIndex)
          : text.codeUnitAt(start + shortIndex);
      if (longUnit == shortUnit) {
        longIndex++;
        shortIndex++;
      } else {
        if (skipped) return false;
        skipped = true;
        longIndex++;
      }
    }
    return true;
  }
}

enum _MatchStrength { none, partial, fuzzy, ordered, exact }
