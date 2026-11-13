
local ADDON = ...
local GREEN = { r = 0.20, g = 1.00, b = 0.30 }
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" -- green triangle

local defaults = { names = {}, party = true, friends = true, guild = false, icon = true, autoPlates = false, hinted = false }
local db

local function say(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff4dFriendGlow:|r " .. string.format(fmt, ...))
end

-- Newer clients can hand addons "secret" values that must never be compared.
local function usable(v)
    if v == nil then return false end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return false end
    end
    return true
end

local function safe(fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function isFriendRaw(unit)
    if not unit or not safe(UnitIsPlayer, unit) then return false end
    if safe(UnitIsUnit, unit, "player") then return false end

    local name = safe(UnitName, unit)
    if usable(name) and db.names[string.lower(name)] then return true end

    if db.party and (safe(UnitInParty, unit) or safe(UnitInRaid, unit)) then return true end

    local guid = safe(UnitGUID, unit)
    if not usable(guid) then return false end

    if db.friends then
        if C_FriendList and C_FriendList.IsFriend and safe(C_FriendList.IsFriend, guid) then return true end
        if C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID
            and safe(C_BattleNet.GetGameAccountInfoByGUID, guid) then return true end
    end

    if db.guild and IsGuildMember and safe(IsGuildMember, guid) then return true end
    return false
end

local function isFriend(unit)
    local ok, result = pcall(isFriendRaw, unit)
    return ok and result == true
end

local function isPlater(plate)
    return plate and plate.unitFrame and plate.unitFrame.healthBar and Plater ~= nil
end

local function nameTexts(plate)
    local out = {}
    if not plate then return out end
    if isPlater(plate) then
        if plate.unitName then out[#out + 1] = plate.unitName end
        if plate.ActorNameSpecial then out[#out + 1] = plate.ActorNameSpecial end
    else
        local uf = plate.UnitFrame
        local fs = uf and (uf.name or uf.Name or (uf.NameContainer and uf.NameContainer.Name))
        if fs then out[#out + 1] = fs end
    end
    return out
end

local function visibleName(plate)
    if isPlater(plate) then
        local cur = plate.CurrentUnitNameString
        if cur and cur.IsShown and cur:IsShown() then return cur end
        if plate.ActorNameSpecial and plate.ActorNameSpecial:IsShown() then return plate.ActorNameSpecial end
        if plate.unitName and plate.unitName:IsShown() then return plate.unitName end
        return plate.unitFrame
    end
    return nameTexts(plate)[1]
end

local function marker(plate)
    local tex = plate.FriendGlowIcon
    if not tex then
        tex = plate:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetTexture(ICON)
        tex:SetSize(26, 26)
        tex:Hide()
        plate.FriendGlowIcon = tex
    end
    local anchor = visibleName(plate) or plate
    if tex.FriendGlowAnchor ~= anchor then
        tex:ClearAllPoints()
        tex:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
        tex.FriendGlowAnchor = anchor
    end
    return tex
end

local function unitOf(plate)
    return plate.namePlateUnitToken
        or (plate.unitFrame and (plate.unitFrame.namePlateUnitToken or plate.unitFrame.unit))
        or (plate.UnitFrame and plate.UnitFrame.unit)
end

local function apply(plate)
    if not plate then return end
    local unit = unitOf(plate)
    local friend = unit and isFriend(unit)

    if friend then
        for _, fs in ipairs(nameTexts(plate)) do
            if not plate.FriendGlowOn and not fs.FriendGlowOrig then
                local ok, r, g, b, a = pcall(fs.GetTextColor, fs)
                if ok and r then fs.FriendGlowOrig = { r, g, b, a or 1 } end
            end
            pcall(fs.SetTextColor, fs, GREEN.r, GREEN.g, GREEN.b)
        end
        local icon = marker(plate)
        if db.icon then icon:Show() else icon:Hide() end
        plate.FriendGlowOn = true
    elseif plate.FriendGlowOn then
        plate.FriendGlowOn = nil
        if plate.FriendGlowIcon then plate.FriendGlowIcon:Hide() end
        for _, fs in ipairs(nameTexts(plate)) do
            local o = fs.FriendGlowOrig
            if o then pcall(fs.SetTextColor, fs, o[1], o[2], o[3], o[4]) end
            fs.FriendGlowOrig = nil
        end
        if not isPlater(plate) and plate.UnitFrame and CompactUnitFrame_UpdateName then
            pcall(CompactUnitFrame_UpdateName, plate.UnitFrame)
        end
    end
end

local function forget(plate)
    if not plate then return end
    plate.FriendGlowOn = nil
    if plate.FriendGlowIcon then plate.FriendGlowIcon:Hide() end
    for _, fs in ipairs(nameTexts(plate)) do fs.FriendGlowOrig = nil end
end

local platerHooked = false
local function hookPlater()
    if platerHooked or not (Plater and Plater.UpdatePlateText) then return end
    platerHooked = true
    hooksecurefunc(Plater, "UpdatePlateText", function(plateFrame)
        if db and plateFrame then apply(plateFrame) end
    end)
end

local function applyAll()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        apply(plate)
    end
end

local function applyUnit(unit)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        apply(safe(C_NamePlate.GetNamePlateForUnit, unit))
    end
end

if type(CompactUnitFrame_UpdateName) == "function" then
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        local unit = frame and frame.unit
        if unit and string.find(unit, "^nameplate") then
            local plate = safe(C_NamePlate.GetNamePlateForUnit, unit)
            if plate and isFriend(unit) then apply(plate) end
        end
    end)
end

-- Forever (modern client) calls it nameplateShowFriendlyPlayers; older clients nameplateShowFriends.
local function plateCVar()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if get and get("nameplateShowFriendlyPlayers") ~= nil then return "nameplateShowFriendlyPlayers" end
    return "nameplateShowFriends"
end

local function friendlyPlatesOn()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    return get and get(plateCVar()) == "1" or false
end

local pendingPlates = false
local function ensureFriendlyPlates()
    if not (db and db.autoPlates) or friendlyPlatesOn() then return end
    if InCombatLockdown() then pendingPlates = true return end -- CVars can't change in combat
    pendingPlates = false
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if set then pcall(set, plateCVar(), "1") end
end

local function hintIfPlatesOff()
    if not db or db.autoPlates or db.hinted or friendlyPlatesOn() then return end
    db.hinted = true
    say("Friendly nameplates are off, so I have nothing to color. Turn them on with your friendly-nameplate key, "
        .. "or tick 'Keep friendly nameplates on automatically' in Options > AddOns > FriendGlow.")
end

local settingsCategory
local function buildSettings()
    if settingsCategory or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category = Settings.RegisterVerticalLayoutCategory("FriendGlow")
    local function checkbox(key, label, tooltip, onChange)
        local setting = Settings.RegisterAddOnSetting(category, "FriendGlow_" .. key, key, db, "boolean", label, defaults[key])
        setting:SetValueChangedCallback(function()
            if onChange then onChange() end
            applyAll()
        end)
        Settings.CreateCheckbox(category, setting, tooltip)
    end
    checkbox("party", "Highlight party and raid members", "Green name + triangle on everyone in your group. On by default.")
    checkbox("friends", "Highlight friends", "Your in-game friends list and Battle.net friends who are playing this game.")
    checkbox("guild", "Highlight guildmates", "Members of your guild.")
    checkbox("icon", "Show the green triangle", "The green raid triangle above highlighted players. Untick for green names only.")
    checkbox("autoPlates", "Keep friendly nameplates on automatically", "FriendGlow can only draw on nameplates. Tick this and it switches friendly nameplates back on whenever they're off (after combat, at login and loading screens).", ensureFriendlyPlates)
    Settings.RegisterAddOnCategory(category)
    settingsCategory = category
end

local function openSettings()
    if settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
        return true
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("FRIENDLIST_UPDATE")
f:RegisterEvent("BN_FRIEND_INFO_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
f:RegisterEvent("CVAR_UPDATE")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Plater" then hookPlater() return end
        if arg1 ~= ADDON then return end
        FriendGlowDB = FriendGlowDB or {}
        db = FriendGlowDB
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = (type(v) == "table") and {} or v end
        end
        hookPlater()
        pcall(buildSettings)
        return
    end
    if not db then return end
    if event == "PLAYER_REGEN_ENABLED" then
        ensureFriendlyPlates()
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        forget(safe(C_NamePlate.GetNamePlateForUnit, arg1))
        return
    end
    if event == "CVAR_UPDATE" then
        if type(arg1) == "string" and arg1:lower() == plateCVar():lower() then C_Timer.After(0.2, ensureFriendlyPlates) end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        ensureFriendlyPlates()
        C_Timer.After(5, hintIfPlatesOff)
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        applyUnit(arg1)
    else
        applyAll()
    end
end)

local elapsedSince = 0
f:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.5 or not db then return end
    elapsedSince = 0
    applyAll()
end)

local function toggle(key, label)
    db[key] = not db[key]
    say("%s %s", label, db[key] and "|cff33ff4dON|r" or "|cffff5555OFF|r")
    applyAll()
end

SLASH_FRIENDGLOW1 = "/fglow"
SLASH_FRIENDGLOW2 = "/friendglow"
SlashCmdList.FRIENDGLOW = function(msg)
    if not db then return end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")

    if cmd == "add" or cmd == "remove" or cmd == "del" then
        local name = rest
        if name == "" then
            local t = safe(UnitName, "target")
            if usable(t) then name = t end
        end
        if name == "" then say("Type a name, or target the player first.") return end
        name = name:gsub("%-.*$", "") -- drop realm
        if cmd == "add" then
            db.names[string.lower(name)] = true
            say("Added |cff33ff4d%s|r", name)
        else
            db.names[string.lower(name)] = nil
            say("Removed %s", name)
        end
        applyAll()
    elseif cmd == "list" then
        local out = {}
        for n in pairs(db.names) do out[#out + 1] = n end
        table.sort(out)
        say("Names: %s", #out > 0 and table.concat(out, ", ") or "(none)")
        say("Party %s, Friends list %s, Guild %s, Triangle %s",
            db.party and "on" or "off", db.friends and "on" or "off",
            db.guild and "on" or "off", db.icon and "on" or "off")
    elseif cmd == "party" then toggle("party", "Party/raid members")
    elseif cmd == "friends" then toggle("friends", "Friends list")
    elseif cmd == "guild" then toggle("guild", "Guildmates")
    elseif cmd == "icon" then toggle("icon", "Green triangle")
    elseif cmd == "test" then
        local unit = "target"
        if not safe(UnitExists, unit) then say("Target a player first.") return end
        say("Target counts as a friend: %s", isFriend(unit) and "|cff33ff4dYES|r" or "|cffff5555NO|r")
        say("Nameplates drawn by: %s", (Plater and "Plater" .. (platerHooked and " (hooked)" or " (NOT hooked)")) or "Blizzard")
    elseif cmd == "plates" then
        toggle("autoPlates", "Turn on friendly nameplates automatically")
        ensureFriendlyPlates()
    elseif cmd == "" and openSettings() then
    else
        say("/fglow  (opens settings)  |  /fglow plates (auto-enable friendly nameplates)")
        say("/fglow add <Name>  (or target them and type /fglow add)")
        say("/fglow remove <Name>  |  /fglow list  |  /fglow test")
        say("/fglow party | friends | guild | icon  (toggle each)")
    end
end
