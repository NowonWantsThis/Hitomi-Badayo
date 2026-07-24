# Privacy

Hitomi Badayo is a local desktop application. The project does not operate an
account service, analytics endpoint, advertising service, or telemetry backend.

## Data stored on the Mac

The app stores runtime data under:

```text
~/Library/Application Support/Hitomi Badayo/
```

That directory can contain queue and history data, source URLs, bookmarks,
managed helper tools, login cookies, and a local cookie-encryption key. macOS
preferences are stored in the `io.github.nowonwantsthis.HitomiBadayo`
preferences domain.
Downloaded media goes to the folder selected by the user, with source-specific
subfolders enabled by default.

Cookies are encrypted with AES-GCM and a randomly generated local key. The key
and encrypted cookie file are both stored with the user's application data.
This reduces accidental disclosure but is not protection from someone who can
read the user's macOS account and application-support directory.

## Network activity

The app sends requests to URLs and source sites selected by the user. Requests
may include cookies, referer values, user-agent strings, or other authentication
material required by that source. Those values are intended for the relevant
source host, not a Hitomi Badayo-operated server.

When the user explicitly installs managed tools, the app downloads:

- yt-dlp release files and checksums from the yt-dlp GitHub project
- FFmpeg and ffprobe archives from the configured third-party build provider

The app may also load source-site pages in an embedded WebKit login window.
Logging into a third-party site is governed by that site's privacy policy.

The optional Browser DPI Bypass starts the bundled SpoofDPI helper as a local
HTTP proxy bound to `127.0.0.1`. It does not listen on the Mac's external
network interfaces. When the user points macOS Web Proxy and Secure Web Proxy
settings to that address, compatible browser traffic passes through the local
helper before reaching the requested site. The app reads the effective system
proxy state to show whether both settings match; it does not upload that state.

## Browser cookie import

Cookie import is optional and user initiated. When used, the app reads the
selected or detected browser cookie database locally and imports supported
entries into its own encrypted cookie store. Browser databases and imported
cookies are not part of source or release archives.

## Removing local data

Cookies can be cleared from Settings. To remove all app-maintained state after
quitting the app, delete the application-support directory and the macOS
preferences for `io.github.nowonwantsthis.HitomiBadayo`. Downloaded media is
separate and must be removed by the user.
