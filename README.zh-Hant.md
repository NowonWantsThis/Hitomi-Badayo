# Hitomi Badayo

<p align="center">
  <a href="README.md"><kbd>English</kbd></a>
  <a href="README.ja.md"><kbd>日本語</kbd></a>
  <a href="README.zh-Hans.md"><kbd>简体中文</kbd></a>
  <strong><a href="README.zh-Hant.md"><kbd>繁體中文</kbd></a></strong>
  <a href="README.ko.md"><kbd>한국어</kbd></a>
</p>

<p>
<img width="687" height="431" alt="sc" src="https://github.com/user-attachments/assets/7105eceb-33c9-441b-976b-b40a1492f79e" />
</p>

Hitomi Badayo 是一款專為 Apple 晶片 Mac 打造的原生下載管理器。它將以佇列為核心的 macOS 介面，與依來源命名、來源資料夾、身分驗證、預覽、封存及媒體下載流程整合在一起。

本應用程式是參考現有桌面下載器中可觀察到的行為，獨立完成的原生實作。本儲存庫不包含原始應用程式的執行檔或反編譯位元碼。

0.5.0 版完成了以可維護性為目標的重構，同時保留 0.4.2 版面向使用者的行為、設定、已儲存資料和下載結果。

## 主要功能

- 使用 SwiftUI 和 AppKit 建構的 macOS 原生介面
- 支援重新排序、取消、重試及逐項進度顯示的並行佇列
- 支援 Hitomi、Pixiv、YouTube、Kemono 類封存站、Booru 類網站及其他來源的專用處理器
- 依來源設定輸出資料夾、命名範本，以及 ZIP 和 CBZ 選項
- 為需要登入的來源提供內建登入視窗，並在本機儲存 Cookie
- 透過僅監聽迴送位址的 SpoofDPI 代理，依需要為應用程式本身或應用程式與瀏覽器啟用 DPI 繞過
- 縮圖預覽、開啟下載結果、安全停止直播錄製及清理功能
- 英文、日文、簡體中文、繁體中文及韓文介面

來源網站的行為可能隨時變更。某個版本中能正常運作的處理器，也可能因網站改版而需要維護。

## 系統需求

- Apple 晶片 Mac（arm64）
- macOS 14 Sonoma 或更新版本
- 存取線上來源及依需要安裝輔助工具所需的網際網路連線

## 安裝發行版本

1. 從對應的 GitHub Release 下載 `Hitomi-Badayo-macOS.zip`。
2. 解壓縮後，可視需要將 `Hitomi Badayo.app` 移到「應用程式」資料夾。
3. 第一次啟動時，按住 Control 鍵並按一下應用程式，然後選擇**打開**。
4. 如果 macOS 仍阻止執行，請前往**系統設定 > 隱私權與安全性 > 仍要打開**。

發行的建置版本採用臨時簽署，未使用 Developer ID 簽署，也未經 Apple 公證。請勿在整個系統中停用 Gatekeeper。關於資料儲存位置及首次執行行為的詳細資訊，請參閱 [INSTALLATION.md](docs/INSTALLATION.md)。

## 從原始碼建置

安裝 Xcode 命令列工具，然後執行：

```sh
xcode-select --install
./build.sh
```

應用程式會產生於 `Build/Hitomi Badayo.app`。若要指定其他輸出目錄，請執行：

```sh
./build.sh Build-Local
```

建置過程使用系統提供的 macOS SDK，不需要 Xcode 專案。

## 外部工具

Apple 晶片版本的 aria2 1.37.0 和 SpoofDPI 1.5.3 會連同各自的授權資訊，以獨立輔助程序的形式隨應用程式提供。yt-dlp、Deno、FFmpeg 和 ffprobe 都是選用工具，只有在使用者主動執行管理工具安裝時才會下載。為了處理 YouTube 的 JavaScript 驗證，Deno 會直接傳遞給 yt-dlp。詳情請參閱 [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)。

## DPI 繞過

選用控制項位於**設定 > 網路 > DPI 繞過**，預設為**關閉**。**僅應用程式**會讓支援的 Hitomi Badayo 下載透過 `127.0.0.1` 上的 SpoofDPI 連線，不會變更 macOS 代理伺服器設定，也不會要求管理者權限。**應用程式與瀏覽器**還會設定目前使用中的 macOS 網頁代理伺服器（HTTP）和安全網頁代理伺服器（HTTPS），因此需要管理者核准。應用程式會儲存原有的系統代理伺服器值，並在停用此模式或結束應用程式時還原。

手動代理伺服器設定會分開儲存。同時啟用 DPI 繞過和手動代理伺服器時，本機 SpoofDPI 路由優先。手動代理伺服器設定不會遺失，並會在關閉 DPI 繞過後重新生效。

## 資料與隱私權

佇列狀態、設定、登入 Cookie、輔助工具和下載內容都會保存在使用者的 Mac 上。本專案不營運遙測服務。網路要求仍會傳送至使用者選擇的來源網站和選用工具提供者。關於確切的儲存位置和限制，請參閱 [PRIVACY.md](docs/PRIVACY.md)。

## 合理使用

請僅將本應用程式用於您有權存取和保存的內容。使用者有責任遵守與下載內容相關的著作權、帳號、訂閱及來源網站條款。本專案與支援的網站沒有隸屬或合作關係，網站名稱和標誌的權利歸各自擁有者所有。

## 專案文件

以下文件目前以英文維護。

- [INSTALLATION.md](docs/INSTALLATION.md)：安裝和首次執行行為
- [CHANGELOG.md](docs/CHANGELOG.md)：版本記錄
- [PRIVACY.md](docs/PRIVACY.md)：本機資料和網路行為
- [SECURITY.md](docs/SECURITY.md)：安全漏洞回報說明
- [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)：隨附及選用工具

## 授權

Hitomi Badayo 專案原始碼採用 [MIT License](LICENSE) 授權。隨附和選用的外部元件仍適用 [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md) 中記錄的各自授權條款。
