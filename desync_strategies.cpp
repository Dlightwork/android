#include "desync_strategies.h"
#include <thread>
#include <chrono>
#include <random>
#include <algorithm>

// Fix for std::min/max conflict with Windows.h
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

namespace dPIBypass {

DesyncEngine::DesyncEngine(const GlobalConfig& config) 
    : config_(config), fakeSniIndex_(0) {
}

DesyncEngine::~DesyncEngine() {
}

DesyncResult DesyncEngine::ProcessPacket(const uint8_t* packet, UINT packetLen,
                                          WINDIVERT_ADDRESS* addr,
                                          const ServiceProfile* profile) {
    if (!ShouldProcess(packet, packetLen, profile)) {
        DesyncResult result;
        PacketSegment original;
        original.data.assign(packet, packet + packetLen);
        original.delayMs = 0;
        original.isFake = false;
        result.segments.push_back(std::move(original));
        result.modified = false;
        result.drop = false;
        return result;
    }

    // Determine which strategy to use based on profile and packet type
    uint8_t ipHdrLen = IP_HDR_LEN(((IPv4Header*)packet)->VersionIHL);
    if (profile->use_quic && packetLen > ipHdrLen) {
        const uint8_t* payload = packet + ipHdrLen;
        uint16_t payloadLen = packetLen - ipHdrLen;
        if (IsQUICInitial(payload, payloadLen)) {
            if (config_.enable_quic_drop) {
                return ApplyQUICDrop(packet, packetLen, addr, profile);
            }
        }
    }

    // For TLS traffic, use the most effective strategy
    if (config_.enable_fakemultisplit && profile->use_desync) {
        return ApplyFakeMultiSplit(packet, packetLen, addr, profile);
    }
    
    if (config_.enable_fake_sni) {
        return ApplyFakeSNIInjection(packet, packetLen, addr, profile);
    }
    
    if (config_.enable_ttl_manipulation) {
        return ApplyTTLTrick(packet, packetLen, addr, profile);
    }

    // Default: pass through
    DesyncResult result;
    PacketSegment original;
    original.data.assign(packet, packet + packetLen);
    original.delayMs = 0;
    original.isFake = false;
    result.segments.push_back(std::move(original));
    result.modified = false;
    result.drop = false;
    return result;
}

DesyncResult DesyncEngine::ApplyFakeMultiSplit(const uint8_t* packet, UINT packetLen,
                                                WINDIVERT_ADDRESS* addr,
                                                const ServiceProfile* profile) {
    DesyncResult result;
    result.modified = true;
    result.drop = false;

    const IPv4Header* ipHdr = (const IPv4Header*)packet;
    uint8_t ipHdrLen = IP_HDR_LEN(ipHdr->VersionIHL);
    
    if (ipHdr->Protocol != IPPROTO_TCP) {
        PacketSegment original;
        original.data.assign(packet, packet + packetLen);
        result.segments.push_back(std::move(original));
        return result;
    }

    const TCPHeader* tcpHdr = (const TCPHeader*)(packet + ipHdrLen);
    uint8_t tcpHdrLen = TCP_HDR_LEN(tcpHdr->DataOffset);
    
    const uint8_t* payload = packet + ipHdrLen + tcpHdrLen;
    uint16_t payloadLen = ntohs(ipHdr->Length) - ipHdrLen - tcpHdrLen;

    if (!IsTLSClientHello(payload, payloadLen)) {
        PacketSegment original;
        original.data.assign(packet, packet + packetLen);
        result.segments.push_back(std::move(original));
        result.modified = false;
        return result;
    }

    uint32_t baseSeq = ntohl(tcpHdr->SeqNum);
    uint32_t ackNum = ntohl(tcpHdr->AckNum);
    uint16_t srcPort = ntohs(tcpHdr->SrcPort);
    uint16_t dstPort = ntohs(tcpHdr->DstPort);

    std::vector<PacketSegment> segments;

    // Create fake segments with different SNIs
    for (uint32_t i = 0; i < config_.fake_sni_count; i++) {
        std::string fakeSni = GetNextFakeSNI();
        std::vector<uint8_t> fakePayload = CreateFakeClientHello(fakeSni, baseSeq + i * 100);
        
        PacketSegment fakeSeg;
        fakeSeg.isFake = true;
        fakeSeg.ttl = profile->ttl_fake;
        fakeSeg.delayMs = i * 2;
        fakeSeg.seqNum = baseSeq + i * 100;
        fakeSeg.ackNum = ackNum;
        
        fakeSeg.data.resize(ipHdrLen + sizeof(TCPHeader) + fakePayload.size());
        
        IPv4Header* newIp = (IPv4Header*)fakeSeg.data.data();
        memcpy(newIp, ipHdr, ipHdrLen);
        newIp->Length = htons((u_short)(ipHdrLen + sizeof(TCPHeader) + fakePayload.size()));
        newIp->TTL = profile->ttl_fake;
        newIp->Id = htons((u_short)(ntohs(ipHdr->Id) + i + 1));
        newIp->Checksum = 0;
        newIp->Checksum = CalculateIPChecksum(newIp);
        
        TCPHeader* newTcp = (TCPHeader*)(fakeSeg.data.data() + ipHdrLen);
        newTcp->SrcPort = htons(srcPort);
        newTcp->DstPort = htons(dstPort);
        newTcp->SeqNum = htonl(fakeSeg.seqNum);
        newTcp->AckNum = htonl(ackNum);
        newTcp->DataOffset = (sizeof(TCPHeader) / 4) << 4;
        newTcp->Flags = 0x18;
        newTcp->Window = tcpHdr->Window;
        newTcp->Urgent = 0;
        newTcp->Checksum = 0;
        
        memcpy(fakeSeg.data.data() + ipHdrLen + sizeof(TCPHeader), 
               fakePayload.data(), fakePayload.size());
        
        newTcp->Checksum = CalculateTCPChecksum(newIp, newTcp, 
                                                fakePayload.data(), 
                                                (uint16_t)fakePayload.size());
        
        segments.push_back(std::move(fakeSeg));
    }

    // Split real ClientHello into small segments
    uint16_t segmentSize = profile->segment_size;
    uint16_t numSegments = (payloadLen + segmentSize - 1) / segmentSize;
    
    for (uint16_t i = 0; i < numSegments; i++) {
        uint16_t offset = i * segmentSize;
        uint16_t remaining = payloadLen - offset;
        uint16_t thisSegSize = (uint16_t)std::min((size_t)remaining, (size_t)segmentSize);
        
        PacketSegment realSeg;
        realSeg.isFake = false;
        realSeg.ttl = profile->ttl_real;
        realSeg.delayMs = profile->desync_delay_ms + (i * 5);
        realSeg.seqNum = baseSeq + offset + (config_.fake_sni_count * 100);
        realSeg.ackNum = ackNum;
        
        realSeg.data.resize(ipHdrLen + sizeof(TCPHeader) + thisSegSize);
        
        IPv4Header* newIp = (IPv4Header*)realSeg.data.data();
        memcpy(newIp, ipHdr, ipHdrLen);
        newIp->Length = htons((u_short)(ipHdrLen + sizeof(TCPHeader) + thisSegSize));
        newIp->TTL = profile->ttl_real;
        newIp->Id = htons((u_short)(ntohs(ipHdr->Id) + config_.fake_sni_count + i + 1));
        newIp->Checksum = 0;
        newIp->Checksum = CalculateIPChecksum(newIp);
        
        TCPHeader* newTcp = (TCPHeader*)(realSeg.data.data() + ipHdrLen);
        newTcp->SrcPort = htons(srcPort);
        newTcp->DstPort = htons(dstPort);
        newTcp->SeqNum = htonl(realSeg.seqNum);
        newTcp->AckNum = htonl(ackNum);
        newTcp->DataOffset = (sizeof(TCPHeader) / 4) << 4;
        newTcp->Flags = (i == numSegments - 1) ? 0x18 : 0x10;
        newTcp->Window = tcpHdr->Window;
        newTcp->Urgent = 0;
        newTcp->Checksum = 0;
        
        memcpy(realSeg.data.data() + ipHdrLen + sizeof(TCPHeader),
               payload + offset, thisSegSize);
        
        newTcp->Checksum = CalculateTCPChecksum(newIp, newTcp, payload + offset, thisSegSize);
        segments.push_back(std::move(realSeg));
    }

    result.segments = std::move(segments);
    return result;
}

DesyncResult DesyncEngine::ApplyFakeSNIInjection(const uint8_t* packet, UINT packetLen,
                                                  WINDIVERT_ADDRESS* addr,
                                                  const ServiceProfile* profile) {
    DesyncResult result;
    result.modified = true;
    result.drop = false;

    const IPv4Header* ipHdr = (const IPv4Header*)packet;
    uint8_t ipHdrLen = IP_HDR_LEN(ipHdr->VersionIHL);
    
    if (ipHdr->Protocol != IPPROTO_TCP) {
        PacketSegment original;
        original.data.assign(packet, packet + packetLen);
        result.segments.push_back(std::move(original));
        return result;
    }

    const TCPHeader* tcpHdr = (const TCPHeader*)(packet + ipHdrLen);
    uint8_t tcpHdrLen = TCP_HDR_LEN(tcpHdr->DataOffset);
    const uint8_t* payload = packet + ipHdrLen + tcpHdrLen;
    uint16_t payloadLen = ntohs(ipHdr->Length) - ipHdrLen - tcpHdrLen;

    if (!IsTLSClientHello(payload, payloadLen)) {
        PacketSegment original;
        original.data.assign(packet, packet + packetLen);
        result.segments.push_back(std::move(original));
        result.modified = false;
        return result;
    }

    uint32_t baseSeq = ntohl(tcpHdr->SeqNum);
    uint32_t ackNum = ntohl(tcpHdr->AckNum);
    uint16_t srcPort = ntohs(tcpHdr->SrcPort);
    uint16_t dstPort = ntohs(tcpHdr->DstPort);

    std::vector<PacketSegment> segments;

    // Fake SNI packet
    std::string fakeSni = GetNextFakeSNI();
    std::vector<uint8_t> fakePayload = CreateFakeClientHello(fakeSni, baseSeq);

    PacketSegment fakeSeg;
    fakeSeg.isFake = true;
    fakeSeg.ttl = profile->ttl_fake;
    fakeSeg.delayMs = 0;
    fakeSeg.seqNum = baseSeq;
    fakeSeg.ackNum = ackNum;
    fakeSeg.data.resize(ipHdrLen + tcpHdrLen + fakePayload.size());
    
    IPv4Header* fakeIp = (IPv4Header*)fakeSeg.data.data();
    memcpy(fakeIp, ipHdr, ipHdrLen);
    fakeIp->Length = htons((u_short)(ipHdrLen + tcpHdrLen + fakePayload.size()));
    fakeIp->TTL = profile->ttl_fake;
    fakeIp->Id = htons((u_short)(ntohs(ipHdr->Id) + 1));
    fakeIp->Checksum = 0;
    fakeIp->Checksum = CalculateIPChecksum(fakeIp);

    memcpy(fakeSeg.data.data() + ipHdrLen, tcpHdr, tcpHdrLen);
    TCPHeader* fakeTcp = (TCPHeader*)(fakeSeg.data.data() + ipHdrLen);
    fakeTcp->SeqNum = htonl(baseSeq);
    fakeTcp->Checksum = 0;
    memcpy(fakeSeg.data.data() + ipHdrLen + tcpHdrLen, fakePayload.data(), fakePayload.size());
    fakeTcp->Checksum = CalculateTCPChecksum(fakeIp, fakeTcp, fakePayload.data(), (uint16_t)fakePayload.size());
    segments.push_back(std::move(fakeSeg));

    // Real packet
    PacketSegment realSeg;
    realSeg.isFake = false;
    realSeg.ttl = profile->ttl_real;
    realSeg.delayMs = profile->desync_delay_ms;
    realSeg.seqNum = baseSeq + (uint32_t)fakePayload.size();
    realSeg.ackNum = ackNum;
    realSeg.data.resize(packetLen);
    memcpy(realSeg.data.data(), packet, packetLen);
    
    IPv4Header* realIp = (IPv4Header*)realSeg.data.data();
    realIp->Id = htons((u_short)(ntohs(realIp->Id) + 2));
    realIp->TTL = profile->ttl_real;
    realIp->Checksum = 0;
    realIp->Checksum = CalculateIPChecksum(realIp);

    TCPHeader* realTcp = (TCPHeader*)(realSeg.data.data() + ipHdrLen);
    realTcp->SeqNum = htonl(realSeg.seqNum);
    realTcp->Checksum = 0;
    realTcp->Checksum = CalculateTCPChecksum(realIp, realTcp, payload, payloadLen);
    segments.push_back(std::move(realSeg));

    result.segments = std::move(segments);
    return result;
}

DesyncResult DesyncEngine::ApplyTTLTrick(const uint8_t* packet, UINT packetLen,
                                          WINDIVERT_ADDRESS* addr,
                                          const ServiceProfile* profile) {
    DesyncResult result;
    result.modified = true;
    result.drop = false;

    std::vector<PacketSegment> segments;

    // Fake packet with low TTL
    PacketSegment fakeSeg;
    fakeSeg.isFake = true;
    fakeSeg.ttl = profile->ttl_fake;
    fakeSeg.delayMs = 0;
    fakeSeg.data.resize(packetLen);
    memcpy(fakeSeg.data.data(), packet, packetLen);
    
    IPv4Header* fakeIp = (IPv4Header*)fakeSeg.data.data();
    fakeIp->TTL = profile->ttl_fake;
    fakeIp->Id = htons((u_short)(ntohs(fakeIp->Id) + 1));
    fakeIp->Checksum = 0;
    fakeIp->Checksum = CalculateIPChecksum(fakeIp);
    
    if (fakeIp->Protocol == IPPROTO_TCP) {
        uint8_t ipHdrLen = IP_HDR_LEN(fakeIp->VersionIHL);
        TCPHeader* tcpHdr = (TCPHeader*)(fakeSeg.data.data() + ipHdrLen);
        uint8_t tcpHdrLen = TCP_HDR_LEN(tcpHdr->DataOffset);
        uint16_t plen = ntohs(fakeIp->Length) - ipHdrLen - tcpHdrLen;
        const uint8_t* payload = fakeSeg.data.data() + ipHdrLen + tcpHdrLen;
        tcpHdr->Checksum = 0;
        tcpHdr->Checksum = CalculateTCPChecksum(fakeIp, tcpHdr, payload, plen);
    }
    segments.push_back(std::move(fakeSeg));

    // Real packet with full TTL
    PacketSegment realSeg;
    realSeg.isFake = false;
    realSeg.ttl = profile->ttl_real;
    realSeg.delayMs = profile->desync_delay_ms;
    realSeg.data.resize(packetLen);
    memcpy(realSeg.data.data(), packet, packetLen);
    
    IPv4Header* realIp = (IPv4Header*)realSeg.data.data();
    realIp->TTL = profile->ttl_real;
    realIp->Id = htons((u_short)(ntohs(realIp->Id) + 2));
    realIp->Checksum = 0;
    realIp->Checksum = CalculateIPChecksum(realIp);

    if (realIp->Protocol == IPPROTO_TCP) {
        uint8_t ipHdrLen = IP_HDR_LEN(realIp->VersionIHL);
        TCPHeader* tcpHdr = (TCPHeader*)(realSeg.data.data() + ipHdrLen);
        uint8_t tcpHdrLen = TCP_HDR_LEN(tcpHdr->DataOffset);
        uint16_t plen = ntohs(realIp->Length) - ipHdrLen - tcpHdrLen;
        const uint8_t* payload = realSeg.data.data() + ipHdrLen + tcpHdrLen;
        tcpHdr->Checksum = 0;
        tcpHdr->Checksum = CalculateTCPChecksum(realIp, tcpHdr, payload, plen);
    }
    segments.push_back(std::move(realSeg));

    result.segments = std::move(segments);
    return result;
}

DesyncResult DesyncEngine::ApplySequenceDesync(const uint8_t* packet, UINT packetLen,
                                                WINDIVERT_ADDRESS* addr,
                                                const ServiceProfile* profile) {
    DesyncResult result;
    const IPv4Header* ipHdr = (const IPv4Header*)packet;
    
    if (ipHdr->Protocol != IPPROTO_TCP) {
        PacketSegment original;
        original.data.assign(packet, packet + packetLen);
        result.segments.push_back(std::move(original));
        result.modified = false;
        return result;
    }

    uint8_t ipHdrLen = IP_HDR_LEN(ipHdr->VersionIHL);
    const TCPHeader* tcpHdr = (const TCPHeader*)(packet + ipHdrLen);
    uint32_t baseSeq = ntohl(tcpHdr->SeqNum);
    uint16_t payloadLen = ntohs(ipHdr->Length) - ipHdrLen - TCP_HDR_LEN(tcpHdr->DataOffset);

    std::vector<PacketSegment> segments;
    
    PacketSegment seg1;
    seg1.data.assign(packet, packet + packetLen);
    seg1.seqNum = baseSeq;
    seg1.delayMs = 0;
    seg1.isFake = false;
    segments.push_back(std::move(seg1));
    
    PacketSegment seg2;
    seg2.data.assign(packet, packet + packetLen);
    seg2.seqNum = baseSeq + payloadLen + 1000;
    seg2.delayMs = profile->desync_delay_ms;
    seg2.isFake = false;
    segments.push_back(std::move(seg2));

    result.segments = std::move(segments);
    result.modified = true;
    return result;
}

DesyncResult DesyncEngine::ApplyQUICDrop(const uint8_t* packet, UINT packetLen,
                                          WINDIVERT_ADDRESS* addr,
                                          const ServiceProfile* profile) {
    DesyncResult result;
    const IPv4Header* ipHdr = (const IPv4Header*)packet;
    uint8_t ipHdrLen = IP_HDR_LEN(ipHdr->VersionIHL);
    const uint8_t* payload = packet + ipHdrLen;
    uint16_t payloadLen = ntohs(ipHdr->Length) - ipHdrLen;

    if (IsQUICInitial(payload, payloadLen)) {
        result.drop = true;
        result.modified = true;
        LogVerbose("QUIC Initial dropped, forcing TCP fallback");
    } else {
        PacketSegment original;
        original.data.assign(packet, packet + packetLen);
        result.segments.push_back(std::move(original));
        result.modified = false;
        result.drop = false;
    }
    return result;
}

DesyncResult DesyncEngine::ApplySplitHandshake(const uint8_t* packet, UINT packetLen,
                                                WINDIVERT_ADDRESS* addr,
                                                const ServiceProfile* profile) {
    DesyncResult result;
    PacketSegment original;
    original.data.assign(packet, packet + packetLen);
    result.segments.push_back(std::move(original));
    result.modified = false;
    return result;
}

std::vector<uint8_t> DesyncEngine::CreateFakeClientHello(const std::string& fakeSni, uint32_t seqNum) {
    std::vector<uint8_t> hello;
    
    // TLS Record Layer
    hello.push_back(0x16);
    hello.push_back(0x03);
    hello.push_back(0x01);
    
    size_t lengthPos = hello.size();
    hello.push_back(0x00);
    hello.push_back(0x00);
    
    // Handshake Header
    hello.push_back(0x01);
    
    size_t hsLengthPos = hello.size();
    hello.push_back(0x00);
    hello.push_back(0x00);
    hello.push_back(0x00);
    
    size_t hsStart = hello.size();
    
    // Client Version (TLS 1.2)
    hello.push_back(0x03);
    hello.push_back(0x03);
    
    // Random (32 bytes)
    for (int i = 0; i < 32; i++) {
        hello.push_back((uint8_t)(rand() & 0xFF));
    }
    
    // Session ID length
    hello.push_back(0x00);
    
    // Cipher suites
    hello.push_back(0x00);
    hello.push_back(0x02);
    hello.push_back(0xc0);
    hello.push_back(0x2f);
    
    // Compression methods
    hello.push_back(0x01);
    hello.push_back(0x00);
    
    // Extensions length
    size_t extLengthPos = hello.size();
    hello.push_back(0x00);
    hello.push_back(0x00);
    
    size_t extStart = hello.size();
    
    // SNI Extension
    hello.push_back(0x00);
    hello.push_back(0x00);
    
    uint16_t sniExtLen = 5 + (uint16_t)fakeSni.length();
    hello.push_back((uint8_t)((sniExtLen >> 8) & 0xFF));
    hello.push_back((uint8_t)(sniExtLen & 0xFF));
    
    uint16_t sniListLen = 3 + (uint16_t)fakeSni.length();
    hello.push_back((uint8_t)((sniListLen >> 8) & 0xFF));
    hello.push_back((uint8_t)(sniListLen & 0xFF));
    
    hello.push_back(0x00);
    
    hello.push_back((uint8_t)((fakeSni.length() >> 8) & 0xFF));
    hello.push_back((uint8_t)(fakeSni.length() & 0xFF));
    
    for (char c : fakeSni) {
        hello.push_back((uint8_t)c);
    }
    
    // Supported Groups Extension
    hello.push_back(0x00);
    hello.push_back(0x0a);
    hello.push_back(0x00);
    hello.push_back(0x04);
    hello.push_back(0x00);
    hello.push_back(0x02);
    hello.push_back(0x00);
    hello.push_back(0x17);
    
    // EC Point Formats
    hello.push_back(0x00);
    hello.push_back(0x0b);
    hello.push_back(0x00);
    hello.push_back(0x02);
    hello.push_back(0x01);
    hello.push_back(0x00);
    
    // Signature Algorithms
    hello.push_back(0x00);
    hello.push_back(0x0d);
    hello.push_back(0x00);
    hello.push_back(0x04);
    hello.push_back(0x00);
    hello.push_back(0x02);
    hello.push_back(0x04);
    hello.push_back(0x03);
    
    // Fill in lengths
    uint16_t extLen = (uint16_t)(hello.size() - extStart);
    hello[extLengthPos] = (uint8_t)((extLen >> 8) & 0xFF);
    hello[extLengthPos + 1] = (uint8_t)(extLen & 0xFF);
    
    uint32_t hsLen = (uint32_t)(hello.size() - hsStart);
    hello[hsLengthPos] = (uint8_t)((hsLen >> 16) & 0xFF);
    hello[hsLengthPos + 1] = (uint8_t)((hsLen >> 8) & 0xFF);
    hello[hsLengthPos + 2] = (uint8_t)(hsLen & 0xFF);
    
    uint16_t recordLen = (uint16_t)(hello.size() - 5);
    hello[lengthPos] = (uint8_t)((recordLen >> 8) & 0xFF);
    hello[lengthPos + 1] = (uint8_t)(recordLen & 0xFF);
    
    return hello;
}

std::vector<uint8_t> DesyncEngine::CreateSegmentedClientHello(const uint8_t* originalPayload,
                                                               uint16_t payloadLen,
                                                               const ServiceProfile* profile) {
    std::vector<uint8_t> result;
    result.assign(originalPayload, originalPayload + payloadLen);
    return result;
}

void DesyncEngine::InjectFakeSegments(HANDLE divertHandle,
                                       const std::vector<PacketSegment>& segments,
                                       WINDIVERT_ADDRESS* baseAddr) {
    for (const auto& seg : segments) {
        if (seg.delayMs > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(seg.delayMs));
        }
        
        UINT sendLen = 0;
        WinDivertSend(divertHandle, seg.data.data(), (UINT)seg.data.size(), &sendLen, baseAddr);
    }
}

bool DesyncEngine::ShouldProcess(const uint8_t* packet, UINT packetLen,
                                  const ServiceProfile* profile) {
    if (packetLen < sizeof(IPv4Header)) {
        return false;
    }

    const IPv4Header* ipHdr = (const IPv4Header*)packet;
    
    if (ipHdr->Protocol != IPPROTO_TCP && ipHdr->Protocol != IPPROTO_UDP) {
        return false;
    }

    uint8_t ipHdrLen = IP_HDR_LEN(ipHdr->VersionIHL);
    
    if (ipHdr->Protocol == IPPROTO_TCP) {
        if (packetLen < ipHdrLen + sizeof(TCPHeader)) {
            return false;
        }
        
        const TCPHeader* tcpHdr = (const TCPHeader*)(packet + ipHdrLen);
        uint8_t tcpHdrLen = TCP_HDR_LEN(tcpHdr->DataOffset);
        uint16_t payloadLen = ntohs(ipHdr->Length) - ipHdrLen - tcpHdrLen;
        
        if (payloadLen == 0) {
            return false;
        }
        
        const uint8_t* payload = packet + ipHdrLen + tcpHdrLen;
        
        if (IsTLSClientHello(payload, payloadLen)) {
            std::string sni = ExtractSNI(payload, payloadLen);
            if (!sni.empty() && IsTargetDomain(sni, profile->domains)) {
                return true;
            }
        }
    } else if (ipHdr->Protocol == IPPROTO_UDP && profile->use_quic) {
        if (packetLen > (UINT)ipHdrLen) {
            const uint8_t* payload = packet + ipHdrLen;
            uint16_t payloadLen = ntohs(ipHdr->Length) - ipHdrLen;
            if (IsQUICInitial(payload, payloadLen)) {
                return true;
            }
        }
    }

    return false;
}

std::string DesyncEngine::GetNextFakeSNI() {
    if (FAKE_SNIS.empty()) {
        return "google.com";
    }
    
    std::string sni = FAKE_SNIS[fakeSniIndex_ % FAKE_SNIS.size()];
    fakeSniIndex_++;
    return sni;
}

void DesyncEngine::UpdateSequenceNumbers(std::vector<PacketSegment>& segments,
                                          uint32_t baseSeq) {
    for (size_t i = 0; i < segments.size(); i++) {
        segments[i].seqNum = baseSeq + (uint32_t)(i * 100);
    }
}

uint16_t DesyncEngine::CalculateSegmentFlags(bool isFirst, bool isLast, bool hasPayload) {
    uint16_t flags = 0x10;
    if (hasPayload && isLast) {
        flags |= 0x08;
    }
    return flags;
}

} // namespace dPIBypass
