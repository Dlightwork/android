#ifndef CONFIG_H
#define CONFIG_H

#include <string>
#include <vector>
#include <cstdint>

namespace dPIBypass {

// 2026-Relevant Fake SNIs - Trusted domains that won't trigger DPI alerts
const std::vector<std::string> FAKE_SNIS = {
    "www.google.com",
    "cloudflare.com",
    "microsoft.com",
    "apple.com",
    "amazon.com",
    "facebook.com",
    "netflix.com",
    "akamai.net",
    "fastly.net",
    "edgekey.net"
};

// Target services configuration
struct ServiceProfile {
    std::string name;
    std::vector<std::string> domains;
    std::vector<std::string> ip_ranges;
    bool use_quic;
    bool use_desync;
    uint8_t ttl_fake;
    uint8_t ttl_real;
    uint16_t segment_size;
    uint32_t desync_delay_ms;
};

// Roblox profile tuned for safe mode.
//
// Roblox experiences rely heavily on TLS connections to download game assets
// and textures from CDN domains.  Splitting TLS ClientHello packets or
// injecting fake SNI records can break the handshake and cause assets to
// load slowly or not at all.  Official Roblox support notes that clients
// require UDP ports 49152–65535 to be open【593804592837219†L65-L72】; therefore
// DPI‑bypass behaviour for Roblox should avoid heavy desync strategies and
// preserve UDP flows.  To achieve this we disable QUIC manipulation and
// disable all desync strategies for Roblox.  TTL manipulation can remain
// enabled via the global configuration if desired.
const ServiceProfile ROBLOX_PROFILE = {
    "roblox",
    {"roblox.com", "www.roblox.com", "rbxcdn.com", "rbx.com", "roblox-api.com", 
     "roblox-studio.com", "gamepedia.com", "rbxtrk.com"},
    {},
    /* use_quic    */ false,  // do not treat UDP QUIC as DPI target for Roblox
    /* use_desync  */ false,  // disable fakemultisplit and other desync strategies
    /* ttl_fake    */ 3,
    /* ttl_real    */ 128,
    /* segment_size*/ 8,
    /* desync_delay*/ 10
};

const ServiceProfile YOUTUBE_PROFILE = {
    "youtube",
    {"youtube.com", "www.youtube.com", "googlevideo.com", "ytimg.com", 
     "youtube-nocookie.com", "youtu.be", "yt.be"},
    {},
    true,   // use_quic
    true,   // use_desync
    4,      // ttl_fake
    64,     // ttl_real
    12,     // segment_size
    15      // desync_delay_ms
};

// Discord profile tuned to preserve voice connections.
//
// Discord uses HTTPS/WebSocket signalling on TCP/443 and voice media over
// dynamic UDP ports (typically 50000–65535【942759798427538†L520-L535】).  Dropping QUIC or
// splitting TLS handshakes can interrupt voice calls or cause the client
// to hang while checking for updates.  To prioritise stability we disable
// QUIC manipulation and heavy desync for Discord.  TTL manipulation can
// still be used to obfuscate flows.
const ServiceProfile DISCORD_PROFILE = {
    "discord",
    {"discord.com", "www.discord.com", "discord.gg", "discord.media", 
     "discordapp.com", "discordstatus.com", "discord.co", "discord.dev"},
    {},
    /* use_quic    */ false,
    /* use_desync  */ false,
    /* ttl_fake    */ 3,
    /* ttl_real    */ 128,
    /* segment_size*/ 10,
    /* desync_delay*/ 8
};

const ServiceProfile TELEGRAM_PROFILE = {
    "telegram",
    {"telegram.org", "telegram.com", "t.me", "tdesktop.com", 
     "telega.one", "tg.dev"},
    {},
    false,  // use_quic - Telegram uses MTProto
    true,   // use_desync
    3,      // ttl_fake
    64,     // ttl_real
    16,     // segment_size
    5       // desync_delay_ms
};

// Global configuration
struct GlobalConfig {
    bool verbose_logging = true;
    bool auto_detect_services = true;
    uint32_t packet_buffer_size = 65535;
    uint16_t divert_priority = 0;
    uint32_t max_pending_packets = 1024;
    bool enable_ttl_manipulation = true;
    bool enable_fake_sni = true;
    bool enable_quic_drop = true;
    bool enable_sequence_desync = true;
    bool enable_fakemultisplit = true;
    bool enable_keepalive = true;
    bool optimize_for_gaming = false;
    bool roblox_safe_mode = true;  // Added missing field
    uint32_t fake_sni_count = 2;
    uint32_t connection_timeout_ms = 30000;
    uint32_t keepalive_interval_ms = 10000;
};

} // namespace dPIBypass

#endif // CONFIG_H
