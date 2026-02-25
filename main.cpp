#include <iostream>
#include <string>
#include <vector>
#include <signal.h>
#include <windows.h>
#include "config.h"
#include <fstream>
#include <sstream>
#include <algorithm>
#include <winsock2.h>
#include <ws2tcpip.h>
#include "packet_engine.h"
#include "utils.h"

using namespace dPIBypass;

// Global engine for signal handling
PacketEngine* g_engine = nullptr;
std::atomic<bool> g_running{true};

// Signal handler
void SignalHandler(int sig) {
    std::cout << "\nReceived signal " << sig << ", shutting down..." << std::endl;
    g_running = false;
    if (g_engine) {
        g_engine->Stop();
    }
}

// Print banner
void PrintBanner() {
    std::cout << R"(
    ╔══════════════════════════════════════════════════════════════════╗
    ║                                                                  ║
    ║     dPI-Bypass - Advanced DPI Circumvention Tool                 ║
    ║     Version: 1.0.0 | 2026-Ready Methods | Roblox-Optimized     ║
    ║                                                                  ║
    ║     ROBLOX-SAFE MODE FEATURES:                                   ║
    ║     • Certificate-safe operations (no MITM, no SSL break)      ║
    ║     • Error 279 prevention (keep-alive packets)                  ║
    ║     • Low-latency game traffic optimization                      ║
    ║     • End-to-end encryption preserved                            ║
    ║                                                                  ║
    ║     Target Services: Roblox, YouTube, Discord, Telegram          ║
    ║                                                                  ║
    ╚══════════════════════════════════════════════════════════════════╝
    )" << std::endl;
}

// Print usage
void PrintUsage(const char* program) {
    std::cout << "Usage: " << program << " [options] <service>" << std::endl;
    std::cout << std::endl;
    std::cout << "Services:" << std::endl;
    std::cout << "  roblox    - Roblox platform (certificate-safe mode)" << std::endl;
    std::cout << "  youtube   - YouTube (youtube.com, googlevideo.com)" << std::endl;
    std::cout << "  discord   - Discord (discord.com, discord.gg)" << std::endl;
    std::cout << "  telegram  - Telegram (telegram.org, t.me)" << std::endl;
    std::cout << "  all       - All services simultaneously" << std::endl;
    std::cout << "  auto      - Use combined auto hostlist/ipset" << std::endl;
    std::cout << std::endl;
    std::cout << "ROBLOX-SPECIFIC OPTIONS:" << std::endl;
    std::cout << "  --roblox-safe       Force certificate-safe mode (default for roblox)" << std::endl;
    std::cout << "  --keepalive         Enable keep-alive injection (prevents Error 279)" << std::endl;
    std::cout << "  --game-optimize     Optimize for low-latency gaming" << std::endl;
    std::cout << "  --no-quic-drop      Keep QUIC/UDP for game traffic (default for roblox)" << std::endl;
    std::cout << std::endl;
    std::cout << "GENERAL OPTIONS:" << std::endl;
    std::cout << "  -v, --verbose       Enable verbose logging" << std::endl;
    std::cout << "  -p, --packet-log    Enable packet logging" << std::endl;
    std::cout << "  -s, --strategy      Select strategy (fakemultisplit, fakesni, ttl, all)" << std::endl;
    std::cout << "  -d, --delay         Set desync delay in ms (default: auto)" << std::endl;
    std::cout << "  -t, --ttl-fake      Set fake TTL (default: 3-5)" << std::endl;
    std::cout << "  --stats             Show statistics periodically" << std::endl;
    std::cout << "  -h, --help          Show this help" << std::endl;
    std::cout << std::endl;
    std::cout << "ROBLOX EXAMPLES:" << std::endl;
    std::cout << "  " << program << " roblox                     # Safe mode with defaults" << std::endl;
    std::cout << "  " << program << " -v --roblox-safe roblox     # Verbose safe mode" << std::endl;
    std::cout << "  " << program << " -v --stats roblox            # With statistics" << std::endl;
    std::cout << std::endl;
    std::cout << "OTHER SERVICES:" << std::endl;
    std::cout << "  " << program << " youtube                    # Basic YouTube bypass" << std::endl;
    std::cout << "  " << program << " -v -s fakemultisplit discord # Verbose with fakemultisplit" << std::endl;
}

// Parse arguments
struct Arguments {
    std::string service;
    bool verbose = false;
    bool packetLog = false;
    std::string strategy = "all";
    int delayMs = -1;
    int fakeTtl = -1;
    bool showStats = false;
    bool robloxSafe = false;
    bool keepAlive = true;      // Default on for Roblox
    bool gameOptimize = true;   // Default on for Roblox
    bool noQuicDrop = true;     // Default on for Roblox (keep UDP)
};

// Utility function to trim whitespace from both ends of a string
static inline std::string Trim(const std::string& s) {
    auto start = s.find_first_not_of(" \t\r\n");
    if (start == std::string::npos) return "";
    auto end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}

// Load list of strings from a text file. Ignores lines starting with '#' and blank lines.
static std::vector<std::string> LoadListFromFile(const std::string& filePath) {
    std::vector<std::string> result;
    std::ifstream file(filePath);
    if (!file.is_open()) {
        return result;
    }
    std::string line;
    while (std::getline(file, line)) {
        line = Trim(line);
        if (line.empty()) continue;
        // skip comments
        if (!line.empty() && line[0] == '#') continue;
        result.push_back(line);
    }
    return result;
}

// Simple structure to hold IPv4 network and mask
struct IPv4Network {
    uint32_t network;
    uint32_t mask;
};

// Parse CIDR notation into IPv4Network. Returns false on failure.
static bool ParseCIDR(const std::string& cidr, IPv4Network& out) {
    size_t slashPos = cidr.find('/');
    std::string ipPart = cidr;
    int prefixLen = 32;
    if (slashPos != std::string::npos) {
        ipPart = cidr.substr(0, slashPos);
        std::string prefixStr = cidr.substr(slashPos + 1);
        try {
            prefixLen = std::stoi(prefixStr);
        } catch (...) {
            return false;
        }
        if (prefixLen < 0 || prefixLen > 32) return false;
    }
    // Convert IP string to numeric
    uint32_t addr = 0;
    int a, b, c, d;
    if (sscanf(ipPart.c_str(), "%d.%d.%d.%d", &a, &b, &c, &d) != 4) {
        return false;
    }
    if (a < 0 || a > 255 || b < 0 || b > 255 || c < 0 || c > 255 || d < 0 || d > 255) {
        return false;
    }
    addr = ((uint32_t)a << 24) | ((uint32_t)b << 16) | ((uint32_t)c << 8) | (uint32_t)d;
    // Build mask
    uint32_t mask = (prefixLen == 0) ? 0 : (0xFFFFFFFFu << (32 - prefixLen));
    out.network = addr & mask;
    out.mask = mask;
    return true;
}

// Check if an IPv4 address (host order) is within any of the provided CIDR ranges
static bool IsIpInRanges(uint32_t ipHostOrder, const std::vector<IPv4Network>& ranges) {
    for (const auto& r : ranges) {
        if ((ipHostOrder & r.mask) == r.network) {
            return true;
        }
    }
    return false;
}

Arguments ParseArguments(int argc, char* argv[]) {
    Arguments args;
    
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        
        if (arg == "-h" || arg == "--help") {
            PrintUsage(argv[0]);
            exit(0);
        } else if (arg == "-v" || arg == "--verbose") {
            args.verbose = true;
        } else if (arg == "-p" || arg == "--packet-log") {
            args.packetLog = true;
        } else if (arg == "-s" || arg == "--strategy") {
            if (i + 1 < argc) {
                args.strategy = argv[++i];
            }
        } else if (arg == "-d" || arg == "--delay") {
            if (i + 1 < argc) {
                args.delayMs = std::stoi(argv[++i]);
            }
        } else if (arg == "-t" || arg == "--ttl-fake") {
            if (i + 1 < argc) {
                args.fakeTtl = std::stoi(argv[++i]);
            }
        } else if (arg == "--stats") {
            args.showStats = true;
        } else if (arg == "--roblox-safe") {
            args.robloxSafe = true;
        } else if (arg == "--keepalive") {
            args.keepAlive = true;
        } else if (arg == "--no-keepalive") {
            args.keepAlive = false;
        } else if (arg == "--game-optimize") {
            args.gameOptimize = true;
        } else if (arg == "--no-game-optimize") {
            args.gameOptimize = false;
        } else if (arg == "--no-quic-drop") {
            args.noQuicDrop = true;
        } else if (arg == "--quic-drop") {
            args.noQuicDrop = false;
        } else if (arg[0] != '-') {
            args.service = arg;
        }
    }
    
    // Auto-enable Roblox options for Roblox service
    if (args.service == "roblox") {
        args.robloxSafe = true;
        args.keepAlive = true;
        args.gameOptimize = true;
        args.noQuicDrop = true;
    }
    
    return args;
}

// Get service profile by name
const ServiceProfile* GetServiceProfile(const std::string& name) {
    if (name == "roblox") return &ROBLOX_PROFILE;
    if (name == "youtube") return &YOUTUBE_PROFILE;
    if (name == "discord") return &DISCORD_PROFILE;
    if (name == "telegram") return &TELEGRAM_PROFILE;
    return nullptr;
}

// Main function
int main(int argc, char* argv[]) {
    PrintBanner();
    
    // Check for admin privileges
    BOOL isAdmin = FALSE;
    PSID administratorsGroup = NULL;
    SID_IDENTIFIER_AUTHORITY NtAuthority = SECURITY_NT_AUTHORITY;
    
    if (AllocateAndInitializeSid(&NtAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID,
                                  DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0,
                                  &administratorsGroup)) {
        CheckTokenMembership(NULL, administratorsGroup, &isAdmin);
        FreeSid(administratorsGroup);
    }
    
    if (!isAdmin) {
        std::cerr << "ERROR: This program requires administrator privileges." << std::endl;
        std::cerr << "Please run as administrator." << std::endl;
        return 1;
    }
    
    // Parse arguments
    Arguments args = ParseArguments(argc, argv);

    // Load extended lists for Discord
    static ServiceProfile discordProfileExtended = DISCORD_PROFILE;
    {
        // Load domain list
        std::vector<std::string> domains = LoadListFromFile("lists/discord_domains.txt");
        if (domains.empty()) {
            domains = LoadListFromFile("discord_domains.txt");
        }
        if (!domains.empty()) {
            discordProfileExtended.domains = domains;
        }
        // Load IP ranges
        std::vector<std::string> ipranges = LoadListFromFile("lists/ipset-discord.txt");
        if (ipranges.empty()) {
            ipranges = LoadListFromFile("ipset-discord.txt");
        }
        if (!ipranges.empty()) {
            discordProfileExtended.ip_ranges = ipranges;
        }
    }

    // Load extended lists for Roblox (domains and IP ranges)
    static ServiceProfile robloxProfileExtended = ROBLOX_PROFILE;
    {
        // Load extended Roblox domain list
        std::vector<std::string> domains = LoadListFromFile("lists/roblox_domains.txt");
        if (domains.empty()) {
            domains = LoadListFromFile("roblox_domains.txt");
        }
        if (!domains.empty()) {
            robloxProfileExtended.domains = domains;
        }
        // Load Roblox IP ranges
        std::vector<std::string> ipranges = LoadListFromFile("lists/ipset-roblox.txt");
        if (ipranges.empty()) {
            ipranges = LoadListFromFile("ipset-roblox.txt");
        }
        if (!ipranges.empty()) {
            robloxProfileExtended.ip_ranges = ipranges;
        }
        // Ensure Roblox extended profile honours safe settings
        robloxProfileExtended.use_quic = false;
        robloxProfileExtended.use_desync = false;
    }

    // Load auto profile if requested via "all" or "auto"
    static ServiceProfile autoProfile = {
        "auto",
        {},
        {},
        true,   // use_quic
        true,   // use_desync
        3,      // ttl_fake
        64,     // ttl_real
        12,     // segment_size
        10      // desync_delay_ms
    };
    {
        // Only load if host or ip lists are present
        std::vector<std::string> autoHosts = LoadListFromFile("lists/_auto_hostlist.txt");
        if (autoHosts.empty()) {
            autoHosts = LoadListFromFile("_auto_hostlist.txt");
        }
        if (!autoHosts.empty()) {
            autoProfile.domains = autoHosts;
        }
        std::vector<std::string> autoIps = LoadListFromFile("lists/_auto_ipset.txt");
        if (autoIps.empty()) {
            autoIps = LoadListFromFile("_auto_ipset.txt");
        }
        if (!autoIps.empty()) {
            autoProfile.ip_ranges = autoIps;
        }
    }
    
    if (args.service.empty()) {
        std::cerr << "ERROR: No service specified." << std::endl;
        PrintUsage(argv[0]);
        return 1;
    }
    
    // Setup signal handlers
    signal(SIGINT, SignalHandler);
    signal(SIGTERM, SignalHandler);
    
    // Create configuration
    GlobalConfig config;
    config.verbose_logging = args.verbose;
    config.roblox_safe_mode = args.robloxSafe;
    config.enable_keepalive = args.keepAlive;
    config.optimize_for_gaming = args.gameOptimize;
    // By default, enable QUIC drop (useful for QUIC‑only services) unless user passed --no-quic-drop
    config.enable_quic_drop = !args.noQuicDrop;

    // Service‑specific safety toggles.  Roblox and Discord rely on
    // reliable TLS/UDP flows; heavy desync or fake SNI injection can break
    // their connections, resulting in long load times or failing to
    // connect.  When roblox_safe_mode is active (either because
    // service==roblox or user passed --roblox-safe), disable those
    // strategies in the global config.  Similarly, disable them for
    // Discord to ensure voice and update checks work correctly.
    if (args.service == "roblox" || args.robloxSafe) {
        // Do not modify TLS beyond safe TTL trick.  Disable heavy multi‑split and fake SNI,
        // but keep TTL manipulation enabled to confuse DPI without breaking TLS.
        config.enable_fakemultisplit = false;
        config.enable_fake_sni = false;
        // Do NOT change TTL setting here; leave default true for safe obfuscation.
        // Never drop QUIC/UDP for Roblox
        config.enable_quic_drop = false;
    } else if (args.service == "discord") {
        // Preserve Discord voice/media by disabling desync and fake SNI
        config.enable_fakemultisplit = false;
        config.enable_fake_sni = false;
        // Do not drop QUIC/UDP for Discord
        config.enable_quic_drop = false;
    }
    
    if (args.delayMs > 0) {
        // Would need to modify profile, for now use defaults
    }
    
    if (args.fakeTtl > 0) {
        // Would need to modify profile
    }
    
    // Create and initialize engine
    PacketEngine engine(config);
    g_engine = &engine;
    
    if (!engine.Initialize()) {
        std::cerr << "ERROR: Failed to initialize packet engine." << std::endl;
        return 1;
    }
    
    // Configure strategies
    if (args.strategy == "fakemultisplit" || args.strategy == "all") {
        engine.EnableStrategy(DesyncStrategy::FAKEMULTISPLIT);
    }
    if (args.strategy == "fakesni" || args.strategy == "all") {
        engine.EnableStrategy(DesyncStrategy::FAKESNI_INJECTION);
    }
    if (args.strategy == "ttl" || args.strategy == "all") {
        engine.EnableStrategy(DesyncStrategy::TTL_TRICK);
    }
    if (args.strategy == "quicdrop" || args.strategy == "all") {
        if (!args.noQuicDrop) {
            engine.EnableStrategy(DesyncStrategy::QUIC_DROP);
        }
    }
    if (args.strategy == "seqdesync" || args.strategy == "all") {
        engine.EnableStrategy(DesyncStrategy::SEQUENCE_DESYNC);
    }
    
    // Set service profile
    {
        const ServiceProfile* profile = nullptr;
        // Special handling for discord and roblox to include extended domain/ip lists
        if (args.service == "discord") {
            profile = &discordProfileExtended;
        } else if (args.service == "roblox") {
            profile = &robloxProfileExtended;
        } else if (args.service == "all" || args.service == "auto") {
            // Use auto profile when all services requested
            profile = &autoProfile;
        } else {
            profile = GetServiceProfile(args.service);
        }
        if (!profile) {
            std::cerr << "ERROR: Unknown service: " << args.service << std::endl;
            return 1;
        }
        engine.SetServiceProfile(profile);
    }
    
    // Enable packet logging if requested
    if (args.packetLog) {
        engine.EnablePacketLogging(true);
    }
    
    // Print Roblox-specific info
    if (args.service == "roblox" || args.robloxSafe) {
        std::cout << "[*] ROBLOX SAFE MODE ENABLED" << std::endl;
        std::cout << "[*] Features: Certificate-safe, Error 279 prevention, Low latency" << std::endl;
        std::cout << "[*] SSL/TLS certificates will NOT be modified or inspected" << std::endl;
        std::cout << "[*] Keep-alive packets: " << (args.keepAlive ? "ENABLED" : "DISABLED") << std::endl;
        std::cout << "[*] Game optimization: " << (args.gameOptimize ? "ENABLED" : "DISABLED") << std::endl;
        std::cout << "[*] UDP/QUIC preservation: " << (args.noQuicDrop ? "ENABLED" : "DISABLED") << std::endl;
        std::cout << std::endl;
    }
    
    // Start engine
    std::cout << "[*] Starting DPI bypass for service: " << args.service << std::endl;
    std::cout << "[*] Strategy: " << args.strategy << std::endl;
    std::cout << "[*] Press Ctrl+C to stop" << std::endl;
    std::cout << std::endl;
    
    engine.Start();
    
    // Main loop
    while (g_running && engine.IsRunning()) {
        if (args.showStats) {
            engine.PrintStats();
        }
        
        // Sleep for stats interval or just yield
        std::this_thread::sleep_for(std::chrono::seconds(args.showStats ? 5 : 1));
    }
    
    // Cleanup
    std::cout << "\n[*] Stopping engine..." << std::endl;
    engine.Stop();
    
    // Final stats
    std::cout << "\n[*] Final statistics:" << std::endl;
    engine.PrintStats();
    
    std::cout << "[*] dPI-Bypass stopped." << std::endl;
    
    return 0;
}
