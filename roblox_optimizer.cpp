#include "roblox_optimizer.h"
#include "utils.h"
#include <chrono>
#include <thread>
#include <algorithm>
#include <sstream>
#include <string>


namespace dPIBypass {

RobloxOptimizer::RobloxOptimizer(const GlobalConfig& config)
    : config_(config)
    , divertHandle_(INVALID_HANDLE_VALUE) {
}

RobloxOptimizer::~RobloxOptimizer() {
    if (divertHandle_ != INVALID_HANDLE_VALUE) {
        // Don't close here - owned by PacketEngine
    }
}

bool RobloxOptimizer::Initialize() {
    LogVerbose("RobloxOptimizer initialized");
    ParseRobloxEndpoints();
    return true;
}

bool RobloxOptimizer::ProcessPacket(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr) {
    if (!config_.enable_keepalive) {
        return false;
    }

    // Track this connection
    TrackConnection(packet, packetLen, addr);

    // Check if it's Roblox traffic
    const IPv4Header* ipHdr = (const IPv4Header*)packet;
    if (ipHdr->Protocol == IPPROTO_TCP) {
        uint8_t ipHdrLen = IP_HDR_LEN(ipHdr->VersionIHL);
        const TCPHeader* tcpHdr = (const TCPHeader*)(packet + ipHdrLen);
        
        uint32_t dstIp = ntohl(ipHdr->DstAddr);
        uint16_t dstPort = ntohs(tcpHdr->DstPort);
        
        if (IsRobloxConnection(dstIp, dstPort)) {
            OptimizeGameTraffic(packet, packetLen, addr);
            return true;
        }
    }

    return false;
}

void RobloxOptimizer::TrackConnection(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr) {
    const IPv4Header* ipHdr = (const IPv4Header*)packet;
    if (ipHdr->Protocol != IPPROTO_TCP) {
        return;
    }

    uint8_t ipHdrLen = IP_HDR_LEN(ipHdr->VersionIHL);
    const TCPHeader* tcpHdr = (const TCPHeader*)(packet + ipHdrLen);

    uint32_t srcIp = ntohl(ipHdr->SrcAddr);
    uint16_t srcPort = ntohs(tcpHdr->SrcPort);
    uint32_t dstIp = ntohl(ipHdr->DstAddr);
    uint16_t dstPort = ntohs(tcpHdr->DstPort);

    uint64_t key = GetConnectionKey(srcIp, srcPort);
    
    std::lock_guard<std::mutex> lock(connectionMutex_);
    
    auto it = connections_.find(key);
    if (it == connections_.end()) {
        // New connection
        RobloxConnection conn;
        conn.srcIp = srcIp;
        conn.srcPort = srcPort;
        conn.dstIp = dstIp;
        conn.dstPort = dstPort;
        conn.lastActivity = GetCurrentTimeMs();
        conn.isOptimized = false;
        conn.packetCount = 1;
        conn.bytesTransferred = packetLen;
        conn.handshakeComplete = false;
        
        connections_[key] = conn;
        activeConnections_++;
        
        if (config_.verbose_logging) {
            std::stringstream ss;
            ss << "New Roblox connection tracked: " 
               << ((srcIp >> 24) & 0xFF) << "." << ((srcIp >> 16) & 0xFF) << "."
               << ((srcIp >> 8) & 0xFF) << "." << (srcIp & 0xFF) << ":" << srcPort;
            LogVerbose(ss.str());
        }
    } else {
        // Update existing
        it->second.lastActivity = GetCurrentTimeMs();
        it->second.packetCount++;
        it->second.bytesTransferred += packetLen;
    }
}

void RobloxOptimizer::UpdateConnectionStats(uint32_t srcIp, uint16_t srcPort, uint32_t bytes) {
    uint64_t key = GetConnectionKey(srcIp, srcPort);
    
    std::lock_guard<std::mutex> lock(connectionMutex_);
    
    auto it = connections_.find(key);
    if (it != connections_.end()) {
        it->second.bytesTransferred += bytes;
        it->second.lastActivity = GetCurrentTimeMs();
        totalBytesOptimized_ += bytes;
    }
}

bool RobloxOptimizer::IsRobloxConnection(uint32_t dstIp, uint16_t dstPort) {
    // Check known Roblox ports
    if (dstPort == 53640 || dstPort == 53641 || dstPort == 53642) {
        return true;
    }
    
    // Check if port is in Roblox range
    if (dstPort >= 49152 && dstPort <= 65535) {
        // Could be Roblox, check further
        return true;
    }
    
    return false;
}

void RobloxOptimizer::OptimizeGameTraffic(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr) {
    // Apply game-specific optimizations
    ReduceLatency(packet, packetLen, addr);
    
    // Check for WebSocket upgrade
    const IPv4Header* ipHdr = (const IPv4Header*)packet;
    uint8_t ipHdrLen = IP_HDR_LEN(ipHdr->VersionIHL);
    const TCPHeader* tcpHdr = (const TCPHeader*)(packet + ipHdrLen);
    uint8_t tcpHdrLen = TCP_HDR_LEN(tcpHdr->DataOffset);
    
    const uint8_t* payload = packet + ipHdrLen + tcpHdrLen;
    uint16_t payloadLen = ntohs(ipHdr->Length) - ipHdrLen - tcpHdrLen;
    
    // Check for HTTP/WebSocket
    if (payloadLen > 10 && 
        (memcmp(payload, "GET ", 4) == 0 || 
         memcmp(payload, "POST ", 5) == 0 ||
         memcmp(payload, "HTTP/", 5) == 0)) {
        HandleWebSocket(payload, payloadLen, addr);
    }
}

void RobloxOptimizer::ReduceLatency(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr) {
    // Mark packet for priority handling
    // In a full implementation, this would set DSCP/ToS bits
    // For now, just track the optimization
}

void RobloxOptimizer::HandleWebSocket(const uint8_t* payload, UINT payloadLen, WINDIVERT_ADDRESS* addr) {
    // Check for WebSocket upgrade request/response
    if (payloadLen > 20) {
        std::string data((const char*)payload, (std::min)((size_t)100, (size_t)payloadLen));

        
        if (data.find("Upgrade: websocket") != std::string::npos ||
            data.find("Sec-WebSocket") != std::string::npos) {
            LogVerbose("WebSocket connection detected for Roblox");
        }
    }
}

void RobloxOptimizer::SendKeepAlive(uint32_t srcIp, uint16_t srcPort, 
                                     uint32_t dstIp, uint16_t dstPort) {
    // Build keep-alive packet (TCP ACK)
    std::vector<uint8_t> packet;
    packet.resize(sizeof(IPv4Header) + sizeof(TCPHeader));
    
    IPv4Header* ipHdr = (IPv4Header*)packet.data();
    TCPHeader* tcpHdr = (TCPHeader*)(packet.data() + sizeof(IPv4Header));
    
    // Fill IP header
    ipHdr->VersionIHL = 0x45;
    ipHdr->TOS = 0;
    ipHdr->Length = htons(packet.size());
    ipHdr->Id = htons(rand() & 0xFFFF);
    ipHdr->FragOff = 0;
    ipHdr->TTL = 64;
    ipHdr->Protocol = IPPROTO_TCP;
    ipHdr->Checksum = 0;
    ipHdr->SrcAddr = htonl(srcIp);
    ipHdr->DstAddr = htonl(dstIp);
    ipHdr->Checksum = CalculateIPChecksum(ipHdr);
    
    // Fill TCP header (ACK)
    tcpHdr->SrcPort = htons(srcPort);
    tcpHdr->DstPort = htons(dstPort);
    tcpHdr->SeqNum = htonl(rand());
    tcpHdr->AckNum = htonl(rand());
    tcpHdr->DataOffset = (sizeof(TCPHeader) / 4) << 4;
    tcpHdr->Flags = 0x10;  // ACK only
    tcpHdr->Window = htons(65535);
    tcpHdr->Urgent = 0;
    tcpHdr->Checksum = 0;
    tcpHdr->Checksum = CalculateTCPChecksum(ipHdr, tcpHdr, nullptr, 0);
    
    // Send via WinDivert would happen here
    // This is a placeholder for the actual implementation
}

void RobloxOptimizer::MaintainConnections() {
    uint64_t now = GetCurrentTimeMs();
    uint64_t timeout = 30000;  // 30 seconds
    
    std::lock_guard<std::mutex> lock(connectionMutex_);
    
    for (auto it = connections_.begin(); it != connections_.end();) {
        if (now - it->second.lastActivity > timeout) {
            // Connection timed out
            if (config_.verbose_logging) {
                std::stringstream ss;
                ss << "Roblox connection timed out: " << it->second.srcPort;
                LogVerbose(ss.str());
            }
            
            it = connections_.erase(it);
            activeConnections_--;
        } else {
            // Send keep-alive for active connections
            if (now - it->second.lastActivity > 10000 && config_.enable_keepalive) {
                SendKeepAlive(it->second.srcIp, it->second.srcPort,
                             it->second.dstIp, it->second.dstPort);
            }
            ++it;
        }
    }
}

uint32_t RobloxOptimizer::GetActiveConnections() const {
    return activeConnections_.load();
}

uint64_t RobloxOptimizer::GetTotalBytesOptimized() const {
    return totalBytesOptimized_.load();
}

uint64_t RobloxOptimizer::GetConnectionKey(uint32_t srcIp, uint16_t srcPort) const {
    return ((uint64_t)srcIp << 32) | srcPort;
}

uint64_t RobloxOptimizer::GetCurrentTimeMs() const {
    auto now = std::chrono::steady_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
}

bool RobloxOptimizer::IsRobloxDomain(const std::string& domain) const {
    std::string lowerDomain = domain;
    std::transform(lowerDomain.begin(), lowerDomain.end(), lowerDomain.begin(), ::tolower);
    
    for (const auto& robloxDomain : ROBLOX_PROFILE.domains) {
        if (lowerDomain.find(robloxDomain) != std::string::npos) {
            return true;
        }
    }
    return false;
}

void RobloxOptimizer::ParseRobloxEndpoints() {
    // Parse known Roblox game server endpoints
    // This would typically load from a configuration file
    
    gameServers_.push_back({"128.116.0.0", 53640, 50, true});
    gameServers_.push_back({"128.116.1.0", 53640, 60, true});
    gameServers_.push_back({"128.116.2.0", 53640, 55, true});
    
    LogVerbose("Roblox endpoints parsed");
}

} // namespace dPIBypass
