import 'package:PiliPlus/common/widgets/flutter/text_field/controller.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, ReplyInfo, SubjectControl, Mode;
import 'package:PiliPlus/grpc/bilibili/pagination.pb.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/models/common/reply/reply_sort_type.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/pages/common/publish/publish_route.dart';
import 'package:PiliPlus/pages/video/reply_new/view.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/reply_utils.dart';
import 'package:PiliPlus/utils/reply_sort_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

abstract class ReplyController<R> extends CommonListController<R, ReplyInfo> {
  ReplyController({int count = -1}) : count = RxInt(count);

  static const int _initialLikeSortPageCount = 3;

  late final RxInt count;

  late final Rx<ReplySortType> sortType;
  late final RxBool sortByLikes;
  late Mode mode;

  final savedReplies = <Object, List<RichTextItem>?>{};

  Int64? upMid;
  Int64? cursorNext;
  SubjectControl? subjectControl;
  FeedPaginationReply? paginationReply;
  late bool hasUpTop = false;

  @override
  bool? get hasFooter => true;

  // comment antifraud
  late final _enableCommAntifraud = Pref.enableCommAntifraud;
  late final _biliSendCommAntifraud = Pref.biliSendCommAntifraud;
  bool get enableCommAntifraud =>
      _enableCommAntifraud || _biliSendCommAntifraud;
  dynamic get sourceId;

  @override
  void onInit() {
    super.onInit();
    final cacheSortType = Pref.replySortType;
    sortType = cacheSortType.obs;
    sortByLikes = Pref.replySortByLikes.obs;
    mode = cacheSortType == .time ? Mode.MAIN_LIST_TIME : Mode.MAIN_LIST_HOT;
  }

  @override
  void handleListResponse(List<ReplyInfo> dataList) {
    if (!sortByLikes.value) return;
    ReplySortUtils.stableSortBatchByLikes(
      dataList,
      likes: (item) => item.like.toInt(),
      protectedPrefix:
          hasUpTop && dataList.isNotEmpty && dataList.first.replyControl.isUpTop
          ? 1
          : 0,
    );
  }

  @override
  Future<void> queryData([bool isRefresh = true]) {
    if (isRefresh && sortByLikes.value) {
      return _queryInitialLikePages();
    }
    return super.queryData(isRefresh);
  }

  /// 首次进入点赞排序时连续读取三页，合并后只排序、展示一次。
  /// 后续滚动加载仍走 [CommonListController.queryData]，因此只对新批次
  /// 内部排序并追加，不会把新评论插入用户已经读过的位置前。
  Future<void> _queryInitialLikePages() async {
    if (isLoading) return;
    isLoading = true;
    final merged = <ReplyInfo>[];
    LoadingState<R>? loadError;

    try {
      for (
        var index = 0;
        index < _initialLikeSortPageCount && !isEnd;
        index++
      ) {
        final res = await customGetData();
        if (res case Success(:final response)) {
          if (customHandleResponse(index == 0, res)) {
            page++;
            continue;
          }
          final dataList = getDataList(response);
          if (dataList == null || dataList.isEmpty) {
            isEnd = true;
            break;
          }
          merged.addAll(dataList);
          page++;
        } else {
          loadError = res;
          break;
        }
      }

      if (merged.isNotEmpty) {
        handleListResponse(merged);
        checkIsEnd(merged.length);
        loadingState.value = Success(merged);
      } else if (loadError case Error(:final errMsg)) {
        if (!handleError(errMsg)) {
          loadingState.value = loadError;
        }
      } else {
        loadingState.value = Success(merged);
      }
    } finally {
      isLoading = false;
    }
  }

  /// 启用本地点赞排序。
  ///
  /// 开启时重新加载前三页并统一排序；之后每个新加载批次在内部排序并
  /// 追加到末尾，所以不会把新出现的高赞评论插到用户已读位置前。
  Future<void> selectLikeSort() async {
    if (isLoading || sortByLikes.value) return;
    sortByLikes.value = true;
    await GStorage.setting.put(SettingBoxKey.replySortByLikes, true);
    feedBack();
    await onReload();
  }

  /// 选择 B 站接口提供的“最热”或“最新”排序。
  Future<void> selectServerSort(ReplySortType target) async {
    if (isLoading || target == ReplySortType.select) return;
    if (!sortByLikes.value && sortType.value == target) return;
    sortByLikes.value = false;
    sortType.value = target;
    mode = target == ReplySortType.time
        ? Mode.MAIN_LIST_TIME
        : Mode.MAIN_LIST_HOT;
    await GStorage.setting.put(SettingBoxKey.replySortByLikes, false);
    await GStorage.setting.put(SettingBoxKey.replySortType, target.index);
    feedBack();
    await onReload();
  }

  @override
  void checkIsEnd(int length) {
    final count = this.count.value;
    if (count != -1 && length >= count) {
      isEnd = true;
    }
  }

  @override
  bool customHandleResponse(bool isRefresh, Success<R> response) {
    final data = response.response as MainListReply;
    cursorNext = data.cursor.next;
    paginationReply = data.paginationReply;
    count.value = data.subjectControl.count.toInt();
    if (isRefresh) {
      subjectControl = data.subjectControl;
      upMid = data.subjectControl.upMid;
      if (hasUpTop = data.hasUpTop()) {
        data.replies.insert(0, data.upTop);
      }
      if (subjectControl?.title == ReplySortType.select.desc) {
        sortType.value = .select;
      }
    }
    isEnd = data.cursor.isEnd;
    return false;
  }

  @override
  Future<void> onRefresh() {
    cursorNext = null;
    subjectControl = null;
    paginationReply = null;
    return super.onRefresh();
  }

  // 排序搜索评论
  void queryBySort() {
    if (isLoading) return;
    switch (sortType.value) {
      case ReplySortType.time:
        sortType.value = ReplySortType.hot;
        mode = Mode.MAIN_LIST_HOT;
        break;
      case ReplySortType.hot:
        sortType.value = ReplySortType.time;
        mode = Mode.MAIN_LIST_TIME;
        break;
      case ReplySortType.select:
        return;
    }
    feedBack();
    onReload();
  }

  (bool inputDisable, String? hint) get replyHint {
    String? hint;
    bool inputDisable = false;
    try {
      if (subjectControl case final subjectControl?) {
        inputDisable = subjectControl.inputDisable;
        if (subjectControl.hasRootText()) {
          final rootText = subjectControl.rootText;
          if (inputDisable) {
            SmartDialog.showToast(rootText);
          }
          if (rootText.contains('可发') || rootText.contains('可见')) {
            hint = rootText;
          }
        }
      }
    } catch (_) {}
    return (inputDisable, hint);
  }

  void onReply(ReplyInfo? replyItem, {int? oid, int? replyType}) {
    if (loadingState.value case Error(:final errMsg, :final code)) {
      if (errMsg != null && (code == 12061 || code == 12002)) {
        SmartDialog.showToast(errMsg);
        return;
      }
    }

    assert(replyItem != null || (oid != null && replyType != null));

    final (bool inputDisable, String? hint) = replyHint;
    if (inputDisable) {
      return;
    }

    final key = oid ?? replyItem!.oid + replyItem.id;
    Get.key.currentState!
        .push(
          PublishRoute(
            pageBuilder: (buildContext, animation, secondaryAnimation) {
              return ReplyPage(
                hint: hint,
                oid: oid ?? replyItem!.oid.toInt(),
                root: oid != null ? 0 : replyItem!.id.toInt(),
                parent: oid != null ? 0 : replyItem!.id.toInt(),
                replyType: replyItem?.type.toInt() ?? replyType!,
                replyItem: replyItem,
                items: savedReplies[key],

                /// hd api deprecated
                // canUploadPic: canUploadPic,
                onSave: (reply) {
                  if (reply.isEmpty) {
                    savedReplies.remove(key);
                  } else {
                    savedReplies[key] = reply.toList();
                  }
                },
              );
            },
            settings: RouteSettings(arguments: Get.arguments),
          ),
        )
        .then((replyInfo) {
          if (replyInfo is ReplyInfo) {
            savedReplies.remove(key);
            if (loadingState.value case Success(:final response)) {
              if (response == null) {
                loadingState.value = Success([replyInfo]);
              } else {
                if (oid != null) {
                  response.insert(hasUpTop ? 1 : 0, replyInfo);
                } else {
                  replyItem!
                    ..count += 1
                    ..replies.add(replyInfo);
                }
                loadingState.refresh();
              }
            } else {
              loadingState.value = Success([replyInfo]);
            }
            count.value += 1;

            // check reply
            if (enableCommAntifraud) {
              onCheckReply(replyInfo, isManual: false);
            }
          }
        });
  }

  void onRemove(int index, ReplyInfo item, int? subIndex) {
    if (subIndex == null) {
      loadingState.value.data!.removeAt(index);
    } else {
      item
        ..count -= 1
        ..replies.removeAt(subIndex);
    }
    count.value -= 1;
    loadingState.refresh();
  }

  void onCheckReply(ReplyInfo replyInfo, {bool isManual = true}) {
    ReplyUtils.onCheckReply(
      replyInfo: replyInfo,
      biliSendCommAntifraud: _biliSendCommAntifraud,
      sourceId: sourceId,
      isManual: isManual,
    );
  }

  Future<void> onToggleTop(ReplyInfo item, int index, oid, int type) async {
    bool isUpTop = item.replyControl.isUpTop;
    final res = await ReplyHttp.replyTop(
      oid: oid,
      type: type,
      rpid: item.id,
      isUpTop: isUpTop,
    );
    if (res.isSuccess) {
      item.replyControl.isUpTop = !isUpTop;
      if (!isUpTop && index != 0) {
        final list = loadingState.value.data!;
        list
          ..first.replyControl.isUpTop = false
          ..insert(0, list.removeAt(index));
      }
      loadingState.refresh();
      SmartDialog.showToast('${isUpTop ? '取消' : ''}置顶成功');
    } else {
      res.toast();
    }
  }

  @override
  void onClose() {
    savedReplies.clear();
    super.onClose();
  }
}
