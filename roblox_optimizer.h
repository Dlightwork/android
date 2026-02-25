#ifndef ROBLOX_OPTIMIZER_H
#define ROBLOX_OPTIMIZER_H

#include <windows.h>
#include <windivert.h>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include <mutex>
#include <unordered_map>
#include "config.h"

namespace dPIBypass {

// Roblox connection tracking
struct RobloxConnection {
    uint32_t srcIp;
    uint16_t srcPort;
    uint32_t dstIp;
    uint16_t dstPort;
    uint64_t lastActivity;
    bool isOptimized;
    uint32_t packetCount;
    uint32_t bytesTransferred;
    bool handshakeComplete;
};

// Game server endpoint
struct GameServer {
    std::string ip;
    uint16_t port;
    uint32_t latency;
    bool isHealthy;
};

class RobloxOptimizer {
public:
    RobloxOptimizer(const GlobalConfig& config);
    ~RobloxOptimizer();

    // Initialize optimizer
    bool Initialize();

    // Process packet for Roblox optimization
    bool ProcessPacket(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr);

    // Connection management
    void TrackConnection(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr);
    void UpdateConnectionStats(uint32_t srcIp, uint16_t srcPort, uint32_t bytes);
    bool IsRobloxConnection(uint32_t dstIp, uint16_t dstPort);

    // Optimization strategies
    void OptimizeGameTraffic(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr);
    void ReduceLatency(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr);
    void HandleWebSocket(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr);

    // Keep-alive for game connections
    void SendKeepAlive(uint32_t srcIp, uint16_t srcPort, uint32_t dstIp, uint16_t dstPort);
    void MaintainConnections();

    // Statistics
    uint32_t GetActiveConnections() const;
    uint64_t GetTotalBytesOptimized() const;

private:
    GlobalConfig config_;
    HANDLE divertHandle_;
    
    // Connection tracking
    std::map<uint64_t, RobloxConnection> connections_;
    mutable std::mutex connectionMutex_;
    
    // Game server list
    std::vector<GameServer> gameServers_;
    
    // Statistics
    std::atomic<uint64_t> totalBytesOptimized_{0};
    std::atomic<uint32_t> activeConnections_{0};
    
    // Helper methods
    uint64_t GetConnectionKey(uint32_t srcIp, uint16_t srcPort) const;
    uint64_t GetCurrentTimeMs() const;
    bool IsRobloxDomain(const std::string& domain) const;
    void ParseRobloxEndpoints();
};

} // namespace dPIBypass

#endif // ROBLOX_OPTIMIZER_H
