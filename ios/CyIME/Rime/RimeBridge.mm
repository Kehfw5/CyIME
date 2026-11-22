#import "RimeBridge.h"

#include "rime_api.h"

// X11 keysym 常量（librime 的 process_key 使用）。
static const int XK_space      = 0x0020;
static const int XK_BackSpace  = 0xFF08;
static const int XK_Tab        = 0xFF09;
static const int XK_Return     = 0xFF0D;
static const int XK_Escape     = 0xFF1B;
static const int XK_Left       = 0xFF51;
static const int XK_Up         = 0xFF52;
static const int XK_Right      = 0xFF53;
static const int XK_Down       = 0xFF54;
static const int XK_Page_Up    = 0xFF55;
static const int XK_Page_Down  = 0xFF56;
static const int XK_Delete     = 0xFFFF;

// 修饰键位掩码。
static const int RimeShiftMask   = 1;
static const int RimeControlMask = 4;

@interface RimeBridge () {
    RimeApi *_api;
    RimeSessionId _sessionId;
    BOOL _sessionValid;
    BOOL _ready;
    NSString *_sharedDataDir;
    NSString *_userDataDir;
}
@end

@implementation RimeBridge

+ (instancetype)shared {
    static RimeBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RimeBridge alloc] init];
    });
    return instance;
}

+ (BOOL)isReady {
    return [self shared]->_ready;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessionId = 0;
        _sessionValid = NO;
        _ready = NO;
    }
    return self;
}

- (void)dealloc {
    [self finalize];
}

- (BOOL)setupWithSharedDataDir:(NSString *)sharedDir userDataDir:(NSString *)userDir {
    _sharedDataDir = [sharedDir copy];
    _userDataDir = [userDir copy];

    _api = rime_get_api();
    if (_api == NULL) {
        return NO;
    }

    RimeTraits traits = {0};
    RIME_STRUCT_INIT(RimeTraits, traits);
    traits.shared_data_dir = _sharedDataDir.UTF8String;
    traits.user_data_dir = _userDataDir.UTF8String;
    traits.app_name = "rime.cyime";
    traits.distribution_name = "CyIME";
    traits.distribution_code_name = "cyime";
    traits.distribution_version = "0.1.0";
    traits.min_log_level = 1; // WARNING

    _api->setup(&traits);
    _api->initialize(&traits);

    _ready = YES;
    return YES;
}

- (void)finalize {
    if (_api == NULL) return;
    if (_sessionValid) {
        _api->destroy_session(_sessionId);
        _sessionValid = NO;
        _sessionId = 0;
    }
    _api->finalize();
    _api = NULL;
    _ready = NO;
}

- (BOOL)deploy {
    if (_api == NULL) return NO;
    // 引擎已 initialize。full_check=TRUE 触发全量维护（构建/重建 .bin），
    // 再等待维护线程结束。标准用法即 StartMaintenance + JoinMaintenanceThread。
    Bool started = _api->start_maintenance(True);
    if (started) {
        _api->join_maintenance_thread();
    }
    return started ? YES : NO;
}

- (BOOL)createSession {
    if (_api == NULL) return NO;
    _sessionId = _api->create_session();
    _sessionValid = (_sessionId != 0);
    return _sessionValid;
}

- (void)destroySession {
    if (_api == NULL || !_sessionValid) return;
    _api->destroy_session(_sessionId);
    _sessionValid = NO;
    _sessionId = 0;
}

- (void)processKey:(int)keycode mask:(int)mask {
    if (_api == NULL || !_sessionValid) return;
    _api->process_key(_sessionId, keycode, mask);
}

- (nullable NSString *)takeCommit {
    if (_api == NULL || !_sessionValid) return nil;

    RimeCommit commit = {0};
    RIME_STRUCT_INIT(RimeCommit, commit);
    if (!_api->get_commit(_sessionId, &commit)) {
        return nil;
    }

    NSString *text = nil;
    if (commit.text != NULL) {
        text = [NSString stringWithUTF8String:commit.text];
    }
    _api->free_commit(&commit);
    return text;
}

- (nullable NSString *)preedit {
    if (_api == NULL || !_sessionValid) return nil;

    RimeContext ctx = {0};
    RIME_STRUCT_INIT(RimeContext, ctx);
    if (!_api->get_context(_sessionId, &ctx)) {
        return nil;
    }

    NSString *text = nil;
    if (ctx.composition.preedit != NULL) {
        text = [NSString stringWithUTF8String:ctx.composition.preedit];
    }
    _api->free_context(&ctx);
    return text;
}

- (NSArray<NSString *> *)candidates {
    if (_api == NULL || !_sessionValid) return @[];

    RimeContext ctx = {0};
    RIME_STRUCT_INIT(RimeContext, ctx);
    if (!_api->get_context(_sessionId, &ctx)) {
        return @[];
    }

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    int count = ctx.menu.num_candidates;
    for (int i = 0; i < count; i++) {
        const char *c = ctx.menu.candidates[i].text;
        if (c != NULL) {
            [result addObject:[NSString stringWithUTF8String:c]];
        }
    }
    _api->free_context(&ctx);
    return result;
}

- (void)selectCandidateAtIndex:(NSInteger)index {
    if (_api == NULL || !_sessionValid) return;
    _api->select_candidate_on_current_page(_sessionId, (int)index);
}

- (void)commitComposition {
    if (_api == NULL || !_sessionValid) return;
    _api->commit_composition(_sessionId);
}

- (void)clearComposition {
    if (_api == NULL || !_sessionValid) return;
    _api->clear_composition(_sessionId);
}

- (void)setAsciiMode:(BOOL)ascii {
    if (_api == NULL || !_sessionValid) return;
    _api->set_option(_sessionId, "ascii_mode", ascii ? True : False);
}

- (BOOL)asciiMode {
    if (_api == NULL || !_sessionValid) return NO;
    return _api->get_option(_sessionId, "ascii_mode") == True;
}

- (nullable NSString *)schemaId {
    if (_api == NULL || !_sessionValid) return nil;

    char buffer[256] = {0};
    if (!_api->get_current_schema(_sessionId, buffer, sizeof(buffer))) {
        return nil;
    }
    return [NSString stringWithUTF8String:buffer];
}

- (NSArray<NSString *> *)previewCandidatesForCode:(NSString *)code {
    if (_api == NULL || code.length == 0) return @[];

    RimeSessionId preview = _api->create_session();
    if (preview == 0) return @[];

    NSMutableArray<NSString *> *result = [NSMutableArray array];
    _api->set_input(preview, code.UTF8String);
    RimeContext ctx = {0};
    RIME_STRUCT_INIT(RimeContext, ctx);
    if (_api->get_context(preview, &ctx)) {
        for (int i = 0; i < ctx.menu.num_candidates; i++) {
            const char *text = ctx.menu.candidates[i].text;
            if (text != NULL) {
                [result addObject:[NSString stringWithUTF8String:text]];
            }
        }
        _api->free_context(&ctx);
    }
    _api->destroy_session(preview);
    return result;
}

@end
