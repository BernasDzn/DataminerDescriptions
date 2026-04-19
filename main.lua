-- =============================================================================
--  DataminerDescriptions -- main.lua
--  Shows procedural effect descriptions for Dataminer-glitched pedestals.
--
--  How glitched items work in Repentance+:
--    The Dataminer uses the same TMTRAINER procedural system.  Each glitched
--    pedestal gets a unique negative CollectibleType (stored as a large uint32
--    in Lua).  The 2-4 procedural effects are determined at pedestal init time
--    (BEFORE pickup) and are exposed via REPENTOGON's ProceduralItemManager.
--
--  Requires: Repentance+   Optional: REPENTOGON (for full effect details)
-- =============================================================================

local MOD = RegisterMod("DataminerDescriptions", 1)

local CFG = {
    DISPLAY_RANGE  = 100,
    TEXT_SCALE     = 0.8,
    LINE_H         = 11,
    PANEL_Y        = -45,   -- screen px above item sprite
    ITEM_FLOAT_Y   = -24,   -- world units the item floats above the pedestal entity
}

local DATAMINER_ID = CollectibleType.COLLECTIBLE_DATAMINER

-- Glitch items have a negative int32 SubType (= large positive number in Lua).
-- Normal collectibles top out around ~750, so 0x80000000 is a safe threshold.
local function isGlitched(subType)
    return type(subType) == "number" and subType >= 0x80000000
end

-- ---------------------------------------------------------------------------
--  REPENTOGON — read procedural effects for a glitched pedestal
--
--  ProceduralItemManager.GetProceduralItem(i) : ProceduralItem
--  ProceduralItem:GetID()                     : int  (negative CollectibleType)
--  ProceduralItem:GetEffectCount()            : int
--  ProceduralItem:GetEffect(i)                : ProceduralEffect
--  ProceduralEffect:GetConditionType()        : ProceduralEffectConditionType
--  ProceduralEffect:GetActionType()           : ProceduralEffectActionType
--  ProceduralEffect:GetActionProperty()       : table
--  ProceduralEffect:GetTriggerChance()        : float  (0..1)
--
--  ProceduralEffectConditionType:
--    0=ACTIVE 1=TEAR_FIRE 2=ENEMY_HIT 3=ENEMY_KILL 4=DAMAGE_TAKEN
--    5=ROOM_CLEAR 6=ENTITY_SPAWN 7=PICKUP_COLLECTED 8=CHAIN
--
--  ProceduralEffectActionType:
--    0=USE_ACTIVE_ITEM 1=ADD_TEMPRORY_EFFECT 2=CONVERT_ENTITIES
--    3=AREA_DAMAGE 4=SPAWN_ENTITY 5=FART
-- ---------------------------------------------------------------------------

local COND_LABEL = {
    [0] = "Use item:",
    [1] = "You take a hit:",
    [2] = "Tear hits enemy:",
    [3] = "Kill enemy:",
    [4] = "Take damage:",
    [5] = "Clear room:",
    [6] = "Entity spawns:",
    [7] = "Collect pickup:",
    -- [8] = CHAIN: appended as ", action" onto the previous effect line
}

-- Convert a raw token like "#PAGEANT_BOY_NAME" to "Pageant Boy".
-- Falls back gracefully if the name is already human-readable.
local function prettyName(raw)
    if type(raw) ~= "string" or raw == "" then return raw end
    local s = raw:match("^#(.+)") or raw   -- strip leading #
    s = s:match("^(.-)_NAME$") or s         -- strip trailing _NAME
    s = s:gsub("_", " ")                    -- underscores -> spaces
    -- title-case each word
    s = s:gsub("(%a)([%a']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
    return s
end

local function itemName(itemCfg, id)
    if not id then return "?" end
    if id == -1 then return "any item" end
    local cfg = itemCfg:GetCollectible(id)
    local raw = cfg and cfg.Name
    if not raw or raw == "" then return "item#" .. tostring(id) end
    return prettyName(raw)
end

-- Returns the description string for a collectible ID from pocketitems.xml.
local function itemDescription(id)
    if not id or not REPENTOGON then return nil end
    local ok, entry = pcall(XMLData.GetEntryById, XMLNode.ITEM, id)
    if ok and entry and type(entry.description) == "string" and entry.description ~= "" then
        return prettyName(entry.description)
    end
    return nil
end

-- Cache to avoid hitting XMLData on every render frame
local entityNameCache = {}

local function entityLabel(eType, eVariant, eSubType)
    local TYPE_FALLBACK = {
        [1] = "player", [2] = "tear",       [3] = "familiar",
        [4] = "bomb",   [5] = "pickup",     [6] = "slot",
        [7] = "laser",  [8] = "knife",      [9] = "projectile",
        [1000] = "effect",
    }
    -- -1 on variant means "all entities of this type" (no specific class known)
    if eVariant == -1 then
        local tLabel = TYPE_FALLBACK[eType] or ("type" .. tostring(eType))
        return "all " .. tLabel .. "s"
    end

    -- -1 on subType means "all of this pickup class" (e.g. variant=40 → Bombs).
    -- Look up subtype 1 as the representative name for the class.
    local allSubs = eSubType == -1
    local lookupSub = allSubs and 1 or (eSubType or 0)

    -- Cache key uses the original subType so allSubs and specific lookups are separate entries.
    local key = eType .. "." .. eVariant .. "." .. tostring(eSubType or 0)
    if entityNameCache[key] then return entityNameCache[key] end

    local name
    local usedFallback = false
    if REPENTOGON then
        local ok, data = pcall(XMLData.GetEntityByTypeVarSub, eType, eVariant, lookupSub, false)
        if ok and data and data.name and data.name ~= "" then
            name = prettyName(data.name)
        end
        -- fall back to subtype 0, then subtype 1 (covers pickups like 5.40 where 0 is empty)
        if not name and lookupSub ~= 0 then
            local ok0, data0 = pcall(XMLData.GetEntityByTypeVarSub, eType, eVariant, 0, false)
            if ok0 and data0 and data0.name and data0.name ~= "" then
                name = prettyName(data0.name)
                usedFallback = true
            end
        end
        if not name and lookupSub ~= 1 then
            local ok1, data1 = pcall(XMLData.GetEntityByTypeVarSub, eType, eVariant, 1, false)
            if ok1 and data1 and data1.name and data1.name ~= "" then
                name = prettyName(data1.name)
                usedFallback = true
            end
        end
    end

    if not name then
        -- Avoid "#" in fallback — EID uses it as a line separator
        local tLabel = TYPE_FALLBACK[eType] or ("type" .. tostring(eType))
        name = tLabel .. "(" .. tostring(eVariant) .. ")"
    end

    -- When allSubs (-1) or we had to fall back to a representative subtype,
    -- the game means the whole class → render as "all Bombs", "all Keys", etc.
    local result = (allSubs or usedFallback) and ("all " .. name .. "s") or name
    entityNameCache[key] = result
    return result
end

local function describeAction(eff, itemCfg)
    local action = eff:GetActionType()
    local prop   = eff:GetActionProperty()

    if action == 0 then  -- USE_ACTIVE_ITEM
        return "uses " .. itemName(itemCfg, prop.id)

    elseif action == 1 then  -- ADD_TEMPRORY_EFFECT (typo is in REPENTOGON's enum)
        return "gives " .. itemName(itemCfg, prop.id) .. "\'s effect"

    elseif action == 2 then  -- CONVERT_ENTITIES
        return string.format("converts %s into %s",
            entityLabel(prop.fromType, prop.fromVariant, prop.fromSubType),
            entityLabel(prop.toType,   prop.toVariant,   prop.toSubType))

    elseif action == 3 then  -- AREA_DAMAGE
        if not prop.damage or math.abs(prop.damage) < 0.001 then return nil end
        return string.format("does %.2g of area damage", prop.damage)

    elseif action == 4 then  -- SPAWN_ENTITY
        return "spawns " .. entityLabel(prop.type, prop.variant, prop.subType)

    elseif action == 5 then  -- FART
        return "farts"

    else
        return "?"
    end
end

-- Returns a table of verbose lines describing one effect's action (for the detail popup).
-- Item-based actions include the item name and its pocketitems.xml description.
local function detailedDescribeAction(eff, itemCfg)
    local action = eff:GetActionType()
    local prop   = eff:GetActionProperty()
    local lines  = {}

    if action == 0 then  -- USE_ACTIVE_ITEM
        local name = itemName(itemCfg, prop.id)
        table.insert(lines, "Uses: " .. name)
        local desc = itemDescription(prop.id)
        if desc then table.insert(lines, "  \"" .. desc .. "\"") end

    elseif action == 1 then  -- ADD_TEMPORARY_EFFECT (typo in REPENTOGON enum)
        local name = itemName(itemCfg, prop.id)
        table.insert(lines, "Applies: " .. name)
        local desc = itemDescription(prop.id)
        if desc then table.insert(lines, "  \"" .. desc .. "\"") end

    elseif action == 2 then  -- CONVERT_ENTITIES
        table.insert(lines, string.format("Converts %s into %s",
            entityLabel(prop.fromType, prop.fromVariant, prop.fromSubType),
            entityLabel(prop.toType,   prop.toVariant,   prop.toSubType)))

    elseif action == 3 then  -- AREA_DAMAGE
        if prop.damage and math.abs(prop.damage) >= 0.001 then
            table.insert(lines, string.format("Area DMG: %.2g", prop.damage))
        end

    elseif action == 4 then  -- SPAWN_ENTITY
        table.insert(lines, "Spawns: " .. entityLabel(prop.type, prop.variant, prop.subType))

    elseif action == 5 then  -- FART
        table.insert(lines, "Fart")

    else
        table.insert(lines, "?")
    end

    return lines
end

-- Normalise any number (signed int, unsigned int, or float) to its uint32 value.
-- Avoids bitwise ops on floats, which throw in Lua 5.4.
local function toU32(n)
    if n < 0 then return n + 0x100000000 end
    if n >= 0x100000000 then return n % 0x100000000 end
    return math.floor(n)
end

-- Returns a table of display strings for the given glitched subType,
-- or nil if REPENTOGON is unavailable / item not found.
local function readProceduralEffects(subType)
    if not REPENTOGON then return nil end

    local ok, result = pcall(function()
        local st32  = toU32(subType)
        -- GetID() is a 0-based index. The CollectibleType for a glitched item is
        -- -(index+1) as int32, so index = 0xFFFFFFFF - u32(subType).
        local targetId = 0xFFFFFFFF - st32
        local count    = ProceduralItemManager.GetProceduralItemCount()

        local pItem = nil
        for i = 0, count - 1 do
            local p  = ProceduralItemManager.GetProceduralItem(i)
            local id = p:GetID()
            if id == targetId then
                pItem = p
                break
            end
        end
        if not pItem then
            return nil
        end

        local itemCfg = Isaac.GetItemConfig()
        local lines   = {}

        -- Stat modifiers (skip zero values)
        local statDefs = {
            { pItem:GetDamage(),    "DMG"   },
            { pItem:GetSpeed(),     "SPD"   },
            { pItem:GetShotSpeed(), "SSPD"  },
            { pItem:GetRange(),     "RNG"   },
            { pItem:GetLuck(),      "LUCK"  },
            { pItem:GetFireDelay(), "DELAY" },
        }
        local statParts = {}
        for _, s in ipairs(statDefs) do
            if math.abs(s[1]) > 0.001 then
                table.insert(statParts, string.format("%s %+.2g", s[2], s[1]))
            end
        end
        if #statParts > 0 then
            table.insert(lines, table.concat(statParts, "  "))
        end

        -- Procedural effects
        local detail = {}
        -- Duplicate stat header into detail panel
        if #statParts > 0 then
            table.insert(detail, table.concat(statParts, "  "))
            table.insert(detail, "")
        end

        local effectCount = pItem:GetEffectCount()
        for i = 0, effectCount - 1 do
            local eff    = pItem:GetEffect(i)
            local cond   = eff:GetConditionType()
            local aLabel = describeAction(eff, itemCfg)
            if aLabel == nil then goto continue_effects end

            local chance  = eff:GetTriggerChance()
            local pctStr  = (chance < 0.99) and string.format(" (%.0f%%)", chance * 100) or ""

            if cond == 8 and #lines > 0 then
                -- CHAIN: append to the previous effect line with a comma.
                -- Chain chance is shown inline since it's conditional on the parent trigger.
                local chainPct = pctStr ~= "" and (" " .. pctStr) or ""
                lines[#lines] = lines[#lines] .. ", " .. aLabel .. chainPct
                -- Detail: remove the trailing spacer, append action lines, re-add spacer
                if detail[#detail] == "" then detail[#detail] = nil end
                for _, dl in ipairs(detailedDescribeAction(eff, itemCfg)) do
                    table.insert(detail, "  , " .. dl)
                end
                table.insert(detail, "")
            else
                local cLabel = COND_LABEL[cond] or ("cond" .. tostring(cond))
                -- Chance goes on the trigger, not the action: "Kill enemy (50%): uses X"
                local cLabelPct = (pctStr ~= "" and cLabel:sub(-1) == ":")
                    and (cLabel:sub(1, -2) .. pctStr .. ":")
                    or  (cLabel .. pctStr)
                table.insert(lines, cLabelPct .. " " .. aLabel)
                -- Detail panel: condition header + indented verbose action lines
                table.insert(detail, cLabelPct)
                for _, dl in ipairs(detailedDescribeAction(eff, itemCfg)) do
                    table.insert(detail, "  " .. dl)
                end
                table.insert(detail, "")  -- blank spacer after each effect
            end
            ::continue_effects::
        end

        -- Remove trailing blank line
        if detail[#detail] == "" then detail[#detail] = nil end

        -- EID description string: registered via EID:addCollectible so it persists
        -- after pickup and shows in the held-item panel too.
        -- Uses "#" as line separator and EID markup for icons and indentation.
        local EID_STAT_ICON = {
            DMG   = "{{Damage}}",   SPD  = "{{Speed}}",    SSPD = "{{Shotspeed}}",
            RNG   = "{{Range}}",    LUCK = "{{Luck}}",     DELAY = "{{Tears}}",
        }
        local EID_STAT_NAME = {
            DMG   = "Damage",       SPD  = "Speed",        SSPD = "Shot Speed",
            RNG   = "Range",        LUCK = "Luck",         DELAY = "Tears",
        }
        local eidParts = {}
        -- One line per stat: ↑ {{Damage}} Damage +1.5
        -- Arrow is EID bullet shortcut; icon + text label identify the stat clearly.
        for _, s in ipairs(statDefs) do
            if math.abs(s[1]) > 0.001 then
                local icon  = EID_STAT_ICON[s[2]] or s[2]
                local label = EID_STAT_NAME[s[2]] or s[2]
                local arrow = s[1] > 0 and "↑" or "↓"
                local sign  = s[1] > 0 and "+" or "-"
                table.insert(eidParts, arrow .. " " .. icon .. " " .. sign .. string.format("%.2f", math.abs(s[1])) .. " " .. label)
            end
        end
        for j = 0, effectCount - 1 do
            local eff2     = pItem:GetEffect(j)
            local cond2    = eff2:GetConditionType()
            local aLabel2  = describeAction(eff2, itemCfg)
            local chance2  = eff2:GetTriggerChance()
            local pct2     = (chance2 < 0.99) and string.format(" (%.0f%%)", chance2 * 100) or ""

            if aLabel2 ~= nil then
                if cond2 == 8 and #eidParts > 0 then
                    -- CHAIN: append action to the previous EID line with a comma
                    local chainPct2 = pct2 ~= "" and (" " .. pct2) or ""
                    eidParts[#eidParts] = eidParts[#eidParts] .. ", " .. aLabel2 .. chainPct2
                else
                    local cLabel2 = COND_LABEL[cond2] or ("cond" .. tostring(cond2))
                    -- Chance on the trigger: "Kill enemy (50%): uses X"
                    local cLabelPct2 = (pct2 ~= "" and cLabel2:sub(-1) == ":")
                        and (cLabel2:sub(1, -2) .. pct2 .. ":")
                        or  (cLabel2 .. pct2)
                    table.insert(eidParts, cLabelPct2 .. " " .. aLabel2)
                end
            end
            -- Inline first few lines of EID's own description for the referenced entity
            if EID then
                local act2   = eff2:GetActionType()
                local prop2  = eff2:GetActionProperty()
                local eType2, eVar2, eSub2
                if act2 == 0 or act2 == 1 then
                    -- USE_ACTIVE_ITEM / ADD_TEMPORARY_EFFECT: collectible lookup
                    eType2 = EntityType.ENTITY_PICKUP
                    eVar2  = PickupVariant.PICKUP_COLLECTIBLE
                    eSub2  = prop2.id
                elseif act2 == 4 and prop2.type == EntityType.ENTITY_PICKUP then
                    -- SPAWN_ENTITY spawning a pickup: skip if variant is -1 ("all variants").
                    if prop2.variant ~= -1 then
                        eType2 = prop2.type
                        eVar2  = prop2.variant
                        -- -1 subType means "all of this class": start with 1 as representative
                        -- (e.g. 5.40.-1 → try 5.40.1 first, which is "Bomb").
                        -- Specific subtypes are used as-is.
                        eSub2  = (prop2.subType == -1) and 1 or (prop2.subType or 0)
                    end
                end
                if eType2 then
                    -- Fallback chain: try eSub2, then 0, then 1 (covers all pickup layouts)
                    local ok2, eidItemDesc = pcall(
                        EID.getDescriptionData, EID, eType2, eVar2, eSub2)
                    if (not ok2 or type(eidItemDesc) ~= "string" or eidItemDesc == "") and eSub2 ~= 0 then
                        ok2, eidItemDesc = pcall(
                            EID.getDescriptionData, EID, eType2, eVar2, 0)
                    end
                    if (not ok2 or type(eidItemDesc) ~= "string" or eidItemDesc == "") and eSub2 ~= 1 then
                        ok2, eidItemDesc = pcall(
                            EID.getDescriptionData, EID, eType2, eVar2, 1)
                    end
                    if ok2 and type(eidItemDesc) == "string" and eidItemDesc ~= "" then
                        local lineN = 0
                        for ln in eidItemDesc:gmatch("[^#]+") do
                            if lineN >= 3 then break end
                            table.insert(eidParts, "{{IND}} " .. ln)
                            lineN = lineN + 1
                        end
                    end
                end
            end
        end
        local eidStr = #eidParts > 0 and table.concat(eidParts, "#") or nil

        return (#lines > 0) and { lines = lines, detail = detail, eidStr = eidStr } or nil
    end)

    return ok and result or nil
end

-- ---------------------------------------------------------------------------
--  Helpers
-- ---------------------------------------------------------------------------

local function shadowText(str, x, y, sc, r, g, b, a)
    Isaac.RenderScaledText(str, x + 1, y + 1, sc, sc, 0, 0, 0, a * 0.55)
    Isaac.RenderScaledText(str, x,     y,     sc, sc, r, g, b, a)
end

-- Inject our decoded description string into EID so it renders with its native UI.
-- Called at every registration site; no-ops when EID is not loaded.
-- EID:addCollectible registers persistently so the description survives pickup
-- and appears in the held-item panel. GetData assignment overrides EID's built-in
-- TMTRAINER lookup for the floor entity while it still exists.
local function injectEIDDesc(ent, result)
    if not EID then return end
    local desc = result and result.eidStr
    if not desc then return end
    -- Persistent: survives pickup, shows for held items / EID tab panel
    EID:addCollectible(ent.SubType, desc)
    -- Highest-priority entity override while pedestal is on the floor
    ent:GetData()["EID_Description"] = desc
end

local function snapshotPedestals()
    local snap = {}
    for _, ent in ipairs(Isaac.GetRoomEntities()) do
        if ent.Type    == EntityType.ENTITY_PICKUP
        and ent.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            snap[ent.InitSeed] = ent.SubType
        end
    end
    return snap
end

-- ---------------------------------------------------------------------------
--  State
--  S.datamined: { [InitSeed] = { pos=Vector, effects=table } }
--    effects is populated immediately at pedestal registration (not post-pickup)
-- ---------------------------------------------------------------------------

local S = {
    preSnap   = {},
    datamined = {},
    pending   = false,
}

-- ---------------------------------------------------------------------------
--  Snapshot before Dataminer C++ effect runs
-- ---------------------------------------------------------------------------

MOD:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, function()
    S.preSnap = snapshotPedestals()
    S.pending = true
end, DATAMINER_ID)

-- ---------------------------------------------------------------------------
--  MC_POST_UPDATE
--    1. Register newly-glitched pedestals and read their effects immediately
--    2. Update positions; remove entries for picked-up pedestals
-- ---------------------------------------------------------------------------

MOD:AddCallback(ModCallbacks.MC_POST_UPDATE, function()

    -- Job 1: register newly-glitched pedestals
    if S.pending then
        S.pending = false
        for _, ent in ipairs(Isaac.GetRoomEntities()) do
            if ent.Type    == EntityType.ENTITY_PICKUP
            and ent.Variant == PickupVariant.PICKUP_COLLECTIBLE then
                local prev = S.preSnap[ent.InitSeed]
                local curr = ent.SubType
                if isGlitched(curr) and (prev == nil or not isGlitched(prev)) then
                    local result  = readProceduralEffects(curr)
                    local effects = (result and result.lines)
                        or { "* glitch item", "* (install REPENTOGON", "*  for effect details)" }
                    local detail  = (result and result.detail) or effects
                    -- Store the item's visual world position (floats above pedestal base)
                    local itemPos = Vector(ent.Position.X, ent.Position.Y + CFG.ITEM_FLOAT_Y)
                    S.datamined[ent.InitSeed] = { pos = itemPos, effects = effects, detail = detail }
                    injectEIDDesc(ent, result)
                end
            end
        end
        S.preSnap = {}
    end

    -- Job 2: scan all collectible pedestals — update/prune tracked ones,
    -- and register any newly-glitched ones not yet tracked (covers replacements
    -- after pickup, rerolls, or any other source of new glitch items).
    local live = {}
    for _, ent in ipairs(Isaac.GetRoomEntities()) do
        if ent.Type    == EntityType.ENTITY_PICKUP
        and ent.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            local itemPos = Vector(ent.Position.X, ent.Position.Y + CFG.ITEM_FLOAT_Y)
            if isGlitched(ent.SubType) then
                if S.datamined[ent.InitSeed] then
                    -- Already tracked: update position
                    live[ent.InitSeed] = itemPos
                else
                    -- Newly appeared glitch pedestal: register it now
                    local result  = readProceduralEffects(ent.SubType)
                    local effects = (result and result.lines)
                        or { "* glitch item", "* (install REPENTOGON", "*  for effect details)" }
                    local detail  = (result and result.detail) or effects
                    S.datamined[ent.InitSeed] = { pos = itemPos, effects = effects, detail = detail }
                    injectEIDDesc(ent, result)
                    live[ent.InitSeed] = itemPos
                end
            end
            -- (if not glitched and was tracked, it simply won't appear in live → gets pruned below)
        end
    end

    for seed, entry in pairs(S.datamined) do
        if live[seed] then
            entry.pos = live[seed]
        else
            S.datamined[seed] = nil  -- pedestal gone or replaced with non-glitch item
        end
    end
end)

-- ---------------------------------------------------------------------------
--  State management on transitions
-- ---------------------------------------------------------------------------

local function clearState()
    S.preSnap   = {}
    S.datamined = {}
    S.pending   = false
end

-- On room entry: clear then re-scan for any glitched pedestals already present.
-- This handles re-entering a room where Dataminer was used on a previous visit.
local function onNewRoom()
    clearState()
    for _, ent in ipairs(Isaac.GetRoomEntities()) do
        if ent.Type    == EntityType.ENTITY_PICKUP
        and ent.Variant == PickupVariant.PICKUP_COLLECTIBLE then
            if isGlitched(ent.SubType) then
                local result  = readProceduralEffects(ent.SubType)
                local effects = (result and result.lines)
                    or { "* glitch item", "* (install REPENTOGON", "*  for effect details)" }
                local detail  = (result and result.detail) or effects
                local itemPos = Vector(ent.Position.X, ent.Position.Y + CFG.ITEM_FLOAT_Y)
                S.datamined[ent.InitSeed] = { pos = itemPos, effects = effects, detail = detail }
                injectEIDDesc(ent, result)
            end
        end
    end
end

MOD:AddCallback(ModCallbacks.MC_POST_NEW_ROOM,  onNewRoom)
MOD:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, clearState)
MOD:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContinue)
    if not isContinue then clearState() end
end)
