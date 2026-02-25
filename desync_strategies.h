#ifndef DESYNC_STRATEGIES_H
#define DESYNC_STRATEGIES_H

#include <cstdint>
#include <vector>
#include <string>
#include <windivert.h>
#include "utils.h"
#include "config.h"

namespace dPIBypass {

// Desync strategy types
enum class DesyncStrategy {
    NONE,
    FAKEMULTISPLIT,      // Multiple small segments with fake SNI
    FAKESNI_INJECTION,   // Inject fake SNI before real
    TTL_TRICK,           // Different TTL for fake vs real
    SEQUENCE_DESYNC,     // Out-of-order sequence numbers
    QUIC_DROP,           // Drop QUIC forcing TCP fallback
    SPLIT_HANDSHAKE,     // SYN with fake payload
    HTTP2_FRAGMENT,      // HTTP/2 frame splitting
    COMBINED             // Multiple strategies combined
};

// Packet segment for splitting
struct PacketSegment {
    std::vector<uint8_t> data;
    uint32_t seqNum;
    uint32_t ackNum;
    uint16_t flags;
    uint8_t ttl;
    uint32_t delayMs;
    bool isFake;
};

// Result of desync processing
struct DesyncResult {
    std::vector<PacketSegment> segments;
    bool modified;
    bool drop;
};

class DesyncEngine {
public:
    DesyncEngine(const GlobalConfig& config);
    ~DesyncEngine();

    // Main processing entry point
    DesyncResult ProcessPacket(const uint8_t* packet, UINT packetLen,
                                WINDIVERT_ADDRESS* addr,
                                const ServiceProfile* profile);

    // Individual strategy implementations
    DesyncResult ApplyFakeMultiSplit(const uint8_t* packet, UINT packetLen,
                                       WINDIVERT_ADDRESS* addr,
                                       const ServiceProfile* profile);
    
    DesyncResult ApplyFakeSNIInjection(const uint8_t* packet, UINT packetLen,
                                         WINDIVERT_ADDRESS* addr,
                                         const ServiceProfile* profile);
    
    DesyncResult ApplyTTLTrick(const uint8_t* packet, UINT packetLen,
                                 WINDIVERT_ADDRESS* addr,
                                 const ServiceProfile* profile);
    
    DesyncResult ApplySequenceDesync(const uint8_t* packet, UINT packetLen,
                                     WINDIVERT_ADDRESS* addr,
                                     const ServiceProfile* profile);
    
    DesyncResult ApplyQUICDrop(const uint8_t* packet, UINT packetLen,
                               WINDIVERT_ADDRESS* addr,
                               const ServiceProfile* profile);
    
    DesyncResult ApplySplitHandshake(const uint8_t* packet, UINT packetLen,
                                     WINDIVERT_ADDRESS* addr,
                                     const ServiceProfile* profile);

    // Helper methods
    std::vector<uint8_t> CreateFakeClientHello(const std::string& fakeSni,
                                                 uint32_t seqNum);
    
    std::vector<uint8_t> CreateSegmentedClientHello(const uint8_t* originalPayload,
                                                      uint16_t payloadLen,
                                                      const ServiceProfile* profile);
    
    void InjectFakeSegments(HANDLE divertHandle,
                            const std::vector<PacketSegment>& segments,
                            WINDIVERT_ADDRESS* baseAddr);

    bool ShouldProcess(const uint8_t* packet, UINT packetLen,
                       const ServiceProfile* profile);

private:
    GlobalConfig config_;
    uint32_t fakeSniIndex_;
    
    // Internal helpers
    std::string GetNextFakeSNI();
    void UpdateSequenceNumbers(std::vector<PacketSegment>& segments,
                               uint32_t baseSeq);
    uint16_t CalculateSegmentFlags(bool isFirst, bool isLast, bool hasPayload);
};

} // namespace dPIBypass

#endif // DESYNC_STRATEGIES_H
