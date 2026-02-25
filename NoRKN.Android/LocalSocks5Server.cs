using System.Net;
using System.Net.Sockets;
using System.Text;

namespace NoRKN.Android;

public sealed class LocalSocks5Server : IDisposable
{
    private static readonly string[] FastPathSuffixes =
    {
        ".googlevideo.com",
        ".youtube.com",
        ".ytimg.com",
        ".ggpht.com",
        ".discord.com",
        ".discord.gg",
        ".discordapp.com",
        ".discord.media",
        ".roblox.com",
        ".rbxcdn.com",
        ".tiktok.com",
        ".tiktokv.com",
        ".ibyteimg.com",
        ".openai.com",
        ".chatgpt.com",
        ".oaistatic.com",
        ".oaiusercontent.com",
        ".instagram.com",
        ".cdninstagram.com",
        ".facebook.com",
        ".fbcdn.net",
        ".x.com",
        ".twitter.com",
        ".twimg.com"
    };

    private readonly Action<string> _log;
    private readonly Func<Socket, bool> _protectSocket;
    private readonly int _port;
    private volatile string _mode;
    private readonly string? _listsDir;
    private readonly string? _runtimeRoot;
    private volatile IReadOnlyList<DpiRule> _dpiRules = Array.Empty<DpiRule>();

    // Additional host suffixes loaded from zapret lists. When present, any host
    // that ends with one of these suffixes will be put on the fast-path for
    // desync. This allows the Android port to mirror zapret2 behaviour by
    // dynamically loading the combined host list rather than relying solely on
    // the static FastPathSuffixes array.
    private static readonly HashSet<string> AdditionalSuffixes = new(StringComparer.OrdinalIgnoreCase);

    private TcpListener? _listener;
    private CancellationTokenSource? _cts;
    private Task? _acceptTask;

    public LocalSocks5Server(
        int port,
        string mode,
        string? listsDir,
        string? runtimeRoot,
        Action<string> log,
        Func<Socket, bool> protectSocket)
    {
        _port = port;
        _mode = string.IsNullOrWhiteSpace(mode) ? "multisplit" : mode;
        _listsDir = listsDir;
        _runtimeRoot = runtimeRoot;
        _log = log;
        _protectSocket = protectSocket;

        // Attempt to load additional host suffixes only once at construction time.
        // If listsDir is null or auto host list is missing, no additional suffixes
        // will be loaded. Errors are silently ignored to avoid crashing the app.
        try
        {
            if (_listsDir != null && AdditionalSuffixes.Count == 0)
            {
                var autoHostFile = Path.Combine(_listsDir, "_auto_hostlist.txt");
                if (File.Exists(autoHostFile))
                {
                    foreach (var line in File.ReadLines(autoHostFile))
                    {
                        var host = line.Trim();
                        if (string.IsNullOrEmpty(host) || host.StartsWith("#"))
                        {
                            continue;
                        }
                        // Normalise to lower and ensure we only add suffixes (leading dot)
                        var suffix = host.StartsWith(".") ? host : $".{host}";
                        AdditionalSuffixes.Add(suffix.ToLowerInvariant());
                    }
                }
            }
        }
        catch
        {
            // ignore any file parsing errors
        }

        _dpiRules = LoadDpiRules(_mode, _listsDir, _runtimeRoot, _log);
    }

    public bool IsRunning => _acceptTask is { IsCompleted: false };

    public void SetMode(string mode)
    {
        if (!string.IsNullOrWhiteSpace(mode))
        {
            _mode = mode;
            _dpiRules = LoadDpiRules(_mode, _listsDir, _runtimeRoot, _log);
        }
    }

    public void Start()
    {
        if (IsRunning)
        {
            _log("[LocalSocks5Server.Start] Already running");
            return;
        }

        _log($"[LocalSocks5Server.Start] Starting SOCKS5 on 127.0.0.1:{_port}...");
        _cts = new CancellationTokenSource();
        _listener = new TcpListener(IPAddress.Loopback, _port);
        
        try
        {
            _listener.Start(128);
            _log($"[LocalSocks5Server.Start] ✓ Listener started, accepting connections");
        }
        catch (Exception ex)
        {
            _log($"[LocalSocks5Server.Start] ✗ Failed to start listener: {ex.Message}");
            throw;
        }
        
        _acceptTask = Task.Run(() => AcceptLoop(_cts.Token));
    }

    public void Stop()
    {
        _log("[LocalSocks5Server.Stop] Stopping SOCKS5 server...");
        try
        {
            _cts?.Cancel();
            _log("[LocalSocks5Server.Stop] Cancellation signaled");
        }
        catch
        {
            // ignored
        }

        try
        {
            _listener?.Stop();
            _log("[LocalSocks5Server.Stop] Listener stopped");
        }
        catch
        {
            // ignored
        }
        
        _log("[LocalSocks5Server.Stop] Server stopped");
    }

    private async Task AcceptLoop(CancellationToken token)
    {
        if (_listener == null)
        {
            return;
        }

        while (!token.IsCancellationRequested)
        {
            TcpClient? client = null;
            try
            {
                client = await _listener.AcceptTcpClientAsync(token);
                _ = Task.Run(() => HandleClient(client, token), token);
            }
            catch (System.OperationCanceledException)
            {
                break;
            }
            catch (ObjectDisposedException)
            {
                break;
            }
            catch (Exception ex)
            {
                _log($"embedded socks accept error: {ex.GetBaseException().Message}");
                client?.Dispose();
                await Task.Delay(200, token);
            }
        }
    }

    private async Task HandleClient(TcpClient client, CancellationToken token)
    {
        using (client)
        {
            try
            {
                using var stream = client.GetStream();

                var helloHead = await ReadExact(stream, 2, token);
                if (helloHead[0] != 0x05)
                {
                    _log($"[HandleClient] Unsupported SOCKS version: 0x{helloHead[0]:X2}");
                    return;
                }

                var nMethods = helloHead[1];
                byte selectedMethod = 0xFF;
                if (nMethods > 0)
                {
                    var methods = await ReadExact(stream, nMethods, token);
                    if (methods.Contains((byte)0x00))
                    {
                        selectedMethod = 0x00;
                    }
                }

                await stream.WriteAsync(new byte[] { 0x05, selectedMethod }, token);
                if (selectedMethod == 0xFF)
                {
                    _log("[HandleClient] No supported auth method from client");
                    return;
                }

                var reqHead = await ReadExact(stream, 4, token);
                var cmd = reqHead[1];
                var atyp = reqHead[3];
                if (reqHead[0] != 0x05)
                {
                    _log($"[HandleClient] Invalid request version: 0x{reqHead[0]:X2}");
                    await SendReply(stream, 0x01, token);
                    return;
                }

                if (cmd != 0x01 && cmd != 0x05)
                {
                    if (cmd == 0x03)
                    {
                        _log("[HandleClient] UDP ASSOCIATE is not supported in embedded SOCKS mode");
                    }
                    else
                    {
                        _log(
                            $"[HandleClient] Unsupported SOCKS command: 0x{cmd:X2} " +
                            $"(head={reqHead[0]:X2} {reqHead[1]:X2} {reqHead[2]:X2} {reqHead[3]:X2})");
                    }
                    await SendReply(stream, 0x07, token);
                    return;
                }

                var host = await ReadAddress(stream, atyp, token);
                var portBytes = await ReadExact(stream, 2, token);
                var port = (portBytes[0] << 8) | portBytes[1];

                if (cmd == 0x05)
                {
                    _log($"[HandleClient] SOCKS5 FWD_UDP request: {host}:{port}");
                    await HandleUdpInTcp(stream, token);
                    return;
                }

                var applyDesync = ShouldApplyDesync(host, port, _mode, _dpiRules);
                _log($"[HandleClient] SOCKS5 CONNECT: {host}:{port} (desync={applyDesync}, mode={_mode})");

                using var remote = new TcpClient();
                if (!_protectSocket(remote.Client))
                {
                    _log($"[HandleClient] Failed to protect socket for {host}:{port}");
                    await SendReply(stream, 0x01, token);
                    return;
                }

                using var connectCts = CancellationTokenSource.CreateLinkedTokenSource(token);
                connectCts.CancelAfter(TimeSpan.FromSeconds(8));
                
                try
                {
                    await remote.ConnectAsync(host, port, connectCts.Token);
                    _log($"[HandleClient] ✓ Connected to {host}:{port}");
                }
                catch (Exception ex)
                {
                    _log($"[HandleClient] ✗ Failed to connect to {host}:{port}: {ex.Message}");
                    await SendReply(stream, 0x04, token); // Host unreachable
                    return;
                }
                
                await SendReply(stream, 0x00, token);

                using var remoteStream = remote.GetStream();
                var toRemote = PumpClientToRemote(stream, remoteStream, port, _mode, applyDesync, token);
                var toClient = remoteStream.CopyToAsync(stream, token);
                _ = await Task.WhenAny(toRemote, toClient);
                
                _log($"[HandleClient] Closed connection to {host}:{port}");
            }
            catch (Exception ex)
            {
                _log($"[HandleClient] Exception: {ex.GetType().Name}: {ex.Message}");
            }
        }
    }

    private static async Task<byte[]> ReadExact(NetworkStream stream, int length, CancellationToken token)
    {
        var buffer = new byte[length];
        var offset = 0;
        while (offset < length)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(offset, length - offset), token);
            if (read <= 0)
            {
                throw new IOException("socks client disconnected");
            }
            offset += read;
        }
        return buffer;
    }

    private static async Task<string> ReadAddress(NetworkStream stream, byte atyp, CancellationToken token)
    {
        if (atyp == 0x01)
        {
            var ip = await ReadExact(stream, 4, token);
            return new IPAddress(ip).ToString();
        }

        if (atyp == 0x03)
        {
            var len = (await ReadExact(stream, 1, token))[0];
            var host = await ReadExact(stream, len, token);
            return Encoding.ASCII.GetString(host);
        }

        if (atyp == 0x04)
        {
            var ip = await ReadExact(stream, 16, token);
            return new IPAddress(ip).ToString();
        }

        throw new IOException("unsupported atyp");
    }

    private static Task SendReply(NetworkStream stream, byte rep, CancellationToken token)
    {
        var resp = new byte[] { 0x05, rep, 0x00, 0x01, 0, 0, 0, 0, 0, 0 };
        return stream.WriteAsync(resp, token).AsTask();
    }

    private async Task HandleUdpInTcp(NetworkStream stream, CancellationToken token)
    {
        Socket? udpSocket = null;
        try
        {
            udpSocket = CreateUdpRelaySocket();
            if (!_protectSocket(udpSocket))
            {
                _log("[HandleClient] Failed to protect UDP relay socket");
                await SendReply(stream, 0x01, token);
                return;
            }

            udpSocket.Bind(
                udpSocket.AddressFamily == AddressFamily.InterNetworkV6
                    ? new IPEndPoint(IPAddress.IPv6Any, 0)
                    : new IPEndPoint(IPAddress.Any, 0));
            udpSocket.Blocking = false;

            await SendReply(stream, 0x00, token);

            using var relayCts = CancellationTokenSource.CreateLinkedTokenSource(token);
            var relayToken = relayCts.Token;

            var toRemote = PumpUdpInTcpClientToRemote(stream, udpSocket, relayToken);
            var toClient = PumpUdpInTcpRemoteToClient(stream, udpSocket, relayToken);
            var finished = await Task.WhenAny(toRemote, toClient);

            try
            {
                await finished;
            }
            catch (OperationCanceledException)
            {
                // ignored
            }

            relayCts.Cancel();
            try
            {
                await Task.WhenAll(toRemote, toClient);
            }
            catch
            {
                // ignored
            }
        }
        catch (IOException ex) when (ex.Message.Contains("socks client disconnected", StringComparison.OrdinalIgnoreCase))
        {
            _log("[HandleClient] UDP relay client disconnected");
        }
        catch (OperationCanceledException)
        {
            // ignored
        }
        catch (Exception ex)
        {
            _log($"[HandleClient] UDP relay setup failed: {ex.Message}");
            try
            {
                await SendReply(stream, 0x01, token);
            }
            catch
            {
                // ignored
            }
        }
        finally
        {
            if (udpSocket != null)
            {
                try
                {
                    udpSocket.Close();
                }
                catch
                {
                    // ignored
                }
                udpSocket.Dispose();
            }
        }
    }

    private async Task PumpUdpInTcpClientToRemote(
        NetworkStream clientStream,
        Socket udpSocket,
        CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            var udpHeader = await ReadExact(clientStream, 3, token);
            var dataLength = (udpHeader[0] << 8) | udpHeader[1];
            var headerLength = udpHeader[2];

            if (headerLength < 5)
            {
                throw new IOException($"invalid UDP relay header length: {headerLength}");
            }

            var addrLength = headerLength - 3;
            var addrBytes = await ReadExact(clientStream, addrLength, token);
            var payload = dataLength == 0 ? Array.Empty<byte>() : await ReadExact(clientStream, dataLength, token);

            if (!TryParseUdpRelayTarget(addrBytes, out var ipEndPoint, out var host, out var port))
            {
                throw new IOException("invalid UDP relay destination");
            }

            if (payload.Length == 0)
            {
                continue;
            }

            if (ipEndPoint != null)
            {
                var destination = AdaptEndpointForSocket(udpSocket, ipEndPoint);
                try
                {
                    udpSocket.SendTo(payload, destination);
                }
                catch (SocketException ex) when (
                    ex.SocketErrorCode == SocketError.WouldBlock ||
                    ex.SocketErrorCode == SocketError.NoBufferSpaceAvailable)
                {
                    continue;
                }
                continue;
            }

            if (string.IsNullOrWhiteSpace(host))
            {
                continue;
            }

            IPAddress[] addresses;
            try
            {
                addresses = await Dns.GetHostAddressesAsync(host);
            }
            catch (Exception ex)
            {
                _log($"[HandleClient] UDP DNS resolve failed for {host}:{port}: {ex.Message}");
                continue;
            }

            var sent = false;
            foreach (var address in addresses)
            {
                var destination = AdaptEndpointForSocket(udpSocket, new IPEndPoint(address, port));
                try
                {
                    udpSocket.SendTo(payload, destination);
                    sent = true;
                    break;
                }
                catch (SocketException)
                {
                    // try next resolved address
                }
            }

            if (!sent)
            {
                _log($"[HandleClient] UDP send failed for {host}:{port}");
            }
        }
    }

    private static async Task PumpUdpInTcpRemoteToClient(
        NetworkStream clientStream,
        Socket udpSocket,
        CancellationToken token)
    {
        var payload = new byte[ushort.MaxValue];
        while (!token.IsCancellationRequested)
        {
            if (!udpSocket.Poll(100_000, SelectMode.SelectRead))
            {
                continue;
            }

            EndPoint remote = udpSocket.AddressFamily == AddressFamily.InterNetworkV6
                ? new IPEndPoint(IPAddress.IPv6Any, 0)
                : new IPEndPoint(IPAddress.Any, 0);

            int received;
            try
            {
                received = udpSocket.ReceiveFrom(payload, ref remote);
            }
            catch (SocketException ex) when (
                ex.SocketErrorCode == SocketError.WouldBlock ||
                ex.SocketErrorCode == SocketError.Interrupted ||
                ex.SocketErrorCode == SocketError.TimedOut)
            {
                continue;
            }

            if (received <= 0 || remote is not IPEndPoint remoteIp)
            {
                continue;
            }

            var addrBytes = BuildUdpRelayAddress(remoteIp);
            if (addrBytes.Length == 0)
            {
                continue;
            }

            var headerLength = 3 + addrBytes.Length;
            if (headerLength > byte.MaxValue)
            {
                continue;
            }

            var frame = new byte[3 + addrBytes.Length + received];
            frame[0] = (byte)((received >> 8) & 0xFF);
            frame[1] = (byte)(received & 0xFF);
            frame[2] = (byte)headerLength;
            Buffer.BlockCopy(addrBytes, 0, frame, 3, addrBytes.Length);
            Buffer.BlockCopy(payload, 0, frame, 3 + addrBytes.Length, received);

            await clientStream.WriteAsync(frame, token);
        }
    }

    private static Socket CreateUdpRelaySocket()
    {
        try
        {
            var socket = new Socket(AddressFamily.InterNetworkV6, SocketType.Dgram, ProtocolType.Udp)
            {
                DualMode = true
            };
            return socket;
        }
        catch (SocketException)
        {
            return new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        }
    }

    private static EndPoint AdaptEndpointForSocket(Socket udpSocket, IPEndPoint endpoint)
    {
        if (udpSocket.AddressFamily == AddressFamily.InterNetworkV6 &&
            endpoint.AddressFamily == AddressFamily.InterNetwork)
        {
            return new IPEndPoint(endpoint.Address.MapToIPv6(), endpoint.Port);
        }

        if (udpSocket.AddressFamily == AddressFamily.InterNetwork &&
            endpoint.AddressFamily == AddressFamily.InterNetworkV6 &&
            endpoint.Address.IsIPv4MappedToIPv6)
        {
            return new IPEndPoint(endpoint.Address.MapToIPv4(), endpoint.Port);
        }

        return endpoint;
    }

    private static bool TryParseUdpRelayTarget(
        byte[] rawAddress,
        out IPEndPoint? endpoint,
        out string? host,
        out int port)
    {
        endpoint = null;
        host = null;
        port = 0;

        if (rawAddress.Length < 4)
        {
            return false;
        }

        var atyp = rawAddress[0];
        switch (atyp)
        {
            case 0x01:
            {
                if (rawAddress.Length != 7)
                {
                    return false;
                }

                var ip = new IPAddress(rawAddress.AsSpan(1, 4));
                port = (rawAddress[5] << 8) | rawAddress[6];
                endpoint = new IPEndPoint(ip, port);
                host = ip.ToString();
                return true;
            }
            case 0x04:
            {
                if (rawAddress.Length != 19)
                {
                    return false;
                }

                var ip = new IPAddress(rawAddress.AsSpan(1, 16));
                port = (rawAddress[17] << 8) | rawAddress[18];
                endpoint = new IPEndPoint(ip, port);
                host = ip.ToString();
                return true;
            }
            case 0x03:
            {
                var domainLength = rawAddress[1];
                if (domainLength == 0 || rawAddress.Length != domainLength + 4)
                {
                    return false;
                }

                host = Encoding.ASCII.GetString(rawAddress, 2, domainLength);
                if (string.IsNullOrWhiteSpace(host))
                {
                    return false;
                }

                var portIndex = 2 + domainLength;
                port = (rawAddress[portIndex] << 8) | rawAddress[portIndex + 1];
                return true;
            }
            default:
                return false;
        }
    }

    private static byte[] BuildUdpRelayAddress(IPEndPoint endpoint)
    {
        var address = endpoint.Address;
        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }

        if (address.AddressFamily == AddressFamily.InterNetwork)
        {
            var addrBytes = address.GetAddressBytes();
            var packed = new byte[7];
            packed[0] = 0x01;
            Buffer.BlockCopy(addrBytes, 0, packed, 1, 4);
            packed[5] = (byte)((endpoint.Port >> 8) & 0xFF);
            packed[6] = (byte)(endpoint.Port & 0xFF);
            return packed;
        }

        if (address.AddressFamily == AddressFamily.InterNetworkV6)
        {
            var addrBytes = address.GetAddressBytes();
            var packed = new byte[19];
            packed[0] = 0x04;
            Buffer.BlockCopy(addrBytes, 0, packed, 1, 16);
            packed[17] = (byte)((endpoint.Port >> 8) & 0xFF);
            packed[18] = (byte)(endpoint.Port & 0xFF);
            return packed;
        }

        return Array.Empty<byte>();
    }

    private static async Task PumpClientToRemote(
        NetworkStream clientStream,
        NetworkStream remoteStream,
        int dstPort,
        string mode,
        bool applyDesync,
        CancellationToken token)
    {
        var buffer = new byte[16 * 1024];
        var firstChunk = true;

        while (!token.IsCancellationRequested)
        {
            var read = await clientStream.ReadAsync(buffer, token);
            if (read <= 0)
            {
                break;
            }

            if (firstChunk && applyDesync)
            {
                // Port 443: could be TLS or QUIC
                if (dstPort == 443)
                {
                    if (IsLikelyTlsClientHello(buffer, read))
                    {
                        await WriteTlsSplit(remoteStream, buffer, read, mode, token);
                    }
                    else if (IsQuicInitialPacket(buffer, read))
                    {
                        await WriteQuicSplit(remoteStream, buffer, read, mode, token);
                    }
                    else
                    {
                        await remoteStream.WriteAsync(buffer.AsMemory(0, read), token);
                    }
                }
                else if (dstPort == 80)
                {
                    // HTTP: apply simple split for HTTP/2 upgrade or to break SNI patterns
                    await WriteHttpSplit(remoteStream, buffer, read, mode, token);
                }
                else
                {
                    await remoteStream.WriteAsync(buffer.AsMemory(0, read), token);
                }
            }
            else
            {
                await remoteStream.WriteAsync(buffer.AsMemory(0, read), token);
            }

            firstChunk = false;
        }
    }

    private static bool IsLikelyTlsClientHello(byte[] data, int len)
    {
        if (len < 11)
        {
            return false;
        }

        // TLS record: Handshake(0x16), TLS version 0x03 xx, HandshakeType=ClientHello(0x01)
        return data[0] == 0x16 && data[1] == 0x03 && data[5] == 0x01;
    }

    private static bool IsQuicInitialPacket(byte[] data, int len)
    {
        if (len < 5)
        {
            return false;
        }

        // QUIC Initial packet: first byte has msbit=1 (header form), next 2 bits=00 (fixed bit),
        // version != 0, and first packet number flag set
        var firstByte = data[0];
        
        // Check fixed bit (0x40) and header form (0x80), version != 0
        if ((firstByte & 0xc0) != 0xc0)
        {
            return false;
        }

        // Check version (bytes 1-4)
        var version = (data[1] << 24) | (data[2] << 16) | (data[3] << 8) | data[4];
        return version != 0; // Non-zero version indicates valid QUIC packet
    }

    private static async Task WriteQuicSplit(
        NetworkStream remoteStream,
        byte[] data,
        int len,
        string mode,
        CancellationToken token)
    {
        if (len <= 1)
        {
            await remoteStream.WriteAsync(data.AsMemory(0, len), token);
            return;
        }

        if (string.Equals(mode, "strong", StringComparison.OrdinalIgnoreCase))
        {
            // Strong mode for QUIC: split header bytes with delays
            // Send first byte (header form + type)
            await remoteStream.WriteAsync(data.AsMemory(0, 1), token);
            await Task.Delay(3, token);
            
            // Send version (4 bytes) separately
            if (len > 1)
            {
                await remoteStream.WriteAsync(data.AsMemory(1, Math.Min(4, len - 1)), token);
                await Task.Delay(2, token);
            }
            
            // Send rest with larger chunks
            var pos = 5;
            while (pos < len)
            {
                var chunk = Math.Min(100, len - pos);
                await remoteStream.WriteAsync(data.AsMemory(pos, chunk), token);
                if (pos + chunk < len)
                {
                    await Task.Delay(1, token);
                }
                pos += chunk;
            }
            return;
        }

        // Multisplit mode: split at reasonable boundaries
        // Send header bytes (version handling)
        await remoteStream.WriteAsync(data.AsMemory(0, Math.Min(5, len)), token);
        if (len > 5)
        {
            await Task.Delay(1, token);
            await remoteStream.WriteAsync(data.AsMemory(5, len - 5), token);
        }
    }

    private static async Task WriteHttpSplit(
        NetworkStream remoteStream,
        byte[] data,
        int len,
        string mode,
        CancellationToken token)
    {
        if (len <= 1)
        {
            await remoteStream.WriteAsync(data.AsMemory(0, len), token);
            return;
        }

        if (string.Equals(mode, "strong", StringComparison.OrdinalIgnoreCase))
        {
            // Strong mode: split HTTP request line across packets
            // Find first line ending (optional for finer control)
            var lineEnd = -1;
            for (var i = 0; i < Math.Min(256, len - 1); i++)
            {
                if (data[i] == (byte)'\n')
                {
                    lineEnd = i + 1;
                    break;
                }
            }

            if (lineEnd > 4)
            {
                // Send first 4 bytes
                await remoteStream.WriteAsync(data.AsMemory(0, 4), token);
                await Task.Delay(2, token);
                
                // Send up to line end
                await remoteStream.WriteAsync(data.AsMemory(4, lineEnd - 4), token);
                
                if (lineEnd < len)
                {
                    await Task.Delay(1, token);
                    await remoteStream.WriteAsync(data.AsMemory(lineEnd, len - lineEnd), token);
                }
            }
            else
            {
                // Fallback: simple split
                var split = Math.Min(4, len - 1);
                await remoteStream.WriteAsync(data.AsMemory(0, split), token);
                await Task.Delay(1, token);
                await remoteStream.WriteAsync(data.AsMemory(split, len - split), token);
            }
            return;
        }

        // Multisplit: moderate split
        var splitPos = Math.Min(16, len - 1);
        await remoteStream.WriteAsync(data.AsMemory(0, splitPos), token);
        if (splitPos < len)
        {
            await Task.Delay(1, token);
            await remoteStream.WriteAsync(data.AsMemory(splitPos, len - splitPos), token);
        }
    }

    private static async Task WriteTlsSplit(
        NetworkStream remoteStream,
        byte[] data,
        int len,
        string mode,
        CancellationToken token)
    {
        if (len <= 1)
        {
            await remoteStream.WriteAsync(data.AsMemory(0, len), token);
            return;
        }

        if (string.Equals(mode, "strong", StringComparison.OrdinalIgnoreCase))
        {
            // Strong mode: maximal fragmentation with delays
            // Split TLS ClientHello into minimal chunks: TLS header (5) + 1 byte
            await remoteStream.WriteAsync(data.AsMemory(0, 1), token);
            await Task.Delay(3, token);
            
            if (len > 1)
            {
                await remoteStream.WriteAsync(data.AsMemory(1, Math.Min(5, len - 1)), token);
                await Task.Delay(2, token);
            }
            
            var pos = Math.Min(6, len);
            while (pos < len)
            {
                var chunk = Math.Min(64, len - pos);
                await remoteStream.WriteAsync(data.AsMemory(pos, chunk), token);
                await Task.Delay(1, token);
                pos += chunk;
            }
            return;
        }

        // Multisplit mode: moderate fragmentation
        // Split at record boundary (TLS header = 5 bytes) + data
        if (len > 10)
        {
            // Send TLS record header (5 bytes) + 3 bytes of payload
            await remoteStream.WriteAsync(data.AsMemory(0, 8), token);
            await Task.Delay(1, token);
            
            // Send remaining in larger chunks to speed up handshake
            var pos = 8;
            while (pos < len)
            {
                var chunk = Math.Min(256, len - pos);
                await remoteStream.WriteAsync(data.AsMemory(pos, chunk), token);
                if (pos + chunk < len)
                {
                    await Task.Delay(1, token);
                }
                pos += chunk;
            }
        }
        else
        {
            // Small packets - just split once
            var split = Math.Min(6, len - 1);
            await remoteStream.WriteAsync(data.AsMemory(0, split), token);
            await Task.Delay(1, token);
            await remoteStream.WriteAsync(data.AsMemory(split, len - split), token);
        }
    }

    private static bool ShouldApplyDesync(string host, int port, string mode, IReadOnlyList<DpiRule> dpiRules)
    {
        if (dpiRules.Count > 0)
        {
            foreach (var rule in dpiRules)
            {
                if (!rule.HasDesyncDirective)
                {
                    continue;
                }

                var portMatch = rule.TcpPorts.Any(r => port >= r.Start && port <= r.End);
                if (!portMatch)
                {
                    continue;
                }

                if (!HostMatchesRule(host, rule))
                {
                    continue;
                }

                return true;
            }

            // Preset exists but nothing matched: do not force fallback behaviour.
            return false;
        }

        // If no parsed preset rules are available, keep strong mode aggressive.
        if (string.Equals(mode, "strong", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        // Fallback profile: only apply desync for TLS (port 443) traffic.
        if (port != 443)
        {
            return false;
        }

        if (string.IsNullOrWhiteSpace(host))
        {
            return false;
        }

        // Ignore numeric IP addresses.
        if (IPAddress.TryParse(host, out _))
        {
            return false;
        }

        var normalized = host.Trim().ToLowerInvariant();

        // Check static fast-path suffixes first for quick positive matches.
        foreach (var suffix in FastPathSuffixes)
        {
            if (normalized.EndsWith(suffix, StringComparison.Ordinal))
            {
                return true;
            }
        }

        // Additionally check the dynamically loaded suffixes from the zapret lists. If any
        // entry matches, apply the TLS split. Entries in AdditionalSuffixes are
        // stored with a leading dot to simplify matching (e.g. ".example.com"). To
        // ensure we handle hosts without a leading dot (e.g. example.com), prepend
        // a dot here before checking.
        var dotted = normalized.StartsWith('.') ? normalized : $".{normalized}";
        foreach (var suffix in AdditionalSuffixes)
        {
            if (dotted.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static bool HostMatchesRule(string host, DpiRule rule)
    {
        if (string.IsNullOrWhiteSpace(host))
        {
            return !rule.RequireIncludeMatch;
        }

        if (IPAddress.TryParse(host, out var ip))
        {
            if (rule.ExcludeIpSubnets.Count > 0 && MatchesAnySubnet(ip, rule.ExcludeIpSubnets))
            {
                return false;
            }

            if (rule.IncludeIpSubnets.Count > 0)
            {
                return MatchesAnySubnet(ip, rule.IncludeIpSubnets);
            }

            return !rule.RequireIncludeMatch;
        }

        if (rule.ExcludeHostSuffixes.Count > 0 && MatchesAnySuffix(host, rule.ExcludeHostSuffixes))
        {
            return false;
        }

        if (rule.IncludeHostSuffixes.Count > 0)
        {
            return MatchesAnySuffix(host, rule.IncludeHostSuffixes);
        }

        return !rule.RequireIncludeMatch;
    }

    private static bool MatchesAnySuffix(string host, IReadOnlyCollection<string> suffixes)
    {
        if (string.IsNullOrWhiteSpace(host))
        {
            return false;
        }

        if (IPAddress.TryParse(host, out _))
        {
            return false;
        }

        var normalized = host.Trim().ToLowerInvariant();
        var dotted = normalized.StartsWith('.') ? normalized : $".{normalized}";

        foreach (var suffix in suffixes)
        {
            if (dotted.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static bool MatchesAnySubnet(IPAddress ip, IReadOnlyList<IpSubnet> subnets)
    {
        foreach (var subnet in subnets)
        {
            if (subnet.Contains(ip))
            {
                return true;
            }
        }

        return false;
    }

    private static IReadOnlyList<DpiRule> LoadDpiRules(
        string mode,
        string? listsDir,
        string? runtimeRoot,
        Action<string> log)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(runtimeRoot))
            {
                return Array.Empty<DpiRule>();
            }

            var presetPath = ResolvePresetPath(mode, runtimeRoot);
            if (string.IsNullOrWhiteSpace(presetPath) || !File.Exists(presetPath))
            {
                return Array.Empty<DpiRule>();
            }

            var rules = new List<DpiRule>();
            var stagedTokens = new List<string>(64);
            foreach (var raw in File.ReadLines(presetPath))
            {
                var line = raw.Trim();
                if (line.Length == 0)
                {
                    FinalizeStagedRule(stagedTokens, rules, listsDir, log);
                    continue;
                }

                if (line.StartsWith('#') || line.StartsWith(';'))
                {
                    continue;
                }

                var tokens = SplitArgs(line);
                if (tokens.Count == 0)
                {
                    continue;
                }

                if (tokens[0].Equals("--new", StringComparison.OrdinalIgnoreCase))
                {
                    FinalizeStagedRule(stagedTokens, rules, listsDir, log);
                    if (tokens.Count > 1)
                    {
                        stagedTokens.AddRange(tokens.Skip(1));
                    }
                    continue;
                }

                // Presets can be represented either as one-line full rules or as
                // multi-line blocks. If a new tcp filter appears while tokens are
                // already staged, flush current block first.
                if (stagedTokens.Count > 0 && HasOption(tokens, "--filter-tcp"))
                {
                    FinalizeStagedRule(stagedTokens, rules, listsDir, log);
                }

                stagedTokens.AddRange(tokens);

                // One-line rule fast path.
                if (HasOption(tokens, "--filter-tcp") &&
                    (HasOption(tokens, "--dpi-desync") || HasOption(tokens, "--lua-desync")))
                {
                    FinalizeStagedRule(stagedTokens, rules, listsDir, log);
                }
            }

            FinalizeStagedRule(stagedTokens, rules, listsDir, log);

            log($"[LocalSocks5Server] Loaded {rules.Count} --dpi rules from {Path.GetFileName(presetPath)}");
            return rules;
        }
        catch (Exception ex)
        {
            log($"[LocalSocks5Server] Failed to load --dpi rules: {ex.Message}");
            return Array.Empty<DpiRule>();
        }
    }

    private static string ResolvePresetPath(string mode, string runtimeRoot)
    {
        var candidates = new List<string>();

        var normalizedMode = mode.Trim();
        if (normalizedMode.Length > 0)
        {
            if (normalizedMode.EndsWith(".args", StringComparison.OrdinalIgnoreCase))
            {
                candidates.Add(normalizedMode);
                candidates.Add($"presets/windows/{normalizedMode}");
                candidates.Add($"presets/{normalizedMode}");
            }
            else
            {
                candidates.Add($"presets/windows/{normalizedMode}.args");
                candidates.Add($"presets/{normalizedMode}.args");
            }
        }

        if (string.Equals(mode, "strong", StringComparison.OrdinalIgnoreCase))
        {
            candidates.Add("presets/windows/strong_roblox_youtube.args");
            candidates.Add("presets/windows/alt4_190b.args");
            candidates.Add("presets/windows/original_bolvan_v2.args");
            candidates.Add("presets/all_tcp_udp_multisplit_sni.args");
        }
        else
        {
            candidates.Add("presets/windows/original_bolvan_v2.args");
            candidates.Add("presets/all_tcp_udp_multisplit_sni.args");
        }

        foreach (var rel in candidates)
        {
            var full = Path.Combine(runtimeRoot, rel.Replace('/', Path.DirectorySeparatorChar));
            if (File.Exists(full))
            {
                return full;
            }
        }

        return string.Empty;
    }

    private static void FinalizeStagedRule(
        List<string> stagedTokens,
        List<DpiRule> rules,
        string? listsDir,
        Action<string> log)
    {
        if (stagedTokens.Count == 0)
        {
            return;
        }

        var rule = ParseDpiRule(stagedTokens, listsDir, log);
        if (rule != null)
        {
            rules.Add(rule);
        }

        stagedTokens.Clear();
    }

    private static DpiRule? ParseDpiRule(IReadOnlyList<string> tokens, string? listsDir, Action<string> log)
    {
        var filterTcp = GetOptionValue(tokens, "--filter-tcp");
        if (string.IsNullOrWhiteSpace(filterTcp))
        {
            return null;
        }

        var tcpPorts = ParsePortRanges(filterTcp!);
        if (tcpPorts.Count == 0)
        {
            return null;
        }

        var rule = new DpiRule
        {
            HasDesyncDirective = HasOption(tokens, "--dpi-desync") || HasOption(tokens, "--lua-desync")
        };
        rule.TcpPorts.AddRange(tcpPorts);
        var hasIncludeConstraint = false;

        foreach (var option in new[] { "--hostlist", "--hostlist-domains" })
        {
            var value = GetOptionValue(tokens, option);
            if (!string.IsNullOrWhiteSpace(value))
            {
                hasIncludeConstraint = true;
                foreach (var suffix in ResolveHostSuffixes(value!, listsDir, log))
                {
                    rule.IncludeHostSuffixes.Add(suffix);
                }
            }
        }

        {
            var value = GetOptionValue(tokens, "--ipset");
            if (!string.IsNullOrWhiteSpace(value))
            {
                hasIncludeConstraint = true;
                foreach (var subnet in ResolveIpSubnets(value!, listsDir, log))
                {
                    rule.IncludeIpSubnets.Add(subnet);
                }
            }
        }

        foreach (var option in new[] { "--hostlist-exclude", "--hostlist-domains-exclude" })
        {
            var value = GetOptionValue(tokens, option);
            if (!string.IsNullOrWhiteSpace(value))
            {
                foreach (var suffix in ResolveHostSuffixes(value!, listsDir, log))
                {
                    rule.ExcludeHostSuffixes.Add(suffix);
                }
            }
        }

        {
            var value = GetOptionValue(tokens, "--ipset-exclude");
            if (!string.IsNullOrWhiteSpace(value))
            {
                foreach (var subnet in ResolveIpSubnets(value!, listsDir, log))
                {
                    rule.ExcludeIpSubnets.Add(subnet);
                }
            }
        }

        rule.RequireIncludeMatch = hasIncludeConstraint;
        return rule;
    }

    private static bool HasOption(IReadOnlyList<string> tokens, string option)
    {
        foreach (var token in tokens)
        {
            if (token.Equals(option, StringComparison.OrdinalIgnoreCase) ||
                token.StartsWith(option + "=", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static string? GetOptionValue(IReadOnlyList<string> tokens, string option)
    {
        for (var i = 0; i < tokens.Count; i++)
        {
            var token = tokens[i];
            if (token.Equals(option, StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 < tokens.Count && !tokens[i + 1].StartsWith("--", StringComparison.Ordinal))
                {
                    return tokens[i + 1];
                }

                return string.Empty;
            }

            if (token.StartsWith(option + "=", StringComparison.OrdinalIgnoreCase))
            {
                return token[(option.Length + 1)..];
            }
        }

        return null;
    }

    private static List<(int Start, int End)> ParsePortRanges(string raw)
    {
        var result = new List<(int Start, int End)>();
        foreach (var part in raw.Split(',', StringSplitOptions.RemoveEmptyEntries))
        {
            var token = part.Trim();
            if (token.Length == 0)
            {
                continue;
            }

            var dash = token.IndexOf('-');
            if (dash > 0)
            {
                var left = token[..dash].Trim();
                var right = token[(dash + 1)..].Trim();
                if (!int.TryParse(left, out var start) || !int.TryParse(right, out var end))
                {
                    continue;
                }

                if (start < 1 || end < 1 || start > 65535 || end > 65535)
                {
                    continue;
                }

                if (end < start)
                {
                    (start, end) = (end, start);
                }

                result.Add((start, end));
                continue;
            }

            if (!int.TryParse(token, out var single) || single < 1 || single > 65535)
            {
                continue;
            }

            result.Add((single, single));
        }

        return result;
    }

    private static IEnumerable<string> ResolveHostSuffixes(string raw, string? listsDir, Action<string> log)
    {
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var tokens = raw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        foreach (var token in tokens)
        {
            if (token.Length == 0)
            {
                continue;
            }

            if (LooksLikeHostToken(token))
            {
                result.Add(NormalizeSuffix(token));
                continue;
            }

            if (string.IsNullOrWhiteSpace(listsDir))
            {
                continue;
            }

            var listPath = ResolveListPath(token, listsDir);
            if (!File.Exists(listPath))
            {
                log($"[LocalSocks5Server] Missing hostlist: {token}");
                continue;
            }

            foreach (var line in File.ReadLines(listPath))
            {
                var trimmed = NormalizeListToken(line);
                if (trimmed.Length == 0)
                {
                    continue;
                }

                if (LooksLikeHostToken(trimmed))
                {
                    result.Add(NormalizeSuffix(trimmed));
                }
            }
        }

        return result;
    }

    private static IEnumerable<IpSubnet> ResolveIpSubnets(string raw, string? listsDir, Action<string> log)
    {
        var result = new HashSet<IpSubnet>();
        var tokens = raw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        foreach (var token in tokens)
        {
            if (token.Length == 0)
            {
                continue;
            }

            if (IpSubnet.TryParse(token, out var directSubnet))
            {
                result.Add(directSubnet!);
                continue;
            }

            if (string.IsNullOrWhiteSpace(listsDir))
            {
                continue;
            }

            var listPath = ResolveListPath(token, listsDir);
            if (!File.Exists(listPath))
            {
                log($"[LocalSocks5Server] Missing ipset: {token}");
                continue;
            }

            foreach (var line in File.ReadLines(listPath))
            {
                var value = NormalizeListToken(line);
                if (value.Length == 0)
                {
                    continue;
                }

                if (IpSubnet.TryParse(value, out var subnet))
                {
                    result.Add(subnet!);
                }
            }
        }

        return result;
    }

    private static bool LooksLikeHostToken(string value)
    {
        var token = value.Trim();
        if (token.Length == 0)
        {
            return false;
        }

        if (token.Contains('/') || token.Contains('\\') || token.Contains(':') || token.StartsWith("@", StringComparison.Ordinal))
        {
            return false;
        }

        return token.Any(char.IsLetter) && token.Contains('.');
    }

    private static string NormalizeSuffix(string host)
    {
        var token = host.Trim().TrimStart('.').ToLowerInvariant();
        return "." + token;
    }

    private static string NormalizeListToken(string line)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return string.Empty;
        }

        var raw = line.Trim().TrimStart('\uFEFF');
        var commentIndex = raw.IndexOfAny(new[] { '#', ';' });
        if (commentIndex == 0)
        {
            return string.Empty;
        }

        if (commentIndex > 0)
        {
            raw = raw[..commentIndex].Trim();
        }

        return raw;
    }

    private static string ResolveListPath(string reference, string listsDir)
    {
        var normalized = reference
            .Trim()
            .Trim('"')
            .Replace('/', Path.DirectorySeparatorChar)
            .Replace('\\', Path.DirectorySeparatorChar);

        var listsPrefix = $"lists{Path.DirectorySeparatorChar}";
        if (normalized.StartsWith(listsPrefix, StringComparison.OrdinalIgnoreCase))
        {
            normalized = normalized[listsPrefix.Length..];
        }

        var dotPrefix = $".{Path.DirectorySeparatorChar}";
        if (normalized.StartsWith(dotPrefix, StringComparison.Ordinal))
        {
            normalized = normalized[dotPrefix.Length..];
        }

        if (Path.IsPathRooted(normalized))
        {
            return normalized;
        }

        var local = Path.Combine(listsDir, normalized);
        if (File.Exists(local))
        {
            return local;
        }

        var rootCandidate = Path.Combine(listsDir, "root", Path.GetFileName(normalized));
        if (File.Exists(rootCandidate))
        {
            return rootCandidate;
        }

        return local;
    }

    private static IReadOnlyList<string> SplitArgs(string line)
    {
        var result = new List<string>();
        var sb = new StringBuilder();
        var inQuotes = false;

        foreach (var ch in line)
        {
            if (ch == '"')
            {
                inQuotes = !inQuotes;
                continue;
            }

            if (!inQuotes && char.IsWhiteSpace(ch))
            {
                if (sb.Length > 0)
                {
                    result.Add(sb.ToString());
                    sb.Clear();
                }
                continue;
            }

            sb.Append(ch);
        }

        if (sb.Length > 0)
        {
            result.Add(sb.ToString());
        }

        return result;
    }

    private sealed class DpiRule
    {
        public List<(int Start, int End)> TcpPorts { get; } = new();
        public HashSet<string> IncludeHostSuffixes { get; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> ExcludeHostSuffixes { get; } = new(StringComparer.OrdinalIgnoreCase);
        public List<IpSubnet> IncludeIpSubnets { get; } = new();
        public List<IpSubnet> ExcludeIpSubnets { get; } = new();
        public bool HasDesyncDirective { get; init; }
        public bool RequireIncludeMatch { get; set; }
    }

    private sealed class IpSubnet : IEquatable<IpSubnet>
    {
        private readonly AddressFamily _family;
        private readonly byte[] _networkBytes;
        private readonly int _prefixLength;

        private IpSubnet(AddressFamily family, byte[] networkBytes, int prefixLength)
        {
            _family = family;
            _networkBytes = networkBytes;
            _prefixLength = prefixLength;
        }

        public static bool TryParse(string token, out IpSubnet? subnet)
        {
            subnet = null;
            if (string.IsNullOrWhiteSpace(token))
            {
                return false;
            }

            var value = NormalizeListToken(token);
            if (value.Length == 0)
            {
                return false;
            }

            string addressPart;
            int prefixLength;
            var slashIndex = value.IndexOf('/');
            if (slashIndex > 0)
            {
                addressPart = value[..slashIndex].Trim();
                var prefixPart = value[(slashIndex + 1)..].Trim();
                if (!int.TryParse(prefixPart, out prefixLength))
                {
                    return false;
                }
            }
            else
            {
                addressPart = value;
                prefixLength = -1;
            }

            if (!IPAddress.TryParse(addressPart, out var address))
            {
                return false;
            }

            if (address.IsIPv4MappedToIPv6)
            {
                address = address.MapToIPv4();
            }

            var family = address.AddressFamily;
            var maxPrefix = family switch
            {
                AddressFamily.InterNetwork => 32,
                AddressFamily.InterNetworkV6 => 128,
                _ => -1
            };
            if (maxPrefix < 0)
            {
                return false;
            }

            if (prefixLength < 0)
            {
                prefixLength = maxPrefix;
            }

            if (prefixLength < 0 || prefixLength > maxPrefix)
            {
                return false;
            }

            var bytes = address.GetAddressBytes();
            ApplyMask(bytes, prefixLength);
            subnet = new IpSubnet(family, bytes, prefixLength);
            return true;
        }

        public bool Contains(IPAddress candidate)
        {
            if (candidate.IsIPv4MappedToIPv6)
            {
                candidate = candidate.MapToIPv4();
            }

            if (candidate.AddressFamily != _family)
            {
                return false;
            }

            var bytes = candidate.GetAddressBytes();
            var fullBytes = _prefixLength / 8;
            var extraBits = _prefixLength % 8;

            for (var i = 0; i < fullBytes; i++)
            {
                if (bytes[i] != _networkBytes[i])
                {
                    return false;
                }
            }

            if (extraBits > 0)
            {
                var mask = (byte)(0xFF << (8 - extraBits));
                if ((bytes[fullBytes] & mask) != (_networkBytes[fullBytes] & mask))
                {
                    return false;
                }
            }

            return true;
        }

        public bool Equals(IpSubnet? other)
        {
            if (other is null)
            {
                return false;
            }

            if (_family != other._family || _prefixLength != other._prefixLength)
            {
                return false;
            }

            if (_networkBytes.Length != other._networkBytes.Length)
            {
                return false;
            }

            for (var i = 0; i < _networkBytes.Length; i++)
            {
                if (_networkBytes[i] != other._networkBytes[i])
                {
                    return false;
                }
            }

            return true;
        }

        public override bool Equals(object? obj)
        {
            return obj is IpSubnet other && Equals(other);
        }

        public override int GetHashCode()
        {
            var hash = HashCode.Combine((int)_family, _prefixLength);
            foreach (var b in _networkBytes)
            {
                hash = HashCode.Combine(hash, b);
            }

            return hash;
        }

        private static void ApplyMask(byte[] bytes, int prefixLength)
        {
            var fullBytes = prefixLength / 8;
            var extraBits = prefixLength % 8;

            if (extraBits > 0 && fullBytes < bytes.Length)
            {
                var mask = (byte)(0xFF << (8 - extraBits));
                bytes[fullBytes] &= mask;
                fullBytes++;
            }

            for (var i = fullBytes; i < bytes.Length; i++)
            {
                bytes[i] = 0;
            }
        }
    }

    public void Dispose()
    {
        Stop();
        try
        {
            _acceptTask?.Wait(200);
        }
        catch
        {
            // ignored
        }
        _cts?.Dispose();
        _cts = null;
        _acceptTask = null;
        _listener = null;
    }
}
