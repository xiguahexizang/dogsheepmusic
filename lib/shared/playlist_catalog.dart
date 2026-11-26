/// 精选歌单目录
///
/// **为什么不再是 catalog sid**（2026-11 实测）：
/// Bilibili 的 `audio/music-service-c/web/song/of-catalog?sid=xxx` 已下线，
/// 旧目录里的 8 个 sid（1001/1002/2002/2003/2005/2006/3001/3002）全部 HTTP 404，
/// 即使可用，其返回也是「歌曲 sid」而非 BV 号，播放器拿到也无法取流
/// —— 表现为歌单详情页永远空白。
///
/// 因此 [PlaylistInfo.id] 改为**数据源描述符**，由
/// [BiliMusic.getPlaylist] 分发到真实可用且返回 BV 号的音乐接口：
/// - `rank:<type>` → `x/web-interface/ranking/v2?rid=3&type=<type>`（实测 97 条全音乐）
/// - `new:3`       → `x/web-interface/newlist?rid=3`（数据在 `data.archives`）
/// - `kw:<关键词>`  → `x/web-interface/search/type` + 音乐分区 tid 过滤
library;

import 'package:dog_sheep_player/shared/models.dart';

/// 精选歌单集合
const List<PlaylistInfo> kCuratedPlaylists = [
  PlaylistInfo(
    id: 'rank:all',
    name: '音乐榜 · 总榜',
    description: '当下最火的音乐整区榜单',
    trackCount: 30,
  ),
  PlaylistInfo(
    id: 'rank:origin',
    name: '原创音乐',
    description: 'UP 主自作曲，新鲜原声',
    trackCount: 30,
  ),
  PlaylistInfo(
    id: 'new:3',
    name: '分区最新',
    description: '音乐区每日新稿首发',
    trackCount: 30,
  ),
  PlaylistInfo(
    id: 'kw:古风 歌曲',
    name: '古风国风',
    description: '戏腔民乐，东方韵律',
    trackCount: 25,
  ),
  PlaylistInfo(
    id: 'kw:电子 音乐',
    name: '电子 / EDM',
    description: '强劲节拍，点燃现场',
    trackCount: 28,
  ),
  PlaylistInfo(
    id: 'kw:说唱',
    name: '说唱嘻哈',
    description: 'Real hip-hop，态度发声',
    trackCount: 32,
  ),
  PlaylistInfo(
    id: 'kw:民谣',
    name: '治愈民谣',
    description: '木吉他与呢喃的午后',
    trackCount: 22,
  ),
  PlaylistInfo(
    id: 'kw:ACG 音乐',
    name: 'ACG 神曲',
    description: '动漫游戏，燃向曲目',
    trackCount: 36,
  ),
  PlaylistInfo(
    id: 'kw:R&B 深夜',
    name: '深夜电台',
    description: '适合一个人的 R&B',
    trackCount: 20,
  ),
];
