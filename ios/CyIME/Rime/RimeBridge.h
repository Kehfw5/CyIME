#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 对 librime C API 的轻量 Objective-C 封装。
/// 实现文件为 RimeBridge.mm（Objective-C++），直接调用 rime_api.h。
/// Swift 侧通过 RimeEngine 再包一层，避免在 Swift 里直接操作 C 结构体/函数指针。
@interface RimeBridge : NSObject

/// librime 是否已成功初始化（用于让 Swift 侧在未链接/未就绪时回退到 stub）。
@property (class, nonatomic, readonly) BOOL isReady;

+ (instancetype)shared;

/// 设置数据目录并初始化引擎。需在调用其它方法前执行。
/// sharedDir 放 schema/词库，userDir 放用户词典与 build 产物。
/// 返回 NO 表示初始化失败。
- (BOOL)setupWithSharedDataDir:(NSString *)sharedDir userDataDir:(NSString *)userDir;

/// 结束引擎（进程退出前调用，释放资源）。
- (void)finalize;

/// 执行完整部署（构建 .bin）。首次运行较慢，通常由主 App 调用。
/// 返回 NO 表示部署失败。
- (BOOL)deploy;

/// 创建输入会话。
- (BOOL)createSession;
- (void)destroySession;

/// 处理一次按键。keycode 为 X11 keysym（可见 ASCII 即其码值），
/// mask 为修饰键位掩码（Shift=1, Control=4）。
- (void)processKey:(int)keycode mask:(int)mask;

/// 取出并清空待上屏文本；没有则返回 nil。
- (nullable NSString *)takeCommit;

/// 当前编码（preedit）串；无则返回 nil。
- (nullable NSString *)preedit;

/// 当前候选页文本列表。
- (NSArray<NSString *> *)candidates;

/// 选中当前页第 index 个候选（0-based）。选中会触发上屏。
- (void)selectCandidateAtIndex:(NSInteger)index;

/// 直接提交当前编码。
- (void)commitComposition;

/// 清空当前编码（不提交）。
- (void)clearComposition;

/// ASCII（英文）模式开关。
- (void)setAsciiMode:(BOOL)ascii;
- (BOOL)asciiMode;

/// 当前 schema id。
- (nullable NSString *)schemaId;

@end

NS_ASSUME_NONNULL_END
