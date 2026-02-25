#include <iostream>
#include <string>
#include <signal.h>
#include <windows.h>
#include "zapret_config.h"
#include "zapret_engine.h"

using namespace Zapret;

ZapretEngine* g_engine = nullptr;
std::atomic<bool> g_running{true};

void SignalHandler(int sig) {
    std::cout << "\n[Zapret] Shutting down..." << std::endl;
    g_running = false;
    if (g_engine) {
        g_engine->Stop();
    }
}

void PrintBanner() {
    std::cout << R"(
    ╔══════════════════════════════════════════════════════════════════╗
    ║                                                                  ║
    ║     ZAPRET2 - Advanced DPI Bypass (February 2026)               ║
    ║     Optimized for: Roblox | YouTube | Discord                    ║
    ║                                                                  ║
    ║     Features:                                                    ║
    ║     • fakemultisplit - Multi-segment SNI spoofing               ║
    ║     • TTL tricks - Fake packet expiration                         ║
    ║     • QUIC drop - Force TCP fallback                              ║
    ║     • Keepalive - Prevent Error 279 (Roblox)                     ║
    ║     • DNS bypass - DoH/DoT support                                ║
    ║                                                                  ║
    ║     Performance Targets:                                          ║
    ║     • Roblox: 20-50ms ping, no Error 279                         ║
    ║     • YouTube: Stable 4K streaming, no buffering                  ║
    ║     • Discord: Clear voice, responsive chat                      ║
    ║                                                                  ║
    ╚══════════════════════════════════════════════════════════════════╝
    )" << std::endl;
}

void PrintUsage(const char* prog) {
    std::cout << "Usage: " << prog << " [options] [service]" << std::endl;
    std::cout << std::endl;
    std::cout << "Services (can combine):" << std::endl;
    std::cout << "  roblox    - Low ping gaming optimization" << std::endl;
    std::cout << "  youtube   - Stable streaming optimization" << std::endl;
    std::cout << "  discord   - Voice + chat optimization" << std::endl;
    std::cout << "  all       - All services (default)" << std::endl;
    std::cout << std::endl;
    std::cout << "Options:" << std::endl;
    std::cout << "  -v, --verbose     Verbose logging" << std::endl;
    std::cout << "  --stats           Show statistics every 10 seconds" << std::endl;
    std::cout << "  --no-quic         Disable QUIC (force TCP)" << std::endl;
    std::cout << "  --fake-count N    Number of fake SNIs (default: 3)" << std::endl;
    std::cout << "  -h, --help        Show this help" << std::endl;
    std::cout << std::endl;
    std::cout << "Examples:" << std::endl;
    std::cout << "  " << prog << " roblox -v              # Roblox only, verbose" << std::endl;
    std::cout << "  " << prog << " youtube --stats        # YouTube with stats" << std::endl;
    std::cout << "  " << prog << " all --no-quic          # All services, TCP only" << std::endl;
    std::cout << "  " << prog << " roblox discord -v      # Roblox + Discord" << std::endl;
}

struct Args {
    uint32_t serviceMask = 0xFFFFFFFF;  // All by default
    bool verbose = false;
    bool stats = false;
    bool noQuic = false;
    uint32_t fakeCount = 3;
};

Args ParseArgs(int argc, char* argv[]) {
    Args args;
    
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        
        if (arg == "-h" || arg == "--help") {
            PrintUsage(argv[0]);
            exit(0);
        } else if (arg == "-v" || arg == "--verbose") {
            args.verbose = true;
        } else if (arg == "--stats") {
            args.stats = true;
        } else if (arg == "--no-quic") {
            args.noQuic = true;
        } else if (arg == "--fake-count" && i + 1 < argc) {
            args.fakeCount = std::stoul(argv[++i]);
        } else if (arg == "roblox") {
            args.serviceMask |= 0x01;
        } else if (arg == "youtube") {
            args.serviceMask |= 0x02;
        } else if (arg == "discord") {
            args.serviceMask |= 0x04;
        } else if (arg == "all") {
            args.serviceMask = 0xFFFFFFFF;
        }
    }
    
    return args;
}

int main(int argc, char* argv[]) {
    PrintBanner();
    
    // Check admin
    BOOL isAdmin = FALSE;
    PSID adminGroup = NULL;
    SID_IDENTIFIER_AUTHORITY ntAuth = SECURITY_NT_AUTHORITY;
    
    if (AllocateAndInitializeSid(&ntAuth, 2, SECURITY_BUILTIN_DOMAIN_RID,
                                  DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0,
                                  &adminGroup)) {
        CheckTokenMembership(NULL, adminGroup, &isAdmin);
        FreeSid(adminGroup);
    }
    
    if (!isAdmin) {
        std::cerr << "[Zapret] ERROR: Run as Administrator!" << std::endl;
        return 1;
    }
    
    Args args = ParseArgs(argc, argv);
    
    signal(SIGINT, SignalHandler);
    signal(SIGTERM, SignalHandler);
    
    // Configure
    ZapretConfig config;
    config.verbose = args.verbose;
    config.enable_quic_drop = !args.noQuic;
    config.fake_sni_count = args.fakeCount;
    
    // Create and init engine
    ZapretEngine engine(config);
    g_engine = &engine;
    
    if (!engine.Initialize()) {
        std::cerr << "[Zapret] Failed to initialize!" << std::endl;
        return 1;
    }
    
    engine.SetActiveServices(args.serviceMask);
    
    std::cout << "[Zapret] Starting with services: ";
    if (args.serviceMask & 0x01) std::cout << "Roblox ";
    if (args.serviceMask & 0x02) std::cout << "YouTube ";
    if (args.serviceMask & 0x04) std::cout << "Discord ";
    std::cout << std::endl;
    
    std::cout << "[Zapret] Press Ctrl+C to stop" << std::endl;
    std::cout << std::endl;
    
    engine.Start();
    
    // Main loop
    while (g_running && engine.IsRunning()) {
        if (args.stats) {
            engine.PrintStats();
        }
        std::this_thread::sleep_for(std::chrono::seconds(args.stats ? 10 : 1));
    }
    
    std::cout << "[Zapret] Stopping..." << std::endl;
    engine.Stop();
    engine.PrintStats();
    
    std::cout << "[Zapret] Done." << std::endl;
    return 0;
}
