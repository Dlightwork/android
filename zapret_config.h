#ifndef ZAPRET_CONFIG_H
#define ZAPRET_CONFIG_H

#include <string>
#include <vector>
#include <cstdint>

namespace Zapret {

// ============ FEBRUARY 2026 DPI BYPASS ============

// Fake SNIs for 2026
const std::vector<std::string> FAKE_SNIS_2026 = {
    "www.google.com", "cloudflare.com", "microsoft.com", "apple.com",
    "amazon.com", "github.com", "stackoverflow.com"
};

// DNS over HTTPS
const std::vector<std::string> DOH_SERVERS = {
    "https://cloudflare-dns.com/dns-query",
    "https://dns.google/dns-query",
    "https://dns.quad9.net/dns-query"
};

// ROBLOX - low ping optimization (20-50ms)
struct RobloxProfile {
    static const char* name;
    static const std::vector<std::string> domains;
    static constexpr bool use_quic = false;
    static constexpr bool use_desync = true;
    static constexpr uint8_t ttl_fake = 2;
    static constexpr uint8_t ttl_real = 64;
    static constexpr uint16_t segment_size = 4;
    static constexpr uint32_t desync_delay_ms = 5;
    static constexpr bool enable_keepalive = true;
    static constexpr uint32_t keepalive_interval_ms = 15000;
};

// YOUTUBE - stable streaming
struct YouTubeProfile {
    static const char* name;
    static const std::vector<std::string> domains;
    static constexpr bool use_quic = true;
    static constexpr bool use_desync = true;
    static constexpr uint8_t ttl_fake = 3;
    static constexpr uint8_t ttl_real = 64;
    static constexpr uint16_t segment_size = 8;
    static constexpr uint32_t desync_delay_ms = 10;
};

// DISCORD - voice + chat stability
struct DiscordProfile {
    static const char* name;
    static const std::vector<std::string> domains;
    static constexpr bool use_quic = false;
    static constexpr bool use_desync = true;
    static constexpr uint8_t ttl_fake = 2;
    static constexpr uint8_t ttl_real = 128;
    static constexpr uint16_t segment_size = 6;
    static constexpr uint32_t desync_delay_ms = 8;
    static constexpr bool preserve_udp = true;
};

// Domain lists
inline const char* RobloxProfile::name = "roblox";
inline const std::vector<std::string> RobloxProfile::domains = {
    "roblox.com", "www.roblox.com", "rbxcdn.com", "rbx.com",
    "roblox-api.com", "api.roblox.com", "realtime.roblox.com",
    "ephemeralcounters.api.roblox.com", "clientsettings.api.roblox.com",
    "client-telemetry.roblox.com", "metrics.roblox.com",
    "apis.roblox.com", "auth.roblox.com", "accountsettings.roblox.com",
    "avatar.roblox.com", "catalog.roblox.com", "chat.roblox.com",
    "friends.roblox.com", "games.roblox.com", "groups.roblox.com",
    "notifications.roblox.com", "presence.roblox.com",
    "thumbnails.roblox.com", "users.roblox.com", "economy.roblox.com",
    "premiumfeatures.roblox.com", "trades.roblox.com",
    "privatemessages.roblox.com", "share.roblox.com", "ads.roblox.com",
    "assetdelivery.roblox.com", "contentstore.roblox.com",
    "universes.roblox.com", "develop.roblox.com", "search.roblox.com",
    "followings.roblox.com", "assetgame.roblox.com",
    "gameinternationalization.roblox.com", "locale.roblox.com",
    "points.roblox.com", "badges.roblox.com", "inventory.roblox.com",
    "web.roblox.com", "setup.rbxcdn.com", "setup-http.rbxcdn.com",
    "c0.rbxcdn.com", "c1.rbxcdn.com", "c2.rbxcdn.com", "c3.rbxcdn.com",
    "c4.rbxcdn.com", "c5.rbxcdn.com", "c6.rbxcdn.com", "c7.rbxcdn.com",
    "t0.rbxcdn.com", "t1.rbxcdn.com", "t2.rbxcdn.com", "t3.rbxcdn.com",
    "t4.rbxcdn.com", "t5.rbxcdn.com", "t6.rbxcdn.com", "t7.rbxcdn.com",
    "roblox-c0.akamaized.net", "roblox-c1.akamaized.net",
    "roblox-c2.akamaized.net", "roblox-c3.akamaized.net"
};

inline const char* YouTubeProfile::name = "youtube";
inline const std::vector<std::string> YouTubeProfile::domains = {
    "youtube.com", "www.youtube.com", "googlevideo.com", "ytimg.com",
    "youtube-nocookie.com", "youtu.be", "yt.be",
    "s.youtube.com", "studio.youtube.com", "music.youtube.com",
    "gaming.youtube.com", "tv.youtube.com", "m.youtube.com",
    "youtubei.googleapis.com", "youtube.googleapis.com",
    "googleapis.com", "googleusercontent.com",
    "ggpht.com", "gvt1.com", "gvt2.com", "gvt3.com",
    "wide-youtube.l.google.com", "youtube-ui.l.google.com",
    "youtubeembeddedplayer.googleapis.com",
    "yt3.ggpht.com", "yt4.ggpht.com",
    "i.ytimg.com", "i9.ytimg.com",
    "s.ytimg.com", "ytimg.l.google.com"
};

inline const char* DiscordProfile::name = "discord";
inline const std::vector<std::string> DiscordProfile::domains = {
    "discord.com", "www.discord.com", "discord.gg", "discord.media",
    "discordapp.com", "discordstatus.com", "discord.co", "discord.dev",
    "discord.new", "discord.gift", "discord.gifts",
    "discordapp.net", "discordcdn.com", "discordmerch.com",
    "discord-attachments-uploads-prd.storage.googleapis.com",
    "dis.gd", "discordactivities.com", "discordsez.com",
    "gateway.discord.gg", "cdn.discordapp.com",
    "images-ext-1.discordapp.net", "images-ext-2.discordapp.net",
    "media.discordapp.net", "status.discord.com",
    "support.discord.com", "blog.discord.com",
    "merch.discord.com", "printer.discord.com",
    "feedback.discord.com", "streamkit.discord.com",
    "i18n.discord.com", "events.discord.com",
    "ptb.discord.com", "canary.discord.com",
    "staging.discord.com", "discord.store", "discord.shop"
};

// Global config
struct ZapretConfig {
    bool verbose = true;
    bool enable_dns_doh = true;
    bool enable_dns_dot = true;
    bool enable_ttl_trick = true;
    bool enable_fakemultisplit = true;
    bool enable_quic_drop = true;
    bool enable_keepalive = true;
    uint32_t fake_sni_count = 3;
    uint32_t buffer_size = 65535;
    uint32_t queue_length = 8192;
};

} // namespace Zapret

#endif // ZAPRET_CONFIG_H
