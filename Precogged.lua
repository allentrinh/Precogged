local AceAddon = LibStub("AceAddon-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDB = LibStub("AceDB-3.0")

local AURA_NAME = "Precognition"
local PRECOGNITION_SPELL_ID = 377362
local SOUND_FILE = "Interface\\AddOns\\Precogged\\Assets\\Shotgun.ogg"
local PRECOGNITION_DURATION = 4 -- in seconds
local ICON_SIZE = 46
local ICON_BORDER_PADDING = 3

local Precogged = AceAddon:NewAddon("Precogged", "AceConsole-3.0", "AceEvent-3.0")
local defaults= {
    profile = {
        enabled = true,
        enableAudio = true,
        iconY = 100,
        iconX = 0,
        iconScale = 1,
    },
}

local iconFrame = nil
local cooldownFrame = nil

local timer = nil

local EventFrame = CreateFrame("Frame")

---
-- OnInitialize is called when the addon is loaded
-- It sets up the database and registers the options menu
function Precogged:OnInitialize()
    -- Initialize the database
    self.db = AceDB:New("PrecoggedDB", defaults, true)

    self:RegisterChatCommand("precogged", "ToggleOptionsPanel")

    self:RegisterMenu()
end

---
-- ToggleOptionsPanel opens or closes the options panel for Precogged
function Precogged:ToggleOptionsPanel()
    if not AceConfigDialog.OpenFrames["Precogged"] then
        AceConfigDialog:Open("Precogged")
    else
        AceConfigDialog:Close("Precogged")
    end
end

---
-- RegisterMenu sets up the configuration options for Precogged
function Precogged:RegisterMenu()
    local options = {
        name = "Precogged",
        type = "group",
        args = {
            test = {
                type = "execute",
                name = "Test Precogged",
                desc = "Simulate gaining the Precognition buff.",
                func = function()
                    self:DestroyIconTexture()
                    self:TriggerEffect()
                end,
                order = 0,
            },
            generalConfig = {
                type = "group",
                name = "General Configuration",
                order = 1,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable Precogged",
                        desc = "Enable or disable the Precogged addon.",
                        order = 1,
                        get = function(info) return self.db.profile.enabled end,
                        set = function(info, value) self.db.profile.enabled = value end,
                    },
                    enableAudio = {
                        type = "toggle",
                        name = "Enable Audio Alert",
                        desc = "Play a sound when Precognition buff is gained.",
                        order = 2,
                        get = function(info) return self.db.profile.enableAudio or false end,
                        set = function(info, value) self.db.profile.enableAudio = value end,
                    },
                    iconScale = {
                        type = "range",
                        name = "Icon Scale",
                        desc = "Set the scale of the Precognition icon.",
                        min = 0.5,
                        max = 2.0,
                        step = 0.1,
                        width = "full",
                        get = function(info) return self.db.profile.iconScale or 1 end,
                        set = function(info, value) self.db.profile.iconScale = value end,
                    },
                    position = {
                        type = "group",
                        name = "Icon Position",
                        inline = true,
                        args = {
                            iconY = {
                                type = "range",
                                name = "Icon Y Position",
                                desc = "Set the Y position of the Precognition icon.",
                                min = -500,
                                max = 500,
                                step = 1,
                                width = "full",
                                get = function(info) return self.db.profile.iconY or 100 end,
                                set = function(info, value) self.db.profile.iconY = value end,
                            },
                            iconX = {
                                type = "range",
                                name = "Icon X Position",
                                desc = "Set the X position of the Precognition icon.",
                                min = -500,
                                max = 500,
                                step = 1,
                                width = "full",
                                get = function(info) return self.db.profile.iconX or 0 end,
                                set = function(info, value) self.db.profile.iconX = value end,
                            },
                        },
                    }
                },
            },
        }
    }

    AceConfig:RegisterOptionsTable("Precogged", options)
end

---
-- OnEnable is called when the addon is enabled
function Precogged:OnEnable()
    -- Check if the addon is enabled in the settings
    if not self.db.profile.enabled then return end

    EventFrame:RegisterEvent("UNIT_AURA")
    EventFrame:SetScript("OnEvent", function(_, event, ...)
        -- Listen for aura changes on the player
        if event == "UNIT_AURA" then
            self:OnEvent(event, ...)
        end
    end)
end

function Precogged:OnEvent(event, unit, updateInfo)
    if unit ~= "player" then return end

    -- Handle the new 12.0 optimization payload
    if updateInfo then
        -- 1. Check if it's a full data reset (rare but happens)
        if updateInfo.isFullUpdate then
            self:CheckForPrecognition()
            return
        end

        -- 2. Check if Precognition was specifically added
        if updateInfo.addedAuras then
            for _, aura in ipairs(updateInfo.addedAuras) do
                if aura.spellId == PRECOGNITION_SPELL_ID then
                    self:TriggerEffect(aura.duration, aura.expirationTime)
                    return
                end
            end
        end
        
        -- 3. Check if it was updated (e.g., refreshed before it fell off)
        if updateInfo.updatedAuraInstanceIDs then
            -- For simplicity, if we see updates, we can just do a quick scan
            self:CheckForPrecognition()
        end
    else
        -- Fallback for older environments or edge cases
        self:CheckForPrecognition()
    end
end

function Precogged:CheckForPrecognition()
    -- Use the plural C_UnitAuras as found in your documentation
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(PRECOGNITION_SPELL_ID)
    if aura then
        self:TriggerEffect(aura.duration, aura.expirationTime)
    end
end

---
-- Creates the icon texture and sets up the cooldown
function Precogged:CreateIconTexture()
    local x = self.db.profile.iconX or 0
    local y = self.db.profile.iconY or 100

    -- Create the Icon using the ActionButtonTemplate
    iconFrame = CreateFrame("Button", "PrecoggedIconFrame", UIParent, "ActionButtonTemplate")
    iconFrame:SetAlpha(1)
    iconFrame:SetScale(self.db.profile.iconScale)
    iconFrame:EnableMouse(false)
    iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
    iconFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    iconFrame.icon:SetTexture(C_Spell.GetSpellTexture(PRECOGNITION_SPELL_ID))

    -- Apply cooldown
    local expiration = GetTime() + PRECOGNITION_DURATION
    local duration = PRECOGNITION_DURATION
    iconFrame.cooldown:SetPoint("CENTER", iconFrame, "CENTER", x - ICON_BORDER_PADDING,  - ICON_BORDER_PADDING)
    iconFrame.cooldown:SetScale(1)
    iconFrame.cooldown:SetCooldown(expiration - duration, duration)

    iconFrame:Show()
end

---
-- Destroys the icon texture and cleans up
function Precogged:DestroyIconTexture()
    if not iconFrame then return end

    iconFrame:Hide()
    iconFrame:UnregisterAllEvents()
    iconFrame = nil

    -- Clear timer
    if timer then
        timer:Cancel()
    end
end

---
-- TriggerEffect handles the visual and audio effects when Precognition is gained
function Precogged:TriggerEffect()
    if not self.db.profile.enabled then return end

    self:CreateIconTexture()

    if self.db.profile.enableAudio then
        PlaySoundFile(SOUND_FILE)
    end

    timer = C_Timer.NewTimer(PRECOGNITION_DURATION, function()
        self:DestroyIconTexture()
    end)
end