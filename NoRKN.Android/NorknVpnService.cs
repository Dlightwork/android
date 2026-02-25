using Android.App;
using Android.Content;
using Android.Net;
using Android.OS;
using System.Globalization;
using System.Net;
using System.Net.Sockets;

namespace NoRKN.Android;

[Service(
    Name = "com.norkn.app.NorknVpnService",
    Permission = "android.permission.BIND_VPN_SERVICE",
    Exported = true)]
[IntentFilter(new[] { "android.net.VpnService" })]
public sealed class NorknVpnService : VpnService
{
    private const string EmbeddedSocksHost = "127.0.0.1";
    private const int EmbeddedSocksPort = 1080;
    private const string AutoHostListFile = "_auto_hostlist.txt";
    private const string AutoIpsetFile = "_auto_ipset.txt";
    private static readonly string[] ChatGptDnsServers =
    {
        "83.220.169.155",
        "212.109.195.93"
    };

    public const string ActionStart = "com.norkn.app.action.START";
    public const string ActionStop = "com.norkn.app.action.STOP";
    public const string ExtraMode = "mode";
    public const string ExtraSocksHost = "socks_host";
    public const string ExtraSocksPort = "socks_port";
    public const string ExtraDns = "dns";
    public const string ExtraMtu = "mtu";
    public const string ExtraFullTunnel = "full_tunnel";

    /// <summary>
    /// Action used to start the VPN service with a specific profile or mode. The
    /// BootCompletedReceiver uses this action to initiate the service when
    /// autostart is enabled. It behaves similarly to <see cref="ActionStart"/>,
    /// but allows external callers to distinguish profile-based starts.
    /// </summary>
    public const string ActionStartProfile = "com.norkn.app.action.START_PROFILE";

    /// <summary>
    /// Extra key used to specify the desired VPN profile (mode) when
    /// starting the service. For backward compatibility the service also
    /// reads <see cref="ExtraMode"/>.
    /// </summary>
    public const string ExtraProfile = "profile";

    private ParcelFileDescriptor? _vpnInterface;
    private Tun2SocksBridge? _tun2Socks;
    private LocalSocks5Server? _localSocks;

    public static event Action<string>? Log;
    public static event Action<bool, string>? StateChanged;

    public override StartCommandResult OnStartCommand(Intent? intent, StartCommandFlags flags, int startId)
    {
        EmitLog("[OnStartCommand] Service received command, intent=" + (intent?.Action ?? "null"));
        
        var action = intent?.Action ?? ActionStart;
        if (action == ActionStop)
        {
            EmitLog("[OnStartCommand] Received STOP command, shutting down");
            StopTunnel();
            StopForegroundCompat();
            StopSelf();
            return StartCommandResult.NotSticky;
        }

        var mode = intent?.GetStringExtra(ExtraMode) ??
                   intent?.GetStringExtra(ExtraProfile) ??
                   "multisplit";
        EmitLog($"[OnStartCommand] Mode={mode}");
        
        var settings = TunnelSettings.Load(this);
        settings.Mode = mode;
        settings.SocksHost = EmbeddedSocksHost;
        settings.SocksPort = EmbeddedSocksPort;
        settings.DnsServer = intent?.GetStringExtra(ExtraDns) ?? settings.DnsServer;
        settings.Mtu = intent?.GetIntExtra(ExtraMtu, settings.Mtu) ?? settings.Mtu;
        settings.FullTunnel = intent?.GetBooleanExtra(ExtraFullTunnel, settings.FullTunnel) ?? settings.FullTunnel;
        settings.Save(this);

        EmitLog($"[OnStartCommand] Settings: MTU={settings.Mtu}, DNS={settings.DnsServer}, FullTunnel={settings.FullTunnel}");
        
        StartTunnel(settings);
        // Return NotSticky so the system will not automatically restart
        // the service if it is killed. A sticky return value could cause
        // the VPN to linger or restart unintentionally, resulting in the
        // key icon remaining after a stop request. By returning NotSticky,
        // we ensure the service is only restarted by explicit user action.
        return StartCommandResult.NotSticky;
    }

    public override void OnDestroy()
    {
        StopTunnel();
        base.OnDestroy();
    }

    public override void OnRevoke()
    {
        EmitLog("[OnRevoke] VPN permission revoked by system");
        StopTunnel();
        StopSelf();
        base.OnRevoke();
    }

    private void StartTunnel(TunnelSettings settings)
    {
        EmitLog("[StartTunnel] Initializing VPN tunnel...");
        
        if (_tun2Socks is { IsRunning: true })
        {
            EmitLog("[StartTunnel] VPN already running, ignoring duplicate start");
            return;
        }

        try
        {
            EmitLog("[StartTunnel] Extracting zapret runtime assets...");
            var runtime = ZapretAssetsBootstrap.Ensure(this, EmitLog);
            EmitLog($"[StartTunnel] Runtime root: {runtime.RootDir}");
            
            var binCount = CountFiles(runtime.BinDir);
            var listCount = CountFiles(runtime.ListsDir);
            var luaCount = CountFiles(runtime.LuaDir);
            EmitLog($"[StartTunnel] Assets loaded: bin={binCount}, lists={listCount}, lua={luaCount}");
            
            LogAutoHostList(runtime.ListsDir);

            EmitLog("[StartTunnel] Starting embedded SOCKS5 server...");
            EnsureEmbeddedSocks(settings.SocksPort, settings.Mode, runtime.ListsDir, runtime.RootDir);

            EmitLog($"[StartTunnel] Checking SOCKS5 reachability on {settings.SocksHost}:{settings.SocksPort}...");
            if (!CanReachSocksServer(settings, out var socksError))
            {
                EmitLog($"[StartTunnel] ✗ SOCKS unreachable: {socksError}");
                EmitLog("[StartTunnel] CRITICAL: Embedded SOCKS5 failed to start or bind");
                
                // Try to provide more details
                try
                {
                    var proc = new System.Diagnostics.Process();
                    proc.StartInfo.FileName = "netstat";
                    proc.StartInfo.Arguments = "-tuln";
                    proc.StartInfo.UseShellExecute = false;
                    proc.StartInfo.RedirectStandardOutput = true;
                    proc.Start();
                    var output = proc.StandardOutput.ReadToEnd();
                    if (output.Contains("1080"))
                    {
                        EmitLog("[StartTunnel] Port 1080 is already in use!");
                    }
                }
                catch { }
                
                StateChanged?.Invoke(false, socksError);
                return;
            }

            EmitLog("[StartTunnel] ✓ SOCKS server reachable, building VPN interface...");
            
            var dnsServers = BuildEffectiveDnsServers(settings.DnsServer);

            var builder = new Builder(this)
                .SetSession($"NoRKN-{settings.Mode}")
                .SetMtu(settings.Mtu)
                .AddAddress("10.66.66.1", 24);

            foreach (var dns in dnsServers)
            {
                builder.AddDnsServer(dns);
            }

            EmitLog(
                $"[StartTunnel] VPN Config: Session=NoRKN-{settings.Mode}, MTU={settings.Mtu}, DNS={string.Join(", ", dnsServers)}");

            if (settings.FullTunnel)
            {
                EmitLog("[StartTunnel] Full tunnel mode - routing all traffic");
                builder.AddRoute("0.0.0.0", 0);
                builder.AddRoute("::", 0);
            }
            else
            {
                EmitLog("[StartTunnel] Selective routing mode - loading IP ranges...");
                var dnsRouteCount = AddDnsRoutes(builder, dnsServers);
                if (dnsRouteCount > 0)
                {
                    EmitLog($"[StartTunnel] Added {dnsRouteCount} DNS routes");
                }

                var selectiveCount = AddSelectiveRoutes(builder, runtime.ListsDir);
                if (selectiveCount == 0)
                {
                    EmitLog("[StartTunnel] No IP ranges found, falling back to full tunnel");
                    builder.AddRoute("0.0.0.0", 0);
                }
                else
                {
                    EmitLog($"[StartTunnel] ✓ Loaded {selectiveCount} selective routes");
                }
            }

            EmitLog("[StartTunnel] Calling VpnService.Establish()...");
            _vpnInterface = builder.Establish();
            
            if (_vpnInterface == null)
            {
                EmitLog("[StartTunnel] ✗ CRITICAL: VpnService.Establish() returned null!");
                EmitLog("[StartTunnel] This usually means:");
                EmitLog("  - VPN permission was not granted");
                EmitLog("  - Device revoked VPN permission");
                EmitLog("  - Another VPN is already active");
                StateChanged?.Invoke(false, "Establish failed");
                return;
            }

            EmitLog("[StartTunnel] ✓ VPN interface established successfully");
            
            EmitLog("[StartTunnel] Starting tun2socks bridge...");
            _tun2Socks?.Dispose();
            _tun2Socks = new Tun2SocksBridge(EmitLog);
            _tun2Socks.Start(_vpnInterface, settings);

            EmitLog($"[StartTunnel] ✓✓✓ VPN STARTED in mode: {settings.Mode}");
            StateChanged?.Invoke(true, settings.Mode);
        }
        catch (Exception ex)
        {
            EmitLog($"[StartTunnel] ✗✗✗ EXCEPTION: {ex.GetType().Name}: {ex.Message}");
            EmitLog($"[StartTunnel] StackTrace: {ex.StackTrace}");
            StateChanged?.Invoke(false, ex.Message);
        }
    }

    private static bool CanReachSocksServer(TunnelSettings settings, out string error)
    {
        error = string.Empty;
        
        if (string.IsNullOrWhiteSpace(settings.SocksHost))
        {
            error = "SOCKS host is empty";
            return false;
        }

        if (settings.SocksPort is <= 0 or > 65535)
        {
            error = $"SOCKS port invalid: {settings.SocksPort}";
            return false;
        }

        try
        {
            using var client = new TcpClient();
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            
            client.ConnectAsync(settings.SocksHost, settings.SocksPort, cts.Token).GetAwaiter().GetResult();

            if (client.Connected)
            {
                // Try a simple SOCKS5 handshake to validate
                using (var stream = client.GetStream())
                {
                    stream.WriteTimeout = 3000;
                    stream.ReadTimeout = 3000;
                    
                    // Send SOCKS5 hello 
                    byte[] hello = new byte[] { 0x05, 0x01, 0x00 };
                    stream.Write(hello, 0, hello.Length);
                    
                    byte[] response = new byte[2];
                    int read = stream.Read(response, 0, 2);
                    
                    if (read == 2 && response[0] == 0x05)
                    {
                        return true;
                    }
                    else
                    {
                        error = "SOCKS5 handshake failed";
                        return false;
                    }
                }
            }
            
            error = "Connect failed";
            return false;
        }
        catch (System.OperationCanceledException)
        {
            error = "Connection timeout (5s)";
            return false;
        }
        catch (System.Net.Sockets.SocketException ex)
        {
            error = $"Socket error: {ex.SocketErrorCode}";
            return false;
        }
        catch (Exception ex)
        {
            error = ex.GetBaseException().GetType().Name + ": " + ex.GetBaseException().Message;
            return false;
        }
    }

    private void EnsureEmbeddedSocks(int port, string mode, string listsDir, string runtimeRoot)
    {
        EmitLog($"[EnsureEmbeddedSocks] Initializing on port {port}");
        
        if (port is <= 0 or > 65535)
        {
            EmitLog($"[EnsureEmbeddedSocks] ✗ Invalid port: {port}");
            return;
        }

        if (_localSocks is { IsRunning: true })
        {
            EmitLog($"[EnsureEmbeddedSocks] Already running, updating mode to: {mode}");
            _localSocks.SetMode(mode);
            return;
        }

        try
        {
            _localSocks?.Dispose();
            
            EmitLog($"[EnsureEmbeddedSocks] Creating SOCKS5 server on 127.0.0.1:{port}");
            _localSocks = new LocalSocks5Server(
                port,
                mode,
                listsDir,
                runtimeRoot,
                EmitLog,
                socket =>
                {
                    try
                    {
                        Protect(socket.Handle.ToInt32());
                        return true;
                    }
                    catch (Exception ex)
                    {
                        EmitLog($"[EnsureEmbeddedSocks] Socket protect failed: {ex.Message}");
                        return false;
                    }
                });
            
            EmitLog($"[EnsureEmbeddedSocks] Starting SOCKS5 server...");
            _localSocks.Start();
            
            if (_localSocks.IsRunning)
            {
                EmitLog($"[EnsureEmbeddedSocks] ✓ SOCKS5 server started at 127.0.0.1:{port}");
            }
            else
            {
                EmitLog($"[EnsureEmbeddedSocks] ✗ SOCKS5 server creation reported but not running!");
            }
        }
        catch (Exception ex)
        {
            EmitLog($"[EnsureEmbeddedSocks] ✗ CRITICAL ERROR: {ex.GetType().Name}");
            EmitLog($"[EnsureEmbeddedSocks] Message: {ex.Message}");
            
            if (ex is System.Net.Sockets.SocketException sockEx)
            {
                EmitLog($"[EnsureEmbeddedSocks] SocketException Code: {sockEx.SocketErrorCode}");
                if (sockEx.SocketErrorCode == System.Net.Sockets.SocketError.AddressAlreadyInUse)
                {
                    EmitLog($"[EnsureEmbeddedSocks] Port {port} is already in use! Cannot start VPN.");
                }
            }
        }
    }

    private static bool IsLoopbackHost(string host)
    {
        if (string.Equals(host, "localhost", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return IPAddress.TryParse(host, out var ip) && IPAddress.IsLoopback(ip);
    }

    private static int CountFiles(string dir)
    {
        try
        {
            return Directory.Exists(dir)
                ? Directory.GetFiles(dir, "*", SearchOption.AllDirectories).Length
                : 0;
        }
        catch
        {
            return 0;
        }
    }

    private static readonly string[] PreferredIpsetFiles =
    {
        AutoIpsetFile,
        "ipset-ru.txt",
        "ipset-discord.txt",
        "ipset-roblox.txt",
        "ipset-youtube.txt",
        "ipset-openai.txt",
        "ipset-instagram.txt",
        "ipset-facebook.txt",
        "ipset-tiktok.txt"
    };

    private static string[] BuildEffectiveDnsServers(string configuredDns)
    {
        var ordered = new List<string>();
        var dedup = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        AddDnsTokens(configuredDns, ordered, dedup);

        // Keep user DNS as primary and append dedicated ChatGPT/OpenAI resolvers.
        foreach (var dns in ChatGptDnsServers)
        {
            AddDnsToken(dns, ordered, dedup);
        }

        if (ordered.Count == 0)
        {
            AddDnsToken("1.1.1.1", ordered, dedup);
        }

        return ordered.ToArray();
    }

    private static void AddDnsTokens(string raw, List<string> ordered, HashSet<string> dedup)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return;
        }

        var tokens = raw.Split(new[] { ',', ';', ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        foreach (var token in tokens)
        {
            AddDnsToken(token, ordered, dedup);
        }
    }

    private static void AddDnsToken(string token, List<string> ordered, HashSet<string> dedup)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            return;
        }

        if (!IPAddress.TryParse(token.Trim(), out var ip))
        {
            return;
        }

        var normalized = ip.ToString();
        if (dedup.Add(normalized))
        {
            ordered.Add(normalized);
        }
    }

    private static int AddDnsRoutes(Builder builder, IEnumerable<string> dnsServers)
    {
        var added = 0;
        var dedup = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var dns in dnsServers)
        {
            if (!IPAddress.TryParse(dns, out var ip))
            {
                continue;
            }

            var normalized = ip.ToString();
            if (!dedup.Add(normalized))
            {
                continue;
            }

            var prefix = ip.AddressFamily == AddressFamily.InterNetwork ? 32 : 128;
            try
            {
                builder.AddRoute(normalized, prefix);
                added++;
            }
            catch
            {
                // skip invalid/non-supported route entries
            }
        }

        return added;
    }

    private int AddSelectiveRoutes(Builder builder, string listsDir)
    {
        if (!Directory.Exists(listsDir))
        {
            return 0;
        }

        var files = new List<string>();
        foreach (var name in PreferredIpsetFiles)
        {
            var path = Path.Combine(listsDir, name);
            if (File.Exists(path))
            {
                files.Add(path);
            }
        }

        if (files.Count == 0)
        {
            files.AddRange(
                Directory.GetFiles(listsDir, "ipset-*.txt", SearchOption.TopDirectoryOnly)
                    .Where(p => !Path.GetFileName(p).StartsWith("_", StringComparison.OrdinalIgnoreCase))
                    .Take(8));
        }

        var dedup = new HashSet<string>(StringComparer.Ordinal);
        var added = 0;
        const int maxRoutes = 4096;

        foreach (var file in files)
        {
            var displayName = $"lists/{Path.GetFileName(file)}";
            EmitLog($"Loading ipset {displayName}");
            EmitLog("loading plain text list");
            var loadedInFile = 0;
            var badShown = 0;

            foreach (var line in File.ReadLines(file))
            {
                if (added >= maxRoutes)
                {
                    return added;
                }

                var raw = NormalizeListToken(line);
                if (raw.Length == 0 || raw.StartsWith("#") || raw.StartsWith(";"))
                {
                    continue;
                }

                if (!TryParseIPv4Route(raw, out var address, out var prefix))
                {
                    if (badShown < 5)
                    {
                        EmitLog($"bad ip or subnet : {raw}");
                        badShown++;
                    }
                    continue;
                }

                var key = $"{address}/{prefix}";
                if (!dedup.Add(key))
                {
                    continue;
                }

                try
                {
                    builder.AddRoute(address, prefix);
                    added++;
                    loadedInFile++;
                }
                catch
                {
                    // skip invalid/non-supported route entries
                }
            }

            EmitLog($"Loaded {loadedInFile} ip/subnets from {displayName}");
        }

        return added;
    }

    private void LogAutoHostList(string listsDir)
    {
        var hostPath = Path.Combine(listsDir, AutoHostListFile);
        if (!File.Exists(hostPath))
        {
            return;
        }

        var loaded = 0;
        foreach (var line in File.ReadLines(hostPath))
        {
            var token = NormalizeListToken(line);
            if (token.Length == 0)
            {
                continue;
            }

            // Hostlist can contain just domains; skip explicit IP entries.
            if (IPAddress.TryParse(token, out _))
            {
                continue;
            }

            loaded++;
        }

        EmitLog($"Loaded {loaded} hosts from lists/{AutoHostListFile}");
    }

    private static string NormalizeListToken(string line)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return string.Empty;
        }

        var raw = line.Trim().TrimStart('\uFEFF');
        var commentIndex = raw.IndexOfAny(new[] { '#', ';' });
        if (commentIndex > 0)
        {
            raw = raw[..commentIndex].Trim();
        }

        return raw;
    }

    private static bool TryParseIPv4Route(string value, out string address, out int prefix)
    {
        address = string.Empty;
        prefix = 0;
        value = value.Trim().TrimStart('\uFEFF');

        var slash = value.IndexOf('/');
        if (slash > 0)
        {
            var ipPart = value[..slash].Trim();
            var prefixPart = value[(slash + 1)..].Trim();
            if (!int.TryParse(prefixPart, NumberStyles.Integer, CultureInfo.InvariantCulture, out prefix))
            {
                return false;
            }

            if (prefix is < 0 or > 32)
            {
                return false;
            }

            if (!IPAddress.TryParse(ipPart, out var ip) || ip.AddressFamily != AddressFamily.InterNetwork)
            {
                return false;
            }

            address = ip.ToString();
            return true;
        }

        if (!IPAddress.TryParse(value, out var onlyIp) || onlyIp.AddressFamily != AddressFamily.InterNetwork)
        {
            return false;
        }

        address = onlyIp.ToString();
        prefix = 32;
        return true;
    }

    private void StopTunnel()
    {
        _tun2Socks?.Dispose();
        _tun2Socks = null;
        _localSocks?.Dispose();
        _localSocks = null;

        try
        {
            _vpnInterface?.Close();
        }
        catch
        {
            // ignored
        }

        _vpnInterface = null;
        StopForegroundCompat();
        EmitLog("VPN stopped.");
        StateChanged?.Invoke(false, "-");
    }

    private void StopForegroundCompat()
    {
        try
        {
            if (Build.VERSION.SdkInt >= BuildVersionCodes.N)
            {
                StopForeground(StopForegroundFlags.Remove);
            }
            else
            {
                StopForeground(true);
            }
        }
        catch
        {
            // ignored
        }
    }

    private static void EmitLog(string message) => Log?.Invoke(message);
}
