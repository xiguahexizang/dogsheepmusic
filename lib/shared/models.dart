/// UI 层共享数据模型
library;

/// 歌单 / 榜单目录信息
class PlaylistInfo {
  /// 歌单 ID（用于 [BiliMusic.getPlaylist] 查询曲目）
  final String id;

  /// 歌单标题
  final String name;

  /// 描述 / 副标题
  final String description;

  /// 封面 URL
  final String cover;

  /// 歌曲数量（可为空表示未知）
  final int? trackCount;

  const PlaylistInfo({
    required this.id,
    required this.name,
    this.description = '',
    this.cover = '',
    this.trackCount,
  });

  PlaylistInfo copyWith({String? name, String? cover, int? trackCount}) =>
      PlaylistInfo(
        id: id,
        name: name ?? this.name,
        description: description,
        cover: cover ?? this.cover,
        trackCount: trackCount ?? this.trackCount,
      );
}

/// 收藏记录（本地持久化的精简曲目信息）
class FavoriteTrack {
  final String bvid;
  final String title;
  final String artist;
  final String? coverUrl;
  final int duration;
  final bool isMusicTrack;

  const FavoriteTrack({
    required this.bvid,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.duration = 0,
    this.isMusicTrack = true,
  });

  Map<String, dynamic> toMap() => {
        'bvid': bvid,
        'title': title,
        'artist': artist,
        'cover': coverUrl,
        'duration': duration,
        'isMusic': isMusicTrack,
      };

  factory FavoriteTrack.fromMap(Map<dynamic, dynamic> m) => FavoriteTrack(
        bvid: (m['bvid'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        artist: (m['artist'] ?? '').toString(),
        coverUrl: m['cover']?.toString(),
        duration: (m['duration'] as num?)?.toInt() ?? 0,
        isMusicTrack: m['isMusic'] as bool? ?? true,
      );
}
