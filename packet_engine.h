#ifndef PACKET_ENGINE_H
#define PACKET_ENGINE_H

#include <windows.h>
#include <windivert.h>
#include <thread>
#include <atomic>
#include <mutex>
#include <queue>
#include <condition_variable>
#include "config.h"
#include "desync_strategies.h"
#include "roblox_optimizer.h"

namespace dPIBypass {

// Pending packet for queue management
struct PendingPacket {
    std::vector<uint8_t> data;
    WINDIVERT_ADDRESS addr;
    uint64_t timestamp;
    uint32_t retryCount;
};

// Packet processing statistics
struct PacketStats {
    std::atomic<uint64_t> totalReceived{0};
    std::atomic<uint64_t> totalSent{0};
    std::atomic<uint64_t> totalDropped{0};
    std::atomic<uint64_t> totalModified{0};
    std::atomic<uint64_t> tlsClientHello{0};
    std::atomic<uint64_t> quicInitial{0};
    std::atomic<uint64_t> desyncApplied{0};
    std::atomic<uint64_t> keepAliveInjected{0};  // Error 279 prevention
    std::atomic<uint64_t> gameTrafficOptimized{0};
    std::atomic<uint64_t> errors{0};
};

class PacketEngine {
public:
    PacketEngine(const GlobalConfig& config);
    ~PacketEngine();

    // Lifecycle
    bool Initialize();
    void Start();
    void Stop();
    bool IsRunning() const;

    // Configuration
    void SetServiceProfile(const ServiceProfile* profile);
    void EnableStrategy(DesyncStrategy strategy);
    void DisableStrategy(DesyncStrategy strategy);

    // Statistics
    void PrintStats() const;
    void ResetStats();


    // Debug
    void SetVerbose(bool verbose);
    void EnablePacketLogging(bool enable);

    // Roblox-specific
    void EnableRobloxSafeMode(bool enable);
    bool IsRobloxSafeMode() const;

private:
    // Core processing
    void CaptureLoop();
    void ProcessPacket(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr);
    void ProcessWithRobloxOptimizer(const uint8_t* packet, UINT packetLen, 
                                     WINDIVERT_ADDRESS* addr);
    void InjectSegments(const std::vector<PacketSegment>& segments, WINDIVERT_ADDRESS* baseAddr);
    void InjectMultiplePackets(const std::vector<std::vector<uint8_t>>& packets,
                                WINDIVERT_ADDRESS* baseAddr);
    void ReinjectPacket(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr);

    // Helper methods
    std::string BuildFilterString() const;
    bool InitializeWinDivert();
    void Cleanup();
    void KeepAliveThread();  // Background keep-alive for Error 279 prevention

    // Member variables
    GlobalConfig config_;
    const ServiceProfile* currentProfile_;
    DesyncEngine* desyncEngine_;
    RobloxOptimizer* robloxOptimizer_;  // Roblox-specific optimizations
    
    // WinDivert handle
    HANDLE divertHandle_;
    
    // Threading
    std::thread captureThread_;
    std::thread keepAliveThread_;
    std::atomic<bool> running_;
    
    // Statistics
    mutable std::mutex statsMutex_;
    PacketStats stats_;
    
    // Logging
    std::atomic<bool> verboseLogging_;
    std::atomic<bool> packetLogging_;
    
    // Filter configuration
    std::vector<DesyncStrategy> enabledStrategies_;
    
    // Roblox mode
    std::atomic<bool> robloxSafeMode_;
};

} // namespace dPIBypass

#endif // PACKET_ENGINE_H
