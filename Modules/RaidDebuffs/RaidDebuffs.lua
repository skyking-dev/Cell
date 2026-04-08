local _, Cell = ...
local L = Cell.L
local F = Cell.funcs
local B = Cell.bFuncs
local P = Cell.pixelPerfectFuncs

local LCG = LibStub("LibCustomGlow-1.0")

local debuffsTab = Cell.CreateFrame("CellOptionsFrame_RaidDebuffsTab", Cell.frames.optionsFrame, nil, nil, true)
Cell.frames.raidDebuffsTab = debuffsTab
debuffsTab:SetAllPoints(Cell.frames.optionsFrame)
debuffsTab:Hide()

-- vars
local loadedExpansion, loadedInstance, loadedBoss, isGeneral
local tierNames = {}
local currentBossTable, selectedButtonIndex, selectedSpellId, selectedSpellName, selectedSpellIcon
-- frames
local instancesFrame, bossesFrame, debuffListFrame, detailsFrame
-- functions
local LoadExpansion, ShowInstances, ShowBosses, ShowDebuffs, ShowDetails, ShowInstanceImage, HideInstanceImage, ShowBossImage, HideBossImage, OpenEncounterJournal
-- buttons
local instanceButtons, bossButtons, debuffButtons = {}, {}, {}
local curationReportFrame, curationReportTitle, curationReportContext, curationReportTextArea
-------------------------------------------------
-- prepare debuff list
-------------------------------------------------
-- NOTE: instanceId is instanceEncounterJournalId
-- mapId = C_Map.GetBestMapForUnit("player")
-- instanceId = EJ_GetInstanceForMap(mapId)
-- instanceName, ... = EJ_GetInstanceInfo(instanceId)

-- used to sort list buttons
local encounterJournalList = {
    -- ["expansionName"] = {
    --     {
    --         ["name"] = instanceName,
    --         ["id"] = instanceId,
    --         ["bosses"] = {
    --             {["name"]=name, ["id"]=id, ["image"]=image},
    --         },
    --     },
    -- },
}

-- used to GetInstanceInfo/GetRealZoneText --> instanceId
local instanceNameMapping = {
    -- [instanceName] = expansionName:instanceIndex:instanceId,
}
Cell.snippetVars.instanceNameMapping = instanceNameMapping

-- used for mapping instanceId --> instanceName
local instanceIdToName = {}

-- used for mapping bossId --> bossName
local bossIdToName = {
    [0] = L["General"]
}

local instanceBossOverrides = {
    [362] = {  -- 雷电王座
        [13] = 831,  -- 莱登
    },
}

local function LoadBossList(instanceId, list)
    EJ_SelectInstance(instanceId)
    for index = 1, 77 do
        local name, id, _
        if instanceBossOverrides[instanceId] and instanceBossOverrides[instanceId][index] then
            name, _, id = EJ_GetEncounterInfo(instanceBossOverrides[instanceId][index])
        else
            name, _, id = EJ_GetEncounterInfoByIndex(index)
        end

        if not name or not id then
            break
        end

        -- id, name, description, displayInfo, iconImage, uiModelSceneID = EJ_GetCreatureInfo(index [, encounterID])
        local image = select(5, EJ_GetCreatureInfo(1, id))
        tinsert(list, {["name"]=name, ["id"]=id, ["image"]=image})
        bossIdToName[id] = name
    end
end

local function LoadInstanceList(tier, instanceType, list)
    EJ_SelectTier(tier)
    local isRaid = instanceType == "raid"
    for index = 1, 77 do
        local id, name, _, _, image = EJ_GetInstanceByIndex(index, isRaid)
        if not id or not name then
            break
        end

        local eName = EJ_GetTierInfo(tier)
        local instanceTable = {["name"]=name, ["id"]=id, ["image"]=image, ["bosses"]={}}
        tinsert(list, instanceTable)
        instanceNameMapping[name] = eName..":"..#list..":"..id -- NOTE: used for searching current zone debuffs & switch to current instance
        instanceIdToName[id] = name

        LoadBossList(id, instanceTable["bosses"])
    end
end

local CURRENT_SEASON_INDEX = 12

local function LoadList()
    local currentTier = EJ_GetCurrentTier()

    local num = EJ_GetNumTiers()

    for tier = 1, num do
        local name = EJ_GetTierInfo(tier)
        encounterJournalList[name] = {}

        if tier ~= CURRENT_SEASON_INDEX then -- don't load raid for "Current Season"
            LoadInstanceList(tier, "raid", encounterJournalList[name])
        end
        LoadInstanceList(tier, "party", encounterJournalList[name])

        tierNames[tier] = name
    end

    EJ_SelectTier(currentTier)
end

-------------------------------------------------
-- dungeons for current mythic season
-------------------------------------------------
--[[
local CURRENT_SEASON = {
    1194, -- 塔扎维什
    860, -- 重返卡拉赞
    1178, -- 麦卡贡行动
    558, -- 钢铁码头
    536, -- 恐轨车站
    -- 226
}

local function LoadDungeonsForCurrentSeason()
    encounterJournalList["Current Season"] = {}
    for i, journalInstanceID in pairs(CURRENT_SEASON) do
        local name, _, _, image = EJ_GetInstanceInfo(journalInstanceID)

        local instanceTable = {["name"]=name, ["id"]=journalInstanceID, ["image"]=image, ["bosses"]={}}
        tinsert(encounterJournalList["Current Season"], instanceTable)

        -- overwrite instanceNameMapping
        instanceNameMapping[name] = "Current Season"..":"..i..":"..journalInstanceID

        LoadBossList(journalInstanceID, instanceTable["bosses"])
    end
end
]]
-------------------------------------------------

LoadExpansion = function(eName)
    if loadedExpansion == eName then return end
    loadedExpansion = eName
    -- show then first boss of the first instance of the expansion
    ShowInstances(eName)
end

local unsortedDebuffs = {}
function F.LoadBuiltInDebuffs(debuffs)
    for instanceId, iTable in pairs(debuffs) do
        unsortedDebuffs[instanceId] = iTable
    end
end

local loadedDebuffs = {
    -- [instanceId] = {
    --     ["general"] = {
    --         ["enabled"]= {
    --             {["id"]=spellId, ["order"]=order, ["trackByID"]=trackByID, ["condition"]={type,operator,value}, ["glowType"]=glowType, ["glowOptions"]={...}, ["glowCondition"]={...}}
    --         },
    --         ["disabled"] = {},
    --     },
    --     [bossId] = {
    --         ["enabled"]= {
    --             {["id"]=spellId, ["order"]=order, ["trackByID"]=trackByID, ["condition"]={type,operator,value}, ["glowType"]=glowType, ["glowOptions"]={...}, ["glowCondition"]={...}}
    --         },
    --         ["disabled"] = {},
    --     },
    -- },
}
Cell.snippetVars.loadedDebuffs = loadedDebuffs

-- db
-- [spellId] = {
--     order = (number),
--     trackByID = (boolean),
--     condition = (table),
--     glowType = (string),
--     glowOptions = (table),
--     glowCondition = (table),
--     glowTarget = (string),
--     useElapsedTime = (boolean),
-- }

local indices = {"order", "trackByID", "condition", "glowType", "glowOptions", "glowCondition", "glowTarget", "useElapsedTime"}

local curationStatusInfo = {
    ["review"] = {
        ["text"] = "Needs Review",
        ["tag"] = "REV",
        ["color"] = {1, 0.82, 0},
    },
    ["confirmed"] = {
        ["text"] = "Confirmed",
        ["tag"] = "OK",
        ["color"] = {0.5, 1, 0},
    },
    ["trash"] = {
        ["text"] = "Trash Mob",
        ["tag"] = "TR",
        ["color"] = {0, 0.8, 1},
    },
    ["non_debuff"] = {
        ["text"] = "Non-Debuff",
        ["tag"] = "ND",
        ["color"] = {1, 0.3, 0.3},
    },
    ["ignore"] = {
        ["text"] = "Ignore",
        ["tag"] = "IG",
        ["color"] = {0.7, 0.7, 0.7},
    },
}

local function EnsureRaidDebuffsCurationDB()
    CellDB["raidDebuffsCuration"] = CellDB["raidDebuffsCuration"] or {}
    return CellDB["raidDebuffsCuration"]
end

local function NormalizeCurationBossId(instanceId, bossId)
    if bossId == nil or bossId == instanceId or bossId == "general" then
        return "general"
    end

    return bossId
end

local function GetRaidDebuffCurationEntry(instanceId, bossId, spellId, create)
    local db = EnsureRaidDebuffsCurationDB()
    local bossKey = NormalizeCurationBossId(instanceId, bossId)

    if create then
        db[instanceId] = db[instanceId] or {}
        db[instanceId][bossKey] = db[instanceId][bossKey] or {}
        db[instanceId][bossKey][spellId] = db[instanceId][bossKey][spellId] or {}
        return db[instanceId][bossKey][spellId]
    end

    return db[instanceId] and db[instanceId][bossKey] and db[instanceId][bossKey][spellId]
end

local function GetRaidDebuffCurationData(instanceId, bossId, spellId)
    local entry = GetRaidDebuffCurationEntry(instanceId, bossId, spellId)

    return {
        ["status"] = entry and entry["status"] or "review",
        ["suggestedOrder"] = entry and entry["suggestedOrder"] or nil,
        ["note"] = entry and entry["note"] or nil,
        ["explicit"] = entry ~= nil,
    }
end

local function CleanupRaidDebuffCuration(instanceId, bossId, spellId)
    local db = EnsureRaidDebuffsCurationDB()
    local bossKey = NormalizeCurationBossId(instanceId, bossId)
    local entry = db[instanceId] and db[instanceId][bossKey] and db[instanceId][bossKey][spellId]
    if not entry then return end

    if (not entry["status"] or entry["status"] == "review") and not entry["suggestedOrder"] and not entry["note"] then
        db[instanceId][bossKey][spellId] = nil

        if not next(db[instanceId][bossKey]) then
            db[instanceId][bossKey] = nil
        end

        if not next(db[instanceId]) then
            db[instanceId] = nil
        end
    end
end

local function SetRaidDebuffCurationField(instanceId, bossId, spellId, key, value)
    local shouldCreate = value ~= nil and value ~= "" and not (key == "status" and value == "review")
    local entry = GetRaidDebuffCurationEntry(instanceId, bossId, spellId, shouldCreate)

    if not entry then return GetRaidDebuffCurationData(instanceId, bossId, spellId) end

    if key == "note" then
        value = strtrim(tostring(value or ""))
        entry[key] = value ~= "" and value or nil
    elseif key == "suggestedOrder" then
        value = tonumber(value)
        entry[key] = value and value > 0 and floor(value) or nil
    elseif key == "status" then
        entry[key] = value ~= "review" and value or nil
    else
        entry[key] = value
    end

    CleanupRaidDebuffCuration(instanceId, bossId, spellId)
    return GetRaidDebuffCurationData(instanceId, bossId, spellId)
end

local function GetRaidDebuffCurationStatusInfo(status)
    return curationStatusInfo[status] or curationStatusInfo["review"]
end

local function GetSelectedBossKey()
    return isGeneral and "general" or loadedBoss
end

local function BuildRaidDebuffCurationReport(instanceId, bossId)
    local bossKey = NormalizeCurationBossId(instanceId, bossId)
    local bossTable = loadedDebuffs[instanceId] and loadedDebuffs[instanceId][bossKey]
    local instanceName = instanceIdToName[instanceId] or tostring(instanceId)
    local bossName = bossKey == "general" and bossIdToName[0] or (bossIdToName[bossKey] or tostring(bossKey))

    if not bossTable then
        return ("Raid Debuff Curation Report\n\nInstance: %s\nBoss: %s\n\nNo debuffs loaded for this context."):format(instanceName, bossName)
    end

    local lines = {
        "Raid Debuff Curation Report",
        "",
        "Instance: " .. instanceName,
        "Boss: " .. bossName,
        "",
    }
    local counts = {
        ["review"] = 0,
        ["confirmed"] = 0,
        ["trash"] = 0,
        ["non_debuff"] = 0,
        ["ignore"] = 0,
    }

    local function AddSpellLine(spellId, order)
        local data = GetRaidDebuffCurationData(instanceId, bossKey, spellId)
        local info = GetRaidDebuffCurationStatusInfo(data["status"])
        local spellName = F.GetSpellInfo(spellId) or tostring(spellId)
        counts[data["status"]] = (counts[data["status"]] or 0) + 1

        tinsert(lines, ("[%s] %s (%s)"):format(info["text"], spellName, spellId))
        tinsert(lines, ("Current order: %s"):format(order > 0 and order or "disabled"))

        if data["suggestedOrder"] then
            tinsert(lines, ("Suggested order: %d"):format(data["suggestedOrder"]))
        end

        if data["note"] then
            tinsert(lines, "Note: " .. data["note"])
        end

        tinsert(lines, "")
    end

    for _, spell in ipairs(bossTable["enabled"] or {}) do
        AddSpellLine(spell["id"], spell["order"] or 0)
    end

    for _, spell in ipairs(bossTable["disabled"] or {}) do
        AddSpellLine(spell["id"], 0)
    end

    table.insert(lines, 6, ("Review: %d  Confirmed: %d  Trash: %d  Non-Debuff: %d  Ignore: %d"):format(
        counts["review"],
        counts["confirmed"],
        counts["trash"],
        counts["non_debuff"],
        counts["ignore"]
    ))

    return table.concat(lines, "\n")
end

local function LoadDB(instanceId, bossId, bossTable)
    if not loadedDebuffs[instanceId][bossId] then loadedDebuffs[instanceId][bossId] = {["enabled"]={}, ["disabled"]={}} end
    -- load from db and set its order
    for spellId, sTable in pairs(bossTable) do
        local t = {["id"] = spellId}
        for _, index in pairs(indices) do
            t[index] = sTable[index]
        end
        if sTable["order"] == 0 then
            tinsert(loadedDebuffs[instanceId][bossId]["disabled"], t)
        else
            loadedDebuffs[instanceId][bossId]["enabled"][sTable["order"]] = t
        end
    end
end

local function LoadBuiltIn(instanceId, bossId, bossTable)
    if not loadedDebuffs[instanceId][bossId] then loadedDebuffs[instanceId][bossId] = {["enabled"]={}, ["disabled"]={}} end
    -- load
    for i, spellId in pairs(bossTable) do
        if not (CellDB["raidDebuffs"][instanceId] and CellDB["raidDebuffs"][instanceId][bossId] and CellDB["raidDebuffs"][instanceId][bossId][abs(tonumber(spellId))]) then
            -- NOTE: is built-in and not modified
            if type(spellId) == "string" then --* track by id
                if tonumber(spellId) < 0 then
                    tinsert(loadedDebuffs[instanceId][bossId]["disabled"], {["id"]=abs(tonumber(spellId)), ["order"]=0, ["trackByID"]=true, ["condition"]={"None"}, ["built-in"]=true})
                else
                    F.TInsert(loadedDebuffs[instanceId][bossId]["enabled"], {["id"]=abs(tonumber(spellId)), ["order"]=#loadedDebuffs[instanceId][bossId]["enabled"]+1, ["trackByID"]=true, ["condition"]={"None"}, ["built-in"]=true})
                end
            elseif spellId < 0 then --* disabled by default
                tinsert(loadedDebuffs[instanceId][bossId]["disabled"], {["id"]=abs(spellId), ["order"]=0, ["condition"]={"None"}, ["built-in"]=true})
            else
                F.TInsert(loadedDebuffs[instanceId][bossId]["enabled"], {["id"]=spellId, ["order"]=#loadedDebuffs[instanceId][bossId]["enabled"]+1, ["condition"]={"None"}, ["built-in"]=true})
            end
        else
            -- NOTE: exists in both CellDB and built-in, mark it as built-in (not deletable)
            local found
            -- find in loadedDebuffs
            for _, sTable in pairs(loadedDebuffs[instanceId][bossId]["enabled"]) do
                if sTable["id"] == abs(tonumber(spellId)) then
                    found = true
                    sTable["built-in"] = true
                    break
                end
            end
            -- check disabled if not found
            if not found then
                for _, sTable in pairs(loadedDebuffs[instanceId][bossId]["disabled"]) do
                    if sTable["id"] == abs(tonumber(spellId)) then
                        sTable["built-in"] = true
                        break
                    end
                end
            end
        end
    end
end

local function CheckOrders(instanceId, bossId, bossTable)
    local currentN, correctN = #bossTable["enabled"], F.Getn(bossTable["enabled"])
    if currentN ~= correctN then -- missing some debuffs, maybe deleted from built-in
        -- texplore(bossTable)
        F.Debug("|cffff2222FIX MISSING DEBUFFS|r", instanceId, bossId)
        local temp = {}
        for _, sTable in pairs(bossTable["enabled"]) do
            tinsert(temp, sTable)
        end
        for k, sTable in ipairs(temp) do
            if sTable["order"] ~= k then
                -- fix loadedDebuffs
                sTable["order"] = k
                -- fix db
                if CellDB["raidDebuffs"][instanceId] and CellDB["raidDebuffs"][instanceId][bossId] and CellDB["raidDebuffs"][instanceId][bossId][sTable["id"]] then
                    CellDB["raidDebuffs"][instanceId][bossId][sTable["id"]]["order"] = k
                end
            end
        end
        bossTable["enabled"] = temp
    end
end

local function LoadDebuffs()
    -- check db
    for instanceId, iTable in pairs(CellDB["raidDebuffs"]) do
        if not loadedDebuffs[instanceId] then loadedDebuffs[instanceId] = {} end

        for bossId, bTable in pairs(iTable) do
            LoadDB(instanceId, bossId, bTable)
        end
    end

    -- check built-in
    for instanceId, iTable in pairs(unsortedDebuffs) do
        if not loadedDebuffs[instanceId] then loadedDebuffs[instanceId] = {} end

        for bossId, bTable in pairs(iTable) do
            LoadBuiltIn(instanceId, bossId, bTable)
        end
    end

    -- check orders
    for instanceId, iTable in pairs(loadedDebuffs) do
        for bossId, bTable in pairs(iTable) do
            CheckOrders(instanceId, bossId, bTable)
        end
    end

    -- texplore(loadedDebuffs[477]) -- 悬槌堡
end

-- Fill in instances from unsortedDebuffs that weren't found by the EJ API.
-- This can happen when new raids/dungeons aren't yet classified in the EJ.
local function FillMissingInstances()
    if not unsortedDebuffs then return end

    local latestTierName = tierNames[#tierNames]
    if not latestTierName or not encounterJournalList[latestTierName] then return end

    for instanceId in pairs(unsortedDebuffs) do
        if not instanceIdToName[instanceId] then
            -- This instance wasn't loaded by EJ_GetInstanceByIndex; try direct lookup
            local name, _, _, image = EJ_GetInstanceInfo(instanceId)
            if name then
                local instanceTable = {["name"]=name, ["id"]=instanceId, ["image"]=image, ["bosses"]={}}
                LoadBossList(instanceId, instanceTable["bosses"])
                tinsert(encounterJournalList[latestTierName], instanceTable)
                local iIndex = #encounterJournalList[latestTierName]
                instanceNameMapping[name] = latestTierName..":"..iIndex..":"..instanceId
                instanceIdToName[instanceId] = name
            end
        end
    end
end

local function UpdateRaidDebuffs()
    LoadList()
    FillMissingInstances()
    -- LoadDungeonsForCurrentSeason()
    LoadDebuffs()
end
Cell.RegisterCallback("UpdateRaidDebuffs", "RaidDebuffsTab_UpdateRaidDebuffs", UpdateRaidDebuffs)

-------------------------------------------------
-- top widgets
-------------------------------------------------
local expansionDropdown, showCurrentBtn

local function CreateCurationReportFrame()
    curationReportFrame = CreateFrame("Frame", "CellOptionsFrame_RaidDebuffsCurationReport", Cell.frames.raidDebuffsTab, "BackdropTemplate")
    curationReportFrame:Hide()
    Cell.StylizeFrame(curationReportFrame, nil, Cell.GetAccentColorTable())
    curationReportFrame:EnableMouse(true)
    curationReportFrame:SetFrameLevel(Cell.frames.raidDebuffsTab:GetFrameLevel() + 50)
    P.Size(curationReportFrame, 430, 250)
    curationReportFrame:SetPoint("TOPLEFT", P.Scale(1), -100)

    if not Cell.frames.raidDebuffsTab.mask then
        Cell.CreateMask(Cell.frames.raidDebuffsTab, nil, {1, -1, -1, 1})
        Cell.frames.raidDebuffsTab.mask:Hide()
    end

    curationReportFrame:SetScript("OnHide", function()
        if Cell.frames.raidDebuffsTab.mask then
            Cell.frames.raidDebuffsTab.mask:Hide()
        end
    end)

    local closeBtn = Cell.CreateButton(curationReportFrame, "×", "red", {18, 18}, false, false, "CELL_FONT_SPECIAL", "CELL_FONT_SPECIAL")
    closeBtn:SetPoint("TOPRIGHT", -5, -1)
    closeBtn:SetScript("OnClick", function()
        curationReportFrame:Hide()
    end)

    curationReportTitle = curationReportFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_CLASS")
    curationReportTitle:SetPoint("TOPLEFT", 5, -5)
    curationReportTitle:SetText("Raid Debuff Curation")

    curationReportContext = curationReportFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    curationReportContext:SetPoint("TOPLEFT", curationReportTitle, "BOTTOMLEFT", 0, -5)
    curationReportContext:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -5, 0)
    curationReportContext:SetJustifyH("LEFT")

    curationReportTextArea = Cell.CreateScrollEditBox(curationReportFrame)
    curationReportTextArea:SetPoint("TOPLEFT", 5, -45)
    curationReportTextArea:SetPoint("BOTTOMRIGHT", -10, 5)
    curationReportTextArea.eb:SetAutoFocus(false)
end

local function ShowRaidDebuffsCurationReport(instanceId, bossId)
    if not instanceId then return end

    if not curationReportFrame then
        CreateCurationReportFrame()
    end

    local bossKey = NormalizeCurationBossId(instanceId, bossId)
    local instanceName = instanceIdToName[instanceId] or tostring(instanceId)
    local bossName = bossKey == "general" and bossIdToName[0] or (bossIdToName[bossKey] or tostring(bossKey))

    Cell.frames.raidDebuffsTab.mask:Show()
    curationReportContext:SetText(("Instance: %s\nBoss: %s"):format(instanceName, bossName))
    curationReportTextArea.eb:SetText(BuildRaidDebuffCurationReport(instanceId, bossKey))
    curationReportTextArea.eb:ClearFocus()
    curationReportTextArea.scrollFrame:ResetScroll()
    curationReportFrame:Show()
end

local function OpenInstanceBoss(instanceName, bossName)
    if not instanceName or not instanceNameMapping[instanceName] then return end

    local eName, iIndex, iId = F.SplitToNumber(":", instanceNameMapping[instanceName])
    expansionDropdown:SetSelected(eName)
    LoadExpansion(eName)
    if loadedInstance == iId and not bossName then
        -- current instance already shown, but instance debuffs updated, force refresh
        ShowBosses(instanceButtons[iIndex].id, true)
    else
        instanceButtons[iIndex]:Click()
    end
    -- scroll
    if iIndex > 9 then
        RaidDebuffsTab_Instances.scrollFrame:SetVerticalScroll((iIndex-9)*19)
    end

    if bossName then
        local bIndex

        if bossName == "general" then
            bIndex = 0
        else
            for i, boss in pairs(encounterJournalList[eName][iIndex]["bosses"]) do
                if bossName == boss["name"] then
                    -- boss found
                    bIndex = i
                    break
                end
            end
        end

        if bIndex then
            C_Timer.After(0.25, function()
                if bIndex == 0 then
                    if loadedBoss == iId then -- general already shown, just reload
                        ShowDebuffs(bossButtons[bIndex].id, 1)
                    else
                        bossButtons[bIndex]:Click()
                    end
                else
                    local bId, _ = F.SplitToNumber("-", bossButtons[bIndex].id)
                    if loadedBoss == bId then
                        ShowDebuffs(bossButtons[bIndex].id, 1)
                    else
                        bossButtons[bIndex]:Click()
                    end
                end
                -- scroll
                if bIndex > 10 then
                    RaidDebuffsTab_Bosses.scrollFrame:SetVerticalScroll((bIndex-10)*19)
                end
            end)
        end
    end
end

local function CreateWidgets()
    -- expansion dropdown
    expansionDropdown = Cell.CreateDropdown(debuffsTab, 269)
    expansionDropdown:SetPoint("TOPLEFT", 5, -7)

    local expansionItems = {}
    for i = EJ_GetNumTiers(), 1, -1 do
        local eName = EJ_GetTierInfo(i)
        local ejList = encounterJournalList[eName]
        tinsert(expansionItems, {
            ["text"] = eName,
            ["disabled"] = not ejList or #ejList == 0,
            ["onClick"] = function()
                LoadExpansion(eName)
            end,
        })
    end

    -- add Current Season to the top
    -- tinsert(expansionItems, 1, {
    --     ["text"] = L["Current Season"],
    --     ["onClick"] = function()
    --         LoadExpansion("Current Season")
    --     end,
    -- })
    expansionDropdown:SetItems(expansionItems)

    -- help
    local helpBtn = Cell.CreateButton(debuffsTab, "", "accent-hover", {33, 20})
    helpBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\info2.tga", {16, 16}, {"CENTER", 0, 0})
    helpBtn:SetPoint("TOPRIGHT", -5, -7)
    helpBtn:HookScript("OnEnter", function()
        CellTooltip:SetOwner(helpBtn, "ANCHOR_NONE")
        CellTooltip:SetPoint("TOPLEFT", helpBtn, "TOPRIGHT", 6, 0)
        CellTooltip:AddLine(L["Want to help improve Raid Debuffs?"])
        CellTooltip:AddLine("|cffffffffUse the curation fields to mark confirmed, trash, or non-debuff spells.")
        CellTooltip:AddLine("|cffffffffOpen the curation report to review notes and suggested priorities for the current boss.")
        CellTooltip:Show()
    end)
    helpBtn:HookScript("OnLeave", function()
        CellTooltip:Hide()
    end)

    -- current instance button
    local showCurrentBtn = Cell.CreateButton(debuffsTab, "", "accent-hover", {34, 20}, nil, nil, nil, nil, nil, L["Show Current Instance"])
    -- showCurrentBtn:SetPoint("TOPRIGHT", -5, -7)
    showCurrentBtn:SetPoint("TOPRIGHT", helpBtn, "TOPLEFT", P.Scale(-5), 0)
    showCurrentBtn:SetTexture("DungeonSkull", {18, 18}, {"CENTER", 0, 0}, true)

    showCurrentBtn:SetScript("OnClick", function()
        if IsInInstance() then
            OpenInstanceBoss(GetInstanceInfo())
        end
    end)
    Cell.RegisterForCloseDropdown(showCurrentBtn)

    -- import/export button
    local exportBtn = Cell.CreateButton(debuffsTab, "", "accent-hover", {33, 20}, nil, nil, nil, nil, nil, L["Export"])
    exportBtn:SetPoint("TOPRIGHT", showCurrentBtn, "TOPLEFT", P.Scale(-5), 0)
    exportBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\export.blp", {16, 16}, {"CENTER", 0, 0})
    exportBtn:SetScript("OnClick", function()
        F.ShowRaidDebuffsExportFrame(loadedInstance, loadedInstance == loadedBoss and "general" or loadedBoss)
    end)

    local importBtn = Cell.CreateButton(debuffsTab, "", "accent-hover", {33, 20}, nil, nil, nil, nil, nil, L["Import"])
    importBtn:SetPoint("TOPRIGHT", exportBtn, "TOPLEFT", P.Scale(-5), 0)
    importBtn:SetTexture("Interface\\AddOns\\Cell\\Media\\Icons\\import.blp", {16, 16}, {"CENTER", 0, 0})
    importBtn:SetScript("OnClick", function()
        F.ShowRaidDebuffsImportFrame()
    end)

    -- tips
    local tips = Cell.CreateScrollTextFrame(debuffsTab, "|cffb7b7b7"..L["RAID_DEBUFFS_TIPS"], 0.02, nil, 2)
    tips:SetPoint("BOTTOMLEFT", 5, 3)
    tips:SetPoint("BOTTOMRIGHT", -5, 3)
end

-------------------------------------------------
-- list button onEnter, onLeave
-------------------------------------------------
local function SetOnEnterLeave(frame)
    frame:SetScript("OnEnter", function()
        frame:SetBackdropBorderColor(unpack(Cell.GetAccentColorTable()))
        frame.scrollFrame.scrollbar:SetBackdropBorderColor(unpack(Cell.GetAccentColorTable()))
        -- frame.scrollFrame.scrollThumb:SetBackdropBorderColor(0, 0, 0, 0.5)
    end)
    frame:SetScript("OnLeave", function()
        frame:SetBackdropBorderColor(0, 0, 0, 1)
        frame.scrollFrame.scrollbar:SetBackdropBorderColor(0, 0, 0, 1)
        frame.scrollFrame.scrollThumb:SetBackdropBorderColor(0, 0, 0, 1)
    end)
end

-------------------------------------------------
-- instances frame
-------------------------------------------------
local function CreateInstanceFrame()
    instancesFrame = Cell.CreateFrame("RaidDebuffsTab_Instances", debuffsTab, 127, 229)
    instancesFrame:SetPoint("TOPLEFT", expansionDropdown, "BOTTOMLEFT", 0, -5)
    -- instancesFrame:SetPoint("BOTTOMLEFT", 5, 5)
    instancesFrame:Show()
    Cell.CreateScrollFrame(instancesFrame)
    instancesFrame.scrollFrame:SetScrollStep(19)
    SetOnEnterLeave(instancesFrame)

    -- instance image frame
    local imageFrame = Cell.CreateFrame("RaidDebuffsTab_InstanceImage", debuffsTab, 128, 64, true)
    imageFrame.bg = imageFrame:CreateTexture(nil, "BACKGROUND")
    imageFrame.bg:SetTexture(Cell.vars.whiteTexture)
    imageFrame.bg:SetGradient("HORIZONTAL", CreateColor(0.1, 0.1, 0.1, 0), CreateColor(0.1, 0.1, 0.1, 1))

    imageFrame.tex = imageFrame:CreateTexture(nil, "ARTWORK")
    imageFrame.tex:SetSize(121, 64)
    imageFrame.tex:SetPoint("TOPRIGHT", -1, -1)

    local instanceNameText = imageFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    instanceNameText:SetPoint("TOPLEFT", imageFrame, "BOTTOMLEFT", 0, -1)
    instanceNameText:SetPoint("TOPRIGHT", imageFrame, "BOTTOMRIGHT", 0, -1)

    imageFrame.bg:SetPoint("TOPLEFT", imageFrame, -2, 0)
    imageFrame.bg:SetPoint("BOTTOMRIGHT", instanceNameText, 0, -1)

    ShowInstanceImage = function(image, b)
        imageFrame.tex:SetTexture(image)
        imageFrame.tex:SetTexCoord(0.015, 0.666, 0.03, 0.72)
        instanceNameText:SetText(b:GetFontString():GetText())

        imageFrame:ClearAllPoints()
        imageFrame:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", -5, 2)
        imageFrame:Show()
    end

    HideInstanceImage = function()
        imageFrame:Hide()
    end
end

ShowInstances = function(eName)
    instancesFrame.scrollFrame:ResetScroll()

    for i, iTable in pairs(encounterJournalList[eName]) do
        if not instanceButtons[i] then
            instanceButtons[i] = Cell.CreateButton(instancesFrame.scrollFrame.content, iTable["name"], "transparent-accent", {20, 20})
        else
            instanceButtons[i]:SetText(iTable["name"])
            instanceButtons[i]:Show()
        end

        instanceButtons[i].id = iTable["id"].."-"..i -- send instanceId-instanceIndex to ShowBosses

        -- open encounter journal
        instanceButtons[i]:SetScript("OnDoubleClick", function()
            OpenEncounterJournal(iTable["id"])
        end)

        if i == 1 then
            instanceButtons[i]:SetPoint("TOPLEFT")
        else
            instanceButtons[i]:SetPoint("TOPLEFT", instanceButtons[i-1], "BOTTOMLEFT", 0, 1)
        end
        instanceButtons[i]:SetPoint("RIGHT")
    end

    local n = #encounterJournalList[eName]

    -- update scrollFrame content height
    instancesFrame.scrollFrame:SetContentHeight(20, n, -1)

    -- hide unused instance buttons
    for i = n+1, #instanceButtons do
        instanceButtons[i]:Hide()
        instanceButtons[i]:ClearAllPoints()
    end

    -- set onclick
    Cell.CreateButtonGroup(instanceButtons, function(id, b)
        if IsShiftKeyDown() and b:IsMouseOver() then -- NOTE: sharing
            -- print("instance:"..iId, "bossId:"..id)
            local editbox = GetCurrentKeyBoardFocus()
            if editbox then
                local iId, iIndex = F.SplitToNumber("-", id)
                editbox:SetText("[Cell.Debuffs: "..instanceIdToName[iId].." - "..Cell.vars.playerNameFull.."]")
            end
        elseif IsAltKeyDown() and b:IsMouseOver() then -- NOTE: reset
            local iId, iIndex = F.SplitToNumber("-", id)
            local popup = Cell.CreateConfirmPopup(Cell.frames.raidDebuffsTab, 200, L["Reset debuffs?"].."\n"..instanceIdToName[iId], function(self)
                -- update
                F.UpdateRaidDebuffs(iId, nil, nil, instanceIdToName[iId])
                -- reload
                C_Timer.After(0.25, function()
                    ShowBosses(id, true)
                end)
            end, nil, true)
            popup:SetPoint("TOPLEFT", 100, -170)
        end
        ShowBosses(id)
    end, nil, nil, function(b)
        local _, iIndex = F.SplitToNumber("-", b.id)
        ShowInstanceImage(encounterJournalList[loadedExpansion][iIndex]["image"], b)

        instancesFrame:GetScript("OnEnter")()
    end, function(b)
        HideInstanceImage()
        instancesFrame:GetScript("OnLeave")()
    end)

    -- show the first boss
    instanceButtons[1]:Click()
end

-------------------------------------------------
-- bosses frame
-------------------------------------------------
local function CreateBossesFrame()
    bossesFrame = Cell.CreateFrame("RaidDebuffsTab_Bosses", debuffsTab, 127, 229)
    bossesFrame:SetPoint("TOPLEFT", instancesFrame, "BOTTOMLEFT", 0, -5)
    -- bossesFrame:SetPoint("BOTTOMLEFT", 5, 5)
    bossesFrame:Show()
    Cell.CreateScrollFrame(bossesFrame)
    bossesFrame.scrollFrame:SetScrollStep(19)
    SetOnEnterLeave(bossesFrame)

    -- boss image frame
    local imageFrame = Cell.CreateFrame("RaidDebuffsTab_BossImage", debuffsTab, 128, 64, true)
    imageFrame.bg = imageFrame:CreateTexture(nil, "BACKGROUND")
    imageFrame.bg:SetTexture(Cell.vars.whiteTexture)
    imageFrame.bg:SetGradient("HORIZONTAL", CreateColor(0.1, 0.1, 0.1, 0), CreateColor(0.1, 0.1, 0.1, 1))
    -- imageFrame.bg:SetAllPoints(imageFrame)

    imageFrame.tex = imageFrame:CreateTexture(nil, "ARTWORK")
    imageFrame.tex:SetSize(128, 64)
    imageFrame.tex:SetPoint("TOPRIGHT")

    local bossNameText = imageFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    bossNameText:SetPoint("TOPLEFT", imageFrame, "BOTTOMLEFT", 0, -1)
    bossNameText:SetPoint("TOPRIGHT", imageFrame, "BOTTOMRIGHT", 0, -1)

    imageFrame.bg:SetPoint("TOPLEFT", imageFrame, -2, 0)
    imageFrame.bg:SetPoint("BOTTOMRIGHT", bossNameText, 0, -1)

    ShowBossImage = function(image, b)
        imageFrame.tex:SetTexture(image)
        bossNameText:SetText(b:GetFontString():GetText())

        imageFrame:ClearAllPoints()
        imageFrame:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", -5, 0)
        imageFrame:Show()
    end

    HideBossImage = function()
        imageFrame:Hide()
    end
end

ShowBosses = function(instanceId, forceRefresh)
    local iId, iIndex = F.SplitToNumber("-", instanceId)

    if loadedInstance == iId and not forceRefresh then return end
    loadedInstance = iId

    bossesFrame.scrollFrame:ResetScroll()

    -- instance general debuff
    if not bossButtons[0] then
        bossButtons[0] = Cell.CreateButton(bossesFrame.scrollFrame.content, L["General"], "transparent-accent", {20, 20})
        bossButtons[0]:SetPoint("TOPLEFT")
        bossButtons[0]:SetPoint("RIGHT")
    end
    bossButtons[0].id = iId

    -- bosses
    for i, bTable in pairs(encounterJournalList[loadedExpansion][iIndex]["bosses"]) do
        if not bossButtons[i] then
            bossButtons[i] = Cell.CreateButton(bossesFrame.scrollFrame.content, bTable["name"], "transparent-accent", {20, 20})
        else
            bossButtons[i]:SetText(bTable["name"])
            bossButtons[i]:Show()
        end

        -- send bossId-bossIndex to ShowDebuffs
        -- bossIndex is used to show boss image when hover on boss button
        bossButtons[i].id = bTable["id"].."-"..i

        bossButtons[i]:SetPoint("TOPLEFT", bossButtons[i-1], "BOTTOMLEFT", 0, 1)
        bossButtons[i]:SetPoint("RIGHT")
    end

    local n = #encounterJournalList[loadedExpansion][iIndex]["bosses"]

    -- update scrollFrame content height
    bossesFrame.scrollFrame:SetContentHeight(20, n+1, -1)

    -- hide unused instance buttons
    for i = n+1, #bossButtons do
        bossButtons[i]:Hide()
        bossButtons[i]:ClearAllPoints()
    end

    -- set onclick/onenter
    Cell.CreateButtonGroup(bossButtons, function(id, b)
        if IsShiftKeyDown() and b:IsMouseOver() then -- NOTE: sharing
            -- print("instance:"..iId, "bossId:"..id)
            local editbox = GetCurrentKeyBoardFocus()
            if editbox then
                if id == iId then -- general
                    editbox:SetText("[Cell.Debuffs: "..bossIdToName[0].." ("..instanceIdToName[iId]..") - "..Cell.vars.playerNameFull.."]")
                else
                    local bId = F.SplitToNumber("-", id)
                    editbox:SetText("[Cell.Debuffs: "..bossIdToName[bId].." ("..instanceIdToName[iId]..") - "..Cell.vars.playerNameFull.."]")
                end
            end
        elseif IsAltKeyDown() and b:IsMouseOver() then -- NOTE: reset
            local text
            if id == iId then -- general
                text = bossIdToName[0]
            else
                local bId = F.SplitToNumber("-", id)
                text = bossIdToName[bId]
            end

            local popup = Cell.CreateConfirmPopup(Cell.frames.raidDebuffsTab, 200, L["Reset debuffs?"].."\n"..text, function(self)
                local which
                if id == iId then -- general
                    which = bossIdToName[0].." ("..instanceIdToName[iId]..")"
                    -- update
                    F.UpdateRaidDebuffs(iId, "general", nil, which)
                    -- reload
                    C_Timer.After(0.25, function()
                        ShowDebuffs(id, 1)
                    end)
                else
                    local bId, index = F.SplitToNumber("-", id)
                    which = bossIdToName[bId].." ("..instanceIdToName[iId]..")"
                    -- update
                    F.UpdateRaidDebuffs(iId, bId, nil, which)
                    -- reload
                    C_Timer.After(0.25, function()
                        ShowDebuffs(id, 1)
                    end)
                end
            end, nil, true)
            popup:SetPoint("TOPLEFT", 100, -170)
        end
        ShowDebuffs(id)
    end, nil, nil, function(b)
        if b.id ~= iId then -- not General
            local _, bIndex = F.SplitToNumber("-", b.id)
            ShowBossImage(encounterJournalList[loadedExpansion][iIndex]["bosses"][bIndex]["image"], b)
        end
        bossesFrame:GetScript("OnEnter")()
    end, function(b)
        HideBossImage()
        bossesFrame:GetScript("OnLeave")()
    end)

    -- show General by default
    if forceRefresh then
        -- if general is already shown
        if loadedBoss == iId then
            ShowDebuffs(iId, 1)
        else
            bossButtons[0]:Click()
        end
    else
        bossButtons[0]:Click()
    end
end

-------------------------------------------------
-- debuff list frame
-------------------------------------------------
local dragged, delete

local function CreateDebuffsFrame()
    debuffListFrame = Cell.CreateFrame("RaidDebuffsTab_Debuffs", debuffsTab, 137, 438)
    debuffListFrame:SetPoint("TOPLEFT", instancesFrame, "TOPRIGHT", 5, 0)
    debuffListFrame:Show()
    Cell.CreateScrollFrame(debuffListFrame)
    debuffListFrame.scrollFrame:SetScrollStep(19)
    SetOnEnterLeave(debuffListFrame)

    local create = Cell.CreateButton(debuffsTab, L["Create"], "accent-hover", {66, 20})
    create:SetPoint("TOPLEFT", debuffListFrame, "BOTTOMLEFT", 0, -5)
    create:SetScript("OnClick", function()
        local popup = Cell.CreateConfirmPopup(debuffsTab, 200, L["Create new debuff (id)"], function(self)
            local id = tonumber(self.editBox:GetText()) or 0
            local name = F.GetSpellInfo(id)
            if not name then
                F.Print(L["Invalid spell id."])
                return
            end
            -- check whether already exists
            if currentBossTable then
                for _, sTable in pairs(currentBossTable["enabled"]) do
                    if sTable["id"] == id then
                        F.Print(L["Debuff already exists."])
                        return
                    end
                end
                for _, sTable in pairs(currentBossTable["disabled"]) do
                    if sTable["id"] == id then
                        F.Print(L["Debuff already exists."])
                        return
                    end
                end
            end

            -- update db
            if not CellDB["raidDebuffs"][loadedInstance] then CellDB["raidDebuffs"][loadedInstance] = {} end
            if isGeneral then
                if not CellDB["raidDebuffs"][loadedInstance]["general"] then CellDB["raidDebuffs"][loadedInstance]["general"] = {} end
                CellDB["raidDebuffs"][loadedInstance]["general"][id] = {
                    ["order"] = currentBossTable and #currentBossTable["enabled"] + 1 or 1,
                    ["trackByID"] = false,
                    ["condition"] = {"None"},
                }
            else
                if not CellDB["raidDebuffs"][loadedInstance][loadedBoss] then CellDB["raidDebuffs"][loadedInstance][loadedBoss] = {} end
                CellDB["raidDebuffs"][loadedInstance][loadedBoss][id] = {
                    ["order"] = currentBossTable and #currentBossTable["enabled"] + 1 or 1,
                    ["trackByID"] = false,
                    ["condition"] = {"None"},
                }
            end
            -- update loadedDebuffs
            if currentBossTable then
                tinsert(currentBossTable["enabled"], {["id"]=id, ["order"]=#currentBossTable["enabled"]+1, ["condition"]={"None"}})
                ShowDebuffs(isGeneral and loadedInstance or loadedBoss, #currentBossTable["enabled"])
            else -- no boss table
                if not loadedDebuffs[loadedInstance] then loadedDebuffs[loadedInstance] = {} end
                loadedDebuffs[loadedInstance][isGeneral and "general" or loadedBoss] = {["enabled"]={{["id"]=id, ["order"]=1, ["condition"]={"None"}}}, ["disabled"]={}}
                ShowDebuffs(isGeneral and loadedInstance or loadedBoss, 1)
            end
            -- notify debuff list changed
            Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
            CellSpellTooltip:Hide()
        end, function()
            CellSpellTooltip:Hide()
        end, true, true)
        popup.editBox:SetNumeric(true)
        popup.editBox:SetScript("OnTextChanged", function()
            local spellId = tonumber(popup.editBox:GetText())
            if not spellId then
                CellSpellTooltip:Hide()
                popup.button1:SetEnabled(false)
                return
            end

            local name, icon = F.GetSpellInfo(spellId)
            if not name then
                CellSpellTooltip:Hide()
                popup.button1:SetEnabled(false)
                return
            end

            popup.button1:SetEnabled(true)
            CellSpellTooltip:SetOwner(popup, "ANCHOR_NONE")
            CellSpellTooltip:SetPoint("TOPLEFT", popup, "BOTTOMLEFT", 0, -1)
            CellSpellTooltip:SetSpellByID(spellId, icon)
            CellSpellTooltip:Show()
        end)
        popup:SetPoint("TOPLEFT", 117, -170)
    end)

    delete = Cell.CreateButton(debuffsTab, L["Delete"], "accent-hover", {66, 20})
    delete:SetPoint("LEFT", create, "RIGHT", 5, 0)
    delete:SetEnabled(false)
    delete:SetScript("OnClick", function()
        local text = selectedSpellName.." ["..selectedSpellId.."]".."\n".."|T"..selectedSpellIcon..":12:12:0:0:12:12:1:11:1:11|t"
        local popup = Cell.CreateConfirmPopup(debuffsTab, 200, L["Delete debuff?"].."\n"..text, function()
            -- update db
            local index = isGeneral and "general" or loadedBoss
            local order = CellDB["raidDebuffs"][loadedInstance][index][selectedSpellId]["order"]
            CellDB["raidDebuffs"][loadedInstance][index][selectedSpellId] = nil
            for sId, sTable in pairs(CellDB["raidDebuffs"][loadedInstance][index]) do
                if sTable["order"] > order then
                    sTable["order"] = sTable["order"] - 1 -- update orders
                end
            end
            -- update loadedDebuffs
            local found
            for k, sTable in ipairs(currentBossTable["enabled"]) do
                if sTable["id"] == selectedSpellId then
                    found = true
                    tremove(currentBossTable["enabled"], k)
                    break
                end
            end
            if found then -- is enabled, update orders
                for i = selectedButtonIndex, #currentBossTable["enabled"] do
                    currentBossTable["enabled"][i]["order"] = currentBossTable["enabled"][i]["order"] - 1 -- update orders
                end
            end
            -- check disabled if not found
            if not found then
                for k, sTable in pairs(currentBossTable["disabled"]) do
                    if sTable["id"] == selectedSpellId then
                        tremove(currentBossTable["disabled"], k)
                        break
                    end
                end
            end
            -- reload
            if isGeneral then -- general
                ShowDebuffs(loadedInstance, 1)
            else
                ShowDebuffs(loadedBoss, 1)
            end
            -- notify debuff list changed
            Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
        end, nil, true)
        popup:SetPoint("TOPLEFT", 117, -170)
    end)

    -- dragged
    dragged = Cell.CreateFrame("RaidDebuffsTab_Dragged", debuffsTab, 20, 20)
    Cell.StylizeFrame(dragged, nil, Cell.GetAccentColorTable())
    dragged:SetFrameStrata("DIALOG")
    dragged:EnableMouse(false)
    dragged:SetMovable(true)
    dragged:SetToplevel(true)
    -- stick dragged to mouse
    dragged:SetScript("OnUpdate", function()
        local scale, x, y = dragged:GetEffectiveScale(), GetCursorPosition()
        dragged:ClearAllPoints()
        dragged:SetPoint("LEFT", nil, "BOTTOMLEFT", 5+x/scale, y/scale)
    end)
    -- icon
    dragged.icon = dragged:CreateTexture(nil, "ARTWORK")
    dragged.icon:SetSize(16, 16)
    dragged.icon:SetPoint("LEFT", 2, 0)
    dragged.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- text
    dragged.text = dragged:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    dragged.text:SetPoint("LEFT", dragged.icon, "RIGHT", 2, 0)
    dragged.text:SetPoint("RIGHT", -2, 0)
    dragged.text:SetJustifyH("LEFT")
    dragged.text:SetWordWrap(false)
end

local function RegisterForDrag(b)
    -- dragging
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        self:SetAlpha(0.5)
        dragged:SetWidth(self:GetWidth())
        dragged.icon:SetTexture(self.spellIcon)
        dragged.text:SetText(self:GetText())
        dragged:Show()
    end)
    b:SetScript("OnDragStop", function(self)
        self:SetAlpha(1)
        dragged:Hide()
        local newB = F.GetMouseFocus()
        -- move on a debuff button & not on currently moving button & not disabled
        if newB:GetParent() == debuffListFrame.scrollFrame.content and newB ~= self and newB.enabled then
            local temp, from, to = self, self.index, newB.index
            local moved = currentBossTable["enabled"][from]

            if self.index > newB.index then
                -- move up -> before newB
                -- update old next button's position
                if debuffButtons[self.index+1] and debuffButtons[self.index+1]:IsShown() then
                    debuffButtons[self.index+1]:ClearAllPoints()
                    debuffButtons[self.index+1]:SetPoint(unpack(self.point1))
                    debuffButtons[self.index+1]:SetPoint("RIGHT")
                    debuffButtons[self.index+1].point1 = F.Copy(self.point1)
                end
                -- update new self position
                self:ClearAllPoints()
                self:SetPoint(unpack(newB.point1))
                self:SetPoint("RIGHT")
                self.point1 = F.Copy(newB.point1)
                -- update new next's position
                newB:ClearAllPoints()
                newB:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, 1)
                newB:SetPoint("RIGHT")
                newB.point1 = {"TOPLEFT", self, "BOTTOMLEFT", 0, 1}
                -- update list & db
                if not CellDB["raidDebuffs"][loadedInstance] then CellDB["raidDebuffs"][loadedInstance] = {} end
                if not CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss] then CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss] = {} end
                for j = from, to, -1 do
                    if j == to then
                        debuffButtons[j] = temp
                        currentBossTable["enabled"][j] = moved
                        -- update db
                        if not CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss][debuffButtons[j].spellId] then
                            CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss][debuffButtons[j].spellId] = {
                                ["order"] = j,
                                ["trackByID"] = false,
                                ["condition"] = {"None"},
                            }
                        else
                            CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss][debuffButtons[j].spellId]["order"] = j
                        end
                    else
                        debuffButtons[j] = debuffButtons[j-1]
                        currentBossTable["enabled"][j] = currentBossTable["enabled"][j-1]
                        -- update db
                        if CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss][debuffButtons[j].spellId] then
                            CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss][debuffButtons[j].spellId]["order"] = j
                        end
                    end
                    debuffButtons[j].index = j
                    currentBossTable["enabled"][j]["order"] = j
                    debuffButtons[j].id = debuffButtons[j].spellId.."-"..j
                    -- update selectedButtonIndex
                    if debuffButtons[j].spellId == selectedSpellId then
                        selectedButtonIndex = j
                    end
                end
            else
                -- move down (after newB)
                -- update old next button's position
                if debuffButtons[self.index+1] and debuffButtons[self.index+1]:IsShown() then
                    debuffButtons[self.index+1]:ClearAllPoints()
                    debuffButtons[self.index+1]:SetPoint(unpack(self.point1))
                    debuffButtons[self.index+1]:SetPoint("RIGHT")
                    debuffButtons[self.index+1].point1 = F.Copy(self.point1)
                end
                -- update new self position
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", newB, "BOTTOMLEFT", 0, 1)
                self:SetPoint("RIGHT")
                self.point1 = {"TOPLEFT", newB, "BOTTOMLEFT", 0, 1}
                -- update new next button's position
                if debuffButtons[newB.index+1] and debuffButtons[newB.index+1]:IsShown() then
                    debuffButtons[newB.index+1]:ClearAllPoints()
                    debuffButtons[newB.index+1]:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, 1)
                    debuffButtons[newB.index+1]:SetPoint("RIGHT")
                    debuffButtons[newB.index+1].point1 = {"TOPLEFT", self, "BOTTOMLEFT", 0, 1}
                end
                -- update list & db
                if not CellDB["raidDebuffs"][loadedInstance] then CellDB["raidDebuffs"][loadedInstance] = {} end
                if not CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss] then CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss] = {} end
                for j = from, to do
                    if j == to then
                        debuffButtons[j] = temp
                        currentBossTable["enabled"][j] = moved
                        -- update db
                        if not CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss][debuffButtons[j].spellId] then
                            CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss][debuffButtons[j].spellId] = {
                                ["order"] = j,
                                ["trackByID"] = false,
                                ["condition"] = {"None"},
                            }
                        else
                            CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss][debuffButtons[j].spellId]["order"] = j
                        end
                    else
                        debuffButtons[j] = debuffButtons[j+1]
                        currentBossTable["enabled"][j] = currentBossTable["enabled"][j+1]
                        -- update db
                        if CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss][debuffButtons[j].spellId] then
                            CellDB["raidDebuffs"][loadedInstance][isGeneral and "general" or loadedBoss][debuffButtons[j].spellId]["order"] = j
                        end
                    end
                    debuffButtons[j].index = j
                    currentBossTable["enabled"][j]["order"] = j
                    debuffButtons[j].id = debuffButtons[j].spellId.."-"..j
                    -- update selectedButtonIndex
                    if debuffButtons[j].spellId == selectedSpellId then
                        selectedButtonIndex = j
                    end
                end
            end
            -- notify debuff list changed
            Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
        end
    end)
end

local function UnregisterForDrag(b)
    b:SetMovable(false)
    b:SetScript("OnDragStart", nil)
    b:SetScript("OnDragStop", nil)
end

local function ApplyDebuffButtonCuration(button, sTable)
    local curation = GetRaidDebuffCurationData(loadedInstance, GetSelectedBossKey(), sTable["id"])
    local info = GetRaidDebuffCurationStatusInfo(curation["status"])
    local r, g, b = unpack(info["color"])

    button.curationData = curation

    if curation["explicit"] then
        button.curationTag:SetText(info["tag"])
        button.curationTag:SetTextColor(r, g, b)
    else
        button.curationTag:SetText("")
    end

    if sTable["order"] == 0 then
        button:SetTextColor(0.4, 0.4, 0.4)
        UnregisterForDrag(button)
        button.enabled = nil
    else
        if curation["explicit"] and curation["status"] ~= "review" then
            button:SetTextColor(r, g, b)
        else
            button:SetTextColor(1, 1, 1)
        end
        RegisterForDrag(button)
        button.enabled = true
    end
end

local last
local function CreateDebuffButton(i, sTable)
    if not debuffButtons[i] then
        debuffButtons[i] = Cell.CreateButton(debuffListFrame.scrollFrame.content, " ", "transparent-accent", {20, 20})
        debuffButtons[i].index = i
        -- icon
        debuffButtons[i].icon = debuffButtons[i]:CreateTexture(nil, "ARTWORK")
        debuffButtons[i].icon:SetSize(16, 16)
        debuffButtons[i].icon:SetPoint("LEFT", 2, 0)
        debuffButtons[i].icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- update text position
        debuffButtons[i]:GetFontString():ClearAllPoints()
        debuffButtons[i]:GetFontString():SetPoint("LEFT", debuffButtons[i].icon, "RIGHT", 2, 0)
        debuffButtons[i].curationTag = debuffButtons[i]:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET_SMALL")
        debuffButtons[i].curationTag:SetPoint("RIGHT", -2, 0)
        debuffButtons[i]:GetFontString():SetPoint("RIGHT", debuffButtons[i].curationTag, "LEFT", -2, 0)
    end

    debuffButtons[i]:Show()

    local name, icon = F.GetSpellInfo(sTable["id"])
    if name then
        debuffButtons[i].icon:SetTexture(icon)
        debuffButtons[i].spellIcon = icon
        debuffButtons[i]:SetText(name)
    else
        debuffButtons[i].icon:SetTexture(134400)
        debuffButtons[i].spellIcon = 134400
        debuffButtons[i]:SetText(sTable["id"])
    end

    debuffButtons[i].spellId = sTable["id"]
    debuffButtons[i].spellTex = icon
    ApplyDebuffButtonCuration(debuffButtons[i], sTable)

    debuffButtons[i].id = sTable["id"].."-"..i -- send spellId-buttonIndex to ShowDetails

    debuffButtons[i]:ClearAllPoints()
    if last then
        debuffButtons[i]:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, 1)
        debuffButtons[i].point1 = {"TOPLEFT", last, "BOTTOMLEFT", 0, 1}
    else
        debuffButtons[i]:SetPoint("TOPLEFT")
        debuffButtons[i].point1 = {"TOPLEFT"}
    end
    debuffButtons[i]:SetPoint("RIGHT")
    debuffButtons[i].point2 = "RIGHT"

    last =  debuffButtons[i]
end

ShowDebuffs = function(bossId, buttonIndex)
    local bId, _ = F.SplitToNumber("-", bossId)

    if loadedBoss == bId and not buttonIndex then return end
    loadedBoss = bId

    last = nil
    -- hide debuffDetails
    selectedSpellId = nil
    selectedButtonIndex = nil
    RaidDebuffsTab_DebuffDetails.scrollFrame:Hide()
    delete:SetEnabled(false)

    debuffListFrame.scrollFrame:ResetScroll()

    isGeneral = bId == loadedInstance

    currentBossTable = nil
    if loadedDebuffs[loadedInstance] then
        if isGeneral then -- General
            currentBossTable = loadedDebuffs[loadedInstance]["general"]
        else
            currentBossTable = loadedDebuffs[loadedInstance][bId]
        end
    end

    local n = 0
    if currentBossTable then
        -- texplore(currentBossTable)
        n = 0
        for i, sTable in ipairs(currentBossTable["enabled"]) do
            n = n + 1
            CreateDebuffButton(i, sTable)
        end
        for _, sTable in pairs(currentBossTable["disabled"]) do
            n = n + 1
            CreateDebuffButton(n, sTable)
        end
    end

    -- update scrollFrame content height
    debuffListFrame.scrollFrame:SetContentHeight(20, n, -1)

    -- hide unused instance buttons
    for i = n+1, #debuffButtons do
        debuffButtons[i]:Hide()
        debuffButtons[i]:ClearAllPoints()
    end

    -- set onclick
    Cell.CreateButtonGroup(debuffButtons, ShowDetails, nil, nil, function(b)
        debuffListFrame:GetScript("OnEnter")()
        CellSpellTooltip:SetOwner(b, "ANCHOR_NONE")
        CellSpellTooltip:SetPoint("TOPRIGHT", b, "TOPLEFT", -1, 0)
        CellSpellTooltip:SetSpellByID(b.spellId, b.spellTex)
        local curation = GetRaidDebuffCurationData(loadedInstance, GetSelectedBossKey(), b.spellId)
        local info = GetRaidDebuffCurationStatusInfo(curation["status"])
        CellSpellTooltip:AddLine(" ")
        CellSpellTooltip:AddLine("|cFFB2B2B2Midnight Curation|r")
        CellSpellTooltip:AddLine(("Status: |cFFFFFFFF%s|r"):format(info["text"]))
        if curation["suggestedOrder"] then
            CellSpellTooltip:AddLine(("Suggested order: |cFFFFFFFF%d|r"):format(curation["suggestedOrder"]))
        end
        if curation["note"] then
            CellSpellTooltip:AddLine("Note: |cFFFFFFFF" .. curation["note"] .. "|r")
        elseif not curation["explicit"] then
            CellSpellTooltip:AddLine("Note: |cFFB2B2B2No curation note yet|r")
        end
        CellSpellTooltip:Show()
    end, function(b)
        debuffListFrame:GetScript("OnLeave")()
        CellSpellTooltip:Hide()
    end)

    if debuffButtons[buttonIndex or 1] and debuffButtons[buttonIndex or 1]:IsShown() then
        debuffButtons[buttonIndex or 1]:Click()
    else
        if CellRaidDebuffsPreviewButton:IsShown() then CellRaidDebuffsPreviewButton.fadeOut:Play() end
    end
end

--------------------------------------------------
-- glow preview
--------------------------------------------------
local previewButton

local function CreatePreviewButton()
    previewButton = CreateFrame("Button", "CellRaidDebuffsPreviewButton", debuffsTab, "CellPreviewButtonTemplate")
    B.UpdateBackdrop(previewButton)
    -- previewButton.type = "main" -- layout setup
    previewButton:SetPoint("TOPLEFT", debuffsTab, "TOPRIGHT", 5, -137)
    previewButton:UnregisterAllEvents()
    previewButton:SetScript("OnEnter", nil)
    previewButton:SetScript("OnLeave", nil)
    previewButton:SetScript("OnShow", nil)
    previewButton:SetScript("OnHide", nil)
    previewButton:SetScript("OnUpdate", nil)
    previewButton:Hide()

    previewButton.widgets.healthBar:SetMinMaxValues(0, 1)
    previewButton.widgets.healthBar:SetValue(1)
    previewButton.widgets.powerBar:SetMinMaxValues(0, 1)
    previewButton.widgets.powerBar:SetValue(1)

    local previewButtonBG = Cell.CreateFrame("CellRaidDebuffsPreviewButtonBG", previewButton)
    previewButtonBG:SetPoint("TOPLEFT", previewButton, 0, 20)
    previewButtonBG:SetPoint("BOTTOMRIGHT", previewButton, "TOPRIGHT")
    Cell.StylizeFrame(previewButtonBG, {0.1, 0.1, 0.1, 0.77}, {0, 0, 0, 0})
    previewButtonBG:Show()

    local previewText = previewButtonBG:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET_TITLE")
    previewText:SetPoint("TOP", 0, -3)
    previewText:SetText(Cell.GetAccentColorString()..L["Preview"])

    previewButton.fadeIn = previewButton:CreateAnimationGroup()
    local fadeIn = previewButton.fadeIn:CreateAnimation("alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.25)
    fadeIn:SetSmoothing("OUT")

    previewButton.fadeOut = previewButton:CreateAnimationGroup()
    local fadeOut = previewButton.fadeOut:CreateAnimation("alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.25)
    fadeOut:SetSmoothing("IN")
    fadeOut:SetScript("OnPlay", function()
        if previewButton.fadeIn:IsPlaying() then
            previewButton.fadeIn:Stop()
        end
    end)
    previewButton.fadeOut:SetScript("OnFinished", function()
        previewButton:Hide()
    end)

    Cell.Fire("CreatePreview", previewButton)
end

local function UpdatePreviewButton()
    if not previewButton then
        CreatePreviewButton()
    end

    local iTable = Cell.vars.currentLayoutTable["indicators"][1]
    if iTable["enabled"] then
        previewButton.indicators.nameText:Show()
        previewButton.states.name = UnitName("player")
        previewButton.indicators.nameText:UpdateName()
        previewButton.indicators.nameText:UpdatePreviewColor(iTable["color"])
        previewButton.indicators.nameText:UpdateTextWidth(iTable["textWidth"])
        previewButton.indicators.nameText:SetFont(unpack(iTable["font"]))
        previewButton.indicators.nameText:ClearAllPoints()
        local relativeTo = iTable["position"][2] == "healthBar" and previewButton.widgets.healthBar or previewButton
        previewButton.indicators.nameText:SetPoint(iTable["position"][1], relativeTo, iTable["position"][3], iTable["position"][4], iTable["position"][5])
    else
        previewButton.indicators.nameText:Hide()
    end

    P.Size(previewButton, Cell.vars.currentLayoutTable["main"]["size"][1], Cell.vars.currentLayoutTable["main"]["size"][2])
    B.SetOrientation(previewButton, Cell.vars.currentLayoutTable["barOrientation"][1], Cell.vars.currentLayoutTable["barOrientation"][2])
    B.SetPowerSize(previewButton, Cell.vars.currentLayoutTable["main"]["powerSize"])

    previewButton.widgets.healthBar:SetStatusBarTexture(Cell.vars.texture)
    previewButton.widgets.powerBar:SetStatusBarTexture(Cell.vars.texture)

    -- health color
    local r, g, b = F.GetHealthBarColor(1, false, F.GetClassColor(Cell.vars.playerClass))
    previewButton.widgets.healthBar:SetStatusBarColor(r, g, b, CellDB["appearance"]["barAlpha"])

    -- power color
    r, g, b = F.GetPowerBarColor("player", Cell.vars.playerClass)
    previewButton.widgets.powerBar:SetStatusBarColor(r, g, b)

    -- alpha
    previewButton:SetBackdropColor(0, 0, 0, CellDB["appearance"]["bgAlpha"])

    Cell.Fire("UpdatePreview", previewButton)
end

-------------------------------------------------
-- debuff details frame
-------------------------------------------------
local spellIcon, spellNameText, spellIdText, enabledCB, trackByIdCB, useElapsedTimeCB
local curationStatusDropdown, curationSuggestedOrder, curationCurrentOrderText, curationNoteEditBox
local conditionDropDown, conditionFrame, conditionOperator, conditionValue
local glowTypeText, glowTypeDropdown, glowTargetDropdown, glowOptionsFrame, glowConditionType, glowConditionOperator, glowConditionValue, glowColor, glowLines, glowParticles, glowDuration, glowFrequency, glowLength, glowThickness, glowScale

local LoadCondition, UpdateCondition
local UpdateGlowType, LoadGlowOptions, LoadGlowCondition, ShowGlowPreview

local conditionHeight, glowOptionsHeight, glowConditionHeight = 0, 0, 0
local curationHeight = 80

local function UpdateDetailsHeight()
    detailsFrame.scrollFrame:SetContentHeight(225 + curationHeight + glowOptionsHeight + glowConditionHeight + conditionHeight)
    detailsFrame.scrollFrame:ResetScroll()
end

local function CreateDetailsFrame()
    detailsFrame = Cell.CreateFrame("RaidDebuffsTab_DebuffDetails", debuffsTab)
    detailsFrame:SetPoint("TOPLEFT", debuffListFrame, "TOPRIGHT", 5, 0)
    detailsFrame:SetPoint("BOTTOMRIGHT", -5, 24)
    detailsFrame:Show()

    local isMouseOver
    detailsFrame:SetScript("OnUpdate", function()
        if detailsFrame:IsMouseOver() then
            if not isMouseOver or isMouseOver ~= 1 then
                detailsFrame:SetBackdropBorderColor(unpack(Cell.GetAccentColorTable()))
                isMouseOver = 1
            end
        else
            if not isMouseOver or isMouseOver ~= 2 then
                detailsFrame:SetBackdropBorderColor(0, 0, 0, 1)
                isMouseOver = 2
            end
        end
    end)

    Cell.CreateScrollFrame(detailsFrame)

    local detailsContentFrame = detailsFrame.scrollFrame.content
    -- local detailsContentFrame = CreateFrame("Frame", "RaidDebuffsTab_DebuffDetailsContent", detailsFrame)
    -- detailsContentFrame:SetAllPoints(detailsFrame)

    -- spell icon
    local spellIconBG = detailsContentFrame:CreateTexture(nil, "ARTWORK")
    spellIconBG:SetSize(27, 27)
    spellIconBG:SetDrawLayer("ARTWORK", 6)
    spellIconBG:SetPoint("TOPLEFT", 5, -5)
    spellIconBG:SetColorTexture(0, 0, 0, 1)

    spellIcon = detailsContentFrame:CreateTexture(nil, "ARTWORK")
    spellIcon:SetDrawLayer("ARTWORK", 7)
    spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    spellIcon:SetPoint("TOPLEFT", spellIconBG, 1, -1)
    spellIcon:SetPoint("BOTTOMRIGHT", spellIconBG, -1, 1)

    -- spell name & id
    spellNameText = detailsContentFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    spellNameText:SetPoint("TOPLEFT", spellIconBG, "TOPRIGHT", 2, 0)
    spellNameText:SetPoint("RIGHT", -1, 0)
    spellNameText:SetJustifyH("LEFT")
    spellNameText:SetWordWrap(false)

    spellIdText = detailsContentFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    spellIdText:SetPoint("BOTTOMLEFT", spellIconBG, "BOTTOMRIGHT", 2, 0)
    spellIdText:SetPoint("RIGHT")
    spellIdText:SetJustifyH("LEFT")

    -- enable
    enabledCB = Cell.CreateCheckButton(detailsContentFrame, L["Enabled"], function(checked)
        local newOrder = checked and #currentBossTable["enabled"]+1 or 0
        -- update db, on re-enabled set its order to the last
        if not CellDB["raidDebuffs"][loadedInstance] then CellDB["raidDebuffs"][loadedInstance] = {} end
        local tIndex = isGeneral and "general" or loadedBoss
        if not CellDB["raidDebuffs"][loadedInstance][tIndex] then CellDB["raidDebuffs"][loadedInstance][tIndex] = {} end
        if not CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId] then
            CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId] = {
                ["order"] = newOrder,
                ["trackByID"] = false,
                ["condition"] = {"None"},
            }
        else
            CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["order"] = newOrder
        end
        if not checked then -- enabled -> disabled
            for i = selectedButtonIndex+1, #currentBossTable["enabled"] do
                local id = currentBossTable["enabled"][i]["id"]
                -- print("update db order: ", id)
                if CellDB["raidDebuffs"][loadedInstance][tIndex][id] then
                    -- update db order
                    CellDB["raidDebuffs"][loadedInstance][tIndex][id]["order"] = CellDB["raidDebuffs"][loadedInstance][tIndex][id]["order"] - 1
                end
            end
        end

        -- update loadedDebuffs
        local buttonIndex
        if checked then -- disabled -> enabled
            local disabledIndex = selectedButtonIndex-#currentBossTable["enabled"] -- index in ["disabled"]
            currentBossTable["enabled"][newOrder] = currentBossTable["disabled"][disabledIndex]
            currentBossTable["enabled"][newOrder]["order"] = newOrder
            tremove(currentBossTable["disabled"], disabledIndex) -- remove from ["disabled"]
            -- button to click
            buttonIndex = newOrder
        else -- enabled -> disabled
            for i = selectedButtonIndex+1, #currentBossTable["enabled"] do
                currentBossTable["enabled"][i]["order"] = currentBossTable["enabled"][i]["order"] - 1 -- update orders
            end
            currentBossTable["enabled"][selectedButtonIndex]["order"] = 0
            tinsert(currentBossTable["disabled"], currentBossTable["enabled"][selectedButtonIndex])
            tremove(currentBossTable["enabled"], selectedButtonIndex)
            -- button to click
            buttonIndex = #currentBossTable["enabled"] + #currentBossTable["disabled"]
        end

        -- update selectedButtonIndex
        -- selectedButtonIndex = buttonIndex
        -- reload
        if isGeneral then -- general
            ShowDebuffs(loadedInstance, buttonIndex)
        else
            ShowDebuffs(loadedBoss, buttonIndex)
        end
        -- notify debuff list changed
        Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
    end)
    enabledCB:SetPoint("TOPLEFT", spellIconBG, "BOTTOMLEFT", 0, -10)

    -- track by id
    trackByIdCB = Cell.CreateCheckButton(detailsContentFrame, L["Track by ID"], function(checked)
        -- update db
        if not CellDB["raidDebuffs"][loadedInstance] then CellDB["raidDebuffs"][loadedInstance] = {} end
        local tIndex = isGeneral and "general" or loadedBoss
        if not CellDB["raidDebuffs"][loadedInstance][tIndex] then CellDB["raidDebuffs"][loadedInstance][tIndex] = {} end
        if not CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId] then
            CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId] = {
                ["order"] = selectedButtonIndex <= #currentBossTable["enabled"] and selectedButtonIndex or 0,
                ["trackByID"] = checked,
                ["condition"] = {"None"},
            }
        else
            CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["trackByID"] = checked
        end

        -- update loadedDebuffs
        local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
        t["trackByID"] = checked

        -- notify debuff list changed
        Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
    end)
    trackByIdCB:SetPoint("TOPLEFT", enabledCB, "BOTTOMLEFT", 0, -10)

    -- use elapsed time
    useElapsedTimeCB = Cell.CreateCheckButton(detailsContentFrame, L["Use Elapsed Time"], function(checked)
        -- update db
        if not CellDB["raidDebuffs"][loadedInstance] then CellDB["raidDebuffs"][loadedInstance] = {} end
        local tIndex = isGeneral and "general" or loadedBoss
        if not CellDB["raidDebuffs"][loadedInstance][tIndex] then CellDB["raidDebuffs"][loadedInstance][tIndex] = {} end
        if not CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId] then
            CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId] = {
                ["order"] = selectedButtonIndex <= #currentBossTable["enabled"] and selectedButtonIndex or 0,
                ["trackByID"] = false,
                ["condition"] = {"None"},
                ["useElapsedTime"] = checked
            }
        else
            CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["useElapsedTime"] = checked
        end

        -- update loadedDebuffs
        local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
        t["useElapsedTime"] = checked

        -- notify debuff list changed
        Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
    end, L["Use Elapsed Time"], L["Display elapsed time since debuff applied"], L["Only affects duration text"])
    useElapsedTimeCB:SetPoint("TOPLEFT", trackByIdCB, "BOTTOMLEFT", 0, -10)

    --------------------------------------------------
    -- midnight curation
    --------------------------------------------------
    local curationText = detailsContentFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    curationText:SetText("Midnight Curation")
    curationText:SetPoint("TOPLEFT", useElapsedTimeCB, "BOTTOMLEFT", 0, -10)

    curationStatusDropdown = Cell.CreateDropdown(detailsContentFrame, 117)
    curationStatusDropdown:SetPoint("TOPLEFT", curationText, "BOTTOMLEFT", 0, -1)
    curationStatusDropdown:SetItems({
        {
            ["text"] = "Needs Review",
            ["value"] = "review",
            ["onClick"] = function()
                SetRaidDebuffCurationField(loadedInstance, GetSelectedBossKey(), selectedSpellId, "status", "review")
                ApplyDebuffButtonCuration(debuffButtons[selectedButtonIndex], selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]])
            end,
        },
        {
            ["text"] = "Confirmed",
            ["value"] = "confirmed",
            ["onClick"] = function()
                SetRaidDebuffCurationField(loadedInstance, GetSelectedBossKey(), selectedSpellId, "status", "confirmed")
                ApplyDebuffButtonCuration(debuffButtons[selectedButtonIndex], selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]])
            end,
        },
        {
            ["text"] = "Trash Mob",
            ["value"] = "trash",
            ["onClick"] = function()
                SetRaidDebuffCurationField(loadedInstance, GetSelectedBossKey(), selectedSpellId, "status", "trash")
                ApplyDebuffButtonCuration(debuffButtons[selectedButtonIndex], selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]])
            end,
        },
        {
            ["text"] = "Non-Debuff",
            ["value"] = "non_debuff",
            ["onClick"] = function()
                SetRaidDebuffCurationField(loadedInstance, GetSelectedBossKey(), selectedSpellId, "status", "non_debuff")
                ApplyDebuffButtonCuration(debuffButtons[selectedButtonIndex], selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]])
            end,
        },
        {
            ["text"] = "Ignore",
            ["value"] = "ignore",
            ["onClick"] = function()
                SetRaidDebuffCurationField(loadedInstance, GetSelectedBossKey(), selectedSpellId, "status", "ignore")
                ApplyDebuffButtonCuration(debuffButtons[selectedButtonIndex], selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]])
            end,
        },
    })

    local curationReportBtn = Cell.CreateButton(detailsContentFrame, "Report", "accent", {54, 20}, nil, nil, "CELL_FONT_WIDGET_SMALL", "CELL_FONT_WIDGET_SMALL")
    curationReportBtn:SetPoint("LEFT", curationStatusDropdown, "RIGHT", 6, 0)
    curationReportBtn:SetScript("OnClick", function()
        ShowRaidDebuffsCurationReport(loadedInstance, GetSelectedBossKey())
    end)

    local curationSuggestedText = detailsContentFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    curationSuggestedText:SetText("Suggested Order")
    curationSuggestedText:SetPoint("TOPLEFT", curationStatusDropdown, "BOTTOMLEFT", 0, -8)

    curationSuggestedOrder = Cell.CreateEditBox(detailsContentFrame, 45, 20, nil, nil, true)
    curationSuggestedOrder:SetPoint("TOPLEFT", curationSuggestedText, "BOTTOMLEFT", 0, -1)
    curationSuggestedOrder:SetMaxLetters(3)
    curationSuggestedOrder:SetJustifyH("RIGHT")
    curationSuggestedOrder:SetScript("OnTextChanged", function(self, userChanged)
        if userChanged then
            SetRaidDebuffCurationField(loadedInstance, GetSelectedBossKey(), selectedSpellId, "suggestedOrder", self:GetText())
        end
    end)

    curationCurrentOrderText = detailsContentFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET_SMALL")
    curationCurrentOrderText:SetPoint("LEFT", curationSuggestedOrder, "RIGHT", 8, 0)
    curationCurrentOrderText:SetPoint("RIGHT", -2, 0)
    curationCurrentOrderText:SetJustifyH("LEFT")

    local curationNoteText = detailsContentFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    curationNoteText:SetText("Note")
    curationNoteText:SetPoint("TOPLEFT", curationSuggestedOrder, "BOTTOMLEFT", 0, -8)

    curationNoteEditBox = Cell.CreateEditBox(detailsContentFrame, 177, 20)
    curationNoteEditBox:SetPoint("TOPLEFT", curationNoteText, "BOTTOMLEFT", 0, -1)
    curationNoteEditBox:SetPoint("RIGHT", -2, 0)
    curationNoteEditBox:SetMaxLetters(120)
    curationNoteEditBox:SetScript("OnTextChanged", function(self, userChanged)
        if userChanged then
            SetRaidDebuffCurationField(loadedInstance, GetSelectedBossKey(), selectedSpellId, "note", self:GetText())
            ApplyDebuffButtonCuration(debuffButtons[selectedButtonIndex], selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]])
        end
    end)

    --------------------------------------------------
    -- condition
    --------------------------------------------------
    local conditionText = detailsContentFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    conditionText:SetText(L["Condition"])
    conditionText:SetPoint("TOPLEFT", curationNoteEditBox, "BOTTOMLEFT", 0, -10)

    -- conditionDropDown TODO: 同时持有另一个debuff
    conditionDropDown = Cell.CreateDropdown(detailsContentFrame, 117)
    conditionDropDown:SetPoint("TOPLEFT", conditionText, "BOTTOMLEFT", 0, -1)
    conditionDropDown:SetItems({
        {
            ["text"] = L["None"],
            ["value"] = "None",
            ["onClick"] = function()
                UpdateCondition({"None"})
                -- notify debuff list changed
                Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
            end,
        },
        {
            ["text"] = L["Stack"],
            ["value"] = "Stack",
            ["onClick"] = function()
                UpdateCondition({"Stack", ">=", 0})
                -- notify debuff list changed
                Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
            end,
        }
    })

    conditionFrame = CreateFrame("Frame", nil, detailsContentFrame, "BackdropTemplate")
    conditionFrame:SetPoint("TOPLEFT", conditionDropDown, "BOTTOMLEFT", 0, -5)
    conditionFrame:SetPoint("RIGHT")
    conditionFrame:SetHeight(20)

    conditionOperator = Cell.CreateDropdown(conditionFrame, 50)
    conditionOperator:SetPoint("TOPLEFT")

    do
        local operators = {"=", ">", ">=", "<", "<=", "!="}
        local items = {}
        for _, opr in pairs(operators) do
            tinsert(items, {
                ["text"] = opr,
                ["onClick"] = function()
                    -- update db
                    local tIndex = isGeneral and "general" or loadedBoss
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["condition"][2] = opr
                    -- update loadedDebuffs
                    local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
                    t["condition"][2] = opr
                    -- notify debuff list changed
                    Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
                end,
            })
        end
        conditionOperator:SetItems(items)
    end

    conditionValue = Cell.CreateEditBox(conditionFrame, 45, 20, nil, nil, true)
    conditionValue:SetPoint("LEFT", conditionOperator, "RIGHT", 5, 0)
    conditionValue:SetMaxLetters(3)
    conditionValue:SetJustifyH("RIGHT")
    conditionValue:SetScript("OnTextChanged", function(self, userChanged)
        if userChanged then
            local value = tonumber(self:GetText()) or 0
            -- update db
            local tIndex = isGeneral and "general" or loadedBoss
            CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["condition"][3] = value
            -- update loadedDebuffs
            local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
            t["condition"][3] = value
            -- notify debuff list changed
            Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
        end
    end)

    --------------------------------------------------
    -- glow
    --------------------------------------------------
    glowTypeText = detailsContentFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    glowTypeText:SetText(L["Glow Type"])

    glowTypeDropdown = Cell.CreateDropdown(detailsContentFrame, 117)
    glowTypeDropdown:SetPoint("TOPLEFT", glowTypeText, "BOTTOMLEFT", 0, -1)
    glowTypeDropdown:SetItems({
        {
            ["text"] = L["None"],
            ["value"] = "None",
            ["onClick"] = function()
                local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
                if t["glowType"] and t["glowType"] ~= "None" then -- exists in db
                    -- update db
                    local tIndex = isGeneral and "general" or loadedBoss
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowType"] = "None"
                    -- update loadedDebuffs
                    t["glowType"] = "None"
                    -- notify debuff list changed
                    Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
                    LoadGlowOptions()
                end
                glowTargetDropdown:Hide()
            end,
        },
        {
            ["text"] = L["Normal"],
            ["value"] = "Normal",
            ["onClick"] = function()
                UpdateGlowType("Normal")
            end,
        },
        {
            ["text"] = L["Pixel"],
            ["value"] = "Pixel",
            ["onClick"] = function()
                UpdateGlowType("Pixel")
            end,
        },
        {
            ["text"] = L["Shine"],
            ["value"] = "Shine",
            ["onClick"] = function()
                UpdateGlowType("Shine")
            end,
        },
        {
            ["text"] = L["Proc"],
            ["value"] = "Proc",
            ["onClick"] = function()
                UpdateGlowType("Proc")
            end,
        },
    })

    -- glowTarget
    glowTargetDropdown = Cell.CreateDropdown(detailsContentFrame, 117)
    glowTargetDropdown:SetEnabled(false) -- TODO:
    glowTargetDropdown:SetPoint("TOPLEFT", glowTypeDropdown, "BOTTOMLEFT", 0, -5)
    glowTargetDropdown:SetItems({
        {
            ["text"] = L["Unit Button"],
            ["value"] = "button",
            ["onClick"] = function()
                -- update db
                local tIndex = isGeneral and "general" or loadedBoss
                CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowTarget"] = "button"
                -- update loadedDebuffs
                local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
                t["glowTarget"] = "button"
                -- notify debuff list changed
                Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
            end,
        },
        {
            ["text"] = L["Icon"],
            ["value"] = "icon",
            ["onClick"] = function()
                -- update db
                local tIndex = isGeneral and "general" or loadedBoss
                CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowTarget"] = "icon"
                -- update loadedDebuffs
                local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
                t["glowTarget"] = "icon"
                -- notify debuff list changed
                Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
            end,
        },
    })

    -- glow options
    glowOptionsFrame = CreateFrame("Frame", nil, detailsContentFrame)
    glowOptionsFrame:SetPoint("TOPLEFT", glowTargetDropdown, "BOTTOMLEFT", -5, -10)
    glowOptionsFrame:SetPoint("BOTTOMRIGHT")

    -- glowCondition
    local glowConditionText = glowOptionsFrame:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
    glowConditionText:SetText(L["Glow Condition"])
    glowConditionText:SetPoint("TOPLEFT", glowOptionsFrame, 5, 0)

    glowConditionType = Cell.CreateDropdown(glowOptionsFrame, 117)
    glowConditionType:SetPoint("TOPLEFT", glowConditionText, "BOTTOMLEFT", 0, -1)
    glowConditionType:SetItems({
        {
            ["text"] = L["None"],
            ["value"] = "None",
            ["onClick"] = function()
                LoadGlowCondition()
                -- update db
                local tIndex = isGeneral and "general" or loadedBoss
                CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowCondition"] = nil
                -- update loadedDebuffs
                local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
                t["glowCondition"] = nil
                -- notify debuff list changed
                Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
            end,
        },
        {
            ["text"] = L["Stack"],
            ["value"] = "Stack",
            ["onClick"] = function()
                LoadGlowCondition({"Stack", ">=", 0})
                -- update db
                local tIndex = isGeneral and "general" or loadedBoss
                CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowCondition"] = {"Stack", ">=", 0}
                -- update loadedDebuffs
                local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
                t["glowCondition"] = {"Stack", ">=", 0}
                -- notify debuff list changed
                Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
            end,
        },
    })

    glowConditionOperator = Cell.CreateDropdown(glowOptionsFrame, 50)
    glowConditionOperator:SetPoint("TOPLEFT", glowConditionType, "BOTTOMLEFT", 0, -5)

    do
        local operators = {"=", ">", ">=", "<", "<=", "!="}
        local items = {}
        for _, opr in pairs(operators) do
            tinsert(items, {
                ["text"] = opr,
                ["onClick"] = function()
                    -- update db
                    local tIndex = isGeneral and "general" or loadedBoss
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowCondition"][2] = opr
                    -- update loadedDebuffs
                    local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
                    t["glowCondition"][2] = opr
                    -- notify debuff list changed
                    Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
                end,
            })
        end
        glowConditionOperator:SetItems(items)
    end

    glowConditionValue = Cell.CreateEditBox(glowOptionsFrame, 45, 20, nil, nil, true)
    glowConditionValue:SetPoint("LEFT", glowConditionOperator, "RIGHT", 5, 0)
    glowConditionValue:SetMaxLetters(3)
    glowConditionValue:SetJustifyH("RIGHT")
    glowConditionValue:SetScript("OnTextChanged", function(self, userChanged)
        if userChanged then
            local value = tonumber(self:GetText()) or 0
            -- update db
            local tIndex = isGeneral and "general" or loadedBoss
            CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowCondition"][3] = value
            -- update loadedDebuffs
            local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
            t["glowCondition"][3] = value
            -- notify debuff list changed
            Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
        end
    end)

    -- glowColor
    glowColor = Cell.CreateColorPicker(glowOptionsFrame, L["Glow Color"], false, function(r, g, b)
        local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
        -- update db
        local tIndex = isGeneral and "general" or loadedBoss
        CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][1][1] = r
        CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][1][2] = g
        CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][1][3] = b
        CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][1][4] = 1
        -- update loadedDebuffs
        t["glowOptions"][1][1] = r
        t["glowOptions"][1][2] = g
        t["glowOptions"][1][3] = b
        t["glowOptions"][1][4] = 1
        -- notify debuff list changed
        Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
        -- update preview
        ShowGlowPreview(t["glowType"], t["glowOptions"])
    end)
    -- glowColor:SetPoint("TOPLEFT", glowOptionsFrame, 5, 0)
    glowColor:SetPoint("TOPLEFT", glowConditionOperator, "BOTTOMLEFT", 0, -10)

    local function SliderValueChanged(index, value, refresh)
        local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
        -- update db
        local tIndex = isGeneral and "general" or loadedBoss
        CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][index] = value
        -- update loadedDebuffs
        t["glowOptions"][index] = value
        -- notify debuff list changed
        Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
        -- update preview
        ShowGlowPreview(t["glowType"], t["glowOptions"], refresh)
    end

    -- glowNumber
    glowLines = Cell.CreateSlider(L["Lines"], glowOptionsFrame, 1, 30, 117, 1, function(value)
        SliderValueChanged(2, value)
    end)
    glowLines:SetPoint("TOPLEFT", glowColor, "BOTTOMLEFT", 0, -25)

    glowParticles = Cell.CreateSlider(L["Particles"], glowOptionsFrame, 1, 30, 117, 1, function(value)
        SliderValueChanged(2, value, true)
    end)
    glowParticles:SetPoint("TOPLEFT", glowColor, "BOTTOMLEFT", 0, -25)

    -- duration
    glowDuration = Cell.CreateSlider(L["Duration"], glowOptionsFrame, 0.1, 3, 117, 0.1, function(value)
        SliderValueChanged(2, value, true)
    end)
    glowDuration:SetPoint("TOPLEFT", glowColor, "BOTTOMLEFT", 0, -25)

    -- glowFrequency
    glowFrequency = Cell.CreateSlider(L["Frequency"], glowOptionsFrame, -2, 2, 117, 0.01, function(value)
        SliderValueChanged(3, value)
    end)
    glowFrequency:SetPoint("TOPLEFT", glowLines, "BOTTOMLEFT", 0, -40)

    -- glowLength
    glowLength = Cell.CreateSlider(L["Length"], glowOptionsFrame, 1, 20, 117, 1, function(value)
        SliderValueChanged(4, value)
    end)
    glowLength:SetPoint("TOPLEFT", glowFrequency, "BOTTOMLEFT", 0, -40)

    -- glowThickness
    glowThickness = Cell.CreateSlider(L["Thickness"], glowOptionsFrame, 1, 20, 117, 1, function(value)
        SliderValueChanged(5, value)
    end)
    glowThickness:SetPoint("TOPLEFT", glowLength, "BOTTOMLEFT", 0, -40)

    -- glowScale
    glowScale = Cell.CreateSlider(L["Scale"], glowOptionsFrame, 50, 500, 117, 1, function(value)
        SliderValueChanged(4, value/100)
    end, nil, true)
    glowScale:SetPoint("TOPLEFT", glowFrequency, "BOTTOMLEFT", 0, -40)
end

--------------------------------------------------
-- details functions
--------------------------------------------------
UpdateCondition = function(condition)
    local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]

    -- update db
    if not CellDB["raidDebuffs"][loadedInstance] then CellDB["raidDebuffs"][loadedInstance] = {} end
    local tIndex = isGeneral and "general" or loadedBoss
    if not CellDB["raidDebuffs"][loadedInstance][tIndex] then CellDB["raidDebuffs"][loadedInstance][tIndex] = {} end
    if not CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId] then
        CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId] = {
            ["order"] = t["order"],
            ["trackByID"] = false,
            ["condition"] = condition,
        }
    else
        CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["condition"] = condition
    end

    -- update loadedDebuffs
    t["condition"] = condition

    LoadCondition(condition)
end

LoadCondition = function(condition)
    if condition[1] == "None" then
        conditionDropDown:SetSelectedValue("None")
        conditionHeight = 0
        conditionFrame:Hide()
        glowTypeText:ClearAllPoints()
        glowTypeText:SetPoint("TOPLEFT", conditionDropDown, "BOTTOMLEFT", 0, -10)
    else
        conditionDropDown:SetSelectedValue(condition[1])
        conditionHeight = 20
        conditionFrame:Show()
        glowTypeText:ClearAllPoints()
        glowTypeText:SetPoint("TOPLEFT", conditionFrame, "BOTTOMLEFT", 0, -10)

        conditionOperator:SetSelected(condition[2])
        conditionValue:SetText(condition[3])
    end

    -- update scroll
    UpdateDetailsHeight()
end

-- glow
UpdateGlowType = function(newType)
    local t = selectedButtonIndex <= #currentBossTable["enabled"] and currentBossTable["enabled"][selectedButtonIndex] or currentBossTable["disabled"][selectedButtonIndex-#currentBossTable["enabled"]]
    if t["glowType"] ~= newType then
        -- update db
        if not CellDB["raidDebuffs"][loadedInstance] then CellDB["raidDebuffs"][loadedInstance] = {} end
        local tIndex = isGeneral and "general" or loadedBoss
        if not CellDB["raidDebuffs"][loadedInstance][tIndex] then CellDB["raidDebuffs"][loadedInstance][tIndex] = {} end
        if not CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId] then
            CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId] = {
                ["order"] = t["order"],
                ["trackByID"] = false,
                ["condition"] = {"None"},
                ["glowType"] = newType,
                ["glowTarget"] = "button",
            }
            if newType == "Normal" then
                CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] = {{0.95,0.95,0.32,1}}
            elseif newType == "Pixel" then
                CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] = {{0.95,0.95,0.32,1}, 9, 0.25, 8, 2}
            elseif newType == "Shine" then
                CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] = {{0.95,0.95,0.32,1}, 9, 0.5, 1}
            elseif newType == "Proc" then
                CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] = {{0.95,0.95,0.32,1}, 1}
            end
        else
            CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowType"] = newType
            if newType == "Normal" then
                if CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] then
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][2] = nil
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][3] = nil
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][4] = nil
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][5] = nil
                else
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] = {{0.95,0.95,0.32,1}}
                end
            elseif newType == "Pixel" then
                if CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] then
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][2] = 9
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][3] = 0.25
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][4] = 8
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][5] = 2
                else
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] = {{0.95,0.95,0.32,1}, 9, 0.25, 8, 2}
                end
            elseif newType == "Shine" then
                if CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] then
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][2] = 9
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][3] = 0.5
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][4] = 1
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][5] = nil
                else
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] = {{0.95,0.95,0.32,1}, 9, 0.5, 1}
                end
            elseif newType == "Proc" then
                if CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] then
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][2] = 1
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][3] = nil
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][4] = nil
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"][5] = nil
                else
                    CellDB["raidDebuffs"][loadedInstance][tIndex][selectedSpellId]["glowOptions"] = {{0.95,0.95,0.32,1}, 1}
                end
            end
        end
        -- update loadedDebuffs
        t["glowType"] = newType
        if newType == "Normal" then
            if t["glowOptions"] then
                t["glowOptions"][2] = nil
                t["glowOptions"][3] = nil
                t["glowOptions"][4] = nil
                t["glowOptions"][5] = nil
            else
                t["glowOptions"] = {{0.95,0.95,0.32,1}}
            end
        elseif newType == "Pixel" then
            if t["glowOptions"] then
                t["glowOptions"][2] = 9
                t["glowOptions"][3] = 0.25
                t["glowOptions"][4] = 8
                t["glowOptions"][5] = 2
            else
                t["glowOptions"] = {{0.95,0.95,0.32,1}, 9, 0.25, 8, 2}
            end
        elseif newType == "Shine" then
            if t["glowOptions"] then
                t["glowOptions"][2] = 9
                t["glowOptions"][3] = 0.5
                t["glowOptions"][4] = 1
                t["glowOptions"][5] = nil
            else
                t["glowOptions"] = {{0.95,0.95,0.32,1}, 9, 0.5, 1}
            end
        elseif newType == "Proc" then
            if t["glowOptions"] then
                t["glowOptions"][2] = 1
                t["glowOptions"][3] = nil
                t["glowOptions"][4] = nil
                t["glowOptions"][5] = nil
            else
                t["glowOptions"] = {{0.95,0.95,0.32,1}, 1}
            end
        end
        LoadGlowOptions(newType, t["glowOptions"])
        -- notify debuff list changed
        Cell.Fire("RaidDebuffsChanged", instanceIdToName[loadedInstance])
    end
    glowTargetDropdown:Show()
end

ShowGlowPreview = function(glowType, glowOptions, refresh)
    if not glowType or glowType == "None" then
        LCG.ButtonGlow_Stop(previewButton)
        LCG.PixelGlow_Stop(previewButton)
        LCG.AutoCastGlow_Stop(previewButton)
        LCG.ProcGlow_Stop(previewButton)
        if previewButton:IsShown() then previewButton.fadeOut:Play() end
        return
    end

    if previewButton.fadeOut:IsPlaying() then
        previewButton.fadeOut:Stop()
    end
    if previewButton:IsShown() then
        if glowType == "Normal" then
            LCG.PixelGlow_Stop(previewButton)
            LCG.AutoCastGlow_Stop(previewButton)
            LCG.ProcGlow_Stop(previewButton)
            LCG.ButtonGlow_Start(previewButton, glowOptions[1])
        elseif glowType == "Pixel" then
            LCG.ButtonGlow_Stop(previewButton)
            LCG.AutoCastGlow_Stop(previewButton)
            LCG.ProcGlow_Stop(previewButton)
            -- color, N, frequency, length, thickness
            LCG.PixelGlow_Start(previewButton, glowOptions[1], glowOptions[2], glowOptions[3], glowOptions[4], glowOptions[5])
        elseif glowType == "Shine" then
            LCG.ButtonGlow_Stop(previewButton)
            LCG.PixelGlow_Stop(previewButton)
            LCG.ProcGlow_Stop(previewButton)
            if refresh then LCG.AutoCastGlow_Stop(previewButton) end
            -- color, N, frequency, scale
            LCG.AutoCastGlow_Start(previewButton, glowOptions[1], glowOptions[2], glowOptions[3], glowOptions[4])
        elseif glowType == "Proc" then
            LCG.ButtonGlow_Stop(previewButton)
            LCG.PixelGlow_Stop(previewButton)
            LCG.AutoCastGlow_Stop(previewButton)
            -- color, duration
            LCG.ProcGlow_Start(previewButton, {color=glowOptions[1], duration=glowOptions[2], startAnim=false})
        end
    else
        previewButton.fadeIn:SetScript("OnFinished", function()
            if glowType == "Normal" then
                LCG.PixelGlow_Stop(previewButton)
                LCG.AutoCastGlow_Stop(previewButton)
                LCG.ProcGlow_Stop(previewButton)
                LCG.ButtonGlow_Start(previewButton, glowOptions[1])
            elseif glowType == "Pixel" then
                LCG.ButtonGlow_Stop(previewButton)
                LCG.AutoCastGlow_Stop(previewButton)
                LCG.ProcGlow_Stop(previewButton)
                -- color, N, frequency, length, thickness
                LCG.PixelGlow_Start(previewButton, glowOptions[1], glowOptions[2], glowOptions[3], glowOptions[4], glowOptions[5])
            elseif glowType == "Shine" then
                LCG.ButtonGlow_Stop(previewButton)
                LCG.PixelGlow_Stop(previewButton)
                LCG.ProcGlow_Stop(previewButton)
                -- color, N, frequency, scale
                LCG.AutoCastGlow_Start(previewButton, glowOptions[1], glowOptions[2], glowOptions[3], glowOptions[4])
            elseif glowType == "Proc" then
                LCG.ButtonGlow_Stop(previewButton)
                LCG.PixelGlow_Stop(previewButton)
                LCG.AutoCastGlow_Stop(previewButton)
                -- color, duration
                LCG.ProcGlow_Start(previewButton, {color=glowOptions[1], duration=glowOptions[2], startAnim=false})
            end
        end)
        previewButton:Show()
        previewButton.fadeIn:Play()
    end
end

LoadGlowOptions = function(glowType, glowOptions)
    if not glowType or glowType == "None" or not glowOptions then
        glowTargetDropdown:Hide()
        glowOptionsFrame:Hide()
        ShowGlowPreview("None")
        glowOptionsHeight = 0
        UpdateDetailsHeight()
        return
    end

    glowTargetDropdown:SetSelectedValue("button")
    glowTargetDropdown:Show()
    ShowGlowPreview(glowType, glowOptions)
    glowColor:SetColor(glowOptions[1])

    if glowType == "Normal" then
        glowLines:Hide()
        glowParticles:Hide()
        glowDuration:Hide()
        glowFrequency:Hide()
        glowLength:Hide()
        glowThickness:Hide()
        glowScale:Hide()
        glowOptionsHeight = 30
    elseif glowType == "Pixel" then
        glowLines:Show()
        glowFrequency:Show()
        glowLength:Show()
        glowThickness:Show()
        glowParticles:Hide()
        glowDuration:Hide()
        glowScale:Hide()
        glowLines:SetValue(glowOptions[2])
        glowFrequency:SetValue(glowOptions[3])
        glowLength:SetValue(glowOptions[4])
        glowThickness:SetValue(glowOptions[5])
        glowOptionsHeight = 235
    elseif glowType == "Shine" then
        glowParticles:Show()
        glowFrequency:Show()
        glowScale:Show()
        glowLines:Hide()
        glowDuration:Hide()
        glowLength:Hide()
        glowThickness:Hide()
        glowParticles:SetValue(glowOptions[2])
        glowFrequency:SetValue(glowOptions[3])
        glowScale:SetValue(glowOptions[4]*100)
        glowOptionsHeight = 175
    elseif glowType == "Proc" then
        glowDuration:Show()
        glowLines:Hide()
        glowParticles:Hide()
        glowFrequency:Hide()
        glowLength:Hide()
        glowThickness:Hide()
        glowScale:Hide()
        glowDuration:SetValue(glowOptions[2])
        glowOptionsHeight = 30
    end

    glowOptionsFrame:Show()

    UpdateDetailsHeight()
end

LoadGlowCondition = function(glowCondition)
    if type(glowCondition) == "table" then
        glowConditionOperator:Show()
        glowConditionValue:Show()
        glowConditionType:SetSelected(L[glowCondition[1]])
        glowConditionOperator:SetSelected(glowCondition[2])
        glowConditionValue:SetText(glowCondition[3])
        glowColor:ClearAllPoints()
        glowColor:SetPoint("TOPLEFT", glowConditionOperator, "BOTTOMLEFT", 0, -10)
        glowConditionHeight = 65
    else
        glowConditionType:SetSelected(L["None"])
        glowConditionOperator:Hide()
        glowConditionValue:Hide()
        glowColor:ClearAllPoints()
        glowColor:SetPoint("TOPLEFT", glowConditionType, "BOTTOMLEFT", 0, -10)
        glowConditionHeight = 40
    end
    UpdateDetailsHeight()
end

-- spell description
-- Cell.CreateScrollFrame(detailsContentFrame, -270, 0) -- spell description
-- local descText = detailsContentFrame.scrollFrame.content:CreateFontString(nil, "OVERLAY", "CELL_FONT_WIDGET")
-- descText:SetPoint("TOPLEFT", 5, -1)
-- descText:SetPoint("RIGHT", -5, 0)
-- descText:SetJustifyH("LEFT")
-- descText:SetSpacing(2)

-- local function SetSpellDesc(desc)
--     descText:SetText(desc)
--     detailsContentFrame.scrollFrame:SetContentHeight(descText:GetStringHeight()+2)
-- end

local timer
ShowDetails = function(spell)
    local spellId, buttonIndex = F.SplitToNumber("-", spell)

    if selectedSpellId == spellId then return end
    selectedSpellId, selectedButtonIndex = spellId, buttonIndex

    -- local name, icon, desc = F.GetSpellTooltipInfo(spellId)
    local name, icon = F.GetSpellInfo(spellId)
    if not name then return end

    detailsFrame.scrollFrame:ResetScroll()
    detailsFrame.scrollFrame:Show()

    selectedSpellIcon = icon
    selectedSpellName = name

    spellIcon:SetTexture(icon)
    spellNameText:SetText(name)
    spellIdText:SetText(spellId)
    -- SetSpellDesc(desc)
    -- -- to ensure desc
    -- if timer then timer:Cancel() end
    -- timer = C_Timer.NewTimer(0.7, function()
    --     SetSpellDesc(select(3, F.GetSpellTooltipInfo(spellId)))
    -- end)

    local isEnabled = selectedButtonIndex <= #currentBossTable["enabled"]
    enabledCB:SetChecked(isEnabled)

    local spellTable
    if isEnabled then
        spellTable = currentBossTable["enabled"][buttonIndex]
    else
        spellTable = currentBossTable["disabled"][buttonIndex-#currentBossTable["enabled"]]
    end

    trackByIdCB:SetChecked(spellTable["trackByID"])
    useElapsedTimeCB:SetChecked(spellTable["useElapsedTime"])
    LoadCondition(spellTable["condition"])

    local curation = GetRaidDebuffCurationData(loadedInstance, GetSelectedBossKey(), spellId)
    curationStatusDropdown:SetSelectedValue(curation["status"])
    curationSuggestedOrder:SetText(curation["suggestedOrder"] or "")
    curationCurrentOrderText:SetText(isEnabled and ("Current order: " .. selectedButtonIndex) or "Current order: disabled")
    curationNoteEditBox:SetText(curation["note"] or "")

    local glowType = spellTable["glowType"] or "None"
    glowTypeDropdown:SetSelected(L[glowType])
    glowTargetDropdown:SetSelectedValue(spellTable["glowTarget"])

    if glowType == "None" then
        LoadGlowCondition()
        LoadGlowOptions()
        glowTargetDropdown:Hide()
    else
        LoadGlowCondition(spellTable["glowCondition"])
        LoadGlowOptions(glowType, spellTable["glowOptions"])
        glowTargetDropdown:Show()
    end

    -- check deletion
    if isEnabled then
        delete:SetEnabled(not currentBossTable["enabled"][buttonIndex]["built-in"])
    else -- disabled
        delete:SetEnabled(not currentBossTable["disabled"][buttonIndex-#currentBossTable["enabled"]]["built-in"])
    end
end

-------------------------------------------------
-- open encounter journal -- from grid2
-------------------------------------------------
OpenEncounterJournal = function(instanceId)
    if not C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then C_AddOns.LoadAddOn("Blizzard_EncounterJournal") end

    local difficulty
    if IsInInstance() then
        difficulty = select(3,GetInstanceInfo())
    else
        difficulty = 14
    end

    ShowUIPanel(EncounterJournal)
    EJ_ContentTab_Select(EncounterJournal.dungeonsTab:GetID())
    EncounterJournal_DisplayInstance(instanceId)
    EncounterJournal.lastInstance = instanceId

    if not EJ_IsValidInstanceDifficulty(difficulty) then
        difficulty = (difficulty==14 and 1) or (difficulty==15 and 2) or (difficulty==16 and 23) or (difficulty==17 and 7) or 0
        if not EJ_IsValidInstanceDifficulty(difficulty) then
            return
        end
    end
    EJ_SetDifficulty(difficulty)
    EncounterJournal.lastDifficulty = difficulty
end


-------------------------------------------------
-- functions
-------------------------------------------------
function F.GetDebuffList(instanceName)
    local list = {}
    local eName, iIndex, iId = F.SplitToNumber(":", instanceNameMapping[instanceName])

    if iId and loadedDebuffs[iId] then
        local n = 0
        -- check general
        if loadedDebuffs[iId]["general"] then
            n = #loadedDebuffs[iId]["general"]["enabled"]
            for _, t in ipairs(loadedDebuffs[iId]["general"]["enabled"]) do
                local spellName = F.GetSpellInfo(t["id"])
                if spellName then
                    -- list[spellName/spellId] = {order, glowType, glowOptions}
                    local entry = {
                        ["order"] = t["order"],
                        ["condition"] = t["condition"],
                        ["glowType"] = t["glowType"],
                        ["glowOptions"] = t["glowOptions"],
                        ["glowCondition"] = t["glowCondition"],
                        ["useElapsedTime"] = t["useElapsedTime"],
                    }
                    list[t["trackByID"] and t["id"] or spellName] = entry
                    -- 12.0+: also index by name for trackByID entries so
                    -- GetDebuffOrder can match by resolved name when spellId is secret
                    if t["trackByID"] and spellName and not list[spellName] then
                        list[spellName] = entry
                    end
                end
            end
        end
        -- check boss
        for bId, bTable in pairs(loadedDebuffs[iId]) do
            if bId ~= "general" then
                for _, t in pairs(bTable["enabled"]) do
                    local spellName = F.GetSpellInfo(t["id"])
                    if spellName then -- check again
                        local entry = {
                            ["order"] = t["order"]+n,
                            ["condition"] = t["condition"],
                            ["glowType"] = t["glowType"],
                            ["glowOptions"] = t["glowOptions"],
                            ["glowCondition"] = t["glowCondition"],
                            ["useElapsedTime"] = t["useElapsedTime"],
                        }
                        list[t["trackByID"] and t["id"] or spellName] = entry
                        -- 12.0+: also index by name for trackByID entries
                        if t["trackByID"] and spellName and not list[spellName] then
                            list[spellName] = entry
                        end
                    end
                end
            end
        end
    end
    -- texplore(list)

    return list
end

-------------------------------------------------
-- sharing functions
-------------------------------------------------
function F.GetInstanceAndBossId(instanceName, bossName)
    local result = instanceNameMapping[instanceName]
    if not result then return end

    -- instance found
    local expansionName, instanceIndex, instanceId = strsplit(":", result)
    instanceIndex = tonumber(instanceIndex)
    instanceId = tonumber(instanceId)

    local bossId

    if bossName == bossIdToName[0] then
        bossId = "general"
    elseif bossName then
        for _, boss in pairs(encounterJournalList[expansionName][instanceIndex]["bosses"]) do
            if bossName == boss["name"] then
                -- boss found
                bossId = boss["id"]
                break
            end
        end
    end

    return instanceId, bossId
end

function F.GetInstanceAndBossName(instanceId, bossId)
    if bossId == "general" then
        return instanceIdToName[instanceId], bossIdToName[0]
    else
        return instanceIdToName[instanceId], bossIdToName[bossId]
    end
end

-- calculate built-ins and customs
function F.CalcRaidDebuffs(instanceId, bossId, data)
    local builtIn = 0

    local customs = {}
    if data then
        if bossId then
            -- 1 boss
            for spellId in pairs(data) do
                customs[spellId] = true
            end
        else
            -- several bosses
            for bId, bTable in pairs(data) do
                for spellId in pairs(bTable) do
                    customs[spellId] = true
                end
            end
        end
    end

    if unsortedDebuffs[instanceId] then
        if not bossId then
            -- calc all bosses
            for bId, bTable in pairs(unsortedDebuffs[instanceId]) do
                for _, spellId in pairs(bTable) do
                    if not customs[spellId] then
                        builtIn = builtIn + 1
                    end
                end
            end
        elseif unsortedDebuffs[instanceId][bossId] then
            -- calc by bossId
            for _, spellId in pairs(unsortedDebuffs[instanceId][bossId]) do
                if not customs[spellId] then
                    builtIn = builtIn + 1
                end
            end
        end
    end

    return builtIn, F.Getn(customs)
end

function F.ShowInstanceDebuffs(instanceId, bossId)
    if not InCombatLockdown() then
        F.ShowRaidDebuffsTab()
        C_Timer.After(0.25, function()
            if bossId == "general" or bossId == nil then
                OpenInstanceBoss(instanceIdToName[instanceId], "general")
            else -- numeric bossId / no bossId
                OpenInstanceBoss(instanceIdToName[instanceId], bossIdToName[bossId])
            end
        end)
    end
end

function F.UpdateRaidDebuffs(instanceId, bossId, data, which)
    -- update db
    if not bossId then
        -- instance debuffs received
        -- replace current db
        CellDB["raidDebuffs"][instanceId] = data
    else
        -- boss debuffs received
        if data then
            if not CellDB["raidDebuffs"][instanceId] then
                CellDB["raidDebuffs"][instanceId] = {}
            end
            CellDB["raidDebuffs"][instanceId][bossId] = data
        else -- no custom debuffs, just built-in
            if CellDB["raidDebuffs"][instanceId] then
                CellDB["raidDebuffs"][instanceId][bossId] = nil
            end
        end
    end

    -- update loadedDebuffs
    if not bossId then -- all bosses
        -- clear old
        loadedDebuffs[instanceId] = {}
        -- load new db
        if data then
            for bid, bTable in pairs(data) do
                LoadDB(instanceId, bid, bTable)
            end
        end
        -- load built-in
        if unsortedDebuffs[instanceId] then -- has built-in
            for bid, bTable in pairs(unsortedDebuffs[instanceId]) do
                LoadBuiltIn(instanceId, bid, bTable)
            end
        end
    else
        -- clear old
        if not loadedDebuffs[instanceId] then
            loadedDebuffs[instanceId] = {}
        else
            loadedDebuffs[instanceId][bossId] = nil
        end
        -- load new db
        if data then
            LoadDB(instanceId, bossId, data)
        end
        -- load built-in
        if unsortedDebuffs[instanceId] and unsortedDebuffs[instanceId][bossId] then -- has built-in
            LoadBuiltIn(instanceId, bossId, unsortedDebuffs[instanceId][bossId])
        end
    end

    -- update current region
    Cell.Fire("RaidDebuffsChanged", instanceIdToName[instanceId])

    F.Print(L["Raid Debuffs updated: %s."]:format(which))
end

-------------------------------------------------
-- show
-------------------------------------------------
local init
local function ShowTab(tab)
    if tab == "debuffs" then
        if not init then
            init = true
            CreateWidgets()
            CreateInstanceFrame()
            CreateBossesFrame()
            CreateDebuffsFrame()
            CreateDetailsFrame()
        end

        debuffsTab:Show()
        UpdatePreviewButton()

        if not loadedExpansion then
            expansionDropdown:SetSelectedItem(1)
            LoadExpansion(tierNames[#tierNames])
        end
    else
        debuffsTab:Hide()
    end
end
Cell.RegisterCallback("ShowOptionsTab", "RaidDebuffsTab_ShowTab", ShowTab)

local function UpdateLayout()
    if previewButton then
        UpdatePreviewButton()
    end
end
Cell.RegisterCallback("UpdateLayout", "RaidDebuffsTab_UpdateLayout", UpdateLayout)

local function UpdateAppearance()
    if previewButton then
        UpdatePreviewButton()
    end
end
Cell.RegisterCallback("UpdateAppearance", "RaidDebuffsTab_UpdateAppearance", UpdateAppearance)

local function UpdateIndicators(layout, indicatorName, setting, value)
    if previewButton then
        if not layout or indicatorName == "nameText" then
            UpdatePreviewButton()
        end
    end
end
Cell.RegisterCallback("UpdateIndicators", "RaidDebuffsTab_UpdateIndicators", UpdateIndicators)
