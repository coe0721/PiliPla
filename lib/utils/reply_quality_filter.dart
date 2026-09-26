import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/utils/storage_pref.dart';

/// 评论淡化只使用评论接口已有的点赞数，不额外请求用户资料或图片。
abstract final class ReplyQualityFilter {
  static bool enabled = Pref.replyDimEnabled;
  static int maxLikes = Pref.replyDimMaxLikes;
  static double opacity = Pref.replyDimOpacity;

  static bool shouldDim(ReplyInfo item) {
    if (!enabled || item.replyControl.isUpTop) return false;
    return item.like.toInt() <= maxLikes;
  }
}
