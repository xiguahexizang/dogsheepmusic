/// B 站接口 JSON 宽容解析回归测试（离线，不依赖网络）
///
/// 背景：B 站各接口的字段类型并不稳定（时长可能为 num 或 `mm:ss` 字符串、
/// `owner` / `data` 在风控或异常返回时可能不是对象）。此前代码直接使用
/// `as` 强转，失败会抛 **TypeError**；TypeError 属于 `Error`，不会被业务层
/// 的 `on Exception` / `on DioException` 捕获，会一路冒泡到 Riverpod
/// FutureProvider，UI 表现为首页“每日推荐 / 热门歌曲”加载失败。
/// 本测试锁定“异常形态输入不得抛错”这一契约。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/core/bili_api/video.dart';

void main() {
  group('MusicTrack.fromJson', () {
    test('排行榜形态：owner.name + pic + 秒数时长', () {
      final t = MusicTrack.fromJson(const {
        'bvid': 'BV17VZpY1ENA',
        'title': '给我们的组合起个名！',
        'owner': {'name': '田一名sir'},
        'pic': 'https://i0.hdslb.com/bfs/archive/x.jpg',
        'duration': 15,
      });
      expect(t.bvid, 'BV17VZpY1ENA');
      expect(t.artist, '田一名sir');
      expect(t.cover, isNotEmpty);
      expect(t.duration, 15);
    });

    test('时长兼容：num / 数字串 / mm:ss / hh:mm:ss / 非法值', () {
      expect(MusicTrack.fromJson(const {'duration': 201}).duration, 201);
      expect(MusicTrack.fromJson(const {'duration': '96'}).duration, 96);
      expect(MusicTrack.fromJson(const {'duration': '03:21'}).duration, 201);
      expect(
        MusicTrack.fromJson(const {'duration': '01:02:03'}).duration,
        3723,
      );
      expect(MusicTrack.fromJson(const {'duration': 'bad'}).duration, 0);
      expect(MusicTrack.fromJson(const {'duration': null}).duration, 0);
      expect(MusicTrack.fromJson(const {}).duration, 0);
    });

    test('字段类型异常时不得抛 Error', () {
      final t = MusicTrack.fromJson(<String, dynamic>{
        'bvid': 12345, // 应为字符串
        'title': const {'a': 1}, // 应为字符串
        'owner': 'not-a-map', // 应为对象
        'duration': const ['x'], // 应为数值
      });
      expect(t.bvid, '12345');
      expect(t.title, isNotEmpty);
      expect(t.artist, isEmpty);
      expect(t.duration, 0);
    });

    test('搜索接口返回的 <em> 高亮标签被剥离', () {
      final t = MusicTrack.fromJson(const {
        'title': '<em class="keyword">歌名</em>',
        'author': '<em>UP主</em>',
      });
      expect(t.title, '歌名');
      expect(t.artist, 'UP主');
    });

    test('作者字段多来源兜底（author / up_name / source / owner.name）', () {
      expect(MusicTrack.fromJson(const {'author': 'A'}).artist, 'A');
      expect(MusicTrack.fromJson(const {'up_name': 'B'}).artist, 'B');
      expect(MusicTrack.fromJson(const {'source': 'C'}).artist, 'C');
      expect(
        MusicTrack.fromJson(const {
          'owner': {'name': 'D'}
        }).artist,
        'D',
      );
    });
  });

  group('MusicPage.fromJson / VideoPage.fromJson', () {
    test('cid / page / duration 为字符串时仍可解析', () {
      final mp = MusicPage.fromJson(const {
        'cid': '29167322421',
        'page': '2',
        'part': 'P2',
        'duration': '120',
      });
      expect(mp.cid, 29167322421);
      expect(mp.page, 2);
      expect(mp.part, 'P2');
      expect(mp.duration, 120);

      final vp = VideoPage.fromJson(const {'cid': 1, 'duration': null});
      expect(vp.cid, 1);
      expect(vp.page, 1, reason: 'page 缺失时应回落为 1');
      expect(vp.duration, 0);
    });
  });

  group('VideoMeta.fromJson', () {
    test('正常形态：owner / stat / pages 嵌套取值', () {
      final m = VideoMeta.fromJson(const {
        'bvid': 'BV1',
        'title': '标题',
        'pic': 'https://i0.hdslb.com/pic.jpg',
        'duration': 15,
        'owner': {'name': 'UP主', 'mid': 100},
        'stat': {'view': 17895933},
        'pages': [
          {'cid': 11, 'page': 1, 'part': 'P1', 'duration': 15},
          {'cid': 22, 'page': 2, 'part': 'P2', 'duration': 15},
        ],
      });
      expect(m.uploaderName, 'UP主');
      expect(m.uploaderMid, 100);
      expect(m.playCount, 17895933);
      expect(m.pages.length, 2);
      expect(m.pages.first.cid, 11);
    });

    test('owner / stat 形态错误或缺失、pages 非数组时不得抛 Error', () {
      final m = VideoMeta.fromJson(<String, dynamic>{
        'bvid': 'BV1',
        'owner': 'oops',
        'stat': null,
        'pages': 'oops',
        'duration': '15',
      });
      expect(m.uploaderName, isEmpty);
      expect(m.uploaderMid, 0);
      expect(m.playCount, 0);
      expect(m.pages, isEmpty);
      expect(m.duration, 15);
    });

    test('pages 内含非对象元素时自动跳过', () {
      final m = VideoMeta.fromJson(<String, dynamic>{
        'pages': <dynamic>[
          const {'cid': 1},
          'oops',
          null,
          const {'cid': 2},
        ],
      });
      expect(m.pages.length, 2);
    });
  });

  group('AudioStreamInfo.fromJson', () {
    test('DASH 字段命名差异与类型宽容', () {
      final s = AudioStreamInfo.fromJson(<String, dynamic>{
        'baseUrl': 'https://xy bilivideo.com/x.m4s',
        'id': '30251',
        'codecs': 'flac',
        'mimeType': '',
        'deadline': '1760000000',
        'backupUrl': 'not-a-list',
      });
      expect(s.qualityId, 30251);
      expect(s.codec, 'flac');
      expect(s.mimeType, isNull, reason: '空串归一为 null');
      expect(s.expireTimestamp, 1760000000);
      expect(s.backupUrls, isEmpty);
    });

    test('backup_url 为数组时全部转成字符串备用直链', () {
      final s = AudioStreamInfo.fromJson(const {
        'base_url': 'https://x/y.m4s',
        'backup_url': ['https://a/y.m4s', 'https://b/y.m4s'],
      });
      expect(s.backupUrls.length, 2);
      expect(s.url, isNotEmpty);
    });
  });
}
