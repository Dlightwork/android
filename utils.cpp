#include "utils.h"
#include <iostream>
#include <iomanip>
#include <sstream>
#include <algorithm>

namespace dPIBypass {

uint16_t CalculateChecksum(const uint16_t* data, size_t len) {
    uint32_t sum = 0;
    
    while (len > 1) {
        sum += *data++;
        len -= 2;
    }
    
    if (len == 1) {
        sum += *(const uint8_t*)data;
    }
    
    while (sum >> 16) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    
    return (uint16_t)(~sum);
}

uint16_t CalculateIPChecksum(const IPv4Header* ipHdr) {
    size_t hdrLen = IP_HDR_LEN(ipHdr->VersionIHL);
    return CalculateChecksum((const uint16_t*)ipHdr, hdrLen);
}

uint16_t CalculateTCPChecksum(const IPv4Header* ipHdr, const TCPHeader* tcpHdr,
                                const uint8_t* payload, uint16_t payloadLen) {
    // Pseudo-header
    struct {
        uint32_t src;
        uint32_t dst;
        uint8_t  zero;
        uint8_t  proto;
        uint16_t tcpLen;
    } pseudoHdr;
    
    pseudoHdr.src = ipHdr->SrcAddr;
    pseudoHdr.dst = ipHdr->DstAddr;
    pseudoHdr.zero = 0;
    pseudoHdr.proto = IPPROTO_TCP;
    
    uint16_t tcpLen = TCP_HDR_LEN(tcpHdr->DataOffset) + payloadLen;
    pseudoHdr.tcpLen = htons(tcpLen);
    
    uint32_t sum = 0;
    
    // Add pseudo-header
    const uint16_t* p = (const uint16_t*)&pseudoHdr;
    for (int i = 0; i < sizeof(pseudoHdr) / 2; i++) {
        sum += *p++;
    }
    
    // Add TCP header (with checksum field zeroed)
    uint8_t tcpCopy[65535];
    memcpy(tcpCopy, tcpHdr, tcpLen);
    ((TCPHeader*)tcpCopy)->Checksum = 0;
    
    p = (const uint16_t*)tcpCopy;
    for (int i = 0; i < tcpLen / 2; i++) {
        sum += *p++;
    }
    if (tcpLen & 1) {
        sum += ((uint8_t*)tcpCopy)[tcpLen - 1] << 8;
    }
    
    while (sum >> 16) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    
    return (uint16_t)(~sum);
}

uint16_t CalculateUDPChecksum(const IPv4Header* ipHdr, const UDPHeader* udpHdr,
                                const uint8_t* payload, uint16_t payloadLen) {
    struct {
        uint32_t src;
        uint32_t dst;
        uint8_t  zero;
        uint8_t  proto;
        uint16_t udpLen;
    } pseudoHdr;
    
    pseudoHdr.src = ipHdr->SrcAddr;
    pseudoHdr.dst = ipHdr->DstAddr;
    pseudoHdr.zero = 0;
    pseudoHdr.proto = IPPROTO_UDP;
    pseudoHdr.udpLen = udpHdr->Length;
    
    uint32_t sum = 0;
    const uint16_t* p = (const uint16_t*)&pseudoHdr;
    for (int i = 0; i < sizeof(pseudoHdr) / 2; i++) {
        sum += *p++;
    }
    
    uint8_t udpCopy[65535];
    memcpy(udpCopy, udpHdr, sizeof(UDPHeader) + payloadLen);
    ((UDPHeader*)udpCopy)->Checksum = 0;
    
    uint16_t udpLen = ntohs(udpHdr->Length);
    p = (const uint16_t*)udpCopy;
    for (int i = 0; i < udpLen / 2; i++) {
        sum += *p++;
    }
    if (udpLen & 1) {
        sum += ((uint8_t*)udpCopy)[udpLen - 1] << 8;
    }
    
    while (sum >> 16) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    
    return (uint16_t)(~sum);
}

bool IsTLSClientHello(const uint8_t* payload, uint16_t payloadLen) {
    if (payloadLen < 5) return false;
    
    // Check TLS record layer
    if (payload[0] != 0x16) return false;  // Not handshake
    
    // Check handshake type (ClientHello = 0x01)
    if (payloadLen < 6) return false;
    if (payload[5] != 0x01) return false;
    
    return true;
}

bool IsQUICInitial(const uint8_t* payload, uint16_t payloadLen) {
    if (payloadLen < 5) return false;
    
    // Check for QUIC long header (1ST bit = 1)
    if ((payload[0] & 0x80) == 0) return false;
    
    // Check for Initial packet type (01)
    if ((payload[0] & 0x30) != 0x00) return false;
    
    // Check version (QUIC v1 = 0x00000001)
    if (payloadLen < 5) return false;
    uint32_t version = ntohl(*(uint32_t*)(payload + 1));
    if (version != 0x00000001 && version != 0x51303433) return false;  // v1 or draft-29
    
    return true;
}

std::string ExtractSNI(const uint8_t* payload, uint16_t payloadLen) {
    if (!IsTLSClientHello(payload, payloadLen)) {
        return "";
    }
    
    try {
        // Skip TLS record header (5 bytes) + handshake header (4 bytes)
        size_t pos = 9;
        
        // Skip client version (2 bytes) + random (32 bytes)
        pos += 34;
        
        if (pos + 1 > payloadLen) return "";
        
        // Skip session ID
        uint8_t sessionIdLen = payload[pos++];
        pos += sessionIdLen;
        
        if (pos + 2 > payloadLen) return "";
        
        // Skip cipher suites
        uint16_t cipherSuitesLen = ntohs(*(uint16_t*)(payload + pos));
        pos += 2 + cipherSuitesLen;
        
        if (pos + 1 > payloadLen) return "";
        
        // Skip compression methods
        uint8_t compMethodsLen = payload[pos++];
        pos += compMethodsLen;
        
        if (pos + 2 > payloadLen) return "";
        
        // Extensions length
        uint16_t extensionsLen = ntohs(*(uint16_t*)(payload + pos));
        pos += 2;
        
        size_t extensionsEnd = pos + extensionsLen;
        
        // Parse extensions
        while (pos + 4 <= extensionsEnd && pos + 4 <= payloadLen) {
            uint16_t extType = ntohs(*(uint16_t*)(payload + pos));
            uint16_t extLen = ntohs(*(uint16_t*)(payload + pos + 2));
            pos += 4;
            
            if (extType == 0x0000) {  // SNI extension
                if (pos + 2 > payloadLen) return "";
                
                uint16_t sniListLen = ntohs(*(uint16_t*)(payload + pos));
                pos += 2;
                
                if (pos + 3 > payloadLen) return "";
                
                uint8_t nameType = payload[pos++];
                if (nameType != 0x00) continue;  // Not hostname
                
                uint16_t nameLen = ntohs(*(uint16_t*)(payload + pos));
                pos += 2;
                
                if (pos + nameLen > payloadLen) return "";
                
                return std::string((const char*)(payload + pos), nameLen);
            }
            
            pos += extLen;
        }
    } catch (...) {
        return "";
    }
    
    return "";
}

bool IsTargetDomain(const std::string& sni, const std::vector<std::string>& targets) {
    std::string lowerSni = sni;
    std::transform(lowerSni.begin(), lowerSni.end(), lowerSni.begin(), ::tolower);
    
    for (const auto& target : targets) {
        std::string lowerTarget = target;
        std::transform(lowerTarget.begin(), lowerTarget.end(), lowerTarget.begin(), ::tolower);
        
        if (lowerSni.find(lowerTarget) != std::string::npos) {
            return true;
        }
    }
    return false;
}

void SetTTL(IPv4Header* ipHdr, uint8_t ttl) {
    ipHdr->TTL = ttl;
    ipHdr->Checksum = 0;
    ipHdr->Checksum = CalculateIPChecksum(ipHdr);
}

void SetHopLimit(IPv6Header* ip6Hdr, uint8_t hopLimit) {
    ip6Hdr->HopLimit = hopLimit;
}

void RecalculateTCPChecksum(PVOID packet, UINT packetLen, WINDIVERT_ADDRESS* addr) {
    // Implementation depends on packet structure
    // This is a placeholder for the full implementation
}

void RecalculateUDPChecksum(PVOID packet, UINT packetLen, WINDIVERT_ADDRESS* addr) {
    // Implementation depends on packet structure
}

void* DeepCopyPacket(const void* packet, UINT packetLen) {
    void* copy = malloc(packetLen);
    if (copy) {
        memcpy(copy, packet, packetLen);
    }
    return copy;
}

std::vector<uint8_t> CreateSegment(const uint8_t* data, uint16_t offset, uint16_t len) {
    std::vector<uint8_t> segment;
    segment.reserve(len);
    for (uint16_t i = 0; i < len && (offset + i) < 65535; i++) {
        segment.push_back(data[offset + i]);
    }
    return segment;
}

void LogVerbose(const std::string& msg) {
    std::cout << "[dPIBypass] " << msg << std::endl;
}

void LogPacket(const std::string& prefix, const WINDIVERT_ADDRESS* addr,
               const uint8_t* packet, UINT packetLen) {
    std::stringstream ss;
    ss << prefix << " ";
    
    if (addr->Layer == WINDIVERT_LAYER_NETWORK) {
        ss << "IPv4 ";
        const IPv4Header* ip = (const IPv4Header*)packet;
        ss << "TTL=" << (int)ip->TTL << " ";
    }
    
    ss << "Len=" << packetLen;
    LogVerbose(ss.str());
}

void HexDump(const uint8_t* data, size_t len) {
    std::stringstream ss;
    ss << "Hex dump (" << len << " bytes):\n";
    
    for (size_t i = 0; i < len; i += 16) {
        ss << std::hex << std::setw(4) << std::setfill('0') << i << "  ";
        
        for (size_t j = 0; j < 16 && (i + j) < len; j++) {
            ss << std::hex << std::setw(2) << std::setfill('0') << (int)data[i + j] << " ";
        }
        
        ss << " ";
        
        for (size_t j = 0; j < 16 && (i + j) < len; j++) {
            char c = data[i + j];
            ss << (isprint(c) ? c : '.');
        }
        
        ss << "\n";
    }
    
    LogVerbose(ss.str());
}

} // namespace dPIBypass
