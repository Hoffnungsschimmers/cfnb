/// 应用配置模型（对应旧版 Python config.Config）。
///
/// 采用普通 Dart class + 手写 fromJson/toJson，避免早期引入 codegen 复杂度。
/// 所有字段均带默认值，等价于旧版的 pydantic Field(default=...)。
class AppConfig {
  // ============ 筛选模式与数量控制 ============
  final bool useGlobalMode;
  final int globalTopN;
  final int perCountryTopN;
  final Map<String, int> perCountryQuota;
  final int bandwidthCandidates;
  final int dnsUpdateTargetCount;
  final double qualitySpeedWeight;
  final double qualityLatencyWeight;

  // ============ TCP 连接测试参数 ============
  final int tcpProbes;
  final double minSuccessRate;
  final double timeout;
  final int socketDefaultTimeout;
  final double progressPrintInterval;

  // ============ 前置过滤参数 ============
  final bool preFilterPortEnabled;
  final List<int> preFilterPorts;
  final bool preFilterBlockedEnabled;
  final List<String> preFilterBlockedCountries;
  final bool filterCountriesEnabled;
  final List<String> allowedCountries;

  // ============ DNS 过滤参数 ============
  final bool filterBlockedCountriesEnabled;
  final List<String> blockedCountries;
  final bool dnsIpRiskFilterEnabled;
  final String dnsIpRiskMaxLevel;
  final bool filterIpv6Availability;

  // ============ 微信通知 (WxPusher) ============
  final bool enableWxpusher;
  final String wxpusherAppToken;
  final List<String> wxpusherUids;
  final String wxpusherApiUrl;
  final int notifyTimeout;
  final int notifyConnectTimeout;

  // ============ GUI 外观 ============
  final String guiTheme;

  // ============ Cloudflare DNS 批量更新 ============
  final bool cfEnabled;
  final String cfApiToken;
  final String cfZoneId;
  final String cfDnsRecordName;
  final int cfTtl;
  final bool cfProxied;
  final int cfDnsConnectTimeout;
  final int cfDnsReadTimeout;
  final String dnsRecordType;

  // ============ 节点数据源 ============
  final List<SourceConfig> additionalSources;
  final int fetchMaxRetries;
  final int fetchRetryDelay;
  final int fetchTimeout;
  final int fetchConnectTimeout;
  final String outputFile;
  final bool enableLogging;
  final String logFile;

  // ============ ASN 网段数据源 ============
  final bool asnSourcesEnabled;
  final List<int> asnSources;
  final bool asnSourcesIpv6;
  final int asnSourcePort;
  final String asnSourceCountry;
  final int asnSourceMaxIps;
  final int asnSourceTimeout;
  final int asnSourceConnectTimeout;
  final int asnSourceRetryMax;
  final int asnSourceRetryDelay;

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
  final int subLatencyTopN;
  final String subLatencyOutputFile;
  final double subLatencyTimeout;
  final int subLatencyWorkers;

  // ============ 自动调度 ============
  final bool autoScheduleEnabled;
  final double autoScheduleIntervalHours;

  // ============ 可用性检测 ============
  final bool testAvailability;
  final String availabilityCheckApi;
  final int availabilityTimeout;
  final int availabilityConnectTimeout;
  final int availabilityRetryMax;
  final int availabilityRetryDelay;

  // ============ 带宽测速 ============
  final double bandwidthSizeMb;
  final int bandwidthTimeout;
  final int bandwidthRetryMax;
  final int bandwidthRetryDelay;
  final String bandwidthUrlTemplate;
  final int bandwidthProcessBuffer;
  final int bandwidthConnectTimeout;

  // ============ 并发控制 ============
  final int maxWorkers;
  final int availabilityWorkers;
  final int fallbackWorkers;
  final int bandwidthWorkers;

  // ============ 重试策略 ============
  final int dnsUpdateMaxRetries;
  final int dnsUpdateRetryDelay;
  final int githubSyncMaxRetries;
  final int githubSyncRetryDelay;
  final int gitSyncProcessTimeout;

  // ============ 广告植入 ============
  final bool adHeaderEnabled;
  final List<String> adHeaderLines;
  final bool adFooterEnabled;
  final List<String> adFooterLines;
  final bool adPerlineEnabled;
  final String adPerlineText;

  // ============ ip.txt 输出控制 ============
  final bool ipTxtShowBandwidth;
  final bool ipTxtShowLatency;

  const AppConfig({
    this.useGlobalMode = true,
    this.globalTopN = 15,
    this.perCountryTopN = 1,
    this.perCountryQuota = const {},
    this.bandwidthCandidates = 5000,
    this.dnsUpdateTargetCount = 15,
    this.qualitySpeedWeight = 0.60,
    this.qualityLatencyWeight = 0.40,
    this.tcpProbes = 1,
    this.minSuccessRate = 1.0,
    this.timeout = 2.0,
    this.socketDefaultTimeout = 3,
    this.progressPrintInterval = 1.0,
    this.preFilterPortEnabled = true,
    this.preFilterPorts = const [443],
    this.preFilterBlockedEnabled = true,
    this.preFilterBlockedCountries = const ['CN'],
    this.filterCountriesEnabled = false,
    this.allowedCountries = const [],
    this.filterBlockedCountriesEnabled = true,
    this.blockedCountries = const [
      'BD','BI','BY','CD','CF','CN','CU','DE','ET','HK','IR','KP','LY','MO',
      'NG','NL','PK','RU','SD','SO','SY','TH','TW','UA','VE','VN','YE','ZW',
    ],
    this.dnsIpRiskFilterEnabled = false,
    this.dnsIpRiskMaxLevel = '高风险',
    this.filterIpv6Availability = true,
    this.enableWxpusher = true,
    this.wxpusherAppToken = 'your_app_token_here',
    this.wxpusherUids = const ['your_uid_here'],
    this.wxpusherApiUrl = 'https://wxpusher.zjiecode.com/api/send/message',
    this.notifyTimeout = 3,
    this.notifyConnectTimeout = 3,
    this.guiTheme = 'light',
    this.cfEnabled = true,
    this.cfApiToken = 'your_CF_API_TOKEN',
    this.cfZoneId = 'your_CF_ZONE_ID',
    this.cfDnsRecordName = 'your_CF_DNS_RECORD_NAME',
    this.cfTtl = 60,
    this.cfProxied = false,
    this.cfDnsConnectTimeout = 3,
    this.cfDnsReadTimeout = 3,
    this.dnsRecordType = 'TXT',
    this.additionalSources = const [],
    this.fetchMaxRetries = 3,
    this.fetchRetryDelay = 3,
    this.fetchTimeout = 20,
    this.fetchConnectTimeout = 10,
    this.outputFile = 'ip.txt',
    this.enableLogging = false,
    this.logFile = 'cfnb.log',
    this.asnSourcesEnabled = false,
    this.asnSources = const [13335],
    this.asnSourcesIpv6 = false,
    this.asnSourcePort = 443,
    this.asnSourceCountry = 'US',
    this.asnSourceMaxIps = 5000,
    this.asnSourceTimeout = 20,
    this.asnSourceConnectTimeout = 10,
    this.asnSourceRetryMax = 2,
    this.asnSourceRetryDelay = 3,
    this.subConvertEnabled = false,
    this.subInputMode = 'both',
    this.subUrls = const [],
    this.subNodeHost = 'example.com',
    this.subNodeUuid = '00000000-0000-4000-8000-000000000000',
    this.subGenerators = const [],
    this.subDisabledGenerators = const {},
    this.subOutputFile = 'addressesapi.txt',
    this.subDefaultCountry = 'UN',
    this.subResolveDomain = true,
    this.subFetchTimeout = 20,
    this.subFetchConnectTimeout = 10,
    this.subFetchMaxRetries = 3,
    this.subFetchRetryDelay = 3,
    this.subResolveWorkers = 32,
    this.subLatencyTopN = 100,
    this.subLatencyOutputFile = 'addressesapi_top.txt',
    this.subLatencyTimeout = 2.0,
    this.subLatencyWorkers = 50,
    this.autoScheduleEnabled = false,
    this.autoScheduleIntervalHours = 6.0,
    this.testAvailability = true,
    this.availabilityCheckApi = 'https://api.090227.xyz/check',
    this.availabilityTimeout = 3,
    this.availabilityConnectTimeout = 3,
    this.availabilityRetryMax = 2,
    this.availabilityRetryDelay = 3,
    this.bandwidthSizeMb = 0.5,
    this.bandwidthTimeout = 30,
    this.bandwidthRetryMax = 2,
    this.bandwidthRetryDelay = 3,
    this.bandwidthUrlTemplate = 'https://speed.cloudflare.com/__down?bytes={bytes}',
    this.bandwidthProcessBuffer = 5,
    this.bandwidthConnectTimeout = 3,
    this.maxWorkers = 200,
    this.availabilityWorkers = 500,
    this.fallbackWorkers = 32,
    this.bandwidthWorkers = 10,
    this.dnsUpdateMaxRetries = 3,
    this.dnsUpdateRetryDelay = 3,
    this.githubSyncMaxRetries = 3,
    this.githubSyncRetryDelay = 3,
    this.gitSyncProcessTimeout = 180,
    this.adHeaderEnabled = false,
    this.adHeaderLines = const [
      '0.0.0.0:443#格式 或纯文本1',
      '0.0.0.0:443#格式 或纯文本2',
    ],
    this.adFooterEnabled = false,
    this.adFooterLines = const [
      '0.0.0.0:443#格式 或纯文本3',
      '0.0.0.0:443#格式 或纯文本4',
    ],
    this.adPerlineEnabled = false,
    this.adPerlineText = ' 纯文本',
    this.ipTxtShowBandwidth = true,
    this.ipTxtShowLatency = true,
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    T pick<T>(String key, T fallback) {
      final v = json[key];
      return v is T ? v : fallback;
    }

    List<int> pickIntList(String key, List<int> fallback) {
      final v = json[key];
      if (v is List) return v.map((e) => int.tryParse(e.toString()) ?? 0).toList();
      if (v is String) {
        return v.split(',').where((s) => s.trim().isNotEmpty).map((s) => int.tryParse(s.trim()) ?? 0).toList();
      }
      return fallback;
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

    Map<String, int> pickQuota(String key, Map<String, int> fallback) {
      final v = json[key];
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), int.tryParse(val.toString()) ?? 0));
      }
      return fallback;
    }

    List<SourceConfig> pickSources(String key, List<SourceConfig> fallback) {
      final v = json[key];
      if (v is List) {
        return v.whereType<Map<String, dynamic>>().map(SourceConfig.fromJson).toList();
      }
      return fallback;
    }

    return AppConfig(
      useGlobalMode: pick('USE_GLOBAL_MODE', true),
      globalTopN: pick('GLOBAL_TOP_N', 15),
      perCountryTopN: pick('PER_COUNTRY_TOP_N', 1),
      perCountryQuota: pickQuota('PER_COUNTRY_QUOTA', const {}),
      bandwidthCandidates: pick('BANDWIDTH_CANDIDATES', 5000),
      dnsUpdateTargetCount: pick('DNS_UPDATE_TARGET_COUNT', 15),
      qualitySpeedWeight: (pick('QUALITY_SPEED_WEIGHT', 0.60) as num).toDouble(),
      qualityLatencyWeight: (pick('QUALITY_LATENCY_WEIGHT', 0.40) as num).toDouble(),
      tcpProbes: pick('TCP_PROBES', 1),
      minSuccessRate: (pick('MIN_SUCCESS_RATE', 1.0) as num).toDouble(),
      timeout: (pick('TIMEOUT', 2.0) as num).toDouble(),
      socketDefaultTimeout: pick('SOCKET_DEFAULT_TIMEOUT', 3),
      progressPrintInterval: (pick('PROGRESS_PRINT_INTERVAL', 1.0) as num).toDouble(),
      preFilterPortEnabled: pick('PRE_FILTER_PORT_ENABLED', true),
      preFilterPorts: pickIntList('PRE_FILTER_PORTS', const [443]),
      preFilterBlockedEnabled: pick('PRE_FILTER_BLOCKED_ENABLED', true),
      preFilterBlockedCountries: pickStrList('PRE_FILTER_BLOCKED_COUNTRIES', const ['CN']),
      filterCountriesEnabled: pick('FILTER_COUNTRIES_ENABLED', false),
      allowedCountries: pickStrList('ALLOWED_COUNTRIES', const []),
      filterBlockedCountriesEnabled: pick('FILTER_BLOCKED_COUNTRIES_ENABLED', true),
      blockedCountries: pickStrList('BLOCKED_COUNTRIES', const [
        'BD','BI','BY','CD','CF','CN','CU','DE','ET','HK','IR','KP','LY','MO',
        'NG','NL','PK','RU','SD','SO','SY','TH','TW','UA','VE','VN','YE','ZW',
      ]),
      dnsIpRiskFilterEnabled: pick('DNS_IP_RISK_FILTER_ENABLED', false),
      dnsIpRiskMaxLevel: pick('DNS_IP_RISK_MAX_LEVEL', '高风险'),
      filterIpv6Availability: pick('FILTER_IPV6_AVAILABILITY', true),
      enableWxpusher: pick('ENABLE_WXPUSHER', true),
      wxpusherAppToken: pick('WXPUSHER_APP_TOKEN', 'your_app_token_here'),
      wxpusherUids: pickStrList('WXPUSHER_UIDS', const ['your_uid_here']),
      wxpusherApiUrl: pick('WXPUSHER_API_URL', 'https://wxpusher.zjiecode.com/api/send/message'),
      notifyTimeout: pick('NOTIFY_TIMEOUT', 3),
      notifyConnectTimeout: pick('NOTIFY_CONNECT_TIMEOUT', 3),
      guiTheme: pick('GUI_THEME', 'light'),
      cfEnabled: pick('CF_ENABLED', true),
      cfApiToken: pick('CF_API_TOKEN', 'your_CF_API_TOKEN'),
      cfZoneId: pick('CF_ZONE_ID', 'your_CF_ZONE_ID'),
      cfDnsRecordName: pick('CF_DNS_RECORD_NAME', 'your_CF_DNS_RECORD_NAME'),
      cfTtl: pick('CF_TTL', 60),
      cfProxied: pick('CF_PROXIED', false),
      cfDnsConnectTimeout: pick('CF_DNS_CONNECT_TIMEOUT', 3),
      cfDnsReadTimeout: pick('CF_DNS_READ_TIMEOUT', 3),
      dnsRecordType: pick('DNS_RECORD_TYPE', 'TXT'),
      additionalSources: pickSources('ADDITIONAL_SOURCES', const []),
      fetchMaxRetries: pick('FETCH_MAX_RETRIES', 3),
      fetchRetryDelay: pick('FETCH_RETRY_DELAY', 3),
      fetchTimeout: pick('FETCH_TIMEOUT', 20),
      fetchConnectTimeout: pick('FETCH_CONNECT_TIMEOUT', 10),
      outputFile: pick('OUTPUT_FILE', 'ip.txt'),
      enableLogging: pick('ENABLE_LOGGING', false),
      logFile: pick('LOG_FILE', 'cfnb.log'),
      asnSourcesEnabled: pick('ASN_SOURCES_ENABLED', false),
      asnSources: pickIntList('ASN_SOURCES', const [13335]),
      asnSourcesIpv6: pick('ASN_SOURCES_IPV6', false),
      asnSourcePort: pick('ASN_SOURCE_PORT', 443),
      asnSourceCountry: pick('ASN_SOURCE_COUNTRY', 'US'),
      asnSourceMaxIps: pick('ASN_SOURCE_MAX_IPS', 5000),
      asnSourceTimeout: pick('ASN_SOURCE_TIMEOUT', 20),
      asnSourceConnectTimeout: pick('ASN_SOURCE_CONNECT_TIMEOUT', 10),
      asnSourceRetryMax: pick('ASN_SOURCE_RETRY_MAX', 2),
      asnSourceRetryDelay: pick('ASN_SOURCE_RETRY_DELAY', 3),
      subConvertEnabled: pick('SUB_CONVERT_ENABLED', false),
      subInputMode: pick('SUB_INPUT_MODE', 'both'),
      subUrls: pickStrList('SUB_URLS', const []),
      subNodeHost: pick('SUB_NODE_HOST', 'example.com'),
      subNodeUuid: pick('SUB_NODE_UUID', '00000000-0000-4000-8000-000000000000'),
      subGenerators: pickStrList('SUB_GENERATORS', const []),
      subDisabledGenerators: pickStrSet('SUB_DISABLED_GENERATORS', const {}),
      subOutputFile: pick('SUB_OUTPUT_FILE', 'addressesapi.txt'),
      subDefaultCountry: pick('SUB_DEFAULT_COUNTRY', 'UN'),
      subResolveDomain: pick('SUB_RESOLVE_DOMAIN', true),
      subFetchTimeout: pick('SUB_FETCH_TIMEOUT', 20),
      subFetchConnectTimeout: pick('SUB_FETCH_CONNECT_TIMEOUT', 10),
      subFetchMaxRetries: pick('SUB_FETCH_MAX_RETRIES', 3),
      subFetchRetryDelay: pick('SUB_FETCH_RETRY_DELAY', 3),
      subResolveWorkers: pick('SUB_RESOLVE_WORKERS', 32),
      subLatencyTopN: pick('SUB_LATENCY_TOPN', 100),
      subLatencyOutputFile: pick('SUB_LATENCY_OUTPUT_FILE', 'addressesapi_top.txt'),
      subLatencyTimeout: (pick('SUB_LATENCY_TIMEOUT', 2.0) as num).toDouble(),
      subLatencyWorkers: pick('SUB_LATENCY_WORKERS', 50),
      autoScheduleEnabled: pick('AUTO_SCHEDULE_ENABLED', false),
      autoScheduleIntervalHours: (pick('AUTO_SCHEDULE_INTERVAL_HOURS', 6.0) as num).toDouble(),
      testAvailability: pick('TEST_AVAILABILITY', true),
      availabilityCheckApi: pick('AVAILABILITY_CHECK_API', 'https://api.090227.xyz/check'),
      availabilityTimeout: pick('AVAILABILITY_TIMEOUT', 3),
      availabilityConnectTimeout: pick('AVAILABILITY_CONNECT_TIMEOUT', 3),
      availabilityRetryMax: pick('AVAILABILITY_RETRY_MAX', 2),
      availabilityRetryDelay: pick('AVAILABILITY_RETRY_DELAY', 3),
      bandwidthSizeMb: (pick('BANDWIDTH_SIZE_MB', 0.5) as num).toDouble(),
      bandwidthTimeout: pick('BANDWIDTH_TIMEOUT', 30),
      bandwidthRetryMax: pick('BANDWIDTH_RETRY_MAX', 2),
      bandwidthRetryDelay: pick('BANDWIDTH_RETRY_DELAY', 3),
      bandwidthUrlTemplate: pick('BANDWIDTH_URL_TEMPLATE', 'https://speed.cloudflare.com/__down?bytes={bytes}'),
      bandwidthProcessBuffer: pick('BANDWIDTH_PROCESS_BUFFER', 5),
      bandwidthConnectTimeout: pick('BANDWIDTH_CONNECT_TIMEOUT', 3),
      maxWorkers: pick('MAX_WORKERS', 200),
      availabilityWorkers: pick('AVAILABILITY_WORKERS', 500),
      fallbackWorkers: pick('FALLBACK_WORKERS', 32),
      bandwidthWorkers: pick('BANDWIDTH_WORKERS', 10),
      dnsUpdateMaxRetries: pick('DNS_UPDATE_MAX_RETRIES', 3),
      dnsUpdateRetryDelay: pick('DNS_UPDATE_RETRY_DELAY', 3),
      githubSyncMaxRetries: pick('GITHUB_SYNC_MAX_RETRIES', 3),
      githubSyncRetryDelay: pick('GITHUB_SYNC_RETRY_DELAY', 3),
      gitSyncProcessTimeout: pick('GIT_SYNC_PROCESS_TIMEOUT', 180),
      adHeaderEnabled: pick('AD_HEADER_ENABLED', false),
      adHeaderLines: pickStrList('AD_HEADER_LINES', const [
        '0.0.0.0:443#格式 或纯文本1',
        '0.0.0.0:443#格式 或纯文本2',
      ]),
      adFooterEnabled: pick('AD_FOOTER_ENABLED', false),
      adFooterLines: pickStrList('AD_FOOTER_LINES', const [
        '0.0.0.0:443#格式 或纯文本3',
        '0.0.0.0:443#格式 或纯文本4',
      ]),
      adPerlineEnabled: pick('AD_PERLINE_ENABLED', false),
      adPerlineText: pick('AD_PERLINE_TEXT', ' 纯文本'),
      ipTxtShowBandwidth: pick('IP_TXT_SHOW_BANDWIDTH', true),
      ipTxtShowLatency: pick('IP_TXT_SHOW_LATENCY', true),
    );
  }

  Map<String, dynamic> toJson() => {
        'USE_GLOBAL_MODE': useGlobalMode,
        'GLOBAL_TOP_N': globalTopN,
        'PER_COUNTRY_TOP_N': perCountryTopN,
        'PER_COUNTRY_QUOTA': perCountryQuota,
        'BANDWIDTH_CANDIDATES': bandwidthCandidates,
        'DNS_UPDATE_TARGET_COUNT': dnsUpdateTargetCount,
        'QUALITY_SPEED_WEIGHT': qualitySpeedWeight,
        'QUALITY_LATENCY_WEIGHT': qualityLatencyWeight,
        'TCP_PROBES': tcpProbes,
        'MIN_SUCCESS_RATE': minSuccessRate,
        'TIMEOUT': timeout,
        'SOCKET_DEFAULT_TIMEOUT': socketDefaultTimeout,
        'PROGRESS_PRINT_INTERVAL': progressPrintInterval,
        'PRE_FILTER_PORT_ENABLED': preFilterPortEnabled,
        'PRE_FILTER_PORTS': preFilterPorts,
        'PRE_FILTER_BLOCKED_ENABLED': preFilterBlockedEnabled,
        'PRE_FILTER_BLOCKED_COUNTRIES': preFilterBlockedCountries,
        'FILTER_COUNTRIES_ENABLED': filterCountriesEnabled,
        'ALLOWED_COUNTRIES': allowedCountries,
        'FILTER_BLOCKED_COUNTRIES_ENABLED': filterBlockedCountriesEnabled,
        'BLOCKED_COUNTRIES': blockedCountries,
        'DNS_IP_RISK_FILTER_ENABLED': dnsIpRiskFilterEnabled,
        'DNS_IP_RISK_MAX_LEVEL': dnsIpRiskMaxLevel,
        'FILTER_IPV6_AVAILABILITY': filterIpv6Availability,
        'ENABLE_WXPUSHER': enableWxpusher,
        'WXPUSHER_APP_TOKEN': wxpusherAppToken,
        'WXPUSHER_UIDS': wxpusherUids,
        'WXPUSHER_API_URL': wxpusherApiUrl,
        'NOTIFY_TIMEOUT': notifyTimeout,
        'NOTIFY_CONNECT_TIMEOUT': notifyConnectTimeout,
        'GUI_THEME': guiTheme,
        'CF_ENABLED': cfEnabled,
        'CF_API_TOKEN': cfApiToken,
        'CF_ZONE_ID': cfZoneId,
        'CF_DNS_RECORD_NAME': cfDnsRecordName,
        'CF_TTL': cfTtl,
        'CF_PROXIED': cfProxied,
        'CF_DNS_CONNECT_TIMEOUT': cfDnsConnectTimeout,
        'CF_DNS_READ_TIMEOUT': cfDnsReadTimeout,
        'DNS_RECORD_TYPE': dnsRecordType,
        'ADDITIONAL_SOURCES': additionalSources.map((s) => s.toJson()).toList(),
        'FETCH_MAX_RETRIES': fetchMaxRetries,
        'FETCH_RETRY_DELAY': fetchRetryDelay,
        'FETCH_TIMEOUT': fetchTimeout,
        'FETCH_CONNECT_TIMEOUT': fetchConnectTimeout,
        'OUTPUT_FILE': outputFile,
        'ENABLE_LOGGING': enableLogging,
        'LOG_FILE': logFile,
        'ASN_SOURCES_ENABLED': asnSourcesEnabled,
        'ASN_SOURCES': asnSources,
        'ASN_SOURCES_IPV6': asnSourcesIpv6,
        'ASN_SOURCE_PORT': asnSourcePort,
        'ASN_SOURCE_COUNTRY': asnSourceCountry,
        'ASN_SOURCE_MAX_IPS': asnSourceMaxIps,
        'ASN_SOURCE_TIMEOUT': asnSourceTimeout,
        'ASN_SOURCE_CONNECT_TIMEOUT': asnSourceConnectTimeout,
        'ASN_SOURCE_RETRY_MAX': asnSourceRetryMax,
        'ASN_SOURCE_RETRY_DELAY': asnSourceRetryDelay,
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
        'SUB_LATENCY_TOPN': subLatencyTopN,
        'SUB_LATENCY_OUTPUT_FILE': subLatencyOutputFile,
        'SUB_LATENCY_TIMEOUT': subLatencyTimeout,
        'SUB_LATENCY_WORKERS': subLatencyWorkers,
        'AUTO_SCHEDULE_ENABLED': autoScheduleEnabled,
        'AUTO_SCHEDULE_INTERVAL_HOURS': autoScheduleIntervalHours,
        'TEST_AVAILABILITY': testAvailability,
        'AVAILABILITY_CHECK_API': availabilityCheckApi,
        'AVAILABILITY_TIMEOUT': availabilityTimeout,
        'AVAILABILITY_CONNECT_TIMEOUT': availabilityConnectTimeout,
        'AVAILABILITY_RETRY_MAX': availabilityRetryMax,
        'AVAILABILITY_RETRY_DELAY': availabilityRetryDelay,
        'BANDWIDTH_SIZE_MB': bandwidthSizeMb,
        'BANDWIDTH_TIMEOUT': bandwidthTimeout,
        'BANDWIDTH_RETRY_MAX': bandwidthRetryMax,
        'BANDWIDTH_RETRY_DELAY': bandwidthRetryDelay,
        'BANDWIDTH_URL_TEMPLATE': bandwidthUrlTemplate,
        'BANDWIDTH_PROCESS_BUFFER': bandwidthProcessBuffer,
        'BANDWIDTH_CONNECT_TIMEOUT': bandwidthConnectTimeout,
        'MAX_WORKERS': maxWorkers,
        'AVAILABILITY_WORKERS': availabilityWorkers,
        'FALLBACK_WORKERS': fallbackWorkers,
        'BANDWIDTH_WORKERS': bandwidthWorkers,
        'DNS_UPDATE_MAX_RETRIES': dnsUpdateMaxRetries,
        'DNS_UPDATE_RETRY_DELAY': dnsUpdateRetryDelay,
        'GITHUB_SYNC_MAX_RETRIES': githubSyncMaxRetries,
        'GITHUB_SYNC_RETRY_DELAY': githubSyncRetryDelay,
        'GIT_SYNC_PROCESS_TIMEOUT': gitSyncProcessTimeout,
        'AD_HEADER_ENABLED': adHeaderEnabled,
        'AD_HEADER_LINES': adHeaderLines,
        'AD_FOOTER_ENABLED': adFooterEnabled,
        'AD_FOOTER_LINES': adFooterLines,
        'AD_PERLINE_ENABLED': adPerlineEnabled,
        'AD_PERLINE_TEXT': adPerlineText,
        'IP_TXT_SHOW_BANDWIDTH': ipTxtShowBandwidth,
        'IP_TXT_SHOW_LATENCY': ipTxtShowLatency,
      };

  AppConfig copyWith({
    bool? useGlobalMode,
    int? globalTopN,
    String? guiTheme,
    bool? subConvertEnabled,
    bool? autoScheduleEnabled,
    // 主要可变字段；其余沿用
    bool? preFilterPortEnabled,
    List<int>? preFilterPorts,
    bool? cfEnabled,
    String? outputFile,
    bool? testAvailability,
    int? bandwidthWorkers,
    int? maxWorkers,
    bool? filterIpv6Availability,
    bool? enableLogging,
  }) {
    return AppConfig(
      useGlobalMode: useGlobalMode ?? this.useGlobalMode,
      globalTopN: globalTopN ?? this.globalTopN,
      perCountryTopN: perCountryTopN,
      perCountryQuota: perCountryQuota,
      bandwidthCandidates: bandwidthCandidates,
      dnsUpdateTargetCount: dnsUpdateTargetCount,
      qualitySpeedWeight: qualitySpeedWeight,
      qualityLatencyWeight: qualityLatencyWeight,
      tcpProbes: tcpProbes,
      minSuccessRate: minSuccessRate,
      timeout: timeout,
      socketDefaultTimeout: socketDefaultTimeout,
      progressPrintInterval: progressPrintInterval,
      preFilterPortEnabled: preFilterPortEnabled ?? this.preFilterPortEnabled,
      preFilterPorts: preFilterPorts ?? this.preFilterPorts,
      preFilterBlockedEnabled: preFilterBlockedEnabled,
      preFilterBlockedCountries: preFilterBlockedCountries,
      filterCountriesEnabled: filterCountriesEnabled,
      allowedCountries: allowedCountries,
      filterBlockedCountriesEnabled: filterBlockedCountriesEnabled,
      blockedCountries: blockedCountries,
      dnsIpRiskFilterEnabled: dnsIpRiskFilterEnabled,
      dnsIpRiskMaxLevel: dnsIpRiskMaxLevel,
      filterIpv6Availability: filterIpv6Availability ?? this.filterIpv6Availability,
      enableWxpusher: enableWxpusher,
      wxpusherAppToken: wxpusherAppToken,
      wxpusherUids: wxpusherUids,
      wxpusherApiUrl: wxpusherApiUrl,
      notifyTimeout: notifyTimeout,
      notifyConnectTimeout: notifyConnectTimeout,
      guiTheme: guiTheme ?? this.guiTheme,
      cfEnabled: cfEnabled ?? this.cfEnabled,
      cfApiToken: cfApiToken,
      cfZoneId: cfZoneId,
      cfDnsRecordName: cfDnsRecordName,
      cfTtl: cfTtl,
      cfProxied: cfProxied,
      cfDnsConnectTimeout: cfDnsConnectTimeout,
      cfDnsReadTimeout: cfDnsReadTimeout,
      dnsRecordType: dnsRecordType,
      additionalSources: additionalSources,
      fetchMaxRetries: fetchMaxRetries,
      fetchRetryDelay: fetchRetryDelay,
      fetchTimeout: fetchTimeout,
      fetchConnectTimeout: fetchConnectTimeout,
      outputFile: outputFile ?? this.outputFile,
      enableLogging: enableLogging ?? this.enableLogging,
      logFile: logFile,
      asnSourcesEnabled: asnSourcesEnabled,
      asnSources: asnSources,
      asnSourcesIpv6: asnSourcesIpv6,
      asnSourcePort: asnSourcePort,
      asnSourceCountry: asnSourceCountry,
      asnSourceMaxIps: asnSourceMaxIps,
      asnSourceTimeout: asnSourceTimeout,
      asnSourceConnectTimeout: asnSourceConnectTimeout,
      asnSourceRetryMax: asnSourceRetryMax,
      asnSourceRetryDelay: asnSourceRetryDelay,
      subConvertEnabled: subConvertEnabled ?? this.subConvertEnabled,
      subInputMode: subInputMode,
      subUrls: subUrls,
      subNodeHost: subNodeHost,
      subNodeUuid: subNodeUuid,
      subGenerators: subGenerators,
      subDisabledGenerators: subDisabledGenerators,
      subOutputFile: subOutputFile,
      subDefaultCountry: subDefaultCountry,
      subResolveDomain: subResolveDomain,
      subFetchTimeout: subFetchTimeout,
      subFetchConnectTimeout: subFetchConnectTimeout,
      subFetchMaxRetries: subFetchMaxRetries,
      subFetchRetryDelay: subFetchRetryDelay,
      subResolveWorkers: subResolveWorkers,
      subLatencyTopN: subLatencyTopN,
      subLatencyOutputFile: subLatencyOutputFile,
      subLatencyTimeout: subLatencyTimeout,
      subLatencyWorkers: subLatencyWorkers,
      autoScheduleEnabled: autoScheduleEnabled ?? this.autoScheduleEnabled,
      autoScheduleIntervalHours: autoScheduleIntervalHours,
      testAvailability: testAvailability ?? this.testAvailability,
      availabilityCheckApi: availabilityCheckApi,
      availabilityTimeout: availabilityTimeout,
      availabilityConnectTimeout: availabilityConnectTimeout,
      availabilityRetryMax: availabilityRetryMax,
      availabilityRetryDelay: availabilityRetryDelay,
      bandwidthSizeMb: bandwidthSizeMb,
      bandwidthTimeout: bandwidthTimeout,
      bandwidthRetryMax: bandwidthRetryMax,
      bandwidthRetryDelay: bandwidthRetryDelay,
      bandwidthUrlTemplate: bandwidthUrlTemplate,
      bandwidthProcessBuffer: bandwidthProcessBuffer,
      bandwidthConnectTimeout: bandwidthConnectTimeout,
      maxWorkers: maxWorkers ?? this.maxWorkers,
      availabilityWorkers: availabilityWorkers,
      fallbackWorkers: fallbackWorkers,
      bandwidthWorkers: bandwidthWorkers ?? this.bandwidthWorkers,
      dnsUpdateMaxRetries: dnsUpdateMaxRetries,
      dnsUpdateRetryDelay: dnsUpdateRetryDelay,
      githubSyncMaxRetries: githubSyncMaxRetries,
      githubSyncRetryDelay: githubSyncRetryDelay,
      gitSyncProcessTimeout: gitSyncProcessTimeout,
      adHeaderEnabled: adHeaderEnabled,
      adHeaderLines: adHeaderLines,
      adFooterEnabled: adFooterEnabled,
      adFooterLines: adFooterLines,
      adPerlineEnabled: adPerlineEnabled,
      adPerlineText: adPerlineText,
      ipTxtShowBandwidth: ipTxtShowBandwidth,
      ipTxtShowLatency: ipTxtShowLatency,
    );
  }

  /// 校验配置合法性（对应旧版 field_validator / model_validator）。
  /// 返回错误字符串列表，为空表示通过。
  List<String> validate() {
    final errors = <String>[];
    const validRisk = ['极度纯净', '纯净', '轻微风险', '高风险', '极度危险'];
    if (!validRisk.contains(dnsIpRiskMaxLevel)) {
      errors.add('DNS_IP_RISK_MAX_LEVEL 必须是: ${validRisk.join(", ")}');
    }
    if (dnsRecordType != 'A' && dnsRecordType != 'TXT') {
      errors.add('DNS_RECORD_TYPE 必须是 A 或 TXT');
    }
    if (!['node', 'url', 'both'].contains(subInputMode)) {
      errors.add("SUB_INPUT_MODE 必须是 'node'、'url' 或 'both'");
    }
    if (asnSourceCountry.length != 2 || !asnSourceCountry.contains(RegExp(r'^[A-Za-z]+$'))) {
      errors.add('ASN_SOURCE_COUNTRY 必须是两位国家码 (例如 US、JP)');
    }
    if (subDefaultCountry.length != 2 || !subDefaultCountry.contains(RegExp(r'^[A-Za-z]+$'))) {
      errors.add('SUB_DEFAULT_COUNTRY 必须是两位国家码 (例如 UN、US)');
    }
    for (final q in perCountryQuota.values) {
      if (q < 0) errors.add('PER_COUNTRY_QUOTA 不能包含负数');
    }
    if (qualitySpeedWeight < 0 || qualitySpeedWeight > 1) {
      errors.add('QUALITY_SPEED_WEIGHT 必须在 0~1 之间');
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
}
