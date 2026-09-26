/// 评论本地排序的纯函数工具。
abstract final class ReplySortUtils {
  /// 按点赞数稳定降序排列一批评论。
  ///
  /// [protectedPrefix] 用于保留置顶评论。点赞数相同时保持接口原顺序，
  /// 避免每次刷新出现没有意义的位置抖动。
  static void stableSortBatchByLikes<T>(
    List<T> list, {
    required int Function(T item) likes,
    int protectedPrefix = 0,
  }) {
    if (list.length - protectedPrefix < 2) return;
    final indexed =
        <({int index, T item})>[
          for (var i = protectedPrefix; i < list.length; i++)
            (index: i, item: list[i]),
        ]..sort((a, b) {
          final byLikes = likes(b.item).compareTo(likes(a.item));
          return byLikes != 0 ? byLikes : a.index.compareTo(b.index);
        });
    for (var i = 0; i < indexed.length; i++) {
      list[protectedPrefix + i] = indexed[i].item;
    }
  }
}
