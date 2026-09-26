import 'package:PiliPlus/utils/reply_sort_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('点赞降序且同赞保持接口顺序，并保留置顶评论', () {
    final comments = [
      (id: 'pinned', likes: 0),
      (id: 'a', likes: 1),
      (id: 'b', likes: 10),
      (id: 'c', likes: 10),
    ];

    ReplySortUtils.stableSortBatchByLikes(
      comments,
      likes: (item) => item.likes,
      protectedPrefix: 1,
    );

    expect(comments.map((e) => e.id), ['pinned', 'b', 'c', 'a']);
  });

  test('后加载批次只在自身内部排序，不会跳到已读批次前', () {
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
    final displayed = [...firstBatch, ...nextBatch];

    expect(displayed.map((e) => e.id), [
      'first-high',
      'first-low',
      'next-high',
      'next-low',
    ]);
  });
}
