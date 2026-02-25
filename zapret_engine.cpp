#include "zapret_engine.h"
#include <iostream>
#include <sstream>
#include <chrono>
#include <thread>

namespace Zapret {

ZapretEngine::ZapretEngine(const ZapretConfig& config)
    : config_(config)
    , divertHandle_(INVALID_HANDLE_VALUE)
    , running_(false)
    , activeServices_(0xFFFFFFFF) {  // All services by default
}

ZapretEngine::~ZapretEngine() {
    Stop();
    if (divertHandle_ != INVALID_HANDLE_VALUE) {
        WinDivertClose(divertHandle_);
    }
}

bool ZapretEngine::Initialize() {
    std::cout << "[Zapret] Initializing DPI bypass engine (February 2026)..." << std::endl;
    
    // Build filter for all target services
    std::string filter = 
        "(tcp.DstPort == 443 or tcp.SrcPort == 443 or "
        "udp.DstPort == 443 or udp.SrcPort == 443 or "
        "udp.DstPort >= 5000 and udp.DstPort <= 65535) and "
        "outbound";
    
    divertHandle_ = WinDivertOpen(filter.c_str(), WINDIVERT_LAYER_NETWORK, 0, 0);
    if (divertHandle_ == INVALID_HANDLE_VALUE) {
        std::cerr << "[Zapret] ERROR: Failed to open WinDivert handle" << std::endl;
        return false;
    }
    
    // Set buffer sizes
    WinDivertSetParam(divertHandle_, WINDIVERT_PARAM_QUEUE_LENGTH, config_.queue_length);
    WinDivertSetParam(divertHandle_, WINDIVERT_PARAM_QUEUE_TIME, 1000);
    
    std::cout << "[Zapret] WinDivert initialized successfully" << std::endl;
    std::cout << "[Zapret] Active services: Roblox (low ping), YouTube (stable), Discord (voice)" << std::endl;
    
    return true;
}

void ZapretEngine::Start() {
    if (running_) return;
    running_ = true;
    captureThread_ = std::thread(&ZapretEngine::CaptureLoop, this);
    std::cout << "[Zapret] Engine started" << std::endl;
}

void ZapretEngine::Stop() {
    if (!running_) return;
    running_ = false;
    
    if (divertHandle_ != INVALID_HANDLE_VALUE) {
        WinDivertClose(divertHandle_);
        divertHandle_ = INVALID_HANDLE_VALUE;
    }
    
    if (captureThread_.joinable()) {
        captureThread_.join();
    }
    
    std::cout << "[Zapret] Engine stopped" << std::endl;
}

bool ZapretEngine::IsRunning() const {
    return running_;
}

void ZapretEngine::SetActiveServices(uint32_t serviceMask) {
    activeServices_ = serviceMask;
}

void ZapretEngine::CaptureLoop() {
    const int MAX_PACKET = 65535;
    std::vector<uint8_t> buffer(MAX_PACKET);
    
    while (running_) {
        UINT recvLen = 0;
        WINDIVERT_ADDRESS addr;
        
        if (!WinDivertRecv(divertHandle_, buffer.data(), MAX_PACKET, &recvLen, &addr)) {
            if (!running_) break;
            errors_++;
            continue;
        }
        
        packetsProcessed_++;
        ProcessPacket(buffer.data(), recvLen, &addr);
    }
}

void ZapretEngine::ProcessPacket(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr) {
    auto detection = DetectService(packet, packetLen);
    
    if (!detection.isTarget) {
        // Not target traffic, reinject unchanged
        WinDivertSend(divertHandle_, packet, packetLen, nullptr, addr);
        return;
    }
    
    switch (detection.type) {
        case ServiceType::ROBLOX:
            if (activeServices_ & 0x01) {
                robloxPackets_++;
                ProcessRoblox(packet, packetLen, addr);
            }
            break;
        case ServiceType::YOUTUBE:
            if (activeServices_ & 0x02) {
                youtubePackets_++;
                ProcessYouTube(packet, packetLen, addr);
            }
            break;
        case ServiceType::DISCORD:
            if (activeServices_ & 0x04) {
                discordPackets_++;
                ProcessDiscord(packet, packetLen, addr);
            }
            break;
        default:
            WinDivertSend(divertHandle_, packet, packetLen, nullptr, addr);
            break;
    }
}

ServiceDetection ZapretEngine::DetectService(const uint8_t* packet, UINT packetLen) {
    ServiceDetection result = {ServiceType::UNKNOWN, false, false, false, false};
    
    if (packetLen < sizeof(IPv4Header)) return result;
    
    const IPv4Header* ip = (const IPv4Header*)packet;
    uint8_t ipLen = IP_HDR_LEN(ip->VersionIHL);
    
    if (ip->Protocol == IPPROTO_TCP && packetLen > ipLen + sizeof(TCPHeader)) {
        const TCPHeader* tcp = (const TCPHeader*)(packet + ipLen);
        uint8_t tcpLen = TCP_HDR_LEN(tcp->DataOffset);
        uint16_t payloadLen = ntohs(ip->Length) - ipLen - tcpLen;
        
        if (payloadLen > 0 && IsTLSClientHello(packet + ipLen + tcpLen, payloadLen)) {
            std::string sni = ExtractSNI(packet + ipLen + tcpLen, payloadLen);
            
            // Check Roblox
            for (const auto& domain : RobloxProfile::domains) {
                if (sni.find(domain) != std::string::npos) {
                    result.type = ServiceType::ROBLOX;
                    result.isTarget = true;
                    result.needsLowLatency = true;
                    return result;
                }
            }
            
            // Check YouTube
            for (const auto& domain : YouTubeProfile::domains) {
                if (sni.find(domain) != std::string::npos) {
                    result.type = ServiceType::YOUTUBE;
                    result.isTarget = true;
                    result.needsStableStream = true;
                    return result;
                }
            }
            
            // Check Discord
            for (const auto& domain : DiscordProfile::domains) {
                if (sni.find(domain) != std::string::npos) {
                    result.type = ServiceType::DISCORD;
                    result.isTarget = true;
                    result.needsVoiceOptimization = true;
                    return result;
                }
            }
        }
    }
    
    return result;
}

void ZapretEngine::ProcessRoblox(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr) {
    // Roblox: minimal delay, small segments, keepalive enabled
    // Goal: 20-50ms ping, prevent Error 279
    
    bool modified = ApplyFakeMultiSplit(
        packet, packetLen, addr,
        RobloxProfile::domains,
        RobloxProfile::segment_size,      // 4 bytes - very small
        RobloxProfile::desync_delay_ms,   // 5ms - minimal
        RobloxProfile::ttl_fake,          // 2
        RobloxProfile::ttl_real           // 64
    );
    
    if (modified) {
        packetsModified_++;
    }
}

void ZapretEngine::ProcessYouTube(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr) {
    // YouTube: allow QUIC for speed, but desync TLS
    // Goal: stable streaming, no buffering
    
    const IPv4Header* ip = (const IPv4Header*)packet;
    uint8_t ipLen = IP_HDR_LEN(ip->VersionIHL);
    
    // Check if QUIC
    if (ip->Protocol == IPPROTO_UDP && config_.enable_quic_drop) {
        uint16_t payloadLen = ntohs(ip->Length) - ipLen;
        if (IsQUICInitial(packet + ipLen, payloadLen)) {
            // Drop QUIC to force TCP (more stable for bypass)
            packetsDropped_++;
            return;  // Don't reinject
        }
    }
    
    bool modified = ApplyFakeMultiSplit(
        packet, packetLen, addr,
        YouTubeProfile::domains,
        YouTubeProfile::segment_size,      // 8 bytes
        YouTubeProfile::desync_delay_ms,   // 10ms
        YouTubeProfile::ttl_fake,          // 3
        YouTubeProfile::ttl_real           // 64
    );
    
    if (modified) {
        packetsModified_++;
    }
}

void ZapretEngine::ProcessDiscord(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr) {
    // Discord: preserve UDP for voice, desync TCP for chat
    // Goal: stable voice, working chat
    
    const IPv4Header* ip = (const IPv4Header*)packet;
    
    // Preserve UDP traffic (voice)
    if (ip->Protocol == IPPROTO_UDP) {
        // Reinject UDP unchanged for voice
        WinDivertSend(divertHandle_, packet, packetLen, nullptr, addr);
        return;
    }
    
    // Desync TCP (chat/API)
    bool modified = ApplyFakeMultiSplit(
        packet, packetLen, addr,
        DiscordProfile::domains,
        DiscordProfile::segment_size,      // 6 bytes
        DiscordProfile::desync_delay_ms,   // 8ms
        DiscordProfile::ttl_fake,          // 2
        DiscordProfile::ttl_real           // 128
    );
    
    if (modified) {
        packetsModified_++;
    }
}

bool ZapretEngine::ApplyFakeMultiSplit(const uint8_t* packet, UINT packetLen,
                                        WINDIVERT_ADDRESS* addr,
                                        const std::vector<std::string>& domains,
                                        uint16_t segmentSize, uint32_t delayMs,
                                        uint8_t ttlFake, uint8_t ttlReal) {
    const IPv4Header* ip = (const IPv4Header*)packet;
    uint8_t ipLen = IP_HDR_LEN(ip->VersionIHL);
    
    if (ip->Protocol != IPPROTO_TCP) {
        WinDivertSend(divertHandle_, packet, packetLen, nullptr, addr);
        return false;
    }
    
    const TCPHeader* tcp = (const TCPHeader*)(packet + ipLen);
    uint8_t tcpLen = TCP_HDR_LEN(tcp->DataOffset);
    uint16_t payloadLen = ntohs(ip->Length) - ipLen - tcpLen;
    
    if (!IsTLSClientHello(packet + ipLen + tcpLen, payloadLen)) {
        WinDivertSend(divertHandle_, packet, packetLen, nullptr, addr);
        return false;
    }
    
    uint32_t baseSeq = ntohl(tcp->SeqNum);
    uint32_t ackNum = ntohl(tcp->AckNum);
    uint16_t srcPort = ntohs(tcp->SrcPort);
    uint16_t dstPort = ntohs(tcp->DstPort);
    
    // Send fake SNI packets
    for (uint32_t i = 0; i < config_.fake_sni_count; i++) {
        std::string fakeSni = FAKE_SNIS_2026[i % FAKE_SNIS_2026.size()];
        SendFakeClientHello(fakeSni, ip, tcp, baseSeq + i * 50, ttlFake, i * 2);
    }
    
    // Split real ClientHello into segments
    uint16_t numSegs = (payloadLen + segmentSize - 1) / segmentSize;
    
    for (uint16_t i = 0; i < numSegs; i++) {
        uint16_t offset = i * segmentSize;
        uint16_t thisSize = std::min((uint16_t)(payloadLen - offset), segmentSize);
        
        // Build segment
        std::vector<uint8_t> segData(ipLen + sizeof(TCPHeader) + thisSize);
        
        IPv4Header* newIp = (IPv4Header*)segData.data();
        memcpy(newIp, ip, ipLen);
        newIp->Length = htons((u_short)(ipLen + sizeof(TCPHeader) + thisSize));
        newIp->TTL = ttlReal;
        newIp->Id = htons((u_short)(ntohs(ip->Id) + config_.fake_sni_count + i + 1));
        newIp->Checksum = 0;
        newIp->Checksum = CalculateIPChecksum(newIp);
        
        TCPHeader* newTcp = (TCPHeader*)(segData.data() + ipLen);
        newTcp->SrcPort = htons(srcPort);
        newTcp->DstPort = htons(dstPort);
        newTcp->SeqNum = htonl(baseSeq + offset + config_.fake_sni_count * 50);
        newTcp->AckNum = htonl(ackNum);
        newTcp->DataOffset = (sizeof(TCPHeader) / 4) << 4;
        newTcp->Flags = (i == numSegs - 1) ? 0x18 : 0x10;
        newTcp->Window = tcp->Window;
        newTcp->Urgent = 0;
        newTcp->Checksum = 0;
        
        memcpy(segData.data() + ipLen + sizeof(TCPHeader),
               packet + ipLen + tcpLen + offset, thisSize);
        
        newTcp->Checksum = CalculateTCPChecksum(newIp, newTcp,
                                                 packet + ipLen + tcpLen + offset,
                                                 thisSize);
        
        // Send with delay
        InjectPacket(segData.data(), (UINT)segData.size(), addr, 
                     delayMs + (i * 3));
    }
    
    return true;
}

void ZapretEngine::SendFakeClientHello(const std::string& fakeSni,
                                        const IPv4Header* origIp,
                                        const TCPHeader* origTcp,
                                        uint32_t seqNum, uint8_t ttl,
                                        uint32_t delayMs) {
    // Build minimal fake ClientHello
    std::vector<uint8_t> fakePayload;
    
    // TLS Record
    fakePayload.push_back(0x16);
    fakePayload.push_back(0x03);
    fakePayload.push_back(0x01);
    size_t lenPos = fakePayload.size();
    fakePayload.push_back(0x00);
    fakePayload.push_back(0x00);
    
    // Handshake
    fakePayload.push_back(0x01);
    size_t hsLenPos = fakePayload.size();
    fakePayload.push_back(0x00);
    fakePayload.push_back(0x00);
    fakePayload.push_back(0x00);
    size_t hsStart = fakePayload.size();
    
    // Version
    fakePayload.push_back(0x03);
    fakePayload.push_back(0x03);
    
    // Random (32 bytes)
    for (int i = 0; i < 32; i++) fakePayload.push_back(rand() & 0xFF);
    
    // Session ID
    fakePayload.push_back(0x00);
    
    // Cipher suites
    fakePayload.push_back(0x00);
    fakePayload.push_back(0x02);
    fakePayload.push_back(0xc0);
    fakePayload.push_back(0x2f);
    
    // Compression
    fakePayload.push_back(0x01);
    fakePayload.push_back(0x00);
    
    // Extensions
    size_t extLenPos = fakePayload.size();
    fakePayload.push_back(0x00);
    fakePayload.push_back(0x00);
    size_t extStart = fakePayload.size();
    
    // SNI
    fakePayload.push_back(0x00);
    fakePayload.push_back(0x00);
    uint16_t sniExtLen = 5 + (uint16_t)fakeSni.length();
    fakePayload.push_back((uint8_t)(sniExtLen >> 8));
    fakePayload.push_back((uint8_t)(sniExtLen & 0xFF));
    uint16_t sniListLen = 3 + (uint16_t)fakeSni.length();
    fakePayload.push_back((uint8_t)(sniListLen >> 8));
    fakePayload.push_back((uint8_t)(sniListLen & 0xFF));
    fakePayload.push_back(0x00);
    fakePayload.push_back((uint8_t)(fakeSni.length() >> 8));
    fakePayload.push_back((uint8_t)(fakeSni.length() & 0xFF));
    for (char c : fakeSni) fakePayload.push_back((uint8_t)c);
    
    // Fill lengths
    uint16_t extLen = (uint16_t)(fakePayload.size() - extStart);
    fakePayload[extLenPos] = (uint8_t)(extLen >> 8);
    fakePayload[extLenPos + 1] = (uint8_t)(extLen & 0xFF);
    
    uint32_t hsLen = (uint32_t)(fakePayload.size() - hsStart);
    fakePayload[hsLenPos] = (uint8_t)((hsLen >> 16) & 0xFF);
    fakePayload[hsLenPos + 1] = (uint8_t)((hsLen >> 8) & 0xFF);
    fakePayload[hsLenPos + 2] = (uint8_t)(hsLen & 0xFF);
    
    uint16_t recordLen = (uint16_t)(fakePayload.size() - 5);
    fakePayload[lenPos] = (uint8_t)(recordLen >> 8);
    fakePayload[lenPos + 1] = (uint8_t)(recordLen & 0xFF);
    
    // Build IP/TCP packet
    uint8_t ipLen = IP_HDR_LEN(origIp->VersionIHL);
    std::vector<uint8_t> packet(ipLen + sizeof(TCPHeader) + fakePayload.size());
    
    IPv4Header* newIp = (IPv4Header*)packet.data();
    memcpy(newIp, origIp, ipLen);
    newIp->Length = htons((u_short)(ipLen + sizeof(TCPHeader) + fakePayload.size()));
    newIp->TTL = ttl;
    newIp->Id = htons((u_short)(ntohs(origIp->Id) + 1));
    newIp->Checksum = 0;
    newIp->Checksum = CalculateIPChecksum(newIp);
    
    TCPHeader* newTcp = (TCPHeader*)(packet.data() + ipLen);
    newTcp->SrcPort = origTcp->SrcPort;
    newTcp->DstPort = origTcp->DstPort;
    newTcp->SeqNum = htonl(seqNum);
    newTcp->AckNum = origTcp->AckNum;
    newTcp->DataOffset = (sizeof(TCPHeader) / 4) << 4;
    newTcp->Flags = 0x18;
    newTcp->Window = origTcp->Window;
    newTcp->Urgent = 0;
    newTcp->Checksum = 0;
    
    memcpy(packet.data() + ipLen + sizeof(TCPHeader), fakePayload.data(), fakePayload.size());
    
    newTcp->Checksum = CalculateTCPChecksum(newIp, newTcp, fakePayload.data(), 
                                              (uint16_t)fakePayload.size());
    
    // Send
    WINDIVERT_ADDRESS addr = {};
    addr.Outbound = 1;
    
    if (delayMs > 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(delayMs));
    }
    
    WinDivertSend(divertHandle_, packet.data(), (UINT)packet.size(), nullptr, &addr);
}

void ZapretEngine::InjectPacket(const uint8_t* packet, UINT packetLen,
                                 WINDIVERT_ADDRESS* addr, uint32_t delayMs) {
    if (delayMs > 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(delayMs));
    }
    
    WINDIVERT_ADDRESS sendAddr = *addr;
    sendAddr.Outbound = 1;
    WinDivertSend(divertHandle_, packet, packetLen, nullptr, &sendAddr);
}

void ZapretEngine::PrintStats() const {
    std::cout << "\n========== Zapret Statistics ==========\n";
    std::cout << "Packets processed: " << packetsProcessed_.load() << "\n";
    std::cout << "Packets modified:  " << packetsModified_.load() << "\n";
    std::cout << "Packets dropped:   " << packetsDropped_.load() << "\n";
    std::cout << "Roblox traffic:    " << robloxPackets_.load() << "\n";
    std::cout << "YouTube traffic:   " << youtubePackets_.load() << "\n";
    std::cout << "Discord traffic:   " << discordPackets_.load() << "\n";
    std::cout << "Errors:            " << errors_.load() << "\n";
    std::cout << "=======================================\n";
}

} // namespace Zapret
