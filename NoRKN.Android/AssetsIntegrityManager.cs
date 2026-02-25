using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Android.Content;
using Android.Content.Res;

namespace NoRKN.Android;

public sealed class AssetExtractionResult
{
    public string RuntimeRoot { get; init; } = string.Empty;
    public string ManifestHash { get; init; } = string.Empty;
    public bool ReExtracted { get; init; }
    public int TotalFiles { get; init; }
    public IReadOnlyDictionary<string, int> GroupCounts { get; init; } = new Dictionary<string, int>();
}

public static class AssetsIntegrityManager
{
    private const string RuntimeFolderName = "zapret";
    private const string ManifestFileName = ".asset_manifest.json";
    private const string ManifestVersion = "android-runtime-v2";

    private static readonly string[] AssetRoots =
    {
        "bin",
        "lists",
        "lua",
        "presets",
        "windivert.filter"
    };

    public static AssetExtractionResult EnsureRuntime(Context context, Action<string>? log = null)
    {
        var runtimeRoot = Path.Combine(context.FilesDir?.AbsolutePath ?? context.FilesDir!.Path!, RuntimeFolderName);
        Directory.CreateDirectory(runtimeRoot);

        var assets = context.Assets;
        if (assets == null)
        {
            throw new InvalidOperationException("Android AssetManager is not available.");
        }

        var files = EnumerateManagedAssets(assets);
        var hash = ComputeManifestHash(files);
        var manifestPath = Path.Combine(runtimeRoot, ManifestFileName);
        var existing = ReadManifest(manifestPath);

        var needsExtract = existing == null ||
                           existing.Version != ManifestVersion ||
                           !string.Equals(existing.ManifestHash, hash, StringComparison.OrdinalIgnoreCase);

        if (needsExtract)
        {
            if (Directory.Exists(runtimeRoot))
            {
                foreach (var root in AssetRoots)
                {
                    var dir = Path.Combine(runtimeRoot, root.Replace('/', Path.DirectorySeparatorChar));
                    if (Directory.Exists(dir))
                    {
                        Directory.Delete(dir, recursive: true);
                    }
                }
            }

            foreach (var relativePath in files)
            {
                var targetPath = Path.Combine(runtimeRoot, relativePath.Replace('/', Path.DirectorySeparatorChar));
                var targetDir = Path.GetDirectoryName(targetPath);
                if (!string.IsNullOrWhiteSpace(targetDir))
                {
                    Directory.CreateDirectory(targetDir);
                }

                using var input = assets.Open(relativePath, Access.Streaming);
                using var output = File.Create(targetPath);
                input.CopyTo(output);
            }

            log?.Invoke($"assets extracted: {files.Count} files");
        }

        var groupCounts = BuildGroupCounts(files);
        WriteManifest(manifestPath, new AssetManifestState
        {
            Version = ManifestVersion,
            ManifestHash = hash,
            TotalFiles = files.Count,
            UpdatedUtc = DateTimeOffset.UtcNow,
            GroupCounts = groupCounts
        });

        return new AssetExtractionResult
        {
            RuntimeRoot = runtimeRoot,
            ManifestHash = hash,
            ReExtracted = needsExtract,
            TotalFiles = files.Count,
            GroupCounts = groupCounts
        };
    }

    private static List<string> EnumerateManagedAssets(AssetManager assets)
    {
        var files = new List<string>(capacity: 512);
        foreach (var root in AssetRoots)
        {
            var rootChildren = assets.List(root) ?? Array.Empty<string>();
            if (rootChildren.Length == 0)
            {
                continue;
            }

            CollectFilesRecursively(assets, root, files);
        }

        files.Sort(StringComparer.OrdinalIgnoreCase);
        return files;
    }

    private static void CollectFilesRecursively(AssetManager assets, string path, List<string> files)
    {
        var children = assets.List(path) ?? Array.Empty<string>();
        if (children.Length == 0)
        {
            files.Add(path.Replace('\\', '/'));
            return;
        }

        foreach (var child in children)
        {
            var childPath = string.IsNullOrEmpty(path) ? child : $"{path}/{child}";
            var nested = assets.List(childPath) ?? Array.Empty<string>();
            if (nested.Length == 0)
            {
                files.Add(childPath.Replace('\\', '/'));
            }
            else
            {
                CollectFilesRecursively(assets, childPath, files);
            }
        }
    }

    private static Dictionary<string, int> BuildGroupCounts(IEnumerable<string> files)
    {
        var result = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (var file in files)
        {
            var group = file.Split('/', 2)[0];
            result.TryGetValue(group, out var count);
            result[group] = count + 1;
        }

        return result;
    }

    private static string ComputeManifestHash(IReadOnlyList<string> files)
    {
        using var sha = SHA256.Create();
        var joined = string.Join('\n', files);
        var bytes = Encoding.UTF8.GetBytes($"{ManifestVersion}\n{joined}");
        var hash = sha.ComputeHash(bytes);
        return Convert.ToHexString(hash);
    }

    private static AssetManifestState? ReadManifest(string path)
    {
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<AssetManifestState>(json);
        }
        catch
        {
            return null;
        }
    }

    private static void WriteManifest(string path, AssetManifestState state)
    {
        var json = JsonSerializer.Serialize(state, new JsonSerializerOptions
        {
            WriteIndented = true
        });
        File.WriteAllText(path, json);
    }

    private sealed class AssetManifestState
    {
        public string Version { get; set; } = string.Empty;
        public string ManifestHash { get; set; } = string.Empty;
        public int TotalFiles { get; set; }
        public DateTimeOffset UpdatedUtc { get; set; }
        public Dictionary<string, int> GroupCounts { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    }
}
