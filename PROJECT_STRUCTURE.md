# Metronome App 项目结构说明

> 维护约定：以后每次修改项目结构、主要功能、平台能力、依赖、数据表、通道协议或关键文件职责，都必须同步更新本文件。代码变了但本文档没变，视为未完成交付。

这是一款 Flutter + Android 原生低延迟节拍引擎的节拍器应用。Flutter 负责三页 UI、WebView、设置抽屉、配置保存、倒计时、调音器展示和状态同步；Android 原生层负责 SoundPool 播放、前台服务、音频焦点、WakeLock、振动、TTS、麦克风采集、基频检测和事件回传。

## 快速入口

- Flutter 主入口：[lib/main.dart](lib/main.dart)
- 本地数据库封装：[lib/metronome_database.dart](lib/metronome_database.dart)
- Android 原生入口：[android/app/src/main/kotlin/com/example/metronome_app/MainActivity.kt](android/app/src/main/kotlin/com/example/metronome_app/MainActivity.kt)
- Android 前台服务：[android/app/src/main/kotlin/com/example/metronome_app/MetronomeService.kt](android/app/src/main/kotlin/com/example/metronome_app/MetronomeService.kt)
- Android 节拍调度引擎：[android/app/src/main/kotlin/com/example/metronome_app/MetronomeEngine.kt](android/app/src/main/kotlin/com/example/metronome_app/MetronomeEngine.kt)
- Android 配置模型与事件发射：[android/app/src/main/kotlin/com/example/metronome_app/MetronomeModels.kt](android/app/src/main/kotlin/com/example/metronome_app/MetronomeModels.kt)
- Android 调音器音频分析：[android/app/src/main/kotlin/com/example/metronome_app/TunerAnalyzer.kt](android/app/src/main/kotlin/com/example/metronome_app/TunerAnalyzer.kt)
- Widget 与逻辑测试：[test/widget_test.dart](test/widget_test.dart)
- 当前重构需求：[节拍器重构需求文档.md](节拍器重构需求文档.md)

## 顶层目录

```text
.
├── lib/                         # Flutter/Dart 应用主体
│   ├── main.dart                 # UI、状态、通道、Tap Tempo 等主实现
│   └── metronome_database.dart   # sqflite 设置、练习记录、已保存配置
├── android/                     # Android 原生工程与节拍引擎
├── assets/
│   ├── images/                  # 图标、演示图等图片资源
│   └── sounds/                  # Flutter 侧声明的 wav 音效资源
├── test/                        # Flutter widget test 与纯 Dart 逻辑测试
├── ios/ macos/ linux/ windows/  # Flutter 初始化生成的平台壳工程
├── web/                         # Flutter Web 壳工程
├── pubspec.yaml                 # 依赖、资源、launcher icon 配置
├── analysis_options.yaml        # Flutter lint 配置
└── PROJECT_STRUCTURE.md         # 当前文档，改动后必须同步更新
```

## 当前 App 结构

底部导航当前为三页：

- `吉他社`：`GuitarSocietyPage`，加载 `https://www.jitashe.org/` 的 WebView，右下角有共享播放状态的 Start/Stop 悬浮按钮。页面首次访问后由 `IndexedStack` 保活，底部切换不会重新创建 WebView。
- `节拍器`：默认首页，包含顶部功能按钮、轻重拍编辑条、BPM 圆盘、Start/Stop。第三轮已移除首页 Stats，练习统计后续迁移到独立页面。
- `设置`：`SettingsPage`，支持输入名称保存当前配置、查看、恢复和删除已保存配置。

播放状态集中在 `_MetronomeMainPageState`，首页 Start 按钮、WebView 悬浮按钮、倒计时自动停止都调用同一套 `_setPlayback` / `_togglePlayback` 逻辑。底部页面通过“访问后懒加载 + IndexedStack 保活”管理，避免 WebView 每次切换都重新加载。

## Flutter 主文件职责

[lib/main.dart](lib/main.dart) 当前仍是较大的单文件实现，主要分为这些模块：

- `main()` / `_applyImmersiveMode()`：启动 Flutter，设置沉浸式系统 UI。
- `MyApp`：Material 主题与入口页面。
- `MetronomeMainPage` / `_MetronomeMainPageState`：全局状态中心，维护 BPM、拍号、轻重拍配置、音色、定时器、播放状态、练习时长、保存配置和 Android 通道。
- `TopFunctionBar` / `FunctionButton`：首页顶部四个功能入口：拍号、音色、调音器、定时。
- `BeatPatternBar` / `BeatPatternCell`：轻重拍编辑条，点击循环 `Light -> Secondary -> Accent -> Rest -> Light`，长按打开单拍编辑预留面板。
- `BpmDial` / `BpmDialPainter`：BPM 圆盘，外圈拖动调速，中心 Tap Tempo，`+/-` 支持微调和长按连调。
- `TransportPanel`：Start/Stop 控制区。第二轮已删除底部 `BEAT` 计数卡片，第三轮已移除首页 Stats 区域。
- `TimeSignatureSheet`：拍号抽屉，双滚轮选择拍数 `1~16` 和时值 `1/2/4/8/16/32`，右上角 Apply，快捷拍型优先一行五个。抽屉不再显示显式关闭按钮，可点击遮罩或下拉关闭。
- `SoundPresetSheet`：音色 UI 入口。第二轮暂不继续开发真实音源逻辑。
- `TunerSheet` / `_TunerDisplay`：真实调音器 UI，通过 Android `tuner/pitch_events` 读取麦克风基频，显示音名、频率、cents 偏差和指针。
- `TimerSheet`：定时抽屉，右上角 Apply，固定尺寸 Off/Countdown，分钟滚轮支持 `1~999`，首页定时按钮显示剩余时间，归零后停止节拍器。滚轮选中框使用 picker 自身 selection overlay，确保数字与选中框居中对齐。
- `GuitarSocietyPage`：WebView 页面和悬浮节拍器按钮。
- `SettingsPage` / `_SavedPresetTile`：保存、恢复、删除本地命名配置。
- `TapTempoTracker`：纯 Dart Tap Tempo 算法，覆盖超时重置、异常值过滤、滑动平均和快速变速适配。
- `MetronomeConfig` / `BeatEvent` / `MetronomeBridge`：Flutter 与 Android 原生层的配置、事件和通道封装。

## 本地数据

[lib/metronome_database.dart](lib/metronome_database.dart) 使用 `sqflite`，数据库文件名为 `pulse_grid.db`，当前版本为 `2`。

数据表：

- `Settings`：最近一次基础设置，用于 App 启动恢复。
- `PracticeLogs`：练习记录，用于今日累计和历史展示。
- `SavedConfigs`：用户命名保存的完整配置，包含 BPM、拍号、轻重拍配置、细分、定时、音色和语言数拍。

Widget test 环境下可能没有 sqflite 初始化，数据库封装会捕获该环境错误，避免 UI 测试被平台数据库阻断。

## Flutter 与 Android 通信

通道定义在 Flutter 的 `MetronomeBridge` 和 Android 的 `MainActivity` 中：

- MethodChannel：`metronome/control`
- EventChannel：`metronome/beat_events`
- EventChannel：`tuner/pitch_events`

Flutter 调用方法：

- `configure`：同步 BPM、拍号、音色、语言、振动、细分、轻重拍/Rest 配置。
- `start`：启动 Android 前台节拍服务。
- `stop`：停止 Android 前台节拍服务。
- `getStatus`：读取原生层当前状态，用于 App 恢复时同步 UI。
- `requestMicrophonePermission`：请求 Android 麦克风权限，供调音器启动采集前使用。

Flutter 下发的 `MetronomeConfig` 关键字段：

- `bpm`
- `beatsPerBar`
- `noteValue`
- `timeSignature`
- `accentSound`
- `regularSound`
- `vocalMode`
- `accentHaptics`
- `subdivisionType`
- `beatTypes`：字符串列表，取值为 `accent / secondary / light / rest`。Android 原生层会将 `rest` 整拍静音。

Android 回传事件：

- `beatIndex`
- `beatsPerBar`
- `cycleCount`
- `timestampNanos`
- `subdivisionIndex`
- `subdivisionSlots`
- `isSilent`

调音器事件：

- `status`：`listening / noSignal / permissionDenied / error`
- `frequency`：检测到的基频 Hz。
- `clarity`：自相关稳定度。
- `rms`：输入信号强度。

## Android 原生层

原生代码位于：

```text
android/app/src/main/kotlin/com/example/metronome_app/
├── MainActivity.kt
├── MetronomeService.kt
├── MetronomeEngine.kt
├── MetronomeModels.kt
└── TunerAnalyzer.kt
```

职责：

- `MainActivity.kt`：注册 MethodChannel / EventChannel，接收 Flutter 指令并转发给服务或状态缓存；同时处理麦克风权限和调音器事件通道。
- `MetronomeService.kt`：前台服务，负责通知、音频焦点、WakeLock、振动、TextToSpeech 和引擎生命周期。
- `MetronomeEngine.kt`：低延迟播放核心，使用 `SoundPool` 预加载 wav，后台线程按纳秒时间调度节拍。Rest 拍会完整跳过音频、细分、振动和 TTS。
- `MetronomeModels.kt`：原生配置模型、Intent 序列化、状态快照和 EventChannel 发射器。
- `TunerAnalyzer.kt`：调音器音频分析器，使用 `AudioRecord` 读取 PCM，并用归一化自相关估算单音基频。

Android 清单：[android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)

当前关键权限：

- `INTERNET`：吉他社 WebView。
- `RECORD_AUDIO`：调音器麦克风输入。
- `WAKE_LOCK`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
- `VIBRATE`
- `POST_NOTIFICATIONS`

## 依赖与资源

[pubspec.yaml](pubspec.yaml) 当前关键依赖：

- `sqflite`：本地设置、练习记录、已保存配置。
- `path`：数据库路径处理。
- `webview_flutter`：吉他社 WebView 页面。
- `flutter_launcher_icons`：Android 启动图标生成。

音效资源：

```text
assets/sounds/
├── click_accent.wav
├── click_electronic.wav
├── click_mechanical.wav
└── click_wood.wav

android/app/src/main/res/raw/
├── click_accent.wav
├── click_electronic.wav
├── click_mechanical.wav
└── click_wood.wav
```

当前低延迟播放实际依赖 Android `res/raw` 下的 wav。替换音色时要同步考虑 Flutter assets 和 Android raw 资源。

## 测试与验证

常用命令：

```powershell
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat build apk --debug
D:\flutter\bin\flutter.bat build apk --release
```

[test/widget_test.dart](test/widget_test.dart) 当前覆盖：

- 首页核心控件渲染。
- 底部导航三页标签。
- 拍号抽屉打开和关键控件。
- 拍号抽屉右上角 Apply。
- 轻重拍 Cell 点击循环。
- 单拍长按预留编辑面板。
- `MetronomeConfig` 能序列化 Rest 拍型。
- BPM 外圈拖拽会触发数值变化。
- Tap Tempo 滑动平均、异常剔除、超时重置、新速度适配。

## Windows / Gradle 注意事项

项目在 `C:`，Flutter / pub cache 可能在 `D:`。此前 Kotlin 增量编译在跨盘符缓存场景下报过错，因此 [android/gradle.properties](android/gradle.properties) 中关闭了 Kotlin 增量编译相关开关：

```properties
kotlin.incremental=false
kotlin.incremental.android=false
kotlin.caching.enabled=false
```

如果未来升级 Kotlin、Gradle 或 Flutter 后想恢复增量编译，建议先在 Windows 跨盘符环境下验证 debug 和 release 构建。

## 后续开发提示

- `lib/main.dart` 已超过 4000 行。下一轮大改建议优先拆分为 `pages/`、`widgets/`、`models/`、`services/`，拆分前后都要保持测试通过。
- 播放状态必须继续集中在 `MetronomeMainPage`，避免首页、WebView 悬浮按钮和倒计时出现不同步。
- Rest 静音必须同时覆盖主拍、细分、TTS 和振动。
- 调音器当前是 Android 原生 `AudioRecord` + 自相关基础识别，后续如追求更高精度可替换为 YIN/MPM 算法。
- 练习统计不再放首页，后续可在独立页面实现类似 GitHub contribution calendar 的练琴日历。
- Tap Tempo 逻辑继续保持纯 Dart 可测试，不要和 UI 动画耦合。
- WebView 只代表 Android/iOS 移动端真实体验，桌面或 Web 壳工程不代表最终低延迟播放表现。

## 2026-04-25 UI 调整记录

- `lib/main.dart` 主节拍器页在 BPM 圆盘外侧下方左右角新增纯图标 `Save` / `Load` 配置快捷入口，避免遮挡圆盘；命名保存使用独立弹窗组件，载入使用较高的底部抽屉，删除后抽屉列表会立即刷新并提示，原 `SavedConfigs` 本地持久化方案保持不变。
- 主节拍器页加大 BPM、配置快捷入口、Start/Stop 控制区之间的竖向间距，Start/Stop 位置整体下移，移动端小高度场景继续使用滚动容器。
- 底部第三页从配置管理改为 `Practice Stats`，只展示练习统计：今日累计、当前会话、最近记录数量、近期总时长、平均 BPM 和最近练习历史；不包含排行榜。
- 练习统计状态由 `_MetronomeMainPageState` 维护，启动、恢复、停止练习时通过 `PracticeLogs` 刷新 `todayTotal` 和 `recentPracticeLogs`，当前正在播放的会话时长会叠加到今日展示值。

## 2026-04-25 Dart 代码拆分记录

- `lib/main.dart` 现在只保留 app 入口、主题装配和 `part` 声明，原 5000+ 行单文件按业务拆到 `lib/src/`。
- `lib/src/pages/metronome_main_page.dart`：顶层节拍器状态、播放控制、保存/载入入口调度、倒计时和练习记录刷新。
- `lib/src/widgets/bpm_dial.dart`：BPM 圆盘、拖动/微调/点击节奏控件、圆盘绘制器。
- `lib/src/widgets/transport_and_presets.dart`：Start/Stop 区域、Save/Load 圆盘外侧图标按钮、保存弹窗、加载抽屉和抽屉内删除反馈。
- `lib/src/widgets/top_function_bar.dart`、`beat_pattern.dart`、`selectors.dart`：首页顶部功能入口、轻重拍编辑条、通用选择控件。
- `lib/src/sheets/function_sheets.dart`、`metronome_settings_sheet.dart`：拍号、音色、调音器、定时器和历史遗留综合设置抽屉。
- `lib/src/pages/webview_page.dart`、`settings_page.dart`：WebView 页、练习统计页、底部导航。
- `lib/src/models/tap_tempo.dart`、`metronome_models.dart`：Tap Tempo 纯逻辑、节拍器/调音器模型、Flutter 和 Android 通道封装。

## 2026-04-25 WebView and Tuner Update

- `lib/metronome_database.dart`: database version is now `3`. `Settings` stores `web_page_url` with default `https://www.jitashe.org/`; older databases add the column during upgrade. `PersistedSettings` now carries this URL with the existing metronome settings snapshot.
- `lib/src/pages/metronome_main_page.dart`: keeps `_webPageUrl` in top-level app state, normalizes empty or scheme-less user input, persists it immediately, and passes it to both the WebView page and settings page.
- `lib/src/pages/webview_page.dart`: the first tab remains kept alive by `IndexedStack`, loads the configured URL, reloads when that URL changes, adds a bottom WebView back button using `canGoBack/goBack`, and makes the floating Start/Stop control semi-transparent while sharing the same transport state as the main page.
- `lib/src/pages/settings_page.dart`: bottom navigation first tab is now `Community`, and the settings page includes a `Community page` URL editor with save and reset-to-default actions.
- `lib/src/sheets/function_sheets.dart`: tuner display now keeps one stable layout for ordinary listening/no-signal states. It caches the latest stable reading for about 800ms, then shows `--`, `-- Hz`, centered needle, and helper text instead of swapping to a separate Listening layout. Permission denied and hard tuner errors still show dedicated status panels.
