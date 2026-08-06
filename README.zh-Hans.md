# Hitomi Badayo

<p align="center">
  <a href="README.md"><kbd>English</kbd></a>
  <a href="README.ja.md"><kbd>日本語</kbd></a>
  <strong><a href="README.zh-Hans.md"><kbd>简体中文</kbd></a></strong>
  <a href="README.zh-Hant.md"><kbd>繁體中文</kbd></a>
  <a href="README.ko.md"><kbd>한국어</kbd></a>
</p>

<p>
<img width="687" height="431" alt="sc" src="https://github.com/user-attachments/assets/7105eceb-33c9-441b-976b-b40a1492f79e" />
</p>

Hitomi Badayo 是一款面向 Apple 芯片 Mac 的原生下载管理器。它将以队列为中心的 macOS 界面与按来源命名、来源文件夹、身份验证、预览、归档以及媒体下载工作流程整合在一起。

本应用是参考现有桌面下载器中可观察到的行为而独立完成的原生实现。本仓库不包含原应用的可执行文件或反编译字节码。

0.5.0 版本完成了以可维护性为目标的重构，同时保留了 0.4.2 版本面向用户的行为、设置、已保存数据和下载结果。

## 主要功能

- 使用 SwiftUI 和 AppKit 构建的 macOS 原生界面
- 支持重新排序、取消、重试和单项进度显示的并发队列
- 支持 Hitomi、Pixiv、YouTube、Kemono 类归档、Booru 类网站及其他来源的专用处理器
- 按来源设置输出文件夹、命名模板以及 ZIP 和 CBZ 选项
- 为需要登录的来源提供内置登录窗口，并在本机保存 Cookie
- 通过仅监听回环地址的 SpoofDPI 代理，按需为应用本身或应用与浏览器启用 DPI 绕过
- 缩略图预览、打开下载结果、安全停止直播录制以及清理功能
- 英语、日语、简体中文、繁体中文和韩语界面

来源网站的行为可能随时变化。某个版本中可以正常工作的处理器，也可能因网站改版而需要维护。

## 系统要求

- Apple 芯片 Mac（arm64）
- macOS 14 Sonoma 或更高版本
- 访问在线来源及按需安装辅助工具所需的互联网连接

## 安装发布版本

1. 从对应的 GitHub Release 下载 `Hitomi-Badayo-macOS.zip`。
2. 解压后，可按需将 `Hitomi Badayo.app` 移到“应用程序”文件夹。
3. 首次启动时，按住 Control 键点按应用，然后选择**打开**。
4. 如果 macOS 仍然阻止运行，请前往**系统设置 > 隐私与安全性 > 仍要打开**。

发布的构建采用临时签名，未使用 Developer ID 签名，也未经过 Apple 公证。请勿在整个系统中禁用 Gatekeeper。有关数据存储位置和首次运行行为的详细信息，请参阅 [INSTALLATION.md](docs/INSTALLATION.md)。

## 从源代码构建

安装 Xcode 命令行工具，然后运行：

```sh
xcode-select --install
./build.sh
```

应用将生成在 `Build/Hitomi Badayo.app`。如需指定其他输出目录，请运行：

```sh
./build.sh Build-Local
```

构建过程使用系统自带的 macOS SDK，不需要 Xcode 项目。

## 外部工具

面向 Apple 芯片的 aria2 1.37.0 和 SpoofDPI 1.5.3 会连同各自的许可证信息，以独立辅助进程的形式随应用提供。yt-dlp、Deno、FFmpeg 和 ffprobe 均为可选工具，仅在用户主动执行管理工具安装时下载。为处理 YouTube 的 JavaScript 验证，Deno 会直接传递给 yt-dlp。详情请参阅 [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)。

## DPI 绕过

可选开关位于**设置 > 网络 > DPI 绕过**，默认状态为**关闭**。**仅应用程序**会让受支持的 Hitomi Badayo 下载通过 `127.0.0.1` 上的 SpoofDPI 连接，不会修改 macOS 代理设置，也不会请求管理员权限。**应用程序和浏览器**还会配置当前使用的 macOS 网页代理（HTTP）和安全网页代理（HTTPS），因此需要管理员批准。应用会保存原有的系统代理值，并在停用该模式或退出应用时恢复。

手动代理设置会单独保存。同时启用 DPI 绕过和手动代理时，本地 SpoofDPI 路由优先。手动代理配置不会丢失，并会在关闭 DPI 绕过后重新生效。

## 数据与隐私

队列状态、设置、登录 Cookie、辅助工具和下载内容都保存在用户的 Mac 上。本项目不运营遥测服务。网络请求仍会发送到用户所选的来源网站和可选工具提供方。有关准确的存储位置和限制，请参阅 [PRIVACY.md](docs/PRIVACY.md)。

## 合理使用

请仅将本应用用于您有权访问和保存的内容。用户有责任遵守与下载内容相关的版权、账号、订阅以及来源网站条款。本项目与受支持的网站没有隶属或合作关系，网站名称和标识的权利归各自所有者所有。

## 项目文档

以下文档目前以英语维护。

- [INSTALLATION.md](docs/INSTALLATION.md)：安装和首次运行行为
- [CHANGELOG.md](docs/CHANGELOG.md)：版本记录
- [PRIVACY.md](docs/PRIVACY.md)：本地数据和网络行为
- [SECURITY.md](docs/SECURITY.md)：安全漏洞报告说明
- [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)：随附及可选工具

## 许可证

Hitomi Badayo 项目的源代码采用 [MIT License](LICENSE) 授权。随附和可选的外部组件继续适用 [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md) 中记录的各自许可证。
