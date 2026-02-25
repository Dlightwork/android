# NoRKN Android Port

## What was ported

- Android app shell (`MainActivity`)
- Android traffic interception layer via `VpnService` (`NorknVpnService`)
- `tun2socks` bridge loader (`Tun2SocksBridge`)
- Packet strategy hooks for `multisplit` / `strong` (`PacketProcessor`)
- Persistent tunnel settings (`TunnelSettings`)
- UI controls for `multisplit` / `strong`, start/stop, diagnostics and tunnel config

## Important architecture note

`WinDivert` is a Windows kernel driver and cannot run on Android.  
So "WinDivert port" on Android means replacing it with `Android.Net.VpnService` (user-space packet interception).

`winws2` logic is being ported as packet processing strategies in userspace:
- TCP/TLS split
- UDP/QUIC fake/split
- host/ip based routing logic

This repo now contains the Android foundation and native bridge integration points.

## Current status

- VPN layer starts via `VpnService`.
- Full tunnel settings are available from UI (SOCKS host/port, DNS, mode).
- Native bridge is wired and uses real `libtun2socks.so` built from `hev-socks5-tunnel`.
- Strategy hooks exist for `multisplit` and `strong`.
- Windows `winws2.exe` is not executable on Android; its profile files from `bat/*.txt`
  are mirrored into Android assets as `zapret/presets/windows/*.args`.
- Embedded SOCKS now reads `--dpi` style presets (`.args`) and applies host/port
  matching rules from those files.
- Build sync now merges assets from local repo + upstream links:
  `bol-van/zapret2` (lua/custom lists) and `CherretGit/zaprett-app` metadata.
- Full parity with Windows `winws2` strategies is **not complete yet** (needs native strategy implementation).

## Native tun2socks

Real `libtun2socks.so` binaries are built from:
`_android_native/hev-socks5-tunnel`

Build and copy to Android project:

```powershell
.\tools\build-android-native-tun2socks.ps1
```

Output layout:

- `NoRKN.Android/native/arm64-v8a/libtun2socks.so`
- `NoRKN.Android/native/armeabi-v7a/libtun2socks.so`
- `NoRKN.Android/native/x86/libtun2socks.so`
- `NoRKN.Android/native/x86_64/libtun2socks.so`

## Build APK

1. Run PowerShell as Administrator in repo root.
2. Install Android workload:
   ```powershell
   .\tools\reset-dotnet-workload.ps1
   .\tools\install-android-workload.ps1
   ```
3. Build APK (native tun2socks builds automatically):
   ```powershell
   .\tools\build-android-apk.ps1 -Configuration Release
   ```

   Or run one-shot setup first (workload + Android SDK + assets sync):
   ```powershell
   .\setup-android.ps1
   .\build-android-apk.ps1 -Configuration Release
   ```

APK output:
- `NoRKN.Android/bin/Release/net8.0-android/publish`
