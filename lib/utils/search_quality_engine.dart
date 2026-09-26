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
    String? author,
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
    final authorMatch = _match(author, query, allowFuzzy: true);
    final titleHit = titleMatch != _MatchStrength.none;
    final tagHit = tagMatch != _MatchStrength.none;
    final descHit = descMatch != _MatchStrength.none;
    final authorHit = authorMatch != _MatchStrength.none;
    final evidenceCount = [
      titleHit,
      tagHit,
      descHit,
      authorHit,
    ].where((value) => value).length;

    var score = 0;
    if (titleHit) score += 5;
    if (tagHit) score += tagMatch == _MatchStrength.fuzzy ? 5 : 6;
    if (descHit) score += 2;
    if (authorHit) score += 4;
    if (evidenceCount >= 2) score += 2;

    final combined = '$title ${tags ?? ''} ${description ?? ''}';
    if (evidenceCount > 0 && _fanwork.hasMatch(combined)) score += 1;

    final titleOnly =
        titleMatch == _MatchStrength.exact &&
        !tagHit &&
        !descHit &&
        !authorHit &&
        ((tags?.trim().isNotEmpty ?? false) ||
            (description?.trim().isNotEmpty ?? false));
    if (titleOnly) score = 3;

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
        reasons.add(titleOnly ? '仅标题命中，标签/简介未命中' : '关联证据较弱');
      case SearchRelevance.unrelated:
        reasons.add('标题、标签、简介和UP均未命中');
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
    return _MatchStrength.none;
  }

  static bool _orderedNear(String text, String query) {
    final maxSpan = query.length * 4;
    for (var start = 0; start < text.length; start++) {
      if (text.codeUnitAt(start) != query.codeUnitAt(0)) continue;
      var queryIndex = 1;
      final end = (start + maxSpan).clamp(0, text.length);
      for (var textIndex = start + 1;
          textIndex < end && queryIndex < query.length;
          textIndex++) {
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

enum _MatchStrength { none, fuzzy, ordered, exact }
