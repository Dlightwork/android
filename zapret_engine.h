#ifndef ZAPRET_ENGINE_H
#define ZAPRET_ENGINE_H

#include <windows.h>
#include <windivert.h>
#include <thread>
#include <atomic>
#include <vector>
#include <string>
#include <cstdint>
#include "zapret_config.h"
#include "utils.h"

namespace Zapret {

enum class ServiceType {
    UNKNOWN,
    ROBLOX,
    YOUTUBE,
    DISCORD,
    TELEGRAM
};

struct ServiceDetection {
    ServiceType type;
    bool isTarget;
    bool needsLowLatency;
    bool needsStableStream;
    bool needsVoiceOptimization;
};

class ZapretEngine {
public:
    ZapretEngine(const ZapretConfig& config);
    ~ZapretEngine();

    bool Initialize();
    void Start();
    void Stop();
    bool IsRunning() const;

    // Service-specific processing
    void SetActiveServices(uint32_t serviceMask); // bitmask of services

    // Statistics
    void PrintStats() const;

private:
    void CaptureLoop();
    void ProcessPacket(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr);
    
    // Service detection
    ServiceDetection DetectService(const uint8_t* packet, UINT packetLen);
    
    // Optimized strategies for each service
    void ProcessRoblox(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr);
    void ProcessYouTube(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr);
    void ProcessDiscord(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr);
    
    // Core techniques (February 2026)
    bool ApplyFakeMultiSplit(const uint8_t* packet, UINT packetLen, 
                             WINDIVERT_ADDRESS* addr,
                             const std::vector<std::string>& domains,
                             uint16_t segmentSize, uint32_t delayMs,
                             uint8_t ttlFake, uint8_t ttlReal);
    
    bool ApplyTTLTrick(const uint8_t* packet, UINT packetLen,
                       WINDIVERT_ADDRESS* addr,
                       uint8_t ttlFake, uint8_t ttlReal, uint32_t delayMs);
    
    bool ApplyQUICDrop(const uint8_t* packet, UINT packetLen,
                       WINDIVERT_ADDRESS* addr);
    
    bool ApplyKeepAlive(const uint8_t* packet, UINT packetLen,
                        WINDIVERT_ADDRESS* addr);

    // Packet injection
    void InjectPacket(const uint8_t* packet, UINT packetLen, 
                      WINDIVERT_ADDRESS* addr, uint32_t delayMs = 0);
    void SendFakeClientHello(const std::string& fakeSni, 
                              const IPv4Header* origIp, const TCPHeader* origTcp,
                              uint32_t seqNum, uint8_t ttl, uint32_t delayMs);

    // Member variables
    ZapretConfig config_;
    HANDLE divertHandle_;
    std::thread captureThread_;
    std::atomic<bool> running_;
    uint32_t activeServices_;
    
    // Statistics
    mutable std::atomic<uint64_t> packetsProcessed_{0};
    mutable std::atomic<uint64_t> packetsModified_{0};
    mutable std::atomic<uint64_t> packetsDropped_{0};
    mutable std::atomic<uint64_t> robloxPackets_{0};
    mutable std::atomic<uint64_t> youtubePackets_{0};
    mutable std::atomic<uint64_t> discordPackets_{0};
    mutable std::atomic<uint64_t> errors_{0};
};

} // namespace Zapret

#endif // ZAPRET_ENGINE_H
