import 'package:PiliPlus/models/common/search/search_filter_mode.dart';

/// 与网络、存储、UI 无关的搜索相关性判断核心。
abstract final class SearchQualityEngine {
  static const int ratioSampleFloor = 1000;
  static final RegExp _htmlTag = RegExp(r'<[^>]*>');
  static final RegExp _separator = RegExp(
    r'''[\s\u3000,，。.!！?？、|/\\:：;；_\-—·•~～`'"“”‘’()（）\[\]【】{}<>《》]+''',
  );
  static final RegExp _fanwork = RegExp(
    r'二创|同人|手书|剪辑|混剪|配音|仿妆|绘画|动画|鬼畜|mmd|mad|cosplay|cos',
    caseSensitive: false,
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
    final titleHit = titleMatch != _MatchStrength.none;
    final tagHit = tagMatch != _MatchStrength.none;
    final descHit = descMatch != _MatchStrength.none;
    final evidenceCount = [
      titleHit,
      tagHit,
      descHit,
    ].where((value) => value).length;

    var score = 0;
    // 搜索结果本身已经经过 B 站召回。这里优先避免误伤：标题或标签只要
    // 有完整、近距离或一次容错命中，就足以视为相关，不再要求标签和简介
    // 必须重复出现同一关键词。
    if (titleHit) {
      score += titleMatch == _MatchStrength.partial ? 2 : 5;
    }
    if (tagHit) {
      score += tagMatch == _MatchStrength.partial ? 3 : 6;
    }
    if (descHit) {
      score += descMatch == _MatchStrength.partial ? 1 : 5;
    }
    if (evidenceCount >= 2) score += 2;

    final combined = '$title ${tags ?? ''} ${description ?? ''}';
    if (evidenceCount > 0 && _fanwork.hasMatch(combined)) score += 1;

    final relevance = switch (score) {
      >= 5 => SearchRelevance.related,
      >= 2 => SearchRelevance.uncertain,
      _ => SearchRelevance.unrelated,
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

    // 长查询常由多个词组成，标题或标签只出现其中一段仍可能是有效结果，
    // 例如搜索“原神深渊”而标题只写角色名、标签只写“原神”。这种情况
    // 只作为弱证据保留，不会被误判成强相关。
    if (query.length >= 4 && _hasMeaningfulFragment(normalized, query)) {
      return _MatchStrength.partial;
    }
    return _MatchStrength.none;
  }

  static bool _hasMeaningfulFragment(String text, String query) {
    final fragmentLength = query.length >= 6 ? 3 : 2;
    for (
      var start = 0;
      start + fragmentLength <= query.length;
      start += fragmentLength
    ) {
      if (text.contains(query.substring(start, start + fragmentLength))) {
        return true;
      }
    }
    return false;
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
