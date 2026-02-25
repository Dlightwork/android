using Android.Content;

namespace NoRKN.Android;

public sealed class ZapretRuntimePaths
{
    public required string RootDir { get; init; }
    public required string BinDir { get; init; }
    public required string ListsDir { get; init; }
    public required string LuaDir { get; init; }
    public required string PresetsDir { get; init; }
    public required string FiltersDir { get; init; }
}

public static class ZapretAssetsBootstrap
{
    private const string AssetPackVersion = "2";

    public static ZapretRuntimePaths Ensure(Context context, Action<string>? log = null)
    {
        var filesRoot = context.FilesDir?.AbsolutePath
            ?? throw new InvalidOperationException("Android files directory is not available.");

        var runtime = new ZapretRuntimePaths
        {
            RootDir = Path.Combine(filesRoot, "zapret"),
            BinDir = Path.Combine(filesRoot, "zapret", "bin"),
            ListsDir = Path.Combine(filesRoot, "zapret", "lists"),
            LuaDir = Path.Combine(filesRoot, "zapret", "lua"),
            PresetsDir = Path.Combine(filesRoot, "zapret", "presets"),
            FiltersDir = Path.Combine(filesRoot, "zapret", "windivert.filter")
        };

        var marker = Path.Combine(runtime.RootDir, ".assets.version");
        var versionOk = File.Exists(marker) &&
                        string.Equals(File.ReadAllText(marker).Trim(), AssetPackVersion, StringComparison.Ordinal);

        if (versionOk)
        {
            EnsureAutoLists(runtime.ListsDir, log);
            return runtime;
        }

        if (Directory.Exists(runtime.RootDir))
        {
            Directory.Delete(runtime.RootDir, true);
        }

        Directory.CreateDirectory(runtime.RootDir);
        Directory.CreateDirectory(runtime.BinDir);
        Directory.CreateDirectory(runtime.ListsDir);
        Directory.CreateDirectory(runtime.LuaDir);
        Directory.CreateDirectory(runtime.PresetsDir);
        Directory.CreateDirectory(runtime.FiltersDir);

        var binCount = ExtractTree(context, "zapret/bin", runtime.BinDir);
        var listCount = ExtractTree(context, "zapret/lists", runtime.ListsDir);
        var luaCount = ExtractTree(context, "zapret/lua", runtime.LuaDir);
        var presetsCount = ExtractTree(context, "zapret/presets", runtime.PresetsDir);
        var filterCount = ExtractTree(context, "zapret/windivert.filter", runtime.FiltersDir);
        EnsureAutoLists(runtime.ListsDir, log);

        File.WriteAllText(marker, AssetPackVersion);
        log?.Invoke(
            $"assets extracted: bin={binCount}, lists={listCount}, lua={luaCount}, presets={presetsCount}, filters={filterCount}");

        return runtime;
    }

    private static int ExtractTree(Context context, string assetPath, string destinationPath)
    {
        var assets = context.Assets;
        if (assets == null)
        {
            return 0;
        }

        string[] children;
        try
        {
            children = assets.List(assetPath) ?? Array.Empty<string>();
        }
        catch
        {
            return 0;
        }

        if (children.Length == 0)
        {
            return ExtractSingleAssetFile(assets, assetPath, destinationPath) ? 1 : 0;
        }

        Directory.CreateDirectory(destinationPath);

        var extracted = 0;
        foreach (var child in children)
        {
            var childAsset = $"{assetPath}/{child}";
            var childDest = Path.Combine(destinationPath, child);
            extracted += ExtractTree(context, childAsset, childDest);
        }

        return extracted;
    }

    private static bool ExtractSingleAssetFile(global::Android.Content.Res.AssetManager assets, string assetPath, string destinationPath)
    {
        try
        {
            using var input = assets.Open(assetPath);
            var dir = Path.GetDirectoryName(destinationPath);
            if (!string.IsNullOrWhiteSpace(dir))
            {
                Directory.CreateDirectory(dir);
            }

            using var output = File.Create(destinationPath);
            input.CopyTo(output);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static void EnsureAutoLists(string listsDir, Action<string>? log)
    {
        if (!Directory.Exists(listsDir))
        {
            return;
        }

        var hostOut = Path.Combine(listsDir, "_auto_hostlist.txt");
        var ipsetOut = Path.Combine(listsDir, "_auto_ipset.txt");

        var hostSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var ipSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        var files = Directory.GetFiles(listsDir, "*.txt", SearchOption.AllDirectories)
            .Where(f =>
            {
                var name = Path.GetFileName(f);
                if (name.Equals("_auto_hostlist.txt", StringComparison.OrdinalIgnoreCase) ||
                    name.Equals("_auto_ipset.txt", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }

                return !name.Contains("Zone.Identifier", StringComparison.OrdinalIgnoreCase);
            })
            .ToArray();

        foreach (var file in files)
        {
            foreach (var line in File.ReadLines(file))
            {
                var token = NormalizeLine(line);
                if (string.IsNullOrWhiteSpace(token))
                {
                    continue;
                }

                if (LooksLikeIpOrSubnet(token))
                {
                    ipSet.Add(token);
                }
                else if (LooksLikeHost(token))
                {
                    hostSet.Add(token);
                }
            }
        }

        var hosts = hostSet.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToArray();
        var ips = ipSet.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToArray();

        File.WriteAllLines(hostOut, hosts);
        File.WriteAllLines(ipsetOut, ips);

        log?.Invoke($"auto lists updated: _auto_hostlist={hosts.Length}, _auto_ipset={ips.Length}");
    }

    private static string NormalizeLine(string rawLine)
    {
        if (string.IsNullOrWhiteSpace(rawLine))
        {
            return string.Empty;
        }

        var line = rawLine.Trim();
        if (line.StartsWith("#") || line.StartsWith(";"))
        {
            return string.Empty;
        }

        var commentIndex = line.IndexOfAny(new[] { '#', ';' });
        if (commentIndex > 0)
        {
            line = line[..commentIndex].Trim();
        }

        return line;
    }

    private static bool LooksLikeHost(string token)
    {
        if (token.Length < 3 || token.Length > 253)
        {
            return false;
        }

        if (token.Any(char.IsWhiteSpace))
        {
            return false;
        }

        if (!token.Contains('.'))
        {
            return false;
        }

        if (token.Contains('/') || token.Contains(':'))
        {
            return false;
        }

        return token.Any(char.IsLetterOrDigit);
    }

    private static bool LooksLikeIpOrSubnet(string token)
    {
        // IPv4/IPv6 literal
        if (System.Net.IPAddress.TryParse(token, out _))
        {
            return true;
        }

        var slash = token.IndexOf('/');
        if (slash <= 0 || slash == token.Length - 1)
        {
            return false;
        }

        var addrPart = token[..slash];
        var prefixPart = token[(slash + 1)..];
        if (!int.TryParse(prefixPart, out var prefix))
        {
            return false;
        }

        if (!System.Net.IPAddress.TryParse(addrPart, out var ip))
        {
            return false;
        }

        if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
        {
            return prefix is >= 0 and <= 32;
        }

        if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetworkV6)
        {
            return prefix is >= 0 and <= 128;
        }

        return false;
    }
}
