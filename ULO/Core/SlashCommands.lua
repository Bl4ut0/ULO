-- ============================================================================
-- ULO: Universal Layer Operator
-- File: Core/SlashCommands.lua
-- Description: Slash command dispatcher for /ulo and /layer. Parses subcommands,
--              manages auto-invite toggles, triggers immediate layer hops, and
--              opens the Blizzard configuration panel.
-- ============================================================================

local addonName, addonTable = ...
local ULO = _G.ULO or (addonTable and addonTable.ULO) or {}
_G.ULO = ULO

local Detection = ULO.Detection
local Monitor = ULO.Monitor
local Coordination = ULO.Coordination
local UI = ULO.UI
local Compat = ULO.Compat
local C = ULO.Constants

--- Safely prints output to default chat frame, falling back to ULO.Print or print.
-- @param msg string: Text message to display
local function OutputChat(msg)
    if _G.DEFAULT_CHAT_FRAME and type(_G.DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
    elseif ULO and type(ULO.Print) == "function" then
        ULO.Print(msg)
    elseif type(print) == "function" then
        print(msg)
    end
end

--- Primary slash command handler for /ulo and /layer.
-- Handles nil, non-string, and fuzz inputs safely without throwing errors.
-- @param rawMsg any: Raw user input passed from slash command
function ULO.HandleSlashCommand(rawMsg)
    local ok, err = pcall(function()
        local msg = ""
        if rawMsg ~= nil then
            if type(rawMsg) == "string" then
                msg = rawMsg
            else
                msg = tostring(rawMsg)
            end
        end

        if ULO.Compat and type(ULO.Compat.SafeTrim) == "function" then
            msg = ULO.Compat.SafeTrim(msg)
        else
            msg = string.match(msg, "^%s*(.-)%s*$") or ""
        end

        local cmd, arg1 = string.match(msg, "^(%S+)%s*(.*)$")
        cmd = cmd and string.lower(cmd) or ""
        arg1 = arg1 and (string.match(arg1, "^%s*(.-)%s*$") or "") or ""

        if cmd == "help" then
            OutputChat("Universal Layer Operator Commands: /ulo help, /ulo ui, /ulo invite, /ulo status, /ulo config, /layer <num>")
        elseif cmd == "ui" or cmd == "hud" or cmd == "show" then
            if ULO.UI and ULO.UI.StatusHUD then
                if type(ULO.UI.StatusHUD.ResetPosition) == "function" then
                    ULO.UI.StatusHUD.ResetPosition()
                elseif type(ULO.UI.StatusHUD.Toggle) == "function" then
                    ULO.UI.StatusHUD.Toggle()
                end
            end
        elseif cmd == "invite" or cmd == "toggle" then
            local argLower = string.lower(arg1 or "")
            if argLower == "off" then
                if ULO.Coordination and type(ULO.Coordination.ToggleAutoInvite) == "function" then
                    ULO.Coordination.ToggleAutoInvite(false)
                end
                _G.ULODB = _G.ULODB or {}
                _G.ULODB.autoInvite = false
                if _G.ULO_CONFIG and _G.ULO_CONFIG.autoInvite then
                    _G.ULO_CONFIG.autoInvite.enabled = false
                end
                if ULO.config and ULO.config.autoInvite then
                    ULO.config.autoInvite.enabled = false
                end
                OutputChat("Auto-Invite Disabled")
            elseif argLower == "on" then
                if ULO.Coordination and type(ULO.Coordination.ToggleAutoInvite) == "function" then
                    ULO.Coordination.ToggleAutoInvite(true)
                end
                _G.ULODB = _G.ULODB or {}
                _G.ULODB.autoInvite = true
                if _G.ULO_CONFIG and _G.ULO_CONFIG.autoInvite then
                    _G.ULO_CONFIG.autoInvite.enabled = true
                end
                if ULO.config and ULO.config.autoInvite then
                    ULO.config.autoInvite.enabled = true
                end
                OutputChat("Auto-Invite Enabled")
            else
                local cur = false
                if ULO.Coordination and type(ULO.Coordination.ToggleAutoInvite) == "function" then
                    cur = ULO.Coordination.ToggleAutoInvite()
                end
                _G.ULODB = _G.ULODB or {}
                _G.ULODB.autoInvite = cur
                if _G.ULO_CONFIG and _G.ULO_CONFIG.autoInvite then
                    _G.ULO_CONFIG.autoInvite.enabled = cur
                end
                if ULO.config and ULO.config.autoInvite then
                    ULO.config.autoInvite.enabled = cur
                end
                OutputChat("Auto-Invite: " .. (cur and "Enabled" or "Disabled"))
            end
        elseif cmd == "status" or (cmd == "layer" and (arg1 == "" or not arg1)) then
            local layer = (ULO.Detection and ULO.Detection.GetCurrentLayer and ULO.Detection.GetCurrentLayer()) or "?"
            local conf = (ULO.Detection and ULO.Detection.GetLayerConfidence and ULO.Detection.GetLayerConfidence()) or "UNDETERMINED"
            local cd = (ULO.Monitor and ULO.Monitor.GetCooldownRemaining and ULO.Monitor.GetCooldownRemaining()) or 0
            OutputChat(string.format("Current Layer: %s (%s) | Cooldown: %ds", tostring(layer), tostring(conf), cd))
        elseif cmd == "hop" or cmd == "layer" then
            local lNum = tonumber(arg1)
            if lNum and lNum >= 1 and lNum <= 20 then
                if ULO.Coordination and type(ULO.Coordination.RequestLayerHop) == "function" then
                    ULO.Coordination.RequestLayerHop(lNum)
                end
            else
                OutputChat("Invalid layer number: " .. tostring(arg1))
            end
        elseif cmd == "refresh" then
            if ULO.Monitor and type(ULO.Monitor.RequestRefreshNow) == "function" then
                ULO.Monitor.RequestRefreshNow()
            end
        elseif cmd == "config" or cmd == "options" then
            if ULO.UI and ULO.UI.SettingsPanel and ULO.UI.SettingsPanel.Open then
                ULO.UI.SettingsPanel.Open()
            end
        elseif cmd == "" then
            OutputChat("Universal Layer Operator Status")
            if ULO.UI and ULO.UI.StatusHUD and type(ULO.UI.StatusHUD.Toggle) == "function" then
                ULO.UI.StatusHUD.Toggle()
            end
        else
            OutputChat("Unknown command. Type /ulo help for commands.")
        end
    end)

    if not ok then
        OutputChat("Universal Layer Operator: command error")
    end
end

-- Register Slash Commands in Blizzard FrameXML Environment
_G.SLASH_ULO1 = "/ulo"
_G.SLASH_ULO2 = "/layeroperator"
_G.SLASH_LAYER1 = "/layer"

_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList["ULO"] = function(msg)
    ULO.HandleSlashCommand(msg)
end

_G.SlashCmdList["LAYER"] = function(msg)
    ULO.HandleSlashCommand("layer " .. (msg or ""))
end

return ULO.HandleSlashCommand
