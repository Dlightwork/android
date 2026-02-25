#ifndef UTILS_H
#define UTILS_H

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <winsock2.h>
#include <windivert.h>

namespace dPIBypass {

// IP/TCP/UDP header structures with bit fields
#pragma pack(push, 1)

struct IPv4Header {
    uint8_t  VersionIHL;           // Version (4 bits) + IHL (4 bits)
    uint8_t  TOS;                    // Type of Service
    uint16_t Length;                 // Total Length
    uint16_t Id;                     // Identification
    uint16_t FragOff;                // Flags (3 bits) + Fragment Offset (13 bits)
    uint8_t  TTL;                    // Time To Live
    uint8_t  Protocol;               // Protocol
    uint16_t Checksum;               // Header Checksum
    uint32_t SrcAddr;                // Source Address
    uint32_t DstAddr;                // Destination Address
};

struct IPv6Header {
    uint32_t VersionTCFL;            // Version (4) + Traffic Class (8) + Flow Label (20)
    uint16_t Length;                 // Payload Length
    uint8_t  NextHdr;                // Next Header
    uint8_t  HopLimit;               // Hop Limit
    uint8_t  SrcAddr[16];            // Source Address
    uint8_t  DstAddr[16];            // Destination Address
};

struct TCPHeader {
    uint16_t SrcPort;                // Source Port
    uint16_t DstPort;                // Destination Port
    uint32_t SeqNum;                 // Sequence Number
    uint32_t AckNum;                 // Acknowledgment Number
    uint8_t  DataOffset;             // Data Offset (4 bits) + Reserved (4 bits)
    uint8_t  Flags;                  // Flags
    uint16_t Window;                 // Window Size
    uint16_t Checksum;               // Checksum
    uint16_t Urgent;                 // Urgent Pointer
};

struct UDPHeader {
    uint16_t SrcPort;                // Source Port
    uint16_t DstPort;                // Destination Port
    uint16_t Length;                 // Length
    uint16_t Checksum;               // Checksum
};

// TLS structures
struct TLSRecord {
    uint8_t  ContentType;            // Content Type (0x16 = handshake)
    uint16_t Version;                // Version
    uint16_t Length;                 // Length
};

struct TLSHandshake {
    uint8_t  MsgType;                // Handshake Type (0x01 = ClientHello)
    uint8_t  Length[3];              // Length (24 bits)
};

struct TLSServerName {
    uint16_t list_length;
    uint16_t type;                   // 0x00 = host_name
    uint16_t name_length;
    // Followed by name bytes
};

#pragma pack(pop)

// Helper macros
#define IP_VERSION(ver_ihl) (((ver_ihl) >> 4) & 0x0F)
#define IP_IHL(ver_ihl) ((ver_ihl) & 0x0F)
#define TCP_DATA_OFFSET(data_off) (((data_off) >> 4) & 0x0F)
#define TCP_FLAGS(data_off) ((data_off) & 0x0F)
#define IP_HDR_LEN(ver_ihl) (IP_IHL(ver_ihl) * 4)
#define TCP_HDR_LEN(data_off) (TCP_DATA_OFFSET(data_off) * 4)

// Utility functions
uint16_t CalculateChecksum(const uint16_t* data, size_t len);
uint16_t CalculateIPChecksum(const IPv4Header* ipHdr);
uint16_t CalculateTCPChecksum(const IPv4Header* ipHdr, const TCPHeader* tcpHdr, 
                                const uint8_t* payload, uint16_t payloadLen);
uint16_t CalculateUDPChecksum(const IPv4Header* ipHdr, const UDPHeader* udpHdr,
                                const uint8_t* payload, uint16_t payloadLen);

// Packet analysis
bool IsTLSClientHello(const uint8_t* payload, uint16_t payloadLen);
bool IsQUICInitial(const uint8_t* payload, uint16_t payloadLen);
std::string ExtractSNI(const uint8_t* payload, uint16_t payloadLen);
bool IsTargetDomain(const std::string& sni, const std::vector<std::string>& targets);

// Packet modification
void SetTTL(IPv4Header* ipHdr, uint8_t ttl);
void SetHopLimit(IPv6Header* ip6Hdr, uint8_t hopLimit);
void RecalculateTCPChecksum(PVOID packet, UINT packetLen, WINDIVERT_ADDRESS* addr);
void RecalculateUDPChecksum(PVOID packet, UINT packetLen, WINDIVERT_ADDRESS* addr);

// Memory helpers
void* DeepCopyPacket(const void* packet, UINT packetLen);
std::vector<uint8_t> CreateSegment(const uint8_t* data, uint16_t offset, uint16_t len);

// Logging
void LogVerbose(const std::string& msg);
void LogPacket(const std::string& prefix, const WINDIVERT_ADDRESS* addr, 
               const uint8_t* packet, UINT packetLen);
void HexDump(const uint8_t* data, size_t len);

} // namespace dPIBypass

#endif // UTILS_H
