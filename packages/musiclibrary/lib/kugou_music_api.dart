import 'dart:ffi';
import 'dart:convert';

import 'package:ffi/ffi.dart';

import 'common.dart';
import 'core.dart';

class KuGouMusicApi {
  final EngineBindings _engine;
  final KugouBindings _bindings;
  late final KugouContextManager _contextManager;
  final KugouProcessEnv _env;
  late final KugouEnvHandle _nativeEnv;
  late final Pointer<JSContext> _ctx;
  Map<String, String> _cookie = {};

  bool _destroyed = false;

  KuGouMusicApi({
    KugouProcessEnv? env,
    String? libraryDir,
  })  : _engine = EngineBindings(libraryDir: libraryDir),
        _bindings = KugouBindings(libraryDir: libraryDir),
        _env = env ?? KugouProcessEnv() {
    _engine.ensureInitialized();

    _contextManager = KugouContextManager(bindings: _bindings);
    _nativeEnv = _env.toNative();
    _contextManager.init(_nativeEnv.pointer);
    _ctx = _contextManager.takeContext();
  }

  void set_cookie(Map<String, String> cookie) {
    _cookie = cookie;
  }

  MusicResponse request(
    String path, {
    Map<String, String> cookie = const {},
    KugouProcessEnv? env,
    Map<String, dynamic>? query,
  }) {
    final useEnv = env ?? _env;
    final envHandle = useEnv == _env ? _nativeEnv : useEnv.toNative();

    // 自动补全cookie，并将cookie转换为JSON字符串
    String cookieJson = jsonEncode(cookie.isEmpty ? _cookie : cookie);

    final pathPtr = path.toNativeUtf8();
    final cookiePtr = cookieJson.toNativeUtf8();
    final paramsPtr =
        encodeQuery(query ?? const <String, dynamic>{}).toNativeUtf8();

    try {
      final responsePtr = _bindings.request(
        _ctx,
        pathPtr,
        cookiePtr,
        paramsPtr,
        envHandle.pointer,
      );
      return parseFfiResponse(responsePtr, _engine);
    } finally {
      calloc.free(pathPtr);
      calloc.free(cookiePtr);
      calloc.free(paramsPtr);
      if (!identical(envHandle, _nativeEnv)) {
        envHandle.dispose();
      }
    }
  }

  void dispose() {
    if (_destroyed) {
      return;
    }

    _engine.destroyContext(_ctx);
    _nativeEnv.dispose();
    _contextManager.destroy();
    _engine.dispose();
    _destroyed = true;
  }

  ///1.手机登录
  ///
  ///说明 : 调用此接口 , 传入手机号码和验证码, 可进行登录
  ///
  ///必选参数：
  ///
  ///mobile: 手机号码
  ///
  ///code: 验证码,使用 captcha_sent(/captcha/sent)接口传入手机号获取验证码,调用此接口传入验证码,可使用验证码登录
  ///
  ///可选参数：
  ///
  ///userid: 用户 id,当用户存在多个账户是时，必须加上需要登录的用户 id
  ///
  ///接口地址： /login/cellphone
  ///
  ///调用例子： /login/cellphone?mobile=xxx&code=xxx
  MusicResponse login_cellphone(String mobile, String code,
      {String? userid,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/login/cellphone",
        cookie: cookie,
        env: env,
        query: {'mobile': mobile, 'code': code, 'userid': userid});
  }

  ///2.用户名登录(该登录可能需要验证，不推荐使用)
  ///
  ///说明 : 调用此接口 , 传入用户名和密码, 可进行登录
  ///
  ///必选参数：
  ///
  ///username: 用户名，可以是手机号、邮箱或者酷狗号
  ///
  ///password: 密码，需 md5 加密后传入
  ///
  ///接口地址： /login
  ///
  ///调用例子： /login?username=xxx&password=yyy
  ///
  ///
  MusicResponse login(String username, String password,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/login",
        cookie: cookie,
        env: env,
        query: {'username': username, 'password': password});
  }

  ///3.开放接口登录(目前仅支持微信登录)
  ///
  ///说明 : 该接口为第三方平台登录，目前仅支持微信登录
  ///
  ///必选参数：
  ///
  ///code: 由微信扫码成功后生成
  ///
  ///接口地址： /login/openplat
  ///
  ///调用例子： /login/openplat?code=xxx
  MusicResponse login_openplat(String code,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/login/openplat",
        cookie: cookie, env: env, query: {'code': code});
  }

  ///4.二维码登录 - 生成 key
  ///
  ///说明: 调用此接口可生成一个 key
  ///
  ///接口地址： /login/qr/key
  ///
  ///调用例子： /login/qr/key
  MusicResponse login_qr_key(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/login/qr/key", cookie: cookie, env: env);
  }

  ///4.二维码登录 - 生成二维码
  ///
  ///说明: 调用此接口传入上一个接口生成的 key 可生成二维码图片的 base64 和二维码信息,可使用 base64 展示图片,或者使用二维码信息内容自行使用第三方二维码生成 库渲染二维码
  ///
  ///必选参数：
  ///
  ///key: 由 /login/qr/key 接口生成
  ///
  ///可选参数：
  ///
  ///qrimg: 传入后会额外返回二维码图片 base64 编码
  ///
  ///接口地址： /login/qr/create
  ///
  ///调用例子： /login/qr/create?key=xxx
  MusicResponse login_qr_create(String key,
      {String? qrimg,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/login/qr/create",
        cookie: cookie, env: env, query: {'key': key, 'qrimg': qrimg});
  }

  ///4.二维码登录 - 检查扫码状态
  ///
  ///说明: 轮询此接口可获取二维码扫码状态,0 为二维码过期，1 为等待扫码，2 为待确认，4 为授权登录成功（4 状态码下会返回 token）
  ///
  ///必选参数：
  ///
  ///key: 由 /login/qr/key 接口生成
  ///
  ///接口地址： /login/qr/check
  ///
  ///调用例子： /login/qr/check?key=xxx
  MusicResponse login_qr_check(String key,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/login/qr/check",
        cookie: cookie, env: env, query: {'key': key});
  }

  ///5.微信登录 - 生成二维码
  ///
  ///说明：调用此接口可生成微信的 uuid, 包括二维码 Bae64 和 二维码扫描链接, 注: 该接口请求的接口过多, 会出现返回较慢的情况
  ///
  ///接口地址： /login/wx/create
  ///
  ///调用例子： /login/wx/create
  MusicResponse login_wx_create(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/login/wx/create", cookie: cookie, env: env);
  }

  ///5.微信登录 - 二维码检测扫码状态接口
  ///
  ///说明：轮询此接口可获取二维码扫码状态, 408 为等待扫描，404 为已经扫描，403 为拒绝登录，405 为登录成功，402 为已过期(405 状态下登陆完成口会返回 wx_code, 用于开放登陆 /login/openplat), 注：该接口有一定延时，不可访问是可以直接到 https://long.open.weixin.qq.com/connect/l/qrconnect?f=json&uuid=xxx 该接口直接请求
  ///
  ///必选参数：
  ///
  ///uuid: 由 /login/wx/create 接口生成
  ///
  ///可选参数：
  ///
  ///timestamp: 建议传递，否则由于缓存会导致延迟
  ///
  ///接口地址： /login/wx/check
  ///
  ///调用例子： /login/wx/check?timestamp=1691256061923&uuid=xxxxxxxxx
  MusicResponse login_wx_check(String uuid,
      {String? timestamp,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/login/wx/check",
        cookie: cookie,
        env: env,
        query: {'uuid': uuid, 'timestamp': timestamp});
  }

  ///刷新登录
  ///
  ///说明 : 调用此接口，可刷新登录状态，可以延长 token 过期时间
  ///
  ///可选参数：
  ///
  ///token: 登录后获取的 token
  ///
  ///userid: 用户 id
  ///
  ///接口地址： /login/token
  ///
  ///调用例子： /login/token /login/token?token=xxx&userid=xxx
  MusicResponse login_token(
      {String? token,
      String? userid,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/login/token",
        cookie: cookie, env: env, query: {'token': token, 'userid': userid});
  }

  ///发送验证码
  ///
  ///说明: 调用此接口 ,传入手机号码, 可发送验证码
  ///
  ///必选参数：
  ///
  ///mobile: 手机号码
  ///
  ///接口地址： /captcha/sent
  ///
  ///调用例子： /captcha/sent?mobile=xxx
  MusicResponse captcha_sent(String mobile,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/captcha/sent",
        cookie: cookie, env: env, query: {'mobile': mobile});
  }

  ///dfid 获取
  ///
  ///接口地址： /register/dev
  ///
  ///调用例子： /register/dev
  MusicResponse register_dev(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/register/dev", cookie: cookie, env: env);
  }

  ///获取用户额外信息
  ///
  ///说明：登陆后调用此接口，可以获取用户额外信息
  ///
  ///接口地址： /user/detail
  MusicResponse user_detail(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/user/detail", cookie: cookie, env: env);
  }

  ///获取用户 vip 信息
  ///
  ///说明：登陆后调用此接口，可以获取用户 vip 信息
  ///
  ///接口地址： /user/vip/detail
  MusicResponse user_vip_detail(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/user/vip/detail", cookie: cookie, env: env);
  }

  ///获取用户歌单
  ///
  ///说明：登录后调用此接口，可以获取用户的所有创建以及收藏的歌单
  ///
  ///可选参数：
  ///
  ///page：页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /user/playlist
  ///
  ///调用例子： /user/playlist
  MusicResponse user_playlist(
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/user/playlist",
        cookie: cookie, env: env, query: {'page': page, 'pagesize': pagesize});
  }

  ///获取用户关注歌手
  ///
  ///说明：登录后调用此接口，可以获取用户的所有关注的歌手/用户
  ///
  ///接口地址： /user/follow
  ///
  ///调用例子： /user/follow
  MusicResponse user_follow(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/user/follow", cookie: cookie, env: env);
  }

  ///获取用户云盘
  ///
  ///说明：登录后调用此接口可以获取用户上传到云盘的音乐（需要登录）
  ///
  ///可选参数
  ///
  ///page : 页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /user/cloud
  ///
  ///调用例子： /user/cloud
  MusicResponse user_cloud(
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/user/cloud",
        cookie: cookie, env: env, query: {'page': page, 'pagesize': pagesize});
  }

  ///获取用户云盘音乐 URL
  ///
  ///说明：登录后调用此接口可以获取用户上传到云盘的音乐 URL，部分可以直接用 /song/url 直接获取 URL（需要登录，目前获取到的文件大小都约为 10M 左右）
  ///
  ///必选参数：
  ///
  ///hash: 音乐 hash
  ///
  ///可选参数：
  ///
  ///album_id: 专辑 id
  ///
  ///name: 云盘音乐名称
  ///
  ///album_audio_id：专辑音频 id
  ///
  ///接口地址： /user/cloud/url
  ///
  ///调用例子： /user/cloud/url
  MusicResponse user_cloud_url(String hash,
      {String? album_id,
      String? name,
      String? album_audio_id,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/user/cloud/url", cookie: cookie, env: env, query: {
      'hash': hash,
      'album_id': album_id,
      'name': name,
      'album_audio_id': album_audio_id
    });
  }

  ///获取用户收藏的视频
  ///
  ///说明：登录后调用此接口可以获取用户收藏的视频（需要登录）
  ///
  ///可选参数
  ///
  ///page : 页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /user/video/collect
  ///
  ///调用例子： /user/video/collect
  MusicResponse user_video_collect(
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/user/video/collect",
        cookie: cookie, env: env, query: {'page': page, 'pagesize': pagesize});
  }

  ///获取用户喜欢的视频
  ///
  ///说明：登录后调用此接口可以获取用户喜欢的视频（需要登录）
  ///
  ///可选参数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /user/video/love
  ///
  ///调用例子： /user/video/love
  MusicResponse user_video_love(
      {String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/user/video/love",
        cookie: cookie, env: env, query: {'pagesize': pagesize});
  }

  ///获取用户听歌历史排行
  ///
  ///说明：登录后调用此接口，可以获取用户听歌历史排行
  ///
  ///可选参数：
  ///
  ///type：0 为获取最近一周前 120 首歌曲，1：获取全部累计前 120 首歌曲
  ///
  ///接口地址： /user/listen
  ///
  ///调用例子： /user/listen
  MusicResponse user_listen(
      {String? type,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/user/listen",
        cookie: cookie, env: env, query: {'type': type});
  }

  ///获取用户最近听歌历史
  ///
  ///说明：登录后调用此接口，可以近期的听歌历史记录(需要登陆)
  ///
  ///可选参数：
  ///
  ///bp: 可以更加上一次返回值传入
  ///
  ///接口地址： /user/history
  ///
  ///调用例子： /user/history
  MusicResponse user_history(
      {String? bp,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/user/history",
        cookie: cookie, env: env, query: {'bp': bp});
  }

  ///获取继续播放信息（对应手机版首页显示继续播放入口）
  ///
  ///说明：登录后调用此接口，可以最后设备播放信息(需要登陆)
  ///
  ///可选参数：
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///接口地址： /lastest/songs/listen
  ///
  ///调用例子： /lastest/songs/listen
  MusicResponse lastest_songs_listen(
      {String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/lastest/songs/listen",
        cookie: cookie, env: env, query: {'pagesize': pagesize});
  }

  ///收藏歌单/新建歌单
  ///
  ///说明 : 调用此接口, 可收藏歌单/新建歌单( 需要登录 ), 收藏成功后建议使用 [/playlist/tracks/add](#对歌单添加歌曲) 把原歌单下的歌曲添加到新的歌单
  ///
  ///必选参数：
  ///
  ///name: 歌单名称
  ///
  ///list_create_userid: 歌单 list_create_userid
  ///
  ///list_create_listid: 歌单 list_create_listid
  ///
  ///可选参数
  ///
  ///is_pri: 是否设为隐私，0：公开，1：隐私，仅支持创建歌单时传入
  ///
  ///type: 1：为收藏歌单，0：创建歌单, 默认为 0
  ///
  ///list_create_gid：歌单 list_create_gid
  ///
  ///接口地址： /playlist/add
  ///
  ///调用例子： /playlist/add?source=1&name=音乐一响%20纯爱登场.&list_create_userid=1782943844&list_create_listid=87
  MusicResponse playlist_add(
      String name, String list_create_userid, String list_create_listid,
      {String? is_pri,
      String? type,
      String? list_create_gid,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/playlist/add", cookie: cookie, env: env, query: {
      'name': name,
      'list_create_userid': list_create_userid,
      'list_create_listid': list_create_listid,
      'is_pri': is_pri,
      'type': type,
      'list_create_gid': list_create_gid
    });
  }

  ///取消收藏歌单/删除歌单
  ///
  ///说明 : 调用此接口 , 取消收藏歌单( 需要登录 )
  ///
  ///必选参数：
  ///
  ///listid: 用户歌单 listid
  ///
  ///接口地址： /playlist/del
  ///
  ///接口地址： /playlist/del?listid=xxx
  MusicResponse playlist_del(String listid,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/playlist/del",
        cookie: cookie, env: env, query: {'listid': listid});
  }

  ///对歌单添加歌曲
  ///
  ///说明 : 调用此接口 , 可以添加歌曲到歌单 ( 需要登录 )
  ///
  ///必选参数：
  ///
  ///listid: 用户歌单 listid
  ///
  ///data: 歌曲数据, 格式为 歌曲名称|歌曲 hash|专辑 id|(mixsongid/album_audio_id)，最少需要 歌曲名称以及歌曲 hash(若返回错误则需要全部参数)， 支持多个，每
  ///个以逗号分隔
  ///
  ///接口地址： /playlist/tracks/add
  ///
  ///调用例子： /playlist/tracks/add?listid=1&data=我们应该算爱过吧|8E10D8825DDE03BCABBDE13E5A4150D2
  ////playlist/tracks/add?listid=1&data=我们应该算爱过吧|8E10D8825DDE03BCABBDE13E5A4150D2|67026620|477417208
  ////playlist/tracks/add?listid=1&data=我们应该算爱过吧|8E10D8825DDE03BCABBDE13E5A4150D2,我们应该算爱过吧|5015FC3FAB5B0C245556A1CC3C4DE355
  MusicResponse playlist_tracks_add(String listid, String data,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/playlist/tracks/add",
        cookie: cookie, env: env, query: {'listid': listid, 'data': data});
  }

  ///对歌单删除歌曲
  ///
  ///说明 : 调用此接口 , 可以删除歌单某首歌曲 ( 需要登录 )
  ///
  ///必选参数：
  ///
  ///listid: 用户歌单 listid
  ///
  ///fileids: 歌单中歌曲的 fileid，可多个,用逗号隔开
  ///
  ///接口地址： /playlist/tracks/del
  ///
  ///调用例子： /playlist/tracks/del?listid=1&fileids=xx /playlist/tracks/del?listid=1&fileids=xx,xx
  MusicResponse playlist_tracks_del(String listid, String fileids,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/playlist/tracks/del",
        cookie: cookie,
        env: env,
        query: {'listid': listid, 'fileids': fileids});
  }

  ///新碟上架
  ///
  ///说明: 调用此接口 , 可获取新碟上架列表, 如需要专辑详细信息需要调用[album/detail](#专辑详情), 如需要获取专辑音乐列表需调
  ///用[album/songs](#专辑音乐列表)
  ///
  ///可选参数：
  ///
  ///type : 1：华语；2：欧美；3：日本；4：韩国；推荐为空，默认为空
  ///
  ///page : 页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /top/album
  ///
  ///调用例子： /top/album
  MusicResponse top_album(
      {String? type,
      String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/top/album",
        cookie: cookie,
        env: env,
        query: {'type': type, 'page': page, 'pagesize': pagesize});
  }

  ///专辑信息
  ///
  ///说明: 调用此接口 ,传入专辑 id 可获取专辑相关信息
  ///
  ///必选参数：
  ///
  ///album_id: 专辑 id,可以传多个，以逗号分割
  ///
  ///可选参数：
  ///
  ///fields: 需要返回的信息，可以传多个，以逗号分割，支持的值有 trans_param special_tag authors album_name publish_date cover intro
  ///publish_company type album_id language_id is_publish heat grade quality exclusive grade_count author_name sizable_cover
  ///language category
  ///
  ///接口地址： /album
  ///
  ///调用例子： /album?album_id=xxx, /album?album_id=xxx,xxx, /album?album_id=xxx&fields=language,authors
  MusicResponse album(String album_id,
      {String? fields,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/album",
        cookie: cookie,
        env: env,
        query: {'album_id': album_id, 'fields': fields});
  }

  ///专辑详情
  ///
  ///说明: 调用此接口 ,传入专辑 id 可获取专辑详情
  ///
  ///必选参数：
  ///
  ///id: 专辑 id
  ///
  ///接口地址： /album/detail
  ///
  ///调用例子： /album/detail?id=10729818
  MusicResponse album_detail(String id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/album/detail",
        cookie: cookie, env: env, query: {'id': id});
  }

  ///专辑音乐列表
  ///
  ///说明: 调用此接口 ,传入专辑 id 可获取专辑音乐列表
  ///
  ///必选参数：
  ///
  ///id: 专辑 id
  ///
  ///可选参数：
  ///
  ///page : 页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /album/songs
  ///
  ///调用例子： /album/songs?id=10729818
  MusicResponse album_songs(String id,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/album/songs",
        cookie: cookie,
        env: env,
        query: {'id': id, 'page': page, 'pagesize': pagesize});
  }

  ///获取音乐 URL
  ///
  ///说明: 调用此接口, 传入的音乐 hash, 可以获取对应的音乐的 url, 未登录状态或者非会员可能会返回为空。
  ///
  ///⚠️ 注意：因接口问题，目前获取 url 接口数据需要先调用 /register/dev 接口获取 dfid，否则会提示 本次请求需要验证
  ///
  ///必选参数：
  ///
  ///hash: 音乐 hash
  ///
  ///可选参数：
  ///
  ///album_id: 专辑 id
  ///
  ///free_part: 是否返回试听部分（仅部分歌曲）
  ///
  ///album_audio_id：专辑音频 id
  ///
  ///quality：获取不同音质的 url
  ///
  ///quality 支持的参数
  ///
  ///piano：对应手机端魔法音乐 钢琴，仅部分音乐支持
  ///
  ///acappella：对应手机端魔法音乐 人声 伴奏，仅部分音乐支持，该模式下返回的音频后缀为 mkv 格式，该文加存在 人声 和 伴奏 两个音轨
  ///
  ///subwoofer：对应手机端魔法音乐 骨笛，仅部分音乐支持
  ///
  ///ancient：对应手机端魔法音乐 尤克里里，仅部分音乐支持
  ///
  ///surnay：对应手机端魔法音乐 唢呐，仅部分音乐支持
  ///
  ///dj：对应手机端魔法音乐 DJ，仅部分音乐支持
  ///
  ///128：返回 128 码率 mp3 格式
  ///
  ///320：返回 320 码率 mp3 格式
  ///
  ///flac：返回 flac 格式音频
  ///
  ///high：返回无损格式音频
  ///
  ///viper_atmos：蝰蛇全景声，仅部分音乐支持
  ///
  ///viper_clear：蝰蛇超清音质
  ///
  ///viper_tape：蝰蛇母带，仅部分音乐支持, 该音质需要转码，关于转码相关的技术还不会
  ///
  ///接口地址： /song/url
  ///
  ///调用例子： /song/url?hash=xxx
  MusicResponse song_url(String hash,
      {String? album_id,
      String? free_part,
      String? album_audio_id,
      String? quality,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/song/url", cookie: cookie, env: env, query: {
      'hash': hash,
      'album_id': album_id,
      'free_part': free_part,
      'album_audio_id': album_audio_id,
      'quality': quality
    });
  }

  ///获取音乐 URL（新版）
  ///
  ///说明: 调用此接口, 传入的音乐 hash, 可以获取对应的音乐的 url, 未登录状态或者非会员可能会返回为空，该接口会一次性返回支持的音质的音频 url, 但该接口存
  ///在音频加密（目前无法解码），请谨慎使用
  ///
  ///⚠️ 注意：因接口问题，目前获取 url 接口数据需要先调用 /register/dev 接口获取 dfid，否则会提示 本次请求需要验证
  ///
  ///必选参数：
  ///
  ///hash: 音乐 hash
  ///
  ///可选参数：
  ///
  ///album_audio_id：专辑音频 id
  ///
  ///free_part: 是否返回试听部分（仅部分歌曲）
  ///
  ///album_audio_id：专辑音频 id
  ///
  ///接口地址： /song/url/new
  ///
  ///调用例子： /song/url/new?hash=xxx
  MusicResponse song_url_new(String hash,
      {String? album_audio_id,
      String? free_part,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/song/url/new", cookie: cookie, env: env, query: {
      'hash': hash,
      'album_audio_id': album_audio_id,
      'free_part': free_part
    });
  }

  ///获取歌曲高潮部分
  ///
  ///说明: 调用此接口, 传入的音乐 hash, 可以获取对应的音乐的高潮时间
  ///
  ///必选参数：
  ///
  ///hash: 音乐 hash, 可以传多个，以逗号分割
  ///
  ///接口地址： /song/climax
  ///
  ///调用例子： /song/climax?hash=xxx
  MusicResponse song_climax(String hash,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/song/climax",
        cookie: cookie, env: env, query: {'hash': hash});
  }

  ///搜索
  ///
  ///说明: 调用此接口 , 传入搜索关键词可以搜索该音乐 / mv / 歌单 / 歌词 / 专辑 / 歌手
  ///
  ///必选参数：
  ///
  ///keywords: 关键词
  ///
  ///可选参数：
  ///
  ///page : 页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///type: 搜索类型；默认为单曲，special：歌单，lyric：歌词，song：单曲，album：专辑，author：歌手，mv：mv
  ///
  ///接口地址： /search
  ///
  ///调用例子： /search?keywords=海阔天空
  MusicResponse search(String keywords,
      {String? page,
      String? pagesize,
      String? type,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/search", cookie: cookie, env: env, query: {
      'keywords': keywords,
      'page': page,
      'pagesize': pagesize,
      'type': type
    });
  }

  ///默认搜索关键词
  ///
  ///说明 : 调用此接口 , 可获取默认搜索关键词
  ///
  ///接口地址： /search/default
  MusicResponse search_default(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/search/default", cookie: cookie, env: env);
  }

  ///综合搜索
  ///
  ///说明: 调用此接口, 传入搜索关键词可以获得综合搜索，搜索结果同时包含单曲 , 歌手 , 歌单等信息
  ///
  ///必选参数：
  ///
  ///keywords: 关键词
  ///
  ///可选参数：
  ///
  ///page : 页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /search/complex
  ///
  ///调用例子： /search/complex?keywords=海阔天空
  MusicResponse search_complex(String keywords,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/search/complex",
        cookie: cookie,
        env: env,
        query: {'keywords': keywords, 'page': page, 'pagesize': pagesize});
  }

  ///热搜列表
  ///
  ///说明 : 调用此接口,可获取热门搜索列表
  ///
  ///接口地址： /search/hot
  ///
  ///调用例子： /search/hot
  MusicResponse search_hot(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/search/hot", cookie: cookie, env: env);
  }

  ///搜索建议
  ///
  ///说明 : 调用此接口 , 传入搜索关键词可获得搜索建议 , 搜索结果同时包含单曲 , 歌手 , 歌单信息
  ///
  ///可选参数：
  ///
  ///albumTipCount : 专辑返回数量
  ///
  ///correctTipCount : 目前未知，可能是歌单
  ///
  ///mvTipCount : MV 返回数量
  ///
  ///musicTipCount : 音乐返回数量
  ///
  ///接口地址： /search/suggest
  ///
  ///调用例子： /search/suggest?keywords=海阔天空
  MusicResponse search_suggest(
      {String? albumTipCount,
      String? correctTipCount,
      String? mvTipCount,
      String? musicTipCount,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/search/suggest", cookie: cookie, env: env, query: {
      'albumTipCount': albumTipCount,
      'correctTipCount': correctTipCount,
      'mvTipCount': mvTipCount,
      'musicTipCount': musicTipCount
    });
  }

  ///歌词搜索
  ///
  ///说明: 调用此接口, 可以搜索歌词，该接口需配合 [/lyric](#获取歌词) 使用。
  ///
  ///必选参数：
  ///
  ///keywords: 关键词，与 hash 二选一
  ///
  ///hash: 歌曲 hash，与 keyword 二选一
  ///
  ///可选参数：
  ///
  ///album_audio_id: 专辑音乐 id,
  ///
  ///man: 是否返回多个歌词，yes：返回多个， no：返回一个。 默认为no
  ///
  ///接口地址： /search/lyric
  ///
  ///调用例子： /search/lyric?keywords=xxx /search/lyric?keywords=xxx&hash=xxx
  MusicResponse search_lyric(String keywords, String hash,
      {String? album_audio_id,
      String? man,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/search/lyric", cookie: cookie, env: env, query: {
      'keywords': keywords,
      'hash': hash,
      'album_audio_id': album_audio_id,
      'man': man
    });
  }

  ///获取歌词
  ///
  ///说明 : 调用此接口，可以获取歌词，调用该接口前则需要调用[/search/lyric](#歌词搜索) 获取完整参数
  ///
  ///必选参数：
  ///
  ///id: 歌词 id, 可以从 [/search/lyric](#歌词搜搜) 接口中获取
  ///
  ///accesskey: 歌词 accesskey, 可以从 [/search/lyric](#歌词搜搜) 接口中获取
  ///
  ///可选参数：
  ///
  ///fmt: 歌词类型，lrc 为普通歌词，krc 为逐字歌词
  ///
  ///decode: 是否解码，传入该参数这返回解码后的歌词
  ///
  ///接口地址： /lyric
  ///
  ///调用例子： /lyric?id=xxx&accesskey=xxx /lyric?id=xxx&accesskey=xxx&fmt=lrc /lyric?id=xxx&accesskey=xxx&decode=true
  MusicResponse lyric(String id, String accesskey,
      {String? fmt,
      String? decode,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/lyric", cookie: cookie, env: env, query: {
      'id': id,
      'accesskey': accesskey,
      'fmt': fmt,
      'decode': decode
    });
  }

  ///歌单分类
  ///
  ///说明 : 调用此接口,可获取歌单分类,包含 category 信息
  ///
  ///接口地址： /playlist/tags
  ///
  ///调用例子： /playlist/tags
  MusicResponse playlist_tags(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/playlist/tags", cookie: cookie, env: env);
  }

  ///歌单
  ///
  ///说明 : 调用此接口 , 可获取歌单
  ///
  ///必选参数：
  ///
  ///category_id: tag，0：推荐，11292：HI-RES，其他可以从 [/playlist/tags](#歌单分类) 接口中获取（接口下的 tag_id 为 category_id的值）
  ///
  ///可选参数：
  ///
  ///withsong: 是否返回歌曲列表（不全），0：不返回，1：返回
  ///
  ///withtag: 是否返回歌单分类，0：不返回，1：返回
  ///
  ///接口地址： /top/playlist
  ///
  ///调用例子： /top/playlist?category_id=0
  MusicResponse top_playlist(String category_id,
      {String? withsong,
      String? withtag,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/top/playlist", cookie: cookie, env: env, query: {
      'category_id': category_id,
      'withsong': withsong,
      'withtag': withtag
    });
  }

  ///主题歌单
  ///
  ///说明 : 调用此接口 , 可获取主题歌单, 通过 [/theme/playlist/track](#获取主题歌单所有歌曲) 可以获取主题个单下的歌曲
  ///
  ///接口地址： /theme/playlist
  ///
  ///调用例子： /theme/playlist
  MusicResponse theme_playlist(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/theme/playlist", cookie: cookie, env: env);
  }

  ///音效歌单
  ///
  ///说明 : 调用此接口 , 可获取音效歌单
  ///
  ///可选参数：
  ///
  ///page : 页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /playlist/effect
  ///
  ///调用例子： /playlist/effect
  MusicResponse playlist_effect(
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/playlist/effect",
        cookie: cookie, env: env, query: {'page': page, 'pagesize': pagesize});
  }

  ///获取歌单详情
  ///
  ///说明: 调用此接口 , 可获取歌单详细信息
  ///
  ///必选参数：
  ///
  ///ids: 歌单中的 global_collection_id，可以传多个，用逗号分隔
  ///
  ///接口地址： /playlist/detail
  ///
  ///调用例子： /playlist/detail?ids=collection_3_1863870844_4_0 /playlist/detail?ids=collection_3_1863870844_4_0,collection_3_2093906551_8_0
  MusicResponse playlist_detail(String ids,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/playlist/detail",
        cookie: cookie, env: env, query: {'ids': ids});
  }

  ///获取歌单所有歌曲
  ///
  ///说明 : 调用此接口，传入对应的歌单 global_collection_id，即可获得对应的所有歌曲
  ///
  ///必选参数：
  ///
  ///id: 歌单中的 global_collection_id
  ///
  ///可选参数：
  ///
  ///page : 页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /playlist/track/all
  ///
  ///调用例子： /playlist/track/all?id=collection_3_1863870844_4_0
  MusicResponse playlist_track_all(String id,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/playlist/track/all",
        cookie: cookie,
        env: env,
        query: {'id': id, 'page': page, 'pagesize': pagesize});
  }

  ///获取歌单所有歌曲(新版)
  ///
  ///说明 : 调用此接口，传入对应的歌单 listid，即可获得对应的所有歌曲, 目前该接口仅支持 用户所创建及收藏的歌单
  ///
  ///必选参数：
  ///
  ///lisdid: 歌单中的 listid
  ///
  ///可选参数：
  ///
  ///page : 页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /playlist/track/all/new
  ///
  ///调用例子： /playlist/track/all/new?listid=xxx
  MusicResponse playlist_track_all_new(String lisdid,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/playlist/track/all/new",
        cookie: cookie,
        env: env,
        query: {'lisdid': lisdid, 'page': page, 'pagesize': pagesize});
  }

  ///相似歌单
  ///
  ///说明 : 调用此接口，根据歌单 id 获取相似歌单
  ///
  ///必选参数：
  ///
  ///ids：歌单 global_collection_id，支持多个，每个以逗号分隔
  ///
  ///接口地址： /playlist/similar
  ///
  ///调用例子： /playlist/similar?ids=collection_1_1341266283_964007_0
  ////playlist/similar?ids=collection_1_1341266283_964007_0,collection_3_1041185112_11_0
  MusicResponse playlist_similar(String ids,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/playlist/similar",
        cookie: cookie, env: env, query: {'ids': ids});
  }

  ///获取主题歌单所有歌曲
  ///
  ///必选参数：
  ///
  ///theme_id: 主题歌单 id
  ///
  ///接口地址： /theme/playlist/track
  ///
  ///调用例子： /theme/playlist/track?theme_id=18
  MusicResponse theme_playlist_track(String theme_id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/theme/playlist/track",
        cookie: cookie, env: env, query: {'theme_id': theme_id});
  }

  ///获取主题音乐
  ///
  ///说明 : 调用此接口，可以获取主题音乐，调用 [/theme/music/detail](#) 可以获取主题音乐详情
  ///
  ///接口地址： /theme/music
  ///
  ///调用例子： /theme/music
  MusicResponse theme_music(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/theme/music", cookie: cookie, env: env);
  }

  ///获取主题音乐详情
  ///
  ///说明 : 调用此接口，传入对应的主题 id 可以获取主题音乐详情.
  ///
  ///必选参数：
  ///
  ///id: 主题音乐 id
  ///
  ///接口地址： /theme/music/detail
  ///
  ///调用例子： /theme/music/detail?id=1002
  MusicResponse theme_music_detail(String id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/theme/music/detail",
        cookie: cookie, env: env, query: {'id': id});
  }

  ///歌曲推荐
  ///
  ///说明 : 调用此接口，可以获取歌曲推荐.
  ///
  ///必选参数：
  ///
  ///card_id: 1：对应安卓 精选好歌随心听 || 私人专属好歌，2：对应安卓 经典怀旧金曲，3：对应安卓 热门好歌精选，4：对应安卓 小众宝藏佳作，5：未知，6：对应
  ///vip 专属推荐
  ///
  ///接口地址： /top/card
  ///
  ///调用例子： /top/card?card_id=1
  ///
  ///歌曲推荐（概念版）
  ///
  ///说明 : 调用此接口，可以获取歌曲推荐
  ///
  ///必选参数：
  ///
  ///card_id: 3006: VIP 专属推荐，3001: 私人专属好歌，3004: 小众宝藏佳作，3014: 喜欢这首歌的 TA 也喜欢，3101: 概念 er 新推，3005: 潮流尝鲜
  ///
  ///可选参数
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///接口地址： /top/card
  ///
  ///调用例子： /top/card/youth?card_id=3006
  MusicResponse top_card(String card_id,
      {String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/top/card",
        cookie: cookie,
        env: env,
        query: {'card_id': card_id, 'pagesize': pagesize});
  }

  ///获取歌手和专辑图片
  ///
  ///说明 : 调用此接口，可以获取歌手和专辑图片.
  ///
  ///必选参数：
  ///
  ///hash: 歌曲 hash, 可以传多个，每个以逗号分开
  ///
  ///可选参数：
  ///
  ///album_id: 专辑 id, 可以传多个，每个以逗号分开
  ///
  ///album_audio_id: 专辑音乐 id, 可以传多个，每个以逗号分开
  ///
  ///count: 最多返回多少张图片，默认为 5
  ///
  ///接口地址： /images
  ///
  ///调用例子： /images?hash=B04ED0F01ABBB62B9D22EC4616ED8AFE
  ////image?hash=B04ED0F01ABBB62B9D22EC4616ED8AFE,55603312694BF99AD6000C2D0D72D368&album_id=,75013431
  MusicResponse images(String hash,
      {String? album_id,
      String? album_audio_id,
      String? count,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/images", cookie: cookie, env: env, query: {
      'hash': hash,
      'album_id': album_id,
      'album_audio_id': album_audio_id,
      'count': count
    });
  }

  ///获取歌手图片
  ///
  ///说明 : 调用此接口，可以获取歌手图片.
  ///
  ///必选参数：
  ///
  ///hash: 歌曲 hash, 可以传多个，每个以逗号分开
  ///
  ///可选参数：
  ///
  ///audio_id: 音乐 id, 可以传多个，每个以逗号分开
  ///
  ///album_audio_id: 专辑音乐 id, 可以传多个，每个以逗号分开
  ///
  ///filename: 音乐文件名称, 可以传多个，每个以逗号分开
  ///
  ///count: 最多返回多少张图片，默认为 5
  ///
  ///接口地址： /images/audio
  ///
  ///调用例子： /images/audio?hash=B04ED0F01ABBB62B9D22EC4616ED8AFE
  ////image/audio?hash=B04ED0F01ABBB62B9D22EC4616ED8AFE,55603312694BF99AD6000C2D0D72D368
  MusicResponse images_audio(String hash,
      {String? audio_id,
      String? album_audio_id,
      String? filename,
      String? count,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/images/audio", cookie: cookie, env: env, query: {
      'hash': hash,
      'audio_id': audio_id,
      'album_audio_id': album_audio_id,
      'filename': filename,
      'count': count
    });
  }

  ///获取音乐相关信息
  ///
  ///说明：调用此接口，可以获取音乐相关信息
  ///
  ///必选参数：
  ///
  ///hash: 歌曲 hash, 可以传多个，每个以逗号分开
  ///
  ///接口地址： /audio
  ///
  ///调用例子： /audio?hash=B04ED0F01ABBB62B9D22EC4616ED8AFE /audio?hash=B04ED0F01ABBB62B9D22EC4616ED8AFE,55603312694BF99AD6000C2D0D72D368
  MusicResponse audio(String hash,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/audio", cookie: cookie, env: env, query: {'hash': hash});
  }

  ///获取更多音乐版本
  ///
  ///说明：调用此接口，可以获取更多版本音乐
  ///
  ///必选参数：
  ///
  ///album_audio_id：音乐的 mixsongid/album_audio_id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///show_type：是否返回分类
  ///
  ///sort：排序，支持 all，hot，new
  ///
  ///type: 分类
  ///
  ///show_detail：是否返回详情，否则只返回总数，0：只返回总数，不传或者其他都返回详情
  ///
  ///接口地址： /audio/related
  ///
  ///调用例子： /audio/related?album_audio_id=573120919 /audio/related?album_audio_id=573120919&show_detail=0
  MusicResponse audio_related(String album_audio_id,
      {String? page,
      String? pagesize,
      String? show_type,
      String? sort,
      String? type,
      String? show_detail,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/audio/related", cookie: cookie, env: env, query: {
      'album_audio_id': album_audio_id,
      'page': page,
      'pagesize': pagesize,
      'show_type': show_type,
      'sort': sort,
      'type': type,
      'show_detail': show_detail
    });
  }

  ///获取音乐伴奏信息
  ///
  ///说明：调用此接口，可以获取最佳伴奏信息
  ///
  ///必选参数：
  ///
  ///hash：音乐 hash
  ///
  ///fileName: 音乐 fileName
  ///
  ///mixid: 音乐的 mixsongid/album_audio_id
  ///
  ///接口地址： /audio/accompany/matching
  ///
  ///调用例子： /audio/accompany/matching?fileName=希林娜依高 - Shine Brighter (愈加璀璨)&mixId=637735200&hash=6D431B0507587447B3D7345434DC5825
  MusicResponse audio_accompany_matching(
      String hash, String fileName, String mixid,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/audio/accompany/matching",
        cookie: cookie,
        env: env,
        query: {'hash': hash, 'fileName': fileName, 'mixid': mixid});
  }

  ///获取音乐 K 歌数量
  ///
  ///说明：调用此接口，可以获取音乐 K 歌数量，参数信息均来自[获取音乐伴奏信息](#获取音乐伴奏信息)
  ///
  ///必选参数：
  ///
  ///songId：音乐 songid, 该字段需要请求 [获取音乐伴奏信息](#获取音乐伴奏信息) 获取
  ///
  ///singerName：歌手名称，多个以 、 隔开，也可以到 [获取音乐伴奏信息](#获取音乐伴奏信息) 中获取
  ///
  ///songHash：音乐 hash, 该字段需要请求 [获取音乐伴奏信息](#获取音乐伴奏信息) 获取
  ///
  ///接口地址： /audio/ktv/total
  ///
  ///调用例子： /audio/ktv/total?songId=43522508&singerName=希林娜依高&songHash=99AE5A7B04FF76550E380C3757D3E273
  MusicResponse audio_ktv_total(
      String songId, String singerName, String songHash,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/audio/ktv/total", cookie: cookie, env: env, query: {
      'songId': songId,
      'singerName': singerName,
      'songHash': songHash
    });
  }

  ///获取音乐详情
  ///
  ///说明：调用此接口，可以获取音乐详情
  ///
  ///必选参数：
  ///
  ///hash: 歌曲 hash, 可以传多个，每个以逗号分开
  ///
  ///接口地址： /privilege/lite
  ///
  ///调用例子： /privilege/lite?hash=B04ED0F01ABBB62B9D22EC4616ED8AFE
  ////privilege/lite?hash=B04ED0F01ABBB62B9D22EC4616ED8AFE,55603312694BF99AD6000C2D0D72D368
  MusicResponse privilege_lite(String hash,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/privilege/lite",
        cookie: cookie, env: env, query: {'hash': hash});
  }

  ///获取音乐专辑/歌手信息
  ///
  ///说明：调用此接口，可以获取音乐专辑/歌手信息
  ///
  ///必选参数：
  ///
  ///album_audio_id: 专辑音乐 id (album_audio_id/MixSongID 均可以), 可以传多个，每个以逗号分开
  ///
  ///可选参数
  ///
  ///fields: 可以传 album_info authors.base base audio_info, authors.ip, extra, tags, tagmap 每个 field 以逗号分开
  ///
  ///接口地址： /krm/audio
  ///
  ///调用例子： /krm/audio?album_audio_id=32155307 /krm/audio?album_audio_id=32155307&fields=album_info,base,authors.base
  MusicResponse krm_audio(String album_audio_id,
      {String? fields,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/krm/audio",
        cookie: cookie,
        env: env,
        query: {'album_audio_id': album_audio_id, 'fields': fields});
  }

  ///私人 FM(对应手机和 pc 端的猜你喜欢)
  ///
  ///说明 : 私人 FM
  ///
  ///可选参数：
  ///
  ///hash: 音乐 hash, 建议
  ///
  ///songid: 音乐 songid, 建议
  ///
  ///playtime: 已播放时间, 建议
  ///
  ///mode: 获取模式，默认为 normal, normal：发现，small： 小众，peak：30s
  ///
  ///action: 默认为 play, garbage: 为不喜欢
  ///
  ///song_pool_id： 手机版的 AI，0：Alpha 根据口味推荐相似歌曲, 1：Beta 根据风格推荐相似歌曲, 2：Gamma
  ///
  ///is_overplay: 是否已播放完成
  ///
  ///remain_songcnt: 剩余未播放歌曲数, 默认为 0，大于 4 不返回推荐歌曲，建议
  ///
  ///接口地址： /personal/fm
  ///
  ///调用例子： /personal/fm
  MusicResponse personal_fm(
      {String? hash,
      String? songid,
      String? playtime,
      String? mode,
      String? action,
      String? song_pool_id,
      String? is_overplay,
      String? remain_songcnt,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/personal/fm", cookie: cookie, env: env, query: {
      'hash': hash,
      'songid': songid,
      'playtime': playtime,
      'mode': mode,
      'action': action,
      'song_pool_id': song_pool_id,
      'is_overplay': is_overplay,
      'remain_songcnt': remain_songcnt
    });
  }

  ///banner
  ///
  ///说明 : 调用此接口 , 可获取 banner( 轮播图 ) 数据
  ///
  ///接口地址： /pc/diantai
  ///
  ///调用例子： /pc/diantai
  MusicResponse pc_diantai(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/pc/diantai", cookie: cookie, env: env);
  }

  ///乐库 banner
  ///
  ///说明 : 调用此接口 , 可获取 乐库 banner( 轮播图 ) 数据
  ///
  ///接口地址： /yueku/banner
  ///
  ///调用例子： /yueku/banner
  MusicResponse yueku_banner(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/yueku/banner", cookie: cookie, env: env);
  }

  ///乐库电台
  ///
  ///说明 : 调用此接口 , 可获取乐库电台数据
  ///
  ///接口地址： /yueku/fm
  ///
  ///调用例子： /yueku/fm
  MusicResponse yueku_fm(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/yueku/fm", cookie: cookie, env: env);
  }

  ///乐库
  ///
  ///说明 : 调用此接口 , 可获取手机端乐库数据
  ///
  ///接口地址： /yueku
  ///
  ///调用例子： /yueku
  MusicResponse yueku(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/yueku", cookie: cookie, env: env);
  }

  ///电台
  ///
  ///说明 : 调用此接口 , 可获取所有电台数据
  ///
  ///接口地址： /fm/class
  ///
  ///调用例子： /fm/class
  MusicResponse fm_class(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/fm/class", cookie: cookie, env: env);
  }

  ///电台 - 推荐
  ///
  ///说明 : 调用此接口 , 可获取推荐电台
  ///
  ///接口地址： /fm/recommend
  ///
  ///调用例子： /fm/recommend
  MusicResponse fm_recommend(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/fm/recommend", cookie: cookie, env: env);
  }

  ///电台 - 图片
  ///
  ///说明 : 调用此接口 , 可获取对应电台的图片
  ///
  ///必选参数：
  ///
  ///fmid: fmid，可以传多个，以逗号分割
  ///
  ///接口地址： /fm/image
  ///
  ///调用例子： /fm/image?fmid=693 /fm/image?fmid=693,37
  MusicResponse fm_image(String fmid,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/fm/image",
        cookie: cookie, env: env, query: {'fmid': fmid});
  }

  ///电台 - 音乐列表
  ///
  ///说明 : 调用此接口 , 可获取对应电台的音乐列表
  ///
  ///必选参数：
  ///
  ///fmid: fmid，可以传多个，以逗号分割
  ///
  ///可选参数：
  ///
  ///fmtype: fmtype, 可以传多个，以逗号分割
  ///
  ///fmoffset: 歌曲偏移，可以传多个，以逗号分割
  ///
  ///fmsize: 歌曲列表大小，可以传多个，以逗号分割
  ///
  ///接口地址： /fm/songs
  ///
  ///调用例子： /fm/image?fmid=693 /fm/image?fmid=693,37&fmtype=2,2&fmoffset=,5&fmsize5,3
  MusicResponse fm_songs(String fmid,
      {String? fmtype,
      String? fmoffset,
      String? fmsize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/fm/songs", cookie: cookie, env: env, query: {
      'fmid': fmid,
      'fmtype': fmtype,
      'fmoffset': fmoffset,
      'fmsize': fmsize
    });
  }

  ///编辑精选
  ///
  ///说明 : 调用此接口 , 可获取编辑精选数据
  ///
  ///接口地址： /top/ip
  ///
  ///调用例子： /top/ip
  MusicResponse top_ip(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/top/ip", cookie: cookie, env: env);
  }

  ///编辑精选数据
  ///
  ///说明 : 调用此接口 , 可获取编辑对应数据
  ///
  ///必选参数：
  ///
  ///id: ip id
  ///
  ///可选参数：
  ///
  ///type: 数据类型，audios: 音乐, albums: 专辑, videos: 视频, author_list: 歌手
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///接口地址： /ip
  ///
  ///调用例子： /ip?id=87473 ip?id=87473&type=author_list
  MusicResponse ip(String id,
      {String? type,
      String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/ip",
        cookie: cookie,
        env: env,
        query: {'id': id, 'type': type, 'page': page, 'pagesize': pagesize});
  }

  ///编辑精选歌单
  ///
  ///说明：调用此接口，可获取编辑精选歌单数据
  ///
  ///必选参数：
  ///
  ///id: ip id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///接口地址： /ip/playlist
  ///
  ///调用例子： /ip/playlist?id=87473
  MusicResponse ip_playlist(String id,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/ip/playlist",
        cookie: cookie,
        env: env,
        query: {'id': id, 'page': page, 'pagesize': pagesize});
  }

  ///编辑精选专区
  ///
  ///说明：调用此接口，可获取编辑精选专区相关内容，若数据中没有 ip_id，可使用[/ip/zone/home](#编辑精选专区详情)来获取数据
  ///
  ///接口地址： /ip/zone
  ///
  ///调用例子： /ip/zone
  MusicResponse ip_zone(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/ip/zone", cookie: cookie, env: env);
  }

  ///编辑精选专区详情
  ///
  ///说明：调用此接口，可获取编辑精选专区详情，若[/ip/zone](#编辑精选专区) 数据中没有 ip_id，可使用该接口获取数据
  ///
  ///必选参数：
  ///
  ///id: ip id
  ///
  ///接口地址： /ip/zone/home
  ///
  ///调用例子： /ip/zone/home?id=329
  MusicResponse ip_zone_home(String id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/ip/zone/home",
        cookie: cookie, env: env, query: {'id': id});
  }

  ///领取 VIP（需要登陆，该接口为测试接口,仅限概念版使用，该接口目前不可使用）
  ///
  ///说明 : 调用此接口 , 每天可领取 1 天 VIP 时长，需要领取 8 次，每次增加 3 小时，该接口来自 KG 概念版，非会员用户需要自行测试是否可用(尽量别频繁调用)
  ///
  ///接口地址： /youth/vip
  ///
  ///调用例子： /youth/vip
  MusicResponse youth_vip(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/youth/vip", cookie: cookie, env: env);
  }

  ///领取一天 VIP（需要登陆，该接口为测试接口,仅限概念版使用）
  ///
  ///说明 : 调用此接口 , 领取概念版 VIP，传入日期可领取改日期一天 VIP，该接口来自 KG 概念版，非会员用户需要自行测试是否可用(尽量别频繁调用)
  ///
  ///注意 ⚠️：建议不要领太多天
  ///
  ///必选参数：
  ///
  ///receive_day: 领取 VIP 日期，格式为：2026-01-30
  ///
  ///接口地址： /youth/day/vip
  ///
  ///调用例子： /youth/day/vip
  MusicResponse youth_day_vip(String receive_day,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/youth/day/vip",
        cookie: cookie, env: env, query: {'receive_day': receive_day});
  }

  ///升级概念版 VIP（需要登录，需要先领取一天 VIP，该接口为测试接口,仅限概念版使用）
  ///
  ///说明 : 调用此接口 , 可以升级成畅听 VIP，该接口需要先领取一天 VIP（/youth/day/vip），该接口来自 KG 概念版，非会员用户需要自行测试是否可用(尽量别频繁
  ///调用)
  ///
  ///接口地址： /youth/day/vip/upgrade
  ///
  ///调用例子： /youth/day/vip/upgrade
  MusicResponse youth_day_vip_upgrade(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/youth/day/vip/upgrade", cookie: cookie, env: env);
  }

  ///获取当月已领取 VIP 天数（需要登陆，该接口为测试接口,仅限概念版使用）
  ///
  ///说明 : 调用此接口 ,获取当月已领取 VIP 天数
  ///
  ///接口地址： /youth/month/vip/record
  ///
  ///调用例子： /youth/month/vip/record
  MusicResponse youth_month_vip_record(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/youth/month/vip/record", cookie: cookie, env: env);
  }

  ///获取已领取 VIP 状态（需要登陆，该接口为测试接口,仅限概念版使用）
  ///
  ///说明 : 调用此接口 ,获取已领取 VIP 状态
  ///
  ///接口地址： /youth/union/vip
  ///
  ///调用例子： /youth/union/vip
  MusicResponse youth_union_vip(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/youth/union/vip", cookie: cookie, env: env);
  }

  ///获取歌手列表
  ///
  ///说明 : 调用此接口，可以获取歌手列表.
  ///
  ///可选参数：
  ///
  ///sextypes：性别类型，0：全部，1：男，2：女，3：组合
  ///
  ///type：类型，0：全部，1：华语，2：欧美，3：日韩，4：其他，5：日本，6：韩国
  ///
  ///musician：音乐人，3：为音乐人,0：默认
  ///
  ///hotsize：返回热门数量，默认 30
  ///
  ///接口地址： /artist/lists
  ///
  ///调用例子： /artist/lists
  MusicResponse artist_lists(
      {String? sextypes,
      String? type,
      String? musician,
      String? hotsize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/artist/lists", cookie: cookie, env: env, query: {
      'sextypes': sextypes,
      'type': type,
      'musician': musician,
      'hotsize': hotsize
    });
  }

  ///获取歌手详情
  ///
  ///说明 : 调用此接口 , 传入歌手 id, 可获得歌手信息
  ///
  ///必选参数：
  ///
  ///id： 歌手 id
  ///
  ///接口地址： /artist/detail
  ///
  ///调用例子： /artist/detail?id=6539
  MusicResponse artist_detail(String id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/artist/detail",
        cookie: cookie, env: env, query: {'id': id});
  }

  ///获取歌手专辑
  ///
  ///说明 : 调用此接口 , 传入歌手 id, 可获得歌手专辑
  ///
  ///必选参数：
  ///
  ///id： 歌手 id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///sort: 排序，hot : 热门, new: 最新
  ///
  ///接口地址： /artist/albums
  ///
  ///调用例子： /artist/albums?id=6539
  MusicResponse artist_albums(String id,
      {String? page,
      String? pagesize,
      String? sort,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/artist/albums",
        cookie: cookie,
        env: env,
        query: {'id': id, 'page': page, 'pagesize': pagesize, 'sort': sort});
  }

  ///获取歌手单曲
  ///
  ///说明 : 调用此接口 , 传入歌手 id, 可获得歌手歌曲
  ///
  ///必选参数：
  ///
  ///id： 歌手 id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///sort: 排序，hot : 热门, new: 最新
  ///
  ///接口地址： /artist/audios
  ///
  ///调用例子： /artist/audios?id=6539
  MusicResponse artist_audios(String id,
      {String? page,
      String? pagesize,
      String? sort,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/artist/audios",
        cookie: cookie,
        env: env,
        query: {'id': id, 'page': page, 'pagesize': pagesize, 'sort': sort});
  }

  ///获取歌手 MV
  ///
  ///说明 : 调用此接口 , 传入歌手 id, 可获得歌手 MV
  ///
  ///必选参数：
  ///
  ///id： 歌手 id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///tag: official: 官方版本，live：现场版本，fan：饭制版本，artist: 歌手发布, all: 获取全部，默认为获取全部
  ///
  ///接口地址： /artist/videos
  ///
  ///调用例子： /artist/videos?id=6539
  MusicResponse artist_videos(String id,
      {String? page,
      String? pagesize,
      String? tag,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/artist/videos",
        cookie: cookie,
        env: env,
        query: {'id': id, 'page': page, 'pagesize': pagesize, 'tag': tag});
  }

  ///关注歌手
  ///
  ///说明：调用此接口, 传入歌手 id, 可以关注该歌手（需要登录）
  ///
  ///必选参数：
  ///
  ///id: 歌手 id
  ///
  ///接口地址： /artist/follow
  ///
  ///调用例子： /artist/follow?id=6539
  MusicResponse artist_follow(String id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/artist/follow",
        cookie: cookie, env: env, query: {'id': id});
  }

  ///取消关注歌手
  ///
  ///说明：调用此接口, 传入歌手 id, 可以取消关注该歌手（需要登录）
  ///
  ///必选参数：
  ///
  ///id: 歌手 id
  ///
  ///接口地址： /artist/unfollow
  ///
  ///调用例子： /artist/unfollow?id=6539
  MusicResponse artist_unfollow(String id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/artist/unfollow",
        cookie: cookie, env: env, query: {'id': id});
  }

  ///获取关注歌手新歌
  ///
  ///说明：调用此接口, 可以获取用户已关注的歌手新歌（需要登录）
  ///
  ///可选参数：
  ///
  ///last_album_id: 最后专辑 id
  ///
  ///pagesize: 每页页数, 默认为 30,
  ///
  ///opt_sort: 排序，1：时间，2：亲密度，默认为 1(时间)
  ///
  ///接口地址： /artist/follow/newsongs
  ///
  ///调用例子： /artist/follow/newsongs
  MusicResponse artist_follow_newsongs(
      {String? last_album_id,
      String? pagesize,
      String? opt_sort,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/artist/follow/newsongs", cookie: cookie, env: env, query: {
      'last_album_id': last_album_id,
      'pagesize': pagesize,
      'opt_sort': opt_sort
    });
  }

  ///获取视频 url
  ///
  ///说明 : 传入的视频的 hash, 可以获取对应的视频的 url
  ///
  ///必选参数：
  ///
  ///hash: 视频 hash
  ///
  ///接口地址： /video/url
  ///
  ///调用例子： /video/url?hash=3B5EE16299F703AEB0E5C28CB152EDF0
  MusicResponse video_url(String hash,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/video/url",
        cookie: cookie, env: env, query: {'hash': hash});
  }

  ///获取歌曲 MV
  ///
  ///说明 : 传入 album_audio_id/MixSongID 获取歌曲 相对应的 mv
  ///
  ///必选参数：
  ///
  ///album_audio_id: 专辑音乐 id (album_audio_id/MixSongID 均可以), 可以传多个，每个以逗号分开,
  ///
  ///可选参数：
  ///
  ///fields: 支持多个，每个以逗号分隔，支持的值有：mkv,tags,h264,h265,authors
  ///
  ///接口地址： /kmr/audio/mv
  ///
  ///调用例子： /kmr/audio/mv?album_audio_id=32155307 /kmr/audio/mv?album_audio_id=32155307&fields=mkv,tags
  MusicResponse kmr_audio_mv(String album_audio_id,
      {String? fields,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/kmr/audio/mv",
        cookie: cookie,
        env: env,
        query: {'album_audio_id': album_audio_id, 'fields': fields});
  }

  ///获取视频相关信息
  ///
  ///说明 : 传入的视频的 hash, 可以获取对应的视频的相关信息
  ///
  ///必选参数：
  ///
  ///hash: 视频 hash，可以传多个，以逗号隔开
  ///
  ///接口地址： /video/privilege
  ///
  ///调用例子： /video/privilege?hash=3B5EE16299F703AEB0E5C28CB152EDF0
  MusicResponse video_privilege(String hash,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/video/privilege",
        cookie: cookie, env: env, query: {'hash': hash});
  }

  ///获取视频详情
  ///
  ///说明：调用此接口，可以获取视频详情，可以获取更高清的视频 hash
  ///
  ///必选参数：
  ///
  ///id: 视频 id/video id
  ///
  ///接口地址： /video/detail
  ///
  ///调用例子： /video/detail?id=11517822
  MusicResponse video_detail(String id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/video/detail",
        cookie: cookie, env: env, query: {'id': id});
  }

  ///新歌速递
  ///
  ///说明：调用此接口，可以获取新歌速递
  ///
  ///接口地址： /top/song
  ///
  ///调用例子： /top/song
  MusicResponse top_song(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/top/song", cookie: cookie, env: env);
  }

  ///场景音乐列表
  ///
  ///说明：调用此接口，可以场景音乐列表
  ///
  ///接口地址： /scene/lists
  ///
  ///调用例子： /scene/lists
  MusicResponse scene_lists(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/scene/lists", cookie: cookie, env: env);
  }

  ///场景音乐详情
  ///
  ///说明：调用此接口，可以场景音乐详情
  ///
  ///必选参数：
  ///
  ///id: 场景音乐 scene_id
  ///
  ///接口地址： /scene/module
  ///
  ///调用例子： /scene/module?id=9
  MusicResponse scene_module(String id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/scene/module",
        cookie: cookie, env: env, query: {'id': id});
  }

  ///获取场景音乐讨论区
  ///
  ///说明：调用此接口，可以获取场景音乐讨论区
  ///
  ///必选参数
  ///
  ///id: 场景音乐 scene_id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///sort: 排序，rec: 推荐，hot: 热门，new: 最新, 默认为推荐
  ///
  ///接口地址： /scene/list/v2
  ///
  ///调用例子： /scene/list/?id=9
  MusicResponse scene_list_v2(String id,
      {String? page,
      String? pagesize,
      String? sort,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/scene/list/v2",
        cookie: cookie,
        env: env,
        query: {'id': id, 'page': page, 'pagesize': pagesize, 'sort': sort});
  }

  ///获取场景音乐模块 Tag
  ///
  ///说明：调用此接口，可以获取场景模块 Tag
  ///
  ///必选参数
  ///
  ///id: 场景音乐 scene_id
  ///
  ///module_id: 场景音乐 module_id
  ///
  ///可选参数：
  ///
  ///接口地址： /scene/module/info
  ///
  ///调用例子： /scene/module/info?id=9&module_id=83
  MusicResponse scene_module_info(String id, String module_id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/scene/module/info",
        cookie: cookie, env: env, query: {'id': id, 'module_id': module_id});
  }

  ///获取场景音乐歌单列表
  ///
  ///说明：调用此接口，可以获取场景音乐歌单列表
  ///
  ///必选参数
  ///
  ///tag_id: 场景音乐 tag_id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///接口地址： /scene/collection/list
  ///
  ///调用例子： /scene/collection/list?tag_id=42391
  MusicResponse scene_collection_list(String tag_id,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/scene/collection/list",
        cookie: cookie,
        env: env,
        query: {'tag_id': tag_id, 'page': page, 'pagesize': pagesize});
  }

  ///获取场景音乐视频列表
  ///
  ///说明：调用此接口，可以获取场景音乐视频列表
  ///
  ///必选参数
  ///
  ///tag_id: 场景音乐视频 tag_id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///接口地址： /scene/video/list
  ///
  ///调用例子： /scene/video/list?tag_id=42399
  MusicResponse scene_video_list(String tag_id,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/scene/video/list",
        cookie: cookie,
        env: env,
        query: {'tag_id': tag_id, 'page': page, 'pagesize': pagesize});
  }

  ///获取场景音乐音乐列表
  ///
  ///说明：调用此接口，可以获取场景音乐音乐列表
  ///
  ///必选参数
  ///
  ///id: 场景音乐 scene_id
  ///
  ///module_id: 场景音乐 module_id
  ///
  ///tag: 场景音乐 tag_id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///接口地址： /scene/audio/list
  ///
  ///调用例子： /scene/audio/list?id=9&module_id=173&tag=42391
  MusicResponse scene_audio_list(String id, String module_id, String tag,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/scene/audio/list", cookie: cookie, env: env, query: {
      'id': id,
      'module_id': module_id,
      'tag': tag,
      'page': page,
      'pagesize': pagesize
    });
  }

  ///每日推荐
  ///
  ///说明：调用此接口，可以获取每日推荐列表
  ///
  ///可选参数：
  ///
  ///platform：设备类型，默认为 ios,支持 android 和 ios
  ///
  ///接口地址： /everyday/recommend
  ///
  ///调用例子： /everyday/recommend
  MusicResponse everyday_recommend(
      {String? platform,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/everyday/recommend",
        cookie: cookie, env: env, query: {'platform': platform});
  }

  ///历史推荐
  ///
  ///说明：调用此接口，可以获取历史推荐
  ///
  ///可选参数：
  ///
  ///mode：当 mode 为 list 时，则返回历史推荐列表，当 mode 为 song 时则返回当前歌曲列表，支持参数为：list 和 song,
  ///
  ///history_name: 当 mode 为 song 该参数为必选参数。
  ///
  ///date: 当 mode 为 song 该参数为必选参数。
  ///
  ///platform：设备类型，默认为 ios,支持 android 和 ios
  ///
  ///接口地址： /everyday/history
  ///
  ///调用例子： /everyday/history /everyday/history?mode=song&history_name=RT_336d5ebc5436534e61d16e63ddfca327_20240106&date=20240106
  MusicResponse everyday_history(
      {String? mode,
      String? history_name,
      String? date,
      String? platform,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/everyday/history", cookie: cookie, env: env, query: {
      'mode': mode,
      'history_name': history_name,
      'date': date,
      'platform': platform
    });
  }

  ///风格推荐
  ///
  ///说明：调用此接口，可以获取风格推荐
  ///
  ///可选参数：
  ///
  ///platform：设备类型，默认为 ios,支持 android 和 ios
  ///
  ///tagids：支持多个，每个以逗号分隔，该接口下可获取 tag 信息
  ///
  ///接口地址： /everyday/style/recommend
  ///
  ///调用例子： /everyday/style/recommend /everyday/style/recommend?tagids=S14,S15,S16
  MusicResponse everyday_style_recommend(
      {String? platform,
      String? tagids,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/everyday/style/recommend",
        cookie: cookie,
        env: env,
        query: {'platform': platform, 'tagids': tagids});
  }

  ///排行列表
  ///
  ///说明：调用此接口，可以获取排行榜列表
  ///
  ///可选参数：
  ///
  ///withsong：是否返回歌曲（部分）
  ///
  ///接口地址： /rank/list
  ///
  ///调用例子： /rank/list
  MusicResponse rank_list(
      {String? withsong,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/rank/list",
        cookie: cookie, env: env, query: {'withsong': withsong});
  }

  ///排行榜推荐列表
  ///
  ///说明：调用此接口，可以获取排行榜推荐列表
  ///
  ///接口地址： /rank/top
  ///
  ///调用例子： /rank/top
  MusicResponse rank_top(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/rank/top", cookie: cookie, env: env);
  }

  ///排行榜往期列表
  ///
  ///说明：调用此接口，可以获取排行榜往期列表
  ///
  ///必选参数：
  ///
  ///rankid：排行榜 id
  ///
  ///可选参数：
  ///
  ///rank_cid：排行榜 cid
  ///
  ///接口地址： /rank/vol
  ///
  ///调用例子： /rank/vol?rankid=8888
  MusicResponse rank_vol(String rankid,
      {String? rank_cid,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/rank/vol",
        cookie: cookie,
        env: env,
        query: {'rankid': rankid, 'rank_cid': rank_cid});
  }

  ///排行榜信息
  ///
  ///说明：调用此接口，可以获取排行榜信息
  ///
  ///必选参数：
  ///
  ///rankid：排行榜 id
  ///
  ///可选参数：
  ///
  ///rank_cid：排行榜 cid
  ///
  ///album_img：是否返回专辑图片，1：返回，0：不返回，默认返回
  ///
  ///zone：排行榜 zone
  ///
  ///接口地址： /rank/info
  ///
  ///调用例子： /rank/info?rankid=8888
  MusicResponse rank_info(String rankid,
      {String? rank_cid,
      String? album_img,
      String? zone,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/rank/info", cookie: cookie, env: env, query: {
      'rankid': rankid,
      'rank_cid': rank_cid,
      'album_img': album_img,
      'zone': zone
    });
  }

  ///排行榜歌曲列表
  ///
  ///说明：调用此接口，可以获排行榜歌曲列表
  ///
  ///必选参数：
  ///
  ///rankid：排行榜 id
  ///
  ///可选参数：
  ///
  ///rank_cid：若需要返回往期歌曲列表，则该参数为必填，否则默认返回最新一期，[/rank/vol](#排行榜往期列表) 返回值中，volid 则为该参数
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///接口地址： /rank/audio
  ///
  ///调用例子： /rank/audio?rankid=8888 /rank/audio?rankid=8888&rank_cid=76442
  MusicResponse rank_audio(String rankid,
      {String? rank_cid,
      String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/rank/audio", cookie: cookie, env: env, query: {
      'rankid': rankid,
      'rank_cid': rank_cid,
      'page': page,
      'pagesize': pagesize
    });
  }

  ///歌曲收藏数
  ///
  ///说明 : 调用此接口 , 传入音乐 mixsongids 参数 , 可获得该音乐的收藏数( 不需要登录 )
  ///
  ///必选参数：
  ///
  ///mixsongids：音乐 mixsongid，多个以逗号分隔
  ///
  ///接口地址： /favorite/count
  ///
  ///调用例子： /favorite/count?mixsongids=368015985,368015986 /favorite/count?mixsongids=368015985
  MusicResponse favorite_count(String mixsongids,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/favorite/count",
        cookie: cookie, env: env, query: {'mixsongids': mixsongids});
  }

  ///歌曲评论数
  ///
  ///说明 : 调用此接口 , 传入音乐 hash/special_id 参数 , 可获得该音乐的评论数( 不需要登录 )
  ///
  ///必选参数：
  ///
  ///hash：音乐 hash
  ///
  ///special_id：为 评论下的 special_child_id 字段
  ///
  ///接口地址： /comment/count
  ///
  ///调用例子： /comment/count?hash=98eb07ad8eaf74bf56dece55518ad63e /comment/count?special_id=20505418
  MusicResponse comment_count(String hash, String special_id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/comment/count",
        cookie: cookie,
        env: env,
        query: {'hash': hash, 'special_id': special_id});
  }

  ///歌曲评论
  ///
  ///说明 : 调用此接口 , 传入音乐 mixsongid 参数 , 可获得该音乐的所有评论 ( 不需要登录 )
  ///
  ///必选参数：
  ///
  ///mixsongid：音乐 mixsongid
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///show_classify： 是否返回分类列表，0 为不返回，1 为返回
  ///
  ///show_hotword_list：是否返回热词，0 为不返回，1 为返回
  ///
  ///接口地址： /comment/music
  ///
  ///调用例子： /comment/music?mixsongid=302362878
  MusicResponse comment_music(String mixsongid,
      {String? page,
      String? pagesize,
      String? show_classify,
      String? show_hotword_list,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/comment/music", cookie: cookie, env: env, query: {
      'mixsongid': mixsongid,
      'page': page,
      'pagesize': pagesize,
      'show_classify': show_classify,
      'show_hotword_list': show_hotword_list
    });
  }

  ///歌曲评论-根据分类返回
  ///
  ///说明 : 调用此接口 , 传入音乐 mixsongid 和 type_id 参数 , 可获得该音乐的分类评论 ( 不需要登录 )
  ///
  ///必选参数：
  ///
  ///mixsongid：音乐 mixsongid
  ///
  ///type_id：分类 id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///sort：排序，1 为正序，2 为倒序
  ///
  ///接口地址： /comment/music/classify
  ///
  ///调用例子： /comment/music/classify?mixsongid=302362878&type_id=12
  MusicResponse comment_music_classify(String mixsongid, String type_id,
      {String? page,
      String? pagesize,
      String? sort,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/comment/music/classify", cookie: cookie, env: env, query: {
      'mixsongid': mixsongid,
      'type_id': type_id,
      'page': page,
      'pagesize': pagesize,
      'sort': sort
    });
  }

  ///歌曲评论-根据热词返回
  ///
  ///说明 : 调用此接口 , 传入音乐 mixsongid 和 hot_word 参数 , 可获得该音乐的热词评论 ( 不需要登录 )
  ///
  ///必选参数：
  ///
  ///mixsongid：音乐 mixsongid
  ///
  ///hot_word：热词
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///接口地址： /comment/music/hotword
  ///
  ///调用例子： /comment/music/hotword?mixsongid=302362878&hot_word=生活
  MusicResponse comment_music_hotword(String mixsongid, String hot_word,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/comment/music/hotword", cookie: cookie, env: env, query: {
      'mixsongid': mixsongid,
      'hot_word': hot_word,
      'page': page,
      'pagesize': pagesize
    });
  }

  ///楼层评论
  ///
  ///说明 : 调用此接口 , 传入资源 special_id 和资源类型 tid 和资源 mixsongid 参数, 可获得该资源的歌曲楼层评论
  ///
  ///必选参数：
  ///
  ///special_id：为 评论下的 special_child_id 字段
  ///
  ///mixsongid：为 歌曲的 mixsongid
  ///
  ///tid：评论 id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///接口地址： /comment/floor
  ///
  ///调用例子： /comment/floor?special_id=100285259&mixsongid=302362878&tid=678433417
  MusicResponse comment_floor(String special_id, String tid, String mixsongid,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/comment/floor", cookie: cookie, env: env, query: {
      'special_id': special_id,
      'tid': tid,
      'mixsongid': mixsongid,
      'page': page,
      'pagesize': pagesize
    });
  }

  ///歌单评论
  ///
  ///说明 : 调用此接口 , 传入歌单 id 参数 , 可获得该歌单的所有评论 ( 不需要登录 )
  ///
  ///必选参数：
  ///
  ///id：歌单 global_collection_id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///show_classify： 是否返回分类列表，0 为不返回，1 为返回
  ///
  ///show_hotword_list：是否返回热词，0 为不返回，1 为返回
  ///
  ///接口地址： /comment/playlist
  ///
  ///调用例子： /comment/playlist?id=collection_3_1373407643_366_0
  MusicResponse comment_playlist(String id,
      {String? page,
      String? pagesize,
      String? show_classify,
      String? show_hotword_list,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/comment/playlist", cookie: cookie, env: env, query: {
      'id': id,
      'page': page,
      'pagesize': pagesize,
      'show_classify': show_classify,
      'show_hotword_list': show_hotword_list
    });
  }

  ///专辑评论
  ///
  ///说明 : 调用此接口 , 传入 专辑 id 参数 , 可获得该专辑的所有评论 ( 不需要登录 )
  ///
  ///id：专辑 id
  ///
  ///可选参数：
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///show_classify： 是否返回分类列表，0 为不返回，1 为返回
  ///
  ///show_hotword_list：是否返回热词，0 为不返回，1 为返回
  ///
  ///接口地址： /comment/album
  ///
  ///调用例子： /comment/album?id=collection_3_1373407643_366_0
  MusicResponse comment_album(String id,
      {String? page,
      String? pagesize,
      String? show_classify,
      String? show_hotword_list,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/comment/album", cookie: cookie, env: env, query: {
      'id': id,
      'page': page,
      'pagesize': pagesize,
      'show_classify': show_classify,
      'show_hotword_list': show_hotword_list
    });
  }

  ///歌曲曲谱
  ///
  ///说明 : 调用此接口，传入歌曲 album_audio_id 可获得该歌曲的曲谱，注意：ai 曲谱为 xml 文件，需要自己解析，别问我，我也看不懂
  ///
  ///必选参数：
  ///
  ///album_audio_id：音乐的 mixsongid/album_audio_id
  ///
  ///可选参数：
  ///
  ///opern_type：曲谱类型，0：全部，1：钢琴，2：吉他，3：鼓，98：简谱，99：其他
  ///
  ///page： 页码
  ///
  ///pagesize: 每页页数, 默认为 30
  ///
  ///接口地址： /sheet/list
  ///
  ///调用例子： /sheet/list?album_audio_id=302362878
  MusicResponse sheet_list(String album_audio_id,
      {String? opern_type,
      String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/sheet/list", cookie: cookie, env: env, query: {
      'album_audio_id': album_audio_id,
      'opern_type': opern_type,
      'page': page,
      'pagesize': pagesize
    });
  }

  ///曲谱详情
  ///
  ///说明 : 调用此接口，传入曲谱 id 和 曲谱 source 可获得该曲谱详情，注意：ai 曲谱为 xml 文件，需要自己解析，别问我，我也看不懂
  ///
  ///必选参数：
  ///
  ///id：曲谱 id,
  ///
  ///source：曲谱 source,
  ///
  ///接口地址： /sheet/detail
  ///
  ///调用例子： /sheet/detail?id=1564334343483305984&source=2
  MusicResponse sheet_detail(String id, String source,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/sheet/detail",
        cookie: cookie, env: env, query: {'id': id, 'source': source});
  }

  ///推荐曲谱
  ///
  ///说明 : 调用此接口，可以获取推荐曲谱
  ///
  ///可选参数：
  ///
  ///opern_type：曲谱类型，1：钢琴，2：吉他，3：鼓，98：简谱，99：其他
  ///
  ///接口地址： /sheet/hot
  ///
  ///调用例子： /sheet/hot
  MusicResponse sheet_hot(
      {String? opern_type,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/sheet/hot",
        cookie: cookie, env: env, query: {'opern_type': opern_type});
  }

  ///曲谱合集&&曲谱合集详情(传入不同参数实现不同功能)
  ///
  ///曲谱合集
  ///
  ///说明 : 调用此接口，可以获取曲谱合集
  ///
  ///可选参数：
  ///
  ///position：2：精选谱单，3：音乐教材，4：古典钢琴
  ///
  ///接口地址： /sheet/collection
  ///
  ///调用例子： /sheet/collection
  ///
  ///曲谱合集详情
  ///
  ///说明 : 调用此接口，可以获取曲谱合集详情
  ///
  ///可选参数：
  ///
  ///collection_id：合集 id
  ///
  ///page： 页码
  ///
  ///接口地址： /sheet/collection
  ///
  ///调用例子： /sheet/collection
  MusicResponse sheet_collection(
      {String? position,
      String? collection_id,
      String? page,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/sheet/collection", cookie: cookie, env: env, query: {
      'position': position,
      'collection_id': collection_id,
      'page': page
    });
  }

  ///提交听歌历史
  ///
  ///说明：提交听歌历史后，支持在其他设备上查看听歌历史
  ///
  ///必选参数：
  ///
  ///mxid： 专辑音乐 id (album_audio_id/MixSongID 均可以)
  ///
  ///可选参数：
  ///
  ///ot：当前时间戳, 秒级，不要传入毫秒级，否者会返回错误，或者从 [获取服务器时间](#获取服务器时间) 中获取
  ///
  ///pc: 当前播放次数，更新播放次数，当服务器的值大于传入值时，将维持服务最大值，否则更新
  ///
  ///接口地址： /playhistory/upload
  ///
  ///调用例子： /playhistory/upload?mxid=32155307
  MusicResponse playhistory_upload(String mxid,
      {String? ot,
      String? pc,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/playhistory/upload",
        cookie: cookie, env: env, query: {'mxid': mxid, 'ot': ot, 'pc': pc});
  }

  ///获取服务器时间
  ///
  ///说明：获取服务器时间，返回服务器时间戳
  ///
  ///接口地址： /server/now
  ///
  ///调用例子： /server/now
  MusicResponse server_now(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/server/now", cookie: cookie, env: env);
  }

  ///刷刷
  ///
  ///说明：获取刷刷视频
  ///
  ///接口地址： /brush
  ///
  ///调用例子： /brush
  MusicResponse brush(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/brush", cookie: cookie, env: env);
  }

  ///AI 推荐
  ///
  ///说明：传入 album_audio_id/MixSongID 获取 AI 推荐歌曲
  ///
  ///必选参数：
  ///
  ///album_audio_id： 专辑音乐 id (album_audio_id/MixSongID 均可以), 可以传多个，每个以逗号分开,
  ///
  ///接口地址： /ai/recommend
  ///
  ///调用例子： /ai/recommend?album_audio_id=274565080 /ai/recommend?album_audio_id=274565080,68435124
  MusicResponse ai_recommend(String album_audio_id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/ai/recommend",
        cookie: cookie, env: env, query: {'album_audio_id': album_audio_id});
  }

  ///频道 - 获取用户所有频道
  ///
  ///说明：登录后调用此接口，可以获取用户所有订阅的频道
  ///
  ///可选参数：
  ///
  ///page：页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /youth/channel/all
  ///
  ///调用例子： /youth/channel/all
  MusicResponse youth_channel_all(
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/youth/channel/all",
        cookie: cookie, env: env, query: {'page': page, 'pagesize': pagesize});
  }

  ///频道 - 详情
  ///
  ///说明：调用此接口，传入 global_collection_id / channel_id 可以获取频道详情
  ///
  ///必选参数：
  ///
  ///global_collection_id：频道 id (global_collection_id / channel_id 均可以), 可以传多个，每个以逗号分开,
  ///
  ///接口地址： /youth/channel/detail
  ///
  ///调用例子： /youth/channel/detail?global_collection_id=11576464149
  MusicResponse youth_channel_detail(String global_collection_id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/youth/channel/detail",
        cookie: cookie,
        env: env,
        query: {'global_collection_id': global_collection_id});
  }

  ///频道 - 频道安利
  ///
  ///说明：调用此接口，传入 global_collection_id / channel_id 可以获取频道安利
  ///
  ///必选参数：
  ///
  ///global_collection_id：频道 id (global_collection_id / channel_id 均可以)
  ///
  ///接口地址： /youth/channel/amway
  ///
  ///调用例子： /youth/channel/amway?global_collection_id=11576464149
  MusicResponse youth_channel_amway(String global_collection_id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/youth/channel/amway",
        cookie: cookie,
        env: env,
        query: {'global_collection_id': global_collection_id});
  }

  ///频道 - 相似频道
  ///
  ///说明：调用此接口，传入 global_collection_id / channel_id 可以获取相似频道
  ///
  ///必选参数：
  ///
  ///channel_id：频道 id (global_collection_id / channel_id 均可以)
  ///
  ///接口地址： /youth/channel/similar
  ///
  ///调用例子： /youth/channel/similar?channel_id=11576464149
  MusicResponse youth_channel_similar(String channel_id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/youth/channel/similar",
        cookie: cookie, env: env, query: {'channel_id': channel_id});
  }

  ///频道 - 订阅
  ///
  ///说明：登录后调用此接口， 传入 global_collection_id / channel_id 可订阅频道
  ///
  ///必选参数：
  ///
  ///global_collection_id：频道 id (global_collection_id / channel_id 均可以)
  ///
  ///可选参数：
  ///
  ///t：1 为订阅，0 为取消订阅，不传默认为订阅
  ///
  ///接口地址： /youth/channel/sub
  ///
  ///调用例子： /youth/channel/sub?global_collection_id=11576464149 /youth/channel/sub?global_collection_id=11576464149&t=0
  MusicResponse youth_channel_sub(String global_collection_id,
      {String? t,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/youth/channel/sub",
        cookie: cookie,
        env: env,
        query: {'global_collection_id': global_collection_id, 't': t});
  }

  ///频道 - 音乐故事
  ///
  ///说明：调用此接口，传入 global_collection_id / channel_id 可以获取音乐故事
  ///
  ///必选参数：
  ///
  ///global_collection_id：频道 id (global_collection_id / channel_id 均可以)
  ///
  ///可选参数：
  ///
  ///page：页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /youth/channel/song
  ///
  ///调用例子： /youth/channel/song?global_collection_id=11576464149
  MusicResponse youth_channel_song(String global_collection_id,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/youth/channel/song", cookie: cookie, env: env, query: {
      'global_collection_id': global_collection_id,
      'page': page,
      'pagesize': pagesize
    });
  }

  ///频道 - 音乐故事详情
  ///
  ///说明：调用此接口，传入 global_collection_id / channel_id 和 fileid 可以获取音乐故事详情
  ///
  ///必选参数：
  ///
  ///global_collection_id：频道 id (global_collection_id / channel_id 均可以)
  ///
  ///fileid: 音乐故事 fileid
  ///
  ///接口地址： /youth/channel/song/detail
  ///
  ///调用例子： /youth/channel/song/detail?global_collection_id=11576464149&fileid=1720958083456581
  MusicResponse youth_channel_song_detail(
      String global_collection_id, String fileid,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/youth/channel/song/detail",
        cookie: cookie,
        env: env,
        query: {
          'global_collection_id': global_collection_id,
          'fileid': fileid
        });
  }

  ///动态 - 最常访问
  ///
  ///说明：登录后调用此接口，可以获取经常访问的频道和用户
  ///
  ///接口地址： /youth/dynamic/recent
  ///
  ///调用例子： /youth/dynamic/recent
  MusicResponse youth_dynamic_recent(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/youth/dynamic/recent", cookie: cookie, env: env);
  }

  ///获取用户公开的音乐
  ///
  ///说明：调用此接口，可以获取用户公开的音乐
  ///
  ///必选参数：
  ///
  ///userid：用户 id
  ///
  ///可选参数：
  ///
  ///page：页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /youth/user/song
  ///
  ///调用例子： /youth/user/song?userid=1354894105
  MusicResponse youth_user_song(String userid,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/youth/user/song",
        cookie: cookie,
        env: env,
        query: {'userid': userid, 'page': page, 'pagesize': pagesize});
  }

  ///听书 - 每日推荐
  ///
  ///可选参数：
  ///
  ///page：页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /longaudio/daily/recommend
  ///
  ///调用例子： /longaudio/daily/recommend
  MusicResponse longaudio_daily_recommend(
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/longaudio/daily/recommend",
        cookie: cookie, env: env, query: {'page': page, 'pagesize': pagesize});
  }

  ///听书 - 排行榜推荐
  ///
  ///接口地址： /longaudio/rank/recommend
  ///
  ///调用例子： /longaudio/rank/recommend
  MusicResponse longaudio_rank_recommend(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/longaudio/rank/recommend", cookie: cookie, env: env);
  }

  ///听书 - VIP 推荐
  ///
  ///接口地址： /longaudio/vip/recommend
  ///
  ///调用例子： /longaudio/vip/recommend
  MusicResponse longaudio_vip_recommend(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/longaudio/vip/recommend", cookie: cookie, env: env);
  }

  ///听书 - 每周推荐
  ///
  ///接口地址： /longaudio/week/recommend
  ///
  ///调用例子： /longaudio/week/recommend
  MusicResponse longaudio_week_recommend(
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/longaudio/week/recommend", cookie: cookie, env: env);
  }

  ///听书 - 专辑详情
  ///
  ///必选参数：
  ///
  ///album_id: 专辑 id 可以传多个，每个以逗号分开,
  ///
  ///接口地址： /longaudio/album/detail
  ///
  ///调用例子： /longaudio/album/detail?album_id=56655759
  MusicResponse longaudio_album_detail(String album_id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/longaudio/album/detail",
        cookie: cookie, env: env, query: {'album_id': album_id});
  }

  ///听书 - 专辑音乐列表
  ///
  ///必选参数：
  ///
  ///album_id: 专辑 id 可以传多个
  ///
  ///接口地址： /longaudio/album/audios
  ///
  ///调用例子： /longaudio/album/audios?album_id=56655759
  MusicResponse longaudio_album_audios(String album_id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/longaudio/album/audios",
        cookie: cookie, env: env, query: {'album_id': album_id});
  }

  ///歌曲详情 - 歌曲成绩单
  ///
  ///说明：调用此接口，可以获取歌曲详情里面的歌曲成绩单信息
  ///
  ///必选参数：
  ///
  ///album_audio_id： 专辑音乐 id (album_audio_id/MixSongID 均可以),
  ///
  ///接口地址： /song/ranking
  ///
  ///调用例子： /song/ranking?album_audio_id=32155307
  MusicResponse song_ranking(String album_audio_id,
      {Map<String, String> cookie = const {}, KugouProcessEnv? env}) {
    return request("/song/ranking",
        cookie: cookie, env: env, query: {'album_audio_id': album_audio_id});
  }

  ///歌曲详情 - 歌曲成绩单详情
  ///
  ///说明：登陆后调用此接口，可以获取更详细的歌曲成绩单信息
  ///
  ///必选参数：
  ///
  ///album_audio_id： 专辑音乐 id (album_audio_id/MixSongID 均可以),
  ///
  ///可选参数：
  ///
  ///page：页数
  ///
  ///pagesize : 每页页数, 默认为 30
  ///
  ///接口地址： /song/ranking/filter
  ///
  ///调用例子： /song/ranking/filter?album_audio_id=32155307
  MusicResponse song_ranking_filter(String album_audio_id,
      {String? page,
      String? pagesize,
      Map<String, String> cookie = const {},
      KugouProcessEnv? env}) {
    return request("/song/ranking/filter", cookie: cookie, env: env, query: {
      'album_audio_id': album_audio_id,
      'page': page,
      'pagesize': pagesize
    });
  }
}
