import 'package:PiliPlus/grpc/dm/v1/dm.pb.dart';
import 'package:PiliPlus/http/danmaku.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage.dart';

class PlDanmakuController {
  PlDanmakuController(
    this.cid,
    this.plPlayerController,
  );
  final int cid;
  final PlPlayerController plPlayerController;

  Map<int, List<DanmakuElem>> dmSegMap = {};
  // 已请求的段落标记
  List<bool> requestedSeg = [];

  bool get initiated => requestedSeg.isNotEmpty;

  static int segmentLength = 60 * 6 * 1000;

  late final mergeDanmaku = GStorage.mergeDanmaku;

  void initiate(int videoDuration, int progress) {
    if (videoDuration <= 0) {
      return;
    }
    if (requestedSeg.isEmpty) {
      int segCount = (videoDuration / segmentLength).ceil();
      requestedSeg = List<bool>.generate(segCount, (index) => false);
    }
    queryDanmaku(calcSegment(progress));
  }

  void dispose() {
    dmSegMap.clear();
    requestedSeg.clear();
  }

  int calcSegment(int progress) {
    return progress ~/ segmentLength;
  }

  void queryDanmaku(int segmentIndex) async {
    if (requestedSeg.length <= segmentIndex) {
      return;
    }
    assert(requestedSeg[segmentIndex] == false);
    requestedSeg[segmentIndex] = true;
    final DmSegMobileReply result = await DanmakaHttp.queryDanmaku(
      cid: cid,
      segmentIndex: segmentIndex + 1,
      mergeDanmaku: mergeDanmaku,
    );
    if (result.elems.isNotEmpty) {
      for (var element in result.elems) {
        int pos = element.progress ~/ 100; //每0.1秒存储一次
        if (dmSegMap[pos] == null) {
          dmSegMap[pos] = [];
        }
        dmSegMap[pos]!.add(element);
      }
    }
  }

  List<DanmakuElem>? getCurrentDanmaku(int progress) {
    int segmentIndex = calcSegment(progress);
    if (requestedSeg.length <= segmentIndex) {
      return <DanmakuElem>[];
    }
    if (!requestedSeg[segmentIndex]) {
      queryDanmaku(segmentIndex);
    }
    if (plPlayerController.danmakuWeight == 0 &&
        plPlayerController.danmakuFilterRule.isEmpty) {
      return dmSegMap[progress ~/ 100];
    } else {
      return dmSegMap[progress ~/ 100]
          ?.where(
              (element) => element.weight >= plPlayerController.danmakuWeight)
          .where(filterDanmaku)
          .toList();
    }
  }

  bool filterDanmaku(DanmakuElem elem) {
    for (var filter in plPlayerController.danmakuFilterRule) {
      switch (filter['type']) {
        case 0:
          if (elem.content.contains(filter['filter'])) {
            return false;
          }
          break;
        case 1:
          if (RegExp(filter['filter'], caseSensitive: false)
              .hasMatch(elem.content)) {
            return false;
          }
          break;
        case 2:
          if (elem.idStr == filter['filter']) {
            return false;
          }
          break;
      }
    }
    return true;
  }
}
