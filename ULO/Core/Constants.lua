-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Core/Constants.lua
-- Description: Central definitions for opcodes, timers, channels, event names,
--              protocol tokens, finite states, and default configuration values.
-- ============================================================================

local addonName, addonTable = ...
_G.ULO = _G.ULO or addonTable or {}
local ULO = _G.ULO

ULO.Constants = {}
local C = ULO.Constants

-- ----------------------------------------------------------------------------
-- Addon Metadata
-- ----------------------------------------------------------------------------
C.ADDON_NAME    = "ULO"
C.ADDON_TITLE   = "Universal Layer Operator"
C.VERSION       = "1.0.0"
C.AUTHOR        = "ULO Team"

-- ----------------------------------------------------------------------------
-- Client Flavors and Interface Numbers
-- ----------------------------------------------------------------------------
C.FLAVORS = {
    FOREVER       = "wowf",
    ANNIVERSARY   = "wow_anniversary",
    CLASSIC_ERA   = "wow_classic_era",
    CLASSIC_MISTS = "wow_classic",
    RETAIL        = "wow",
}

C.TOC_VERSIONS = {
    CLASSIC_ERA     = 11509,
    FOREVER         = 16001,
    ANNIVERSARY_TBC = 20506,
    CLASSIC_MISTS   = 50504,
    RETAIL          = 120105,
}

-- ----------------------------------------------------------------------------
-- Layer Detection Constants
-- ----------------------------------------------------------------------------
C.DETECTION = {
    CONSENSUS_THRESHOLD   = 2,       -- Minimum distinct GUIDs required to confirm a layer
    GUID_TOKEN_TYPE       = 1,       -- Token 1: Entity type (Creature, Vehicle, etc.)
    GUID_TOKEN_ZERO       = 2,       -- Token 2: Literal "0"
    GUID_TOKEN_SERVER_ID  = 3,       -- Token 3: Physical server layer / shard ID
    GUID_TOKEN_INSTANCE_ID= 4,       -- Token 4: Instance ID (0 in open world)
    GUID_TOKEN_ZONE_ID    = 5,       -- Token 5: Zone / continent shard instance ID
    GUID_TOKEN_NPC_ID     = 6,       -- Token 6: Creature ID
    GUID_TOKEN_SPAWN_UID  = 7,       -- Token 7: Unique spawn identifier
    MAX_CACHE_ENTRIES     = 100,     -- Maximum entries in GUID resolution cache
    DEBOUNCE_TIME         = 0.5,     -- Debounce delay (seconds) following invalidation events
    MAX_LAYER_NUMBER      = 30,      -- Upper bound for human-facing layer index
    SHARD_LAYER_ID_MAX    = 1000000, -- Upper bound for raw server shard ID
    VALID_UNIT_TYPES = {
        Creature   = true,
        Vehicle    = true,
        GameObject = true,
        Vignette   = true,
    },
    SCAN_UNITS = {
        "target",
        "mouseover",
        "focus",
        "softenemy",
        "softfriend",
        "softinteract",
    },
}

-- ----------------------------------------------------------------------------
-- Confidence States
-- ----------------------------------------------------------------------------
C.CONFIDENCE = {
    CONFIRMED    = "CONFIRMED",      -- Verified by >= 2 distinct creature GUIDs
    ESTIMATED    = "ESTIMATED",      -- 1 GUID or cached prior to minor zone movement
    UNDETERMINED = "UNDETERMINED",   -- No valid GUIDs in range / newly entered area
    INSTANCED    = "INSTANCED",      -- In a dungeon, raid, or battleground (layering disabled)
}

-- ----------------------------------------------------------------------------
-- Timing and Throttle Thresholds (Seconds)
-- ----------------------------------------------------------------------------
C.TIMERS = {
    REFRESH_WINDOW         = 180,    -- 180s (3:00) layer refresh warning window
    REFRESH_CRITICAL       = 10,     -- <= 10s auto-expand chevron notification
    COOLDOWN_DEFAULT       = 300,    -- 300s (5-minute) post-refresh hopping cooldown
    COOLDOWN_MIN           = 300,
    COOLDOWN_MAX           = 900,
    INVITE_TIMEOUT         = 180,    -- 180s pending invite expiration
    INVITE_THROTTLE        = 300,    -- 300s throttle before re-inviting same player
    INVITE_PACING_DELAY    = 0.5,    -- 500ms delay for low-priority public channel requests
    DEPARTURE_DELAY        = 2.0,    -- 2s delay after layer verification before leaving group
    COMBAT_DEFERRAL_GRACE  = 2.0,    -- 2s grace period out of combat before refresh execution
    CHANNEL_JOIN_INTERVAL  = 10.0,   -- 10s between channel join attempts
    CHANNEL_RETRY_INTERVAL = 30.0,   -- 30s delay if layer channel displaces default chat
    HEARTBEAT_INTERVAL     = 1.0,    -- 1s tick for UI countdown and cooldown updates
}

-- ----------------------------------------------------------------------------
-- Group Management & Safety Limits
-- ----------------------------------------------------------------------------
C.GROUP = {
    MAX_PARTY_MEMBERS = 4,           -- Party limit: allows 5th player to join
    MAX_RAID_MEMBERS  = 39,          -- Raid limit: allows 40th player to join
    AUTO_CONVERT_RAID = false,       -- Never auto-convert 5-man party to raid
}

-- ----------------------------------------------------------------------------
-- Sound Files to Mute (Anti-Spam)
-- ----------------------------------------------------------------------------
C.SOUNDS_TO_MUTE = {
    567490, -- Standard party invite chime
    567451, -- Group invite popup sound
    567458, -- Ready check / group prompt sound
    567478, -- Raid warning sound
}

-- ----------------------------------------------------------------------------
-- Wire Protocol: Overlord ("OverlordLJ")
-- ----------------------------------------------------------------------------
C.OVERLORD = {
    PREFIX                  = "OverlordLJ",
    CHANNEL                 = "WHISPER",
    PROTOCOL_VERSION        = 2,
    MSG_REQUEST             = "R",          -- Format: R:2:<requestId>:<originLayer|->
    MSG_DECLINE             = "N",          -- Format: N:<requestId>:<reason>
    HELPER_PER_SENDER_GAP   = 5,            -- 5s per-requester flood protection
    HELPER_SAME_REQUESTER_GAP = 30,         -- 30s gap for same requester
    HELPER_INVITE_GAP       = 15,           -- 15s gap between outbound invites
    HELPER_INVITES_PER_HOUR = 20,           -- Maximum 20 automated invites per hour
    INVITE_WAIT             = 12,           -- 12s wait for invite dispatch
    JOIN_WAIT               = 10,           -- 10s wait for join confirmation
    VERIFY_TIMEOUT          = 40,           -- 40s layer verification timeout
    GUEST_KICK_AFTER        = 120,          -- 120s guest kick timeout
    REASONS = {
        OFF      = "off",
        INSTANCE = "instance",
        COMBAT   = "combat",
        QUEUE    = "queue",
        FULL     = "full",
        BUSY     = "busy",
        SAME     = "same",
        SILENT   = "silent",
        LOST     = "lost",
    },
}

-- ----------------------------------------------------------------------------
-- Wire Protocol: AutoLayer / NetherAutoLayer
-- ----------------------------------------------------------------------------
C.AUTOLAYER = {
    STATIC_CHANNEL          = "layer",
    DYNAMIC_CHANNEL_PREFIX  = "layer", -- layer + 8-char Adler32 hex
    SEGMENTS = {
        AZEROTH   = "AZ",
        OUTLAND   = "OL",
        ZEPHRAS   = "ZI",
        DARKSPEAR = "DI",
    },
    SEGMENT_MAPS = {
        [947]  = "AZ",
        [1945] = "OL",
        [2521] = "ZI",
        [2665] = "ZI",
        [2524] = "DI",
    },
    PROTOCOL_V2_PREFIX       = "AL2",
    PROTOCOL_V2_REGEX        = "^<AL(%d+)V(%d+)_(%d+)_(%d+)Z(%d+)>(.*)$",
    CLASSIC_REQUEST_REGEX    = "^<([A-Z]+)>%s+inv%s+layer%s*(.*)$",
    WHISPER_TAG              = "[AutoLayer] ",
    MISPLACED_CHANNEL_LIMIT  = 5,      -- Slots 1-5 reserved for General/Trade/LocalDefense
}

-- ----------------------------------------------------------------------------
-- Wire Protocol: NovaWorldBuffs
-- ----------------------------------------------------------------------------
C.NWB = {
    COMM_PREFIX          = "NWB",
    GLOBAL_LAYER_VAR     = "NWB_CurrentLayer",
    GLOBAL_ZONE_VAR      = "NWB_CurrentLayerZoneID",
    GLOBAL_CALLBACK_VAR  = "NWB_LayerUpdated",
}

-- ----------------------------------------------------------------------------
-- Whisper Keywords and Filters
-- ----------------------------------------------------------------------------
C.KEYWORDS = {
    DEFAULT_TRIGGERS = { "layer", "inv", "invite", "inv layer", "layer inv" },
    INVERTED = {
        "not", "off", "except", "but", "out",
        "other than", "besides", "apart from",
    },
    BLACKLIST = {
        "wts", "wtb", "lfm", "lfg", "ashen", "auto inv", "autoinv",
        "pst for", "guild", "raid", "enchant", "player",
        "what layer", "which layer", "worldbuffs",
    },
    MAX_LAYER = 20,
}

-- ----------------------------------------------------------------------------
-- Blizzard Events Registry
-- ----------------------------------------------------------------------------
C.EVENTS = {
    ADDON_LOADED                 = "ADDON_LOADED",
    PLAYER_LOGIN                 = "PLAYER_LOGIN",
    PLAYER_LOGOUT                = "PLAYER_LOGOUT",
    PLAYER_ENTERING_WORLD        = "PLAYER_ENTERING_WORLD",
    ZONE_CHANGED_NEW_AREA        = "ZONE_CHANGED_NEW_AREA",
    ZONE_CHANGED                 = "ZONE_CHANGED",
    ZONE_CHANGED_INDOORS         = "ZONE_CHANGED_INDOORS",
    UNIT_PHASE                   = "UNIT_PHASE",
    PLAYER_TARGET_CHANGED        = "PLAYER_TARGET_CHANGED",
    UPDATE_MOUSEOVER_UNIT        = "UPDATE_MOUSEOVER_UNIT",
    PLAYER_FOCUS_CHANGED         = "PLAYER_FOCUS_CHANGED",
    NAME_PLATE_UNIT_ADDED        = "NAME_PLATE_UNIT_ADDED",
    COMBAT_LOG_EVENT_UNFILTERED  = "COMBAT_LOG_EVENT_UNFILTERED",
    PLAYER_REGEN_DISABLED        = "PLAYER_REGEN_DISABLED",
    PLAYER_REGEN_ENABLED         = "PLAYER_REGEN_ENABLED",
    CHAT_MSG_WHISPER             = "CHAT_MSG_WHISPER",
    CHAT_MSG_WHISPER_INFORM      = "CHAT_MSG_WHISPER_INFORM",
    CHAT_MSG_BN_WHISPER          = "CHAT_MSG_BN_WHISPER",
    CHAT_MSG_CHANNEL             = "CHAT_MSG_CHANNEL",
    CHAT_MSG_ADDON               = "CHAT_MSG_ADDON",
    PARTY_INVITE_REQUEST         = "PARTY_INVITE_REQUEST",
    GROUP_ROSTER_UPDATE          = "GROUP_ROSTER_UPDATE",
    GROUP_JOINED                 = "GROUP_JOINED",
    GROUP_LEFT                   = "GROUP_LEFT",
    UI_ERROR_MESSAGE             = "UI_ERROR_MESSAGE",
}

-- ----------------------------------------------------------------------------
-- Internal ULO Event Bus Callback Identifiers
-- ----------------------------------------------------------------------------
C.CALLBACKS = {
    ON_LAYER_CHANGED       = "OnLayerChanged",       -- (layerNumber, serverId, zoneId, oldLayer)
    ON_REFRESH_WARNING     = "OnRefreshWarning",     -- (remainingSeconds, isDeferred)
    ON_REFRESH_TRIGGERED   = "OnRefreshTriggered",   -- ()
    ON_COOLDOWN_STARTED    = "OnCooldownStarted",    -- (durationSeconds)
    ON_COOLDOWN_EXPIRED    = "OnCooldownExpired",    -- ()
    ON_INVITE_SENT         = "OnInviteSent",         -- (targetName, reason)
    ON_HOP_REQUESTED       = "OnHopRequested",       -- (targetLayer, protocol)
    ON_CONFIG_CHANGED      = "OnConfigChanged",      -- (key, value)
}

-- ----------------------------------------------------------------------------
-- Finite State Machine States
-- ----------------------------------------------------------------------------
C.STATES = {
    UNINITIALIZED       = "UNINITIALIZED",
    LAYER_DETECTING     = "LAYER_DETECTING",
    LAYER_STABLE        = "LAYER_STABLE",
    REFRESH_PENDING     = "REFRESH_PENDING",
    IN_COMBAT_LOCKED    = "IN_COMBAT_LOCKED",
    REFRESH_IN_PROGRESS = "REFRESH_IN_PROGRESS",
    REFRESH_COOLDOWN    = "REFRESH_COOLDOWN",
    INSTANCED_DISABLED  = "INSTANCED_DISABLED",
}

-- ----------------------------------------------------------------------------
-- Default Configuration Schema (Stored in ULO_CONFIG)
-- ----------------------------------------------------------------------------
C.DEFAULT_CONFIG = {
    version = 1,
    debug   = false,

    autoInvite = {
        enabled           = true,
        onlyInCity        = false,
        whileInRaid       = false,
        whileLFG          = false,
        muteInviteSounds  = true,
        throttleSeconds   = 300,
        timeoutSeconds    = 180,
        maxPartyMembers   = 4,
        triggers          = { "layer", "inv", "invite" },
        blacklist         = { "wts", "wtb", "lfm", "lfg", "ashen", "autoinv" },
    },

    refreshMonitor = {
        enabled           = true,
        warningSeconds    = 180,
        criticalSeconds   = 10,
        soundAlert        = true,
        showCenterBanner  = true,
        showPopup         = true,
        minimizeToChevron = true,
        deferCombat       = true,
    },

    cooldown = {
        enabled           = true,
        durationSeconds   = 300,
    },

    interop = {
        overlordEnabled    = true,
        autoLayerEnabled   = true,
        nwbEnabled         = true,
        joinHashedChannels = true,
        joinStaticChannel  = true,
    },

    ui = {
        showMinimapBadge  = true,
        minimapPos        = 220,
        showStatusHUD     = true,
        hudLocked         = false,
        hudScale          = 1.0,
        hudPoint          = "TOP",
        hudRelPoint       = "TOP",
        hudX              = 0,
        hudY              = -80,
    },
}
