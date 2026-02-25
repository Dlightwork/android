# NoRKN Android - DPI Evasion Tool for Android

**NoRKN** is a VPN-based DPI (Deep Packet Inspection) and censorship evasion tool for Android. It implements multiple DPI bypass strategies including TLS ClientHello fragmentation, QUIC packet splitting, and HTTP header manipulation.

## Features

- **VPN-based traffic interception** (via Android VpnService)
- **Multiple DPI evasion strategies**:
  - TLS ClientHello split with delays
  - QUIC Initial packet fragmentation
  - HTTP request line splitting
  - DNS over HTTPS/TLS support
- **Built-in SOCKS5 proxy** (localhost:1080) for local traffic handling
- **Zapret integration** - uses proven DPI bypass templates from bol-van/zapret
- **Multi-architecture support** - ARM64, ARM32, x86, x86_64
- **Selective routing** - route only blocked domains through VPN
- **Persistent settings** - save tunnel configuration across sessions
- **Auto-start on boot** (optional)

## Technical Architecture

```
┌─────────────────────────────────────────┐
│       Android Applications              │
├─────────────────────────────────────────┤
│        VpnService (TUN interface)       │
│    ┌──────────────────────────────────┐ │
│    │ NorknVpnService                  │ │
│    │ • Intercepts all IP traffic      │ │
│    │ • Routes to tun2socks            │ │
│    └──────────────────────────────────┘ │
├─────────────────────────────────────────┤
│    LocalSocks5Server (localhost:1080)   │
│    ┌──────────────────────────────────┐ │
│    │ • SOCKS5 protocol handler        │ │
│    │ • TLS/QUIC split strategies      │ │
│    │ • HTTP fragmentation             │ │
│    │ • Host-based strategy selection  │ │
│    └──────────────────────────────────┘ │
├─────────────────────────────────────────┤
│      tun2socks (native library)          │
│    ┌──────────────────────────────────┐ │
│    │ • TCP/UDP forwarding             │ │
│    │ • SOCKS5 connection handling     │ │
│    │ • Packet composition/decomp.     │ │
│    └──────────────────────────────────┘ │
├─────────────────────────────────────────┤
│    Network & DPI Circumvention          │
│    (modified packet flow)               │
└─────────────────────────────────────────┘
```

## Supported Bypass Strategies

### 1. TLS ClientHello Fragmentation (Port 443)

**Problem**: DPI inspects TLS handshake to detect and block SNI patterns.

**Solution**: Split ClientHello packet into multiple TCP segments with delays:

- **Multisplit**: Split into 2-3 parts (standard DPI evasion)
- **Strong**: Extreme fragmentation into 6+ parts with 1-3ms delays

```
Original:  [TLS Record: ClientHello ... (256+ bytes)]
Multisplit: [1-8 bytes] --1ms-- [remaining bytes]
Strong:     [1B] --3ms-- [5B] --2ms-- [chunks...] --delays--
```

### 2. QUIC Initial Packet Splitting (Port 443 UDP)

**Problem**: QUIC header inspection by DPI.

**Solution**: Fragment QUIC Initial packet:

```
Original:  [QUIC Initial Packet ... (1200+ bytes)]
Strong:    [1B] --3ms-- [4B version] --2ms-- [rest ...]
```

### 3. HTTP Request Header Splitting (Port 80)

**Problem**: DPI detects upgrade attempts and Host headers.

**Solution**: Split HTTP request at request-line boundary.

## Prerequisites

1. **Android Device Requirements**:
   - Android 5.0+ (API 21+)
   - Installed via `adb install`
   - No root required
   - Network connectivity

2. **Build Requirements** (Windows/Linux/macOS):
   - .NET SDK 8.0 or later: https://dotnet.microsoft.com/download
   - Android SDK (optional, for advanced debugging)
   - PowerShell 7+ (for build scripts)

3. **Installation Requirements**:
   - Android Debug Bridge (ADB): Install via Android SDK or direct download
   - Signing key (optional, for production builds)

## Installation & Building

### Quick Start

```powershell
# 1. Clone/download the repository
cd d:\project2

# 2. Build APK (Release mode)
.\build-android-apk.ps1 -Configuration Release

# 3. Install on connected device
adb install -r build\android\com.norkn.app-release.apk

# 4. Open the app and click "Start"
```

### Building with Signing

```powershell
# Create a signing key (one-time)
keytool -genkey -v -keystore signing.jks -keyalg RSA -keysize 2048 -validity 10000 -alias android

# Build and sign
.\build-android-apk.ps1 -Configuration Release -SignKey signing.jks -KeyAlias android -KeyPassword "your_password"
```

### Build Output

- **Debug APK**: `build/android/com.norkn.app-debug.apk` (~45MB)
- **Release APK**: `build/android/com.norkn.app-release.apk` (~35MB)

## Usage

### Starting the VPN

1. **Via App UI**:
   - Open NoRKN app
   - Select mode (Multisplit / Strong)
   - Click "Start VPN"
   - Accept Android VPN permission prompt
   - Check "VPN" icon in status bar

2. **Via Command Line**:
   ```bash
   adb shell am startservice -n com.norkn.app/.NorknVpnService \
     --es mode multisplit \
     --ez full_tunnel true
   ```

3. **Via Intent with Custom DNS**:
   ```bash
   adb shell am startservice com.norkn.app/.NorknVpnService \
     --es dns 1.1.1.1
   ```

### Stopping the VPN

```bash
adb shell am stopservice com.norkn.app/.NorknVpnService
```

### Viewing Logs

```bash
adb logcat | grep NoRKN
```

## Configuration

### Tunnel Settings (Persistent)

Settings are saved in Android's SharedPreferences:
- **Mode**: `multisplit` (balanced) or `strong` (aggressive)
- **SOCKS Host**: `127.0.0.1` (embedded)
- **SOCKS Port**: `1080` (default)
- **DNS Server**: `1.1.1.1` (default, configurable)
- **MTU**: `1500` (auto-detect)
- **Full Tunnel**: `true` = all traffic, `false` = selective routing

### Domain Lists

Selective routing uses lists in `NoRKN.Android/zapret/lists/`:
- `_auto_hostlist.txt` - domains to route through VPN
- `_auto_ipset.txt` - IP ranges to route through VPN

Default includes:
- Roblox (`roblox.com`, `*.rbxcdn.com`)
- YouTube (`youtube.com`, `*.ytimg.com`)
- Discord (`discord.com`)
- Various CDNs and services

## Advanced Usage

### Custom Domain Lists

1. Edit `NoRKN.Android/zapret/lists/_auto_hostlist.txt`:
   ```
   example.com
   .subdomain.example.com
   ```

2. Rebuild APK:
   ```powershell
   .\build-android-apk.ps1
   ```

### UDP-over-TCP for QUIC

In strong mode, UDP/QUIC traffic is encapsulated:
```
Client → App → SOCKS5 (embedded) → TCP stream → tun2socks → remote server
```

### Debugging NDK Native Issues

If `libtun2socks.so` fails to load:

```bash
# Check native library
adb shell ldd /data/app/com.norkn.app*/lib/libtun2socks.so

# Check permissions
adb shell ls -la /data/app/com.norkn.app*/lib/

# View error logs
adb logcat | grep "tun2socks\|libtun2socks"
```

## Modes Explained

### Multisplit (Default)

- **Aggressiveness**: Balanced
- **Performance**: Good (minimal latency)
- **Detection Risk**: Low-Medium
- **Best For**: Most networks

**Strategy**:
- TLS: Split at 8 bytes + remainder
- QUIC: Split at 5 bytes (header) + payload
- HTTP: Split at 16-byte boundary

### Strong

- **Aggressiveness**: Maximum
- **Performance**: Acceptable (1-3ms delays)
- **Detection Risk**: Very Low
- **Best For**: Aggressive filtering networks

**Strategy**:
- TLS: 1B → 5B → 8B fragments with 2-3ms delays
- QUIC: 1B → 4B → rest with delays
- HTTP: Request-line split + payload

## Troubleshooting

### "VPN connection failed"
- **Cause**: SOCKS5 server failed to start
- **Fix**: Restart app, check logs: `adb logcat | grep "embedded socks"`

### "Permission denied" or "BIND_VPN_SERVICE error"
- **Cause**: Android VPN permission not granted
- **Fix**: Open Settings → Apps → Permissions → check VPN permission

### "Connection timeout"
- **Cause**: Network connectivity issue or DNS failure
- **Fix**: 
  - Check WiFi/mobile connection
  - Try changing DNS (e.g., `1.1.1.1`, `8.8.8.8`)
  - Disable IPv6 if present (Settings → Network)

### Logs not appearing
- **Cause**: Incorrect log filter
- **Fix**: `adb logcat | grep -i "norkn\|tun2socks"`

### APK build errors

**Error**: `error MSB3073: The command "... tun2socks.dll" exited with code 1`
- **Cause**: Native library missing/outdated
- **Fix**: Rebuild native libraries:
  ```powershell
  .\tools\build-android-native-tun2socks.ps1
  ```

## Privacy & Security Notes

⚠️ **Important Disclaimers**:

1. **VPN Service Model**: This app *is* a local VPN application. It has access to:
   - All network traffic on the device
   - DNS queries
   - Application connection metadata

2. **Trust Model**: You must trust this application. Only users who compiled it themselves or have verified the source should use it.

3. **No External Servers**: Unlike typical VPN apps, NoRKN does NOT:
   - Connect to external VPN servers
   - Send traffic to third parties
   - Log or exfiltrate data
   - Require account registration

4. **Traffic Obfuscation**: The packet modifications are local transformations only—traffic is still sent to the real destination server.

5. **DPI Evasion Risks**: Using DPI evasion tools may violate local laws or ToS in some jurisdictions. Use at your own risk.

## Legal Status

See [LEGAL.md](LEGAL.md) for jurisdiction-specific information.

## Building from Source

### Source Structure

```
NoRKN.Android/
├── NorknVpnService.cs     # VPN service implementation
├── LocalSocks5Server.cs   # SOCKS5 proxy + DPI evasion logic
├── Tun2SocksBridge.cs     # Native library integration
├── MainActivity.cs         # UI / app entry point
├── BootCompletedReceiver.cs # Auto-start on boot
├── ZapretAssetsBootstrap.cs # Asset extraction (domains, lua scripts)
├── TunnelSettings.cs       # Persistent configuration
├── native/                 # Compiled libtun2socks.so (all ABIs)
├── zapret/                 # Bypass templates & domain lists
│   ├── lists/              # .txt domain/IP lists
│   ├── presets/            # .args config templates
│   ├── lua/                # Lua scripts for advanced filtering
│   └── bin/                # Binary packet templates
└── Resources/              # Android UI resources

_android_native/
└── hev-socks5-tunnel/     # Source for libtun2socks (C)

tools/
└── build-android-native-tun2socks.ps1  # Build script for native libs
```

### Rebuilding Native Libraries

If you modify `_android_native/hev-socks5-tunnel/`:

```powershell
# Install NDK (one-time)
.\tools\download-ndk.ps1

# Rebuild for all ABIs
.\tools\build-android-native-tun2socks.ps1
```

## Contributing

Contributions are welcome! Areas for improvement:

- [ ] More DPI evasion strategies (SNI rotation, fake packets, etc.)
- [ ] QUIC version negotiation spoofing
- [ ] HTTP/2 header compression tricks
- [ ] DNS randomization
- [ ] IPv6 support improvements
- [ ] UI/UX enhancements
- [ ] Performance optimizations

## Related Projects

- **bol-van/zapret** (Linux/macOS): https://github.com/bol-van/zapret
- **hev-socks5-tunnel** (native tun2socks): https://github.com/heiher/hev-socks5-tunnel
- **Android VpnService** docs: https://developer.android.com/reference/android/net/VpnService

## License

This project uses code from:
- **hev-socks5-tunnel** (MIT License)
- **zapret** (GPL-3.0)
- **Android SDK** (Apache 2.0)

See LICENSE files in respective directories.

## Support

For issues and questions:
1. Check [Troubleshooting](#troubleshooting) section
2. Review logs: `adb logcat | grep NoRKN`
3. Check GitHub issues (if available)

---

**⚠️ Use at your own risk. This tool is for educational and circumvention purposes only.**
