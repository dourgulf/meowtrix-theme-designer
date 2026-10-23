# Meowtrix Theme Designer

手工绘制爱心、猫脸、条带等区域图案，再补全为唯一解、提示可解的关卡。这个目录是独立 Flutter 项目，包含规则、提示引擎和主题生成器，可以整体移动到其他目录或单独的 Git 仓库；不依赖旧 Flutter 游戏、Cocos 构建或父目录的 Dart 包。

## 启动与验证

使用 FVM 固定的 Flutter 3.47.7，以及 Xcode 的 macOS 工具链：

```sh
cd meowtrix-theme-designer
fvm flutter pub get --offline  # 首次未缓存依赖时去掉 --offline
fvm flutter run -d macos
```

也可在项目目录执行 `bash run.sh`。此脚本会读取本机忽略的 `designer.local.env`；本机已在该文件配置喵阵共享目录。独立克隆后可自行创建该文件，或使用下面的环境变量。

```sh
fvm flutter analyze
fvm flutter test
fvm flutter build macos --debug
```

依赖只有 Flutter、`equatable`、`desktop_multi_window` 和测试/分析工具；`pubspec.lock` 保留依赖解析版本。`lib/domain/` 是离线生成器使用的 Dart 规则与提示基线，`lib/level_design/` 是主题生成器及其依赖，均在本项目内。它们与当前游戏的 Cocos 引擎是两套实现；安装生成结果前仍需用当前游戏验证。

## 草稿和外部资料

- 在喵阵仓库内启动：自动读取并保存到 `shared/level-design/designs/`，参考窗口读取 `shared/level-design/linkedin_themes.json`。
- 移到其他地方后：默认使用启动工作目录下的 `designs/`；可设置 `MEOWTRIX_WORKSPACE=/绝对路径/喵阵仓库` 接回共享草稿和参考数据。
- `MEOWTRIX_DESIGNS_DIR` 可单独指定草稿目录，`THEME_DESIGNER_REFERENCES` 可单独指定参考数据 JSON。这些是本机运行配置，不写入项目依赖。
- 参考题库是外部研究资料，本项目不打包 LinkedIn 数据；未连接资料时，参考窗口显示配置提示，绘制和生成照常可用。

例如从独立项目接入喵阵：

```sh
MEOWTRIX_WORKSPACE=/绝对路径/catpuzzle_flutter fvm flutter run -d macos
```

## 使用流程

1. 选择 6–12 阶盘面和画笔颜色，左键点击/拖动涂色，右键擦除；可启用镜像或旋转对称。
2. 设置目标技巧、高级提示次数、规则 2 和是否允许涂色区域扩展。颜色区域必须连通。
3. 点击“生成”；搜索在独立 isolate 中进行，支持“停止”。涂过的格子会保持颜色，空白区域由生成器补全。
4. “复制关卡 JSON”导出游戏关卡格式；“保存”将图案、生成条件和结果写为草稿。“打开草稿…”可恢复，“转为草稿继续改”可编辑完整结果。已加载草稿的隐藏 `caps` 限制会参与生成并在保存时保留。
5. “图案参考”打开独立窗口，可按主题、尺寸筛选外部研究盘面。

保存只修改草稿目录，不自动安装或替换正式关卡。共享草稿应使用新名字保存候选；正式内容变更需另行审查、验证存档兼容和当前 Cocos 求解结果。

命令行也可以生成指定草稿；命令会更新传入文件，建议先复制一份：

```sh
fvm dart run lib/level_design/theme_cli.dart /tmp/candidate.json 20 30000
```

参考资料提取脚本接受显式来源与输出路径：

```sh
python3 tool/extract_references.py /path/to/linkedin_boards.json --output /tmp/references.json
```

`test/fixtures/theme.json` 是原创数字图案的冻结测试样本，不是运行时资源。macOS 工具沿用原本的非沙盒配置，以便读写用户指定的草稿目录；游戏 App 配置不受影响。`test_driver/app.dart` 保留为可选桌面自动化入口。

本次恢复的实际编译、窗口操作与独立目录测试记录见 [VERIFY.md](VERIFY.md)。

## License

Copyright (C) 2026 lidawen. 本项目原创代码采用 **GNU GPL v3 或更新版本（GPL-3.0-or-later）**。完整协议见 [LICENSE](LICENSE)，第三方依赖声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
