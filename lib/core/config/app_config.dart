/// 应用配置模型（仅保留「订阅转换 → 延迟优选 → 推送 GitHub」三步流程所需字段）。
///
/// 普通 Dart class + 手写 fromJson/toJson，避免 codegen 复杂度。所有字段带默认值，
/// 等价于旧版 Python config.Config 的 pydantic Field(default=...)。SharedPreferences
/// 中的旧键（CF DNS / WxPusher / ASN / 可用性 / 广告 / 旧筛选等）读时忽略，向后兼容。
class AppConfig {
  // ============ 订阅转换 ============
  final bool subConvertEnabled;
  final String subInputMode;
  final List<String> subUrls;
  final String subNodeHost;
  final String subNodeUuid;
  final List<String> subGenerators;
  final Set<String> subDisabledGenerators;
  final String subOutputFile;
  final String subDefaultCountry;
  final bool subResolveDomain;
  final int subFetchTimeout;
  final int subFetchConnectTimeout;
  final int subFetchMaxRetries;
  final int subFetchRetryDelay;
  final int subResolveWorkers;

  // ============ 延迟优选 ============
  final int subLatencyMaxMs;
  final int subLatencyTopN; // 按质量分保留前 N 名推送（0/负表示全部保留）
  final String subLatencyOutputFile;
  final double subLatencyTimeout;
  final int subLatencyWorkers;
  final int subLatencyProbes;
  final String subLatencySni;

  // ============ 带宽测速 ============
  final bool subSpeedEnabled;
  final int subSpeedLatencyLimit; // 仅对延迟 ≤ 该值(ms)的节点测带宽
  final double subSpeedTimeout;
  final double subSpeedSizeMb;
  final int subSpeedWorkers;
  final double subQualityLatencyWeight; // 综合优选延迟权重(0-1)，带宽权重 = 1 - 该值

  // ============ GitHub 推送（独立 cf-ip 仓） ============
  final String githubToken;
  final String githubRepo;
  final String githubBranch;

  // ============ 外观 ============
  final String guiTheme;

  // ============ 数据源（仅 url 列表，供 UI 编辑） ============
  final List<SourceConfig> additionalSources;

  const AppConfig({
    this.subConvertEnabled = true,
    this.subInputMode = 'both',
    this.subUrls = const [],
    this.subNodeHost = 'example.com',
    this.subNodeUuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx',
    this.subGenerators = defaultSubGenerators,
    this.subDisabledGenerators = const {},
    this.subOutputFile = 'addressesapi.txt',
    this.subDefaultCountry = '',
    this.subResolveDomain = true,
    this.subFetchTimeout = 20,
    this.subFetchConnectTimeout = 10,
    this.subFetchMaxRetries = 3,
    this.subFetchRetryDelay = 3,
    this.subResolveWorkers = 32,
    this.subLatencyMaxMs = 200,
    this.subLatencyTopN = 50,
    this.subLatencyOutputFile = 'addressesapi_top.txt',
    this.subLatencyTimeout = 3.0,
    this.subLatencyWorkers = 50,
    this.subLatencyProbes = 3,
    this.subLatencySni = 'sdtbu.campusblog.ccwu.cc',
    this.subSpeedEnabled = true,
    this.subSpeedLatencyLimit = 200,
    this.subSpeedTimeout = 20.0,
    this.subSpeedSizeMb = 10.0,
    this.subSpeedWorkers = 10,
    this.subQualityLatencyWeight = 0.6,
    this.githubToken = '',
    this.githubRepo = 'Hoffnungsschimmers/cf-ip',
    this.githubBranch = 'main',
    this.guiTheme = 'light',
    this.additionalSources = defaultAdditionalSources,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    T pick<T>(String key, T fallback) {
      final v = json[key];
      return v is T ? v : fallback;
    }
    List<String> pickStrList(String key, List<String> fallback) {
      final v = json[key];
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String) return v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      return fallback;
    }
    Set<String> pickStrSet(String key, Set<String> fallback) {
      final v = json[key];
      if (v is List) return v.map((e) => e.toString()).toSet();
      return fallback;
    }
    List<SourceConfig> pickSources(String key, List<SourceConfig> fallback) {
      final v = json[key];
      if (v is List) return v.whereType<Map<String, dynamic>>().map(SourceConfig.fromJson).toList();
      return fallback;
    }
    return AppConfig(
      subConvertEnabled: pick('SUB_CONVERT_ENABLED', true),
      subInputMode: pick('SUB_INPUT_MODE', 'both'),
      subUrls: pickStrList('SUB_URLS', const []),
      subNodeHost: pick('SUB_NODE_HOST', 'example.com'),
      subNodeUuid: pick('SUB_NODE_UUID', 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'),
      subGenerators: pickStrList('SUB_GENERATORS', const []),
      subDisabledGenerators: pickStrSet('SUB_DISABLED_GENERATORS', const {}),
      subOutputFile: pick('SUB_OUTPUT_FILE', 'addressesapi.txt'),
      subDefaultCountry: pick('SUB_DEFAULT_COUNTRY', ''),
      subResolveDomain: pick('SUB_RESOLVE_DOMAIN', true),
      subFetchTimeout: pick('SUB_FETCH_TIMEOUT', 20),
      subFetchConnectTimeout: pick('SUB_FETCH_CONNECT_TIMEOUT', 10),
      subFetchMaxRetries: pick('SUB_FETCH_MAX_RETRIES', 3),
      subFetchRetryDelay: pick('SUB_FETCH_RETRY_DELAY', 3),
      subResolveWorkers: pick('SUB_RESOLVE_WORKERS', 32),
      subLatencyMaxMs: pick('SUB_LATENCY_MAX_MS', 200),
      subLatencyTopN: pick('SUB_LATENCY_TOP_N', 50),
      subLatencyOutputFile: pick('SUB_LATENCY_OUTPUT_FILE', 'addressesapi_top.txt'),
      subLatencyTimeout: (pick('SUB_LATENCY_TIMEOUT', 3.0) as num).toDouble(),
      subLatencyWorkers: pick('SUB_LATENCY_WORKERS', 50),
      subLatencyProbes: pick('SUB_LATENCY_PROBES', 3),
      subLatencySni: pick('SUB_LATENCY_SNI', 'sdtbu.campusblog.ccwu.cc'),
      subSpeedEnabled: pick('SUB_SPEED_ENABLED', true),
      subSpeedLatencyLimit: pick('SUB_SPEED_LATENCY_LIMIT', 200),
      subSpeedTimeout: (pick('SUB_SPEED_TIMEOUT', 20.0) as num).toDouble(),
      subSpeedSizeMb: (pick('SUB_SPEED_SIZE_MB', 10.0) as num).toDouble(),
      subSpeedWorkers: pick('SUB_SPEED_WORKERS', 10),
      subQualityLatencyWeight: (pick('SUB_QUALITY_LATENCY_WEIGHT', 0.6) as num).toDouble(),
      githubToken: pick('GITHUB_TOKEN', ''),
      githubRepo: pick('GITHUB_REPO', 'Hoffnungsschimmers/cf-ip'),
      githubBranch: pick('GITHUB_BRANCH', 'main'),
      guiTheme: pick('GUI_THEME', 'light'),
      additionalSources: pickSources('ADDITIONAL_SOURCES', const []),
    );
  }

  Map<String, dynamic> toJson() => {
        'SUB_CONVERT_ENABLED': subConvertEnabled,
        'SUB_INPUT_MODE': subInputMode,
        'SUB_URLS': subUrls,
        'SUB_NODE_HOST': subNodeHost,
        'SUB_NODE_UUID': subNodeUuid,
        'SUB_GENERATORS': subGenerators,
        'SUB_DISABLED_GENERATORS': subDisabledGenerators.toList(),
        'SUB_OUTPUT_FILE': subOutputFile,
        'SUB_DEFAULT_COUNTRY': subDefaultCountry,
        'SUB_RESOLVE_DOMAIN': subResolveDomain,
        'SUB_FETCH_TIMEOUT': subFetchTimeout,
        'SUB_FETCH_CONNECT_TIMEOUT': subFetchConnectTimeout,
        'SUB_FETCH_MAX_RETRIES': subFetchMaxRetries,
        'SUB_FETCH_RETRY_DELAY': subFetchRetryDelay,
        'SUB_RESOLVE_WORKERS': subResolveWorkers,
        'SUB_LATENCY_MAX_MS': subLatencyMaxMs,
        'SUB_LATENCY_TOP_N': subLatencyTopN,
        'SUB_LATENCY_OUTPUT_FILE': subLatencyOutputFile,
        'SUB_LATENCY_TIMEOUT': subLatencyTimeout,
        'SUB_LATENCY_WORKERS': subLatencyWorkers,
        'SUB_LATENCY_PROBES': subLatencyProbes,
        'SUB_LATENCY_SNI': subLatencySni,
        'SUB_SPEED_ENABLED': subSpeedEnabled,
        'SUB_SPEED_LATENCY_LIMIT': subSpeedLatencyLimit,
        'SUB_SPEED_TIMEOUT': subSpeedTimeout,
        'SUB_SPEED_SIZE_MB': subSpeedSizeMb,
        'SUB_SPEED_WORKERS': subSpeedWorkers,
        'SUB_QUALITY_LATENCY_WEIGHT': subQualityLatencyWeight,
        'GITHUB_TOKEN': githubToken,
        'GITHUB_REPO': githubRepo,
        'GITHUB_BRANCH': githubBranch,
        'GUI_THEME': guiTheme,
        'ADDITIONAL_SOURCES': additionalSources.map((s) => s.toJson()).toList(),
      };

  AppConfig copyWith({
    bool? subConvertEnabled,
    String? subInputMode,
    List<String>? subUrls,
    String? subNodeHost,
    String? subNodeUuid,
    List<String>? subGenerators,
    Set<String>? subDisabledGenerators,
    String? subOutputFile,
    String? subDefaultCountry,
    bool? subResolveDomain,
    int? subFetchTimeout,
    int? subFetchConnectTimeout,
    int? subFetchMaxRetries,
    int? subFetchRetryDelay,
    int? subResolveWorkers,
    int? subLatencyMaxMs,
    int? subLatencyTopN,
    String? subLatencyOutputFile,
    double? subLatencyTimeout,
    int? subLatencyWorkers,
    int? subLatencyProbes,
    String? subLatencySni,
    bool? subSpeedEnabled,
    int? subSpeedLatencyLimit,
    double? subSpeedTimeout,
    double? subSpeedSizeMb,
    int? subSpeedWorkers,
    double? subQualityLatencyWeight,
    String? githubToken,
    String? githubRepo,
    String? githubBranch,
    String? guiTheme,
    List<SourceConfig>? additionalSources,
  }) {
    return AppConfig(
      subConvertEnabled: subConvertEnabled ?? this.subConvertEnabled,
      subInputMode: subInputMode ?? this.subInputMode,
      subUrls: subUrls ?? this.subUrls,
      subNodeHost: subNodeHost ?? this.subNodeHost,
      subNodeUuid: subNodeUuid ?? this.subNodeUuid,
      subGenerators: subGenerators ?? this.subGenerators,
      subDisabledGenerators: subDisabledGenerators ?? this.subDisabledGenerators,
      subOutputFile: subOutputFile ?? this.subOutputFile,
      subDefaultCountry: subDefaultCountry ?? this.subDefaultCountry,
      subResolveDomain: subResolveDomain ?? this.subResolveDomain,
      subFetchTimeout: subFetchTimeout ?? this.subFetchTimeout,
      subFetchConnectTimeout: subFetchConnectTimeout ?? this.subFetchConnectTimeout,
      subFetchMaxRetries: subFetchMaxRetries ?? this.subFetchMaxRetries,
      subFetchRetryDelay: subFetchRetryDelay ?? this.subFetchRetryDelay,
      subResolveWorkers: subResolveWorkers ?? this.subResolveWorkers,
      subLatencyMaxMs: subLatencyMaxMs ?? this.subLatencyMaxMs,
      subLatencyTopN: subLatencyTopN ?? this.subLatencyTopN,
      subLatencyOutputFile: subLatencyOutputFile ?? this.subLatencyOutputFile,
      subLatencyTimeout: subLatencyTimeout ?? this.subLatencyTimeout,
      subLatencyWorkers: subLatencyWorkers ?? this.subLatencyWorkers,
      subLatencyProbes: subLatencyProbes ?? this.subLatencyProbes,
      subLatencySni: subLatencySni ?? this.subLatencySni,
      subSpeedEnabled: subSpeedEnabled ?? this.subSpeedEnabled,
      subSpeedLatencyLimit: subSpeedLatencyLimit ?? this.subSpeedLatencyLimit,
      subSpeedTimeout: subSpeedTimeout ?? this.subSpeedTimeout,
      subSpeedSizeMb: subSpeedSizeMb ?? this.subSpeedSizeMb,
      subSpeedWorkers: subSpeedWorkers ?? this.subSpeedWorkers,
      subQualityLatencyWeight: subQualityLatencyWeight ?? this.subQualityLatencyWeight,
      githubToken: githubToken ?? this.githubToken,
      githubRepo: githubRepo ?? this.githubRepo,
      githubBranch: githubBranch ?? this.githubBranch,
      guiTheme: guiTheme ?? this.guiTheme,
      additionalSources: additionalSources ?? this.additionalSources,
    );
  }

  /// 校验配置合法性。返回错误字符串列表，为空表示通过。
  List<String> validate() {
    final errors = <String>[];
    if (!['node', 'url', 'both'].contains(subInputMode)) {
      errors.add("SUB_INPUT_MODE 必须是 'node'、'url' 或 'both'");
    }
    return errors;
  }
}

class SourceConfig {
  final String url;
  final bool enabled;

  const SourceConfig({required this.url, this.enabled = true});

  factory SourceConfig.fromJson(Map<String, dynamic> json) => SourceConfig(
        url: json['url']?.toString() ?? '',
        enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      );

  Map<String, dynamic> toJson() => {'url': url, 'enabled': enabled};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceConfig && other.url == url && other.enabled == enabled;

  @override
  int get hashCode => url.hashCode ^ enabled.hashCode;
}

// 默认数据源：edgetunnel 生态常用优选源（公开聚合器）。
const List<SourceConfig> defaultAdditionalSources = [
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/us.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/tw.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/jp.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/hk.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/sg.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/kr.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng/mini.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng2/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng2/mini.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/tiancheng3/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/gslege/Cfxyz.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/gslege/SG.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/gslege/DE.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/gslege/US.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/wetest/ipv4.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/wetest/ipv6.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/cfyes/ipv4.txt'),
  SourceConfig(url: 'https://cf.junzhen.qzz.io/best_ips.txt'),
  SourceConfig(url: 'https://cf.junzhen.qzz.io/best_ips_bj.txt'),
  SourceConfig(url: 'https://cf.090227.xyz/ct?ips=6'),
  SourceConfig(url: 'https://cf.090227.xyz/cu'),
  SourceConfig(url: 'https://cf.090227.xyz/cmcc?ips=8'),
  SourceConfig(url: 'https://090227.pages.dev/bestcf?isp=all&ips=20'),
  SourceConfig(url: 'https://090227.pages.dev/bestcf?isp=ct&ips=50'),
  SourceConfig(url: 'https://090227.pages.dev/bestcf?isp=cu&ips=50'),
  SourceConfig(url: 'https://090227.pages.dev/bestcf?isp=cmcc&ips=50'),
  SourceConfig(url: 'https://bestcf.pages.dev/vps789/top20.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/vps789/top50.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/vps789/top100.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/tw.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/hk.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/jp.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/kr.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/sg.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/s5gy/us.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/cmliu/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/cmliu2/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/lzj/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/lajiao/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/kristi/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/idk/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/moistr/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/ircf/ipv4.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/uouin/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/luoli/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/zhixuanwang/ipv4-onlyip.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/ygkkk/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/qms/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/fiatnorm/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/senflare/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/wuya/all.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/gshtwy/CF-DNS-Clone/refs/heads/main/wetest-cloudflare-v4.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/ymyuuu/IPDB/refs/heads/main/BestCF/bestcfv4.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/ymyuuu/IPDB/refs/heads/main/BestCF/bestcfv6.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/joname1/BestCFip/refs/heads/main/ipv4.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/Senflare/Senflare-IP/refs/heads/main/IPlist-Pro.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/einsitang/my-fast-cf-ip/refs/heads/master/fastips.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/hubbylei/bestcf/refs/heads/main/bestcf.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/love-ztm/cfip/refs/heads/main/best_ips.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/love-ztm/cfip/refs/heads/main/ubest_ips.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/svip-s/cloudflare_ip/refs/heads/main/best_ips.txt'),
  SourceConfig(url: 'https://raw.githubusercontent.com/yuanxiawan/cfipv4db/refs/heads/main/cfip.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/WARP/WARP-MASQUE-IPs-443.txt', enabled: false),
  SourceConfig(url: 'https://warp-masque-bestip.pages.dev/?ips=100&level=all&port=443', enabled: false),
  SourceConfig(url: 'https://warp-masque-bestip.pages.dev/?ips=100&level=198&port=443', enabled: false),
  SourceConfig(url: 'https://warp-masque-bestip.pages.dev/?ips=100&level=197&port=443', enabled: false),
  SourceConfig(url: 'https://warp-masque-bestip.pages.dev/?ips=100&level=193&port=443', enabled: false),
  SourceConfig(url: 'https://warp-masque-bestip.pages.dev/?ips=100&level=192&port=443', enabled: false),
  SourceConfig(url: 'https://addressesapi.090227.xyz/CloudFlareYes'),
  SourceConfig(url: 'https://zip.cm.edu.kg/all.txt'),
  SourceConfig(url: 'https://countrymerge.pages.dev/all.txt'),
  SourceConfig(url: 'https://sub.pjq.cc/cd'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/all.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/mini.txt'),
  SourceConfig(url: 'https://bestcf.pages.dev/domain/Domain-TOP.txt'),
  SourceConfig(url: 'https://randomip.pages.dev/?c=162.159.38.0/24&n=50&p=443', enabled: false),
  SourceConfig(url: 'https://randomip.pages.dev/?c=172.64.0.0/13&n=50&p=random', enabled: false),
  SourceConfig(url: 'https://bestcf.pages.dev/entryip/50.txt', enabled: false),
];

// 默认订阅器（格式：名称|域名）。
const List<String> defaultSubGenerators = [
  'IDK|sub.pjq.cc.cd',
  'CM|sub.cmliussss.net',
  'Moist_R|owo.o00o.ooo',
  '洛璃|loli.sub.us.ci',
  '辣子鸡|sub.lzjbaby.com',
  '辣椒炒肉少放辣|sub.xdu.qzz.io',
  'S5公益|sub.995677.xyz',
  '文烨|sub.keaeye.icu',
  'Kristi|sub.mot.cloudns.biz',
  '天诚|cm.soso.edu.kg',
];
