#include "packet_engine.h"
#include "utils.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <chrono>
#include <fstream>
#include <winsock2.h>
#include <ws2tcpip.h>

namespace dPIBypass {

// Helper: parse CIDR string into network and mask (host order).
// Returns true on success.
static bool ParseCIDRString(const std::string& cidr, uint32_t& network, uint32_t& mask) {
    size_t slashPos = cidr.find('/');
    std::string ipPart = cidr;
    int prefixLen = 32;
    if (slashPos != std::string::npos) {
        ipPart = cidr.substr(0, slashPos);
        std::string prefixStr = cidr.substr(slashPos + 1);
        try {
            prefixLen = std::stoi(prefixStr);
        } catch (...) {
            return false;
        }
        if (prefixLen < 0 || prefixLen > 32) return false;
    }
    int a, b, c, d;
    if (sscanf(ipPart.c_str(), "%d.%d.%d.%d", &a, &b, &c, &d) != 4) {
        return false;
    }
    if (a < 0 || a > 255 || b < 0 || b > 255 || c < 0 || c > 255 || d < 0 || d > 255) {
        return false;
    }
    uint32_t addr = ((uint32_t)a << 24) | ((uint32_t)b << 16) | ((uint32_t)c << 8) | (uint32_t)d;
    uint32_t m = (prefixLen == 0) ? 0 : (0xFFFFFFFFu << (32 - prefixLen));
    network = addr & m;
    mask = m;
    return true;
}

// Check if given IPv4 host-order address belongs to any CIDR in profile
static bool IsIpInProfile(uint32_t ipHostOrder, const ServiceProfile* profile) {
    if (!profile) return false;
    for (const auto& cidr : profile->ip_ranges) {
        uint32_t net, mask;
        if (ParseCIDRString(cidr, net, mask)) {
            if ((ipHostOrder & mask) == net) {
                return true;
            }
        }
    }
    return false;
}

PacketEngine::PacketEngine(const GlobalConfig& config)
    : config_(config)
    , currentProfile_(nullptr)
    , desyncEngine_(nullptr)
    , divertHandle_(INVALID_HANDLE_VALUE)
    , running_(false)
    , verboseLogging_(config.verbose_logging)
    , packetLogging_(false) {
}

PacketEngine::~PacketEngine() {
    Stop();
    Cleanup();
}

bool PacketEngine::Initialize() {
    LogVerbose("Initializing PacketEngine...");
    
    // Create desync engine
    desyncEngine_ = new DesyncEngine(config_);
    if (!desyncEngine_) {
        LogVerbose("ERROR: Failed to create DesyncEngine");
        return false;
    }

    // Initialize WinDivert
    if (!InitializeWinDivert()) {
        LogVerbose("ERROR: Failed to initialize WinDivert");
        return false;
    }

    LogVerbose("PacketEngine initialized successfully");
    return true;
}

bool PacketEngine::InitializeWinDivert() {
    // Build filter string for target traffic
    std::string filter = BuildFilterString();
    
    LogVerbose("WinDivert filter: " + filter);

    // Open WinDivert handle
    divertHandle_ = WinDivertOpen(
        filter.c_str(),
        WINDIVERT_LAYER_NETWORK,
        config_.divert_priority,
        WINDIVERT_FLAG_SNIFF  // Sniff mode - copy packets, don't block
    );

    if (divertHandle_ == INVALID_HANDLE_VALUE) {
        DWORD error = GetLastError();
        std::stringstream ss;
        ss << "WinDivertOpen failed with error: " << error;
        LogVerbose(ss.str());
        return false;
    }

    // Set packet queue length
    if (!WinDivertSetParam(divertHandle_, WINDIVERT_PARAM_QUEUE_LENGTH, config_.max_pending_packets)) {
        LogVerbose("Warning: Failed to set queue length");
    }


    if (!WinDivertSetParam(divertHandle_, WINDIVERT_PARAM_QUEUE_TIME, 1000)) {
        LogVerbose("Warning: Failed to set queue time");
    }

    return true;
}

std::string PacketEngine::BuildFilterString() const {
    // Build the WinDivert filter string.  Start with common HTTP/HTTPS ports,
    // then append any additional ports loaded from configuration files.
    std::stringstream filter;

    // Base ports: capture outbound traffic to/from standard HTTPS and HTTP ports.
    filter << "(tcp.DstPort == 443 or tcp.SrcPort == 443)";
    filter << " or (tcp.DstPort == 80 or tcp.SrcPort == 80)";

    // Also capture UDP on 443 and 80 (QUIC and DNS‑over‑HTTPS) by default.
    filter << " or (udp.DstPort == 443 or udp.SrcPort == 443)";
    filter << " or (udp.DstPort == 80 or udp.SrcPort == 80)";

    // Roblox game port (TCP 53640).  Leave this hard‑coded because many
    // community servers rely on it and it is unlikely to change.
    filter << " or (tcp.DstPort == 53640 or tcp.SrcPort == 53640)";

    // Load extra port ranges from configuration files.  These allow the tool
    // to intercept additional ports used by voice/video services (e.g., Discord,
    // Teams, Skype, Zoom) or other custom services.  Users can edit
    // lists/extra_ports_tcp.txt and lists/extra_ports_udp.txt to add or remove
    // port numbers or ranges (e.g., 6457‑6463).  Lines starting with '#' are
    // ignored.  A single number represents an individual port; a dash
    // separates a start and end port for a range.
    auto loadPortRanges = [](const std::string& filePath) -> std::vector<std::pair<int,int>> {
        std::vector<std::pair<int,int>> ranges;
        std::ifstream file(filePath);
        if (!file.is_open()) {
            return ranges;
        }
        std::string line;
        while (std::getline(file, line)) {
            // Trim whitespace
            line.erase(0, line.find_first_not_of(" \t\r\n"));
            line.erase(line.find_last_not_of(" \t\r\n") + 1);
            if (line.empty() || line[0] == '#') continue;
            // Check for range specified with '-'
            size_t dashPos = line.find('-');
            if (dashPos != std::string::npos) {
                std::string startStr = line.substr(0, dashPos);
                std::string endStr = line.substr(dashPos + 1);
                try {
                    int startPort = std::stoi(startStr);
                    int endPort = std::stoi(endStr);
                    if (startPort > 0 && endPort > 0 && startPort <= 65535 && endPort <= 65535) {
                        if (startPort > endPort) std::swap(startPort, endPort);
                        ranges.emplace_back(startPort, endPort);
                    }
                } catch (...) {
                    // ignore invalid lines
                }
            } else {
                try {
                    int port = std::stoi(line);
                    if (port > 0 && port <= 65535) {
                        ranges.emplace_back(port, port);
                    }
                } catch (...) {
                    // ignore invalid lines
                }
            }
        }
        return ranges;
    };

    // Load TCP and UDP extra port ranges.  Use both lists from the lists/ directory
    // and fallback to current working directory if not found.
    std::vector<std::pair<int,int>> extraTcp;
    {
        // Search in lists/extra_ports_tcp.txt first
        auto ports = loadPortRanges("lists/extra_ports_tcp.txt");
        if (!ports.empty()) extraTcp = ports;
        else {
            ports = loadPortRanges("extra_ports_tcp.txt");
            if (!ports.empty()) extraTcp = ports;
        }
    }
    std::vector<std::pair<int,int>> extraUdp;
    {
        auto ports = loadPortRanges("lists/extra_ports_udp.txt");
        if (!ports.empty()) extraUdp = ports;
        else {
            ports = loadPortRanges("extra_ports_udp.txt");
            if (!ports.empty()) extraUdp = ports;
        }
    }

    // Append extra TCP port rules
    for (const auto& pr : extraTcp) {
        int startPort = pr.first;
        int endPort = pr.second;
        if (startPort == endPort) {
            filter << " or (tcp.DstPort == " << startPort << " or tcp.SrcPort == " << startPort << ")";
        } else {
            filter << " or ((tcp.DstPort >= " << startPort << " and tcp.DstPort <= " << endPort
                   << ") or (tcp.SrcPort >= " << startPort << " and tcp.SrcPort <= " << endPort << "))";
        }
    }
    // Append extra UDP port rules
    for (const auto& pr : extraUdp) {
        int startPort = pr.first;
        int endPort = pr.second;
        if (startPort == endPort) {
            filter << " or (udp.DstPort == " << startPort << " or udp.SrcPort == " << startPort << ")";
        } else {
            filter << " or ((udp.DstPort >= " << startPort << " and udp.DstPort <= " << endPort
                   << ") or (udp.SrcPort >= " << startPort << " and udp.SrcPort <= " << endPort << "))";
        }
    }

    // Finally, restrict to outbound traffic from the local machine.
    filter << " and outbound";

    return filter.str();
}

void PacketEngine::Start() {
    if (running_) {
        LogVerbose("PacketEngine already running");
        return;
    }

    running_ = true;
    captureThread_ = std::thread(&PacketEngine::CaptureLoop, this);
    
    LogVerbose("PacketEngine started");
}

void PacketEngine::Stop() {
    if (!running_) {
        return;
    }

    running_ = false;
    
    // Close handle to unblock recv
    if (divertHandle_ != INVALID_HANDLE_VALUE) {
        WinDivertClose(divertHandle_);
        divertHandle_ = INVALID_HANDLE_VALUE;
    }

    if (captureThread_.joinable()) {
        captureThread_.join();
    }

    LogVerbose("PacketEngine stopped");
}

bool PacketEngine::IsRunning() const {
    return running_;
}

void PacketEngine::CaptureLoop() {
    LogVerbose("Capture loop started");

    const int MAX_PACKET_SIZE = 65535;
    std::vector<uint8_t> packetBuffer(MAX_PACKET_SIZE);
    
    while (running_) {
        UINT recvLen = 0;
        WINDIVERT_ADDRESS addr;

        // Receive packet
        if (!WinDivertRecv(divertHandle_, packetBuffer.data(), (UINT)packetBuffer.size(), 
                          &recvLen, &addr)) {
            DWORD error = GetLastError();
            if (error == ERROR_OPERATION_ABORTED || !running_) {
                break;  // Normal shutdown
            }
            
            stats_.errors++;
            
            if (verboseLogging_) {
                std::stringstream ss;
                ss << "WinDivertRecv error: " << error;
                LogVerbose(ss.str());
            }
            
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            continue;
        }

        stats_.totalReceived++;

        // Process packet
        ProcessPacket(packetBuffer.data(), recvLen, &addr);
    }

    LogVerbose("Capture loop ended");
}

void PacketEngine::ProcessPacket(const uint8_t* packet, UINT packetLen, WINDIVERT_ADDRESS* addr) {
    if (packetLen < sizeof(IPv4Header)) {
        // Too small, just reinject
        ReinjectPacket(packet, packetLen, addr);
        return;
    }

    const IPv4Header* ipHdr = (const IPv4Header*)packet;
    
    // Log packet if enabled
    if (packetLogging_) {
        LogPacket("RECV", addr, packet, packetLen);
    }

    // Quick check for TLS/QUIC
    uint8_t ipHdrLen = IP_HDR_LEN(ipHdr->VersionIHL);
    
    if (ipHdr->Protocol == IPPROTO_TCP && packetLen > ipHdrLen + sizeof(TCPHeader)) {
        const TCPHeader* tcpHdr = (const TCPHeader*)(packet + ipHdrLen);
        uint8_t tcpHdrLen = TCP_HDR_LEN(tcpHdr->DataOffset);
        
        if (packetLen > (UINT)(ipHdrLen + tcpHdrLen)) {
            const uint8_t* payload = packet + ipHdrLen + tcpHdrLen;
            uint16_t payloadLen = ntohs(ipHdr->Length) - ipHdrLen - tcpHdrLen;

            if (IsTLSClientHello(payload, payloadLen)) {
                stats_.tlsClientHello++;
                
                std::string sni = ExtractSNI(payload, payloadLen);
                if (verboseLogging_ && !sni.empty()) {
                    std::stringstream ss;
                    ss << "TLS ClientHello detected, SNI: " << sni;
                    LogVerbose(ss.str());
                }

                // Check if this is a target domain
                if (currentProfile_) {
                    bool domainMatch = false;
                    bool ipMatch = false;
                    if (!sni.empty()) {
                        domainMatch = IsTargetDomain(sni, currentProfile_->domains);
                    }
                    // If domain didn't match, fall back to IP range matching
                    if (!domainMatch && !currentProfile_->ip_ranges.empty()) {
                        // Determine remote IP (host order). We only process outbound packets,
                        // so destination address is remote.
                        uint32_t dst = ntohl(ipHdr->DstAddr);
                        ipMatch = IsIpInProfile(dst, currentProfile_);
                    }
                    if (domainMatch || ipMatch) {
                        if (verboseLogging_) {
                            LogVerbose("Target destination detected (" +
                                (domainMatch ? std::string("domain: ") + sni : std::string("IP")) +
                                "), applying desync...");
                        }

                        // Apply desync strategy
                        DesyncResult result = desyncEngine_->ProcessPacket(
                            packet, packetLen, addr, currentProfile_);

                        if (result.drop) {
                            stats_.totalDropped++;
                            return;  // Don't reinject
                        }

                        if (result.modified) {
                            stats_.totalModified++;
                            stats_.desyncApplied++;
                            
                            // Inject segments with delays
                            InjectSegments(result.segments, addr);
                            return;
                        }
                    }
                }
            }
        }
    } else if (ipHdr->Protocol == IPPROTO_UDP && currentProfile_ && currentProfile_->use_quic) {
        // Check for QUIC
        if (packetLen > (UINT)ipHdrLen) {
            const uint8_t* payload = packet + ipHdrLen;
            uint16_t payloadLen = ntohs(ipHdr->Length) - ipHdrLen;
            if (IsQUICInitial(payload, payloadLen)) {
                stats_.quicInitial++;
                
                if (verboseLogging_) {
                    LogVerbose("QUIC Initial detected");
                }

                // Apply QUIC drop strategy
                DesyncResult result = desyncEngine_->ProcessPacket(
                    packet, packetLen, addr, currentProfile_);

                if (result.drop) {
                    stats_.totalDropped++;
                    return;  // Drop QUIC to force TCP fallback
                }
            }
        }
    }

    // Default: reinject unchanged
    ReinjectPacket(packet, packetLen, addr);
}

void PacketEngine::InjectSegments(const std::vector<PacketSegment>& segments, 
                                   WINDIVERT_ADDRESS* baseAddr) {
    for (const auto& seg : segments) {
        // Apply delay
        if (seg.delayMs > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(seg.delayMs));
        }

        // Send segment
        WINDIVERT_ADDRESS addr = *baseAddr;
        
        // Modify address for outbound injection
        addr.Outbound = 1;
        addr.Loopback = 0;
        
        UINT sendLen = 0;
        if (!WinDivertSend(divertHandle_, seg.data.data(), (UINT)seg.data.size(), &sendLen, &addr)) {
            DWORD error = GetLastError();
            if (verboseLogging_) {
                std::stringstream ss;
                ss << "WinDivertSend failed: " << error;
                LogVerbose(ss.str());
            }
            stats_.errors++;
        } else {
            stats_.totalSent++;
            
            if (verboseLogging_) {
                std::stringstream ss;
                ss << "Injected " << (seg.isFake ? "FAKE" : "REAL") 
                   << " segment, len=" << seg.data.size()
                   << " ttl=" << (int)seg.ttl
                   << " delay=" << seg.delayMs << "ms";
                LogVerbose(ss.str());
            }
        }
    }
}

void PacketEngine::ReinjectPacket(const uint8_t* packet, UINT packetLen, 
                                   WINDIVERT_ADDRESS* addr) {
    WINDIVERT_ADDRESS sendAddr = *addr;
    sendAddr.Outbound = 1;
    
    UINT sendLen = 0;
    if (!WinDivertSend(divertHandle_, packet, packetLen, &sendLen, &sendAddr)) {
        DWORD error = GetLastError();
        if (verboseLogging_) {
            std::stringstream ss;
            ss << "WinDivertSend (reinject) failed: " << error;
            LogVerbose(ss.str());
        }
        stats_.errors++;
    } else {
        stats_.totalSent++;
    }
}

void PacketEngine::SetServiceProfile(const ServiceProfile* profile) {
    currentProfile_ = profile;
    
    if (profile && verboseLogging_) {
        std::stringstream ss;
        ss << "Service profile set to: " << profile->name;
        LogVerbose(ss.str());
    }
}

void PacketEngine::EnableStrategy(DesyncStrategy strategy) {
    std::lock_guard<std::mutex> lock(statsMutex_);
    
    // Check if already enabled
    for (auto& s : enabledStrategies_) {
        if (s == strategy) return;
    }
    
    enabledStrategies_.push_back(strategy);
    
    if (verboseLogging_) {
        std::stringstream ss;
        ss << "Enabled strategy: " << (int)strategy;
        LogVerbose(ss.str());
    }
}

void PacketEngine::DisableStrategy(DesyncStrategy strategy) {
    std::lock_guard<std::mutex> lock(statsMutex_);
    
    enabledStrategies_.erase(
        std::remove(enabledStrategies_.begin(), enabledStrategies_.end(), strategy),
        enabledStrategies_.end()
    );
}

void PacketEngine::PrintStats() const {

    std::cout << "\n=== PacketEngine Statistics ===\n";
    std::cout << "Total Received:    " << stats_.totalReceived.load() << "\n";
    std::cout << "Total Sent:        " << stats_.totalSent.load() << "\n";
    std::cout << "Total Dropped:     " << stats_.totalDropped.load() << "\n";
    std::cout << "Total Modified:    " << stats_.totalModified.load() << "\n";
    std::cout << "TLS ClientHello:   " << stats_.tlsClientHello.load() << "\n";
    std::cout << "QUIC Initial:      " << stats_.quicInitial.load() << "\n";
    std::cout << "Desync Applied:    " << stats_.desyncApplied.load() << "\n";
    std::cout << "Errors:            " << stats_.errors.load() << "\n";
    std::cout << "================================\n";
}

void PacketEngine::ResetStats() {
    stats_.totalReceived = 0;
    stats_.totalSent = 0;
    stats_.totalDropped = 0;
    stats_.totalModified = 0;
    stats_.tlsClientHello = 0;
    stats_.quicInitial = 0;
    stats_.desyncApplied = 0;
    stats_.errors = 0;
}

void PacketEngine::SetVerbose(bool verbose) {
    verboseLogging_ = verbose;
}

void PacketEngine::EnablePacketLogging(bool enable) {
    packetLogging_ = enable;
}

void PacketEngine::Cleanup() {
    if (desyncEngine_) {
        delete desyncEngine_;
        desyncEngine_ = nullptr;
    }
}

} // namespace dPIBypass
