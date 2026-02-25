using System.Text;
using System.Text.Json;

namespace NoRKN.Android;

public sealed class PresetCompilationResult
{
    public string ProfileName { get; init; } = "multisplit";
    public string ActivePresetPath { get; init; } = string.Empty;
    public IReadOnlyList<string> EngineArgs { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> UnsupportedOptions { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> MissingReferences { get; init; } = Array.Empty<string>();
    public bool QuicPreferred { get; init; }

    public string ToOptionsJson()
    {
        var payload = new
        {
            profile = ProfileName,
            activePreset = ActivePresetPath,
            quicPreferred = QuicPreferred,
            engineArgs = EngineArgs,
            unsupported = UnsupportedOptions,
            missingReferences = MissingReferences
        };

        return JsonSerializer.Serialize(payload);
    }
}

public static class PresetRuntime
{
    private static readonly Dictionary<string, string> ProfilePresetMap = new(StringComparer.OrdinalIgnoreCase)
    {
        ["multisplit"] = "presets/all_tcp_udp_multisplit_sni.args",
        ["strong"] = "presets/all_tcp_udp_multisplit_sni.args"
    };

    private static readonly HashSet<string> SupportedOptions = new(StringComparer.OrdinalIgnoreCase)
    {
        "--wf-tcp",
        "--wf-udp",
        "--filter-l3",
        "--filter-tcp",
        "--filter-udp",
        "--hostlist",
        "--ipset",
        "--new",
        "--dpi-desync",
        "--dpi-desync-any-protocol",
        "--dpi-desync-cutoff",
        "--dpi-desync-repeats",
        "--dpi-desync-ttl",
        "--dpi-desync-autottl",
        "--dpi-desync-fooling",
        "--dpi-desync-split-pos",
        "--dpi-desync-split-seqovl",
        "--dpi-desync-fake-tls",
        "--dpi-desync-fake-quic",
        "--dpi-desync-fake-syndata",
        "--dpi-desync-fake-unknown-udp",
        "--dpi-desync-fake-wireguard",
        "--dpi-desync-fake-dht",
        "--dpi-desync-fake-discord",
        "--dpi-desync-fake-stun",
        "--dpi-desync-fwmark",
        "--dpi-desync-start",
        "--dpi-desync-end"
    };

    private static readonly HashSet<string> FileReferenceOptions = new(StringComparer.OrdinalIgnoreCase)
    {
        "--hostlist",
        "--ipset",
        "--dpi-desync-fake-tls",
        "--dpi-desync-fake-quic",
        "--dpi-desync-fake-syndata",
        "--dpi-desync-fake-unknown-udp",
        "--dpi-desync-fake-wireguard",
        "--dpi-desync-fake-dht",
        "--dpi-desync-fake-discord",
        "--dpi-desync-fake-stun"
    };

    public static PresetCompilationResult Compile(string runtimeRoot, string profileName, Action<string>? log = null)
    {
        if (!ProfilePresetMap.TryGetValue(profileName, out var presetRelative))
        {
            presetRelative = ProfilePresetMap["multisplit"];
        }

        var presetPath = Path.Combine(runtimeRoot, presetRelative.Replace('/', Path.DirectorySeparatorChar));
        var args = new List<string>();
        var unsupported = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var missing = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        if (!File.Exists(presetPath))
        {
            missing.Add(presetPath);
            log?.Invoke($"[skip] Missing preset: {presetPath}");
            return new PresetCompilationResult
            {
                ProfileName = profileName,
                ActivePresetPath = presetRelative,
                EngineArgs = args,
                UnsupportedOptions = unsupported.ToArray(),
                MissingReferences = missing.ToArray(),
                QuicPreferred = false
            };
        }

        foreach (var line in File.ReadLines(presetPath))
        {
            var trimmed = line.Trim();
            if (string.IsNullOrWhiteSpace(trimmed) || trimmed.StartsWith('#') || trimmed.StartsWith(';'))
            {
                continue;
            }

            foreach (var token in SplitArgs(trimmed))
            {
                args.Add(token);
            }
        }

        var quicPreferred = false;
        for (var i = 0; i < args.Count; i++)
        {
            var token = args[i];
            if (!token.StartsWith("--", StringComparison.Ordinal))
            {
                continue;
            }

            var option = token;
            var valueInSameToken = string.Empty;
            var eqIndex = token.IndexOf('=');
            if (eqIndex > 0)
            {
                option = token[..eqIndex];
                valueInSameToken = token[(eqIndex + 1)..];
            }

            if (option.Equals("--wf-udp", StringComparison.OrdinalIgnoreCase) ||
                token.Contains("quic", StringComparison.OrdinalIgnoreCase))
            {
                quicPreferred = true;
            }

            if (!SupportedOptions.Contains(option))
            {
                unsupported.Add(option);
            }

            if (!FileReferenceOptions.Contains(option))
            {
                continue;
            }

            var value = valueInSameToken;
            if (string.IsNullOrWhiteSpace(value))
            {
                if (i + 1 >= args.Count)
                {
                    continue;
                }

                value = args[i + 1];
            }

            var normalized = NormalizeReferencePath(runtimeRoot, value);
            if (!File.Exists(normalized))
            {
                missing.Add(normalized);
                log?.Invoke($"[skip] Missing reference: {value}");
            }
        }

        return new PresetCompilationResult
        {
            ProfileName = profileName,
            ActivePresetPath = presetRelative,
            EngineArgs = args,
            UnsupportedOptions = unsupported.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToArray(),
            MissingReferences = missing.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToArray(),
            QuicPreferred = quicPreferred
        };
    }

    private static string NormalizeReferencePath(string runtimeRoot, string raw)
    {
        var value = raw.Trim().Trim('"');
        if (Path.IsPathRooted(value))
        {
            return value;
        }

        var combined = Path.Combine(runtimeRoot, value.Replace('/', Path.DirectorySeparatorChar));
        return Path.GetFullPath(combined);
    }

    private static IReadOnlyList<string> SplitArgs(string line)
    {
        var result = new List<string>();
        var sb = new StringBuilder();
        var inQuotes = false;

        for (var i = 0; i < line.Length; i++)
        {
            var ch = line[i];
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
}
