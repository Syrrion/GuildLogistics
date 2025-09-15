-- Core/Player/MythicProgress.lua - Capture per-dungeon Mythic+ scores for mains
local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG, U = ns.GLOG, ns.Util

-- Contract
-- - On group/raid changes (and at login), read player's own Mythic+ rating summary via
--   C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player").currentSeasonBestMapScores
-- - Persist only for MAIN characters (not alts), under GuildLogisticsDB.players[main].mplusMaps = { [mapName] = { score=number, best=number, medal=string, runs=number, mapID=number } }
-- - Later UI will read this aggregated per-main map score table.
-- - Throttled and very lightweight to respect performance guidance.

local function ensureDB()
    if GLOG.EnsureDB then GLOG.EnsureDB() end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
end

-- Internal: write map scores for a given main full name
local function setMainMapScores(mainFullName, scores)
    if not mainFullName or mainFullName == "" then return end
    ensureDB()
    local p = GuildLogisticsDB.players[mainFullName]
    if not p then return end -- never create non-roster entries
    -- Minimal footprint: reuse table when possible
    p.mplusMaps = p.mplusMaps or {}
    local dest = p.mplusMaps

    -- Wipe previous content efficiently
    if next(dest) ~= nil then wipe(dest) end

    for _, it in ipairs(scores or {}) do
        local mapName = tostring(it.mapName or it.name or "")
        if mapName ~= "" then
            local timed = nil
            -- Prefer finishedSuccess from the Blizzard API when available
            if type(it.finishedSuccess) == "boolean" then
                timed = it.finishedSuccess
            end
            if timed == nil and type(it.timed) == "boolean" then timed = it.timed end
            if timed == nil and type(it.runScoreInfo) == "table" then
                local r = it.runScoreInfo
                timed = (r.inTime == true) or (r.withinTime == true) or (r.finishedInTime == true) or (r.onTime == true) or (r.isTimed == true) or nil
            end
            if timed == nil then
                local tier = tostring(it.tier or ""):lower()
                if tier == "d" or tier == "depleted" then timed = false end
            end
            dest[mapName] = {
                score = tonumber(it.mapScore or it.score or 0) or 0,
                best  = tonumber(it.bestRunLevel or it.level or 0) or 0,
                medal = tostring(it.runScoreInfo and it.runScoreInfo.tier or it.tier or ""),
                runs  = tonumber(it.numRuns or 0) or 0,
                mapID = tonumber(it.mapChallengeModeID or it.mapID or 0) or 0,
                timed = (timed == true) and true or false,
                durMS = tonumber(it.bestRunDurationMS or it.bestRunDurationMs or it.durationMS or it.durationMs or 0) or 0,
            }
        end
    end
    p.mplusMapsTs = time and time() or (p.mplusMapsTs or 0)
    -- (silenced) previously: print("[GLOG] M+ maps saved for:", mainFullName, "count=", #scores)
    if GLOG and GLOG.DebugLocal and GLOG.IsDebugEnabled and GLOG.IsDebugEnabled() then
        GLOG.DebugLocal("MPLUS_CAPTURE", {
            main = mainFullName,
            count = #scores,
        })
    end
    if ns.Emit then ns.Emit("mplus:maps-updated", mainFullName) end
end

-- Internal: write overall (season) mythic+ score for a given main (stored as mplusScore)
local function setMainScore(mainFullName, score)
    if not mainFullName or mainFullName == "" then return end
    ensureDB()
    local p = GuildLogisticsDB.players[mainFullName]
    if not p then return end
    p.mplusScore = tonumber(score or 0) or 0
    p.mplusScoreTs = time and time() or (p.mplusScoreTs or 0)
end

-- Read current player's season best map scores from Blizzard API (Retail 11.x)
local function readBestMapScores(unit)
    unit = unit or "player"
    if not C_PlayerInfo or not C_PlayerInfo.GetPlayerMythicPlusRatingSummary then return nil end
    local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
    if not ok or type(summary) ~= "table" then return nil end
    -- Expected shapes vary by client; try known keys first, then a generic scan
    local list = nil
    do
        local candidates = {
            "currentSeasonBestMapScores",
            "currentSeasonMapScores",
            "seasonBestMapScores",
            "bestSeasonMapScores",
            "bestMapScores",
            "mapScores",
            "bestRunScores",
            -- API doc suggests 'runs' under ratingSummary
            "runs",
        }
        for i = 1, #candidates do
            local v = rawget(summary, candidates[i])
            if type(v) == "table" and (#v >= 0) then list = v; break end
        end
        if not list then
            for k, v in pairs(summary) do
                if type(v) == "table" and (#v >= 0) and type(v[1]) == "table" then
                    local e = v[1]
                    if type(e) == "table" and (e.mapChallengeModeID or e.mapID or e.mapScore or (type(e.runScoreInfo) == "table" and (e.runScoreInfo.bestRunLevel or e.runScoreInfo.tier))) then
                        list = v; break
                    end
                end
            end
        end
    end
    if type(list) ~= "table" then return nil end

    -- Normalize items: prefer map name using GLOG.ResolveMKeyMapName if only mapID present
    local out = {}
    for i = 1, #list do
        local e = list[i]
        if type(e) == "table" then
            local mid = tonumber(e.mapChallengeModeID or e.challengeModeID or e.mapID or 0) or 0
            local name = tostring(e.mapName or e.name or "")
            if (name == "" or name == nil) and mid > 0 and GLOG.ResolveMKeyMapName then
                local nm = GLOG.ResolveMKeyMapName(mid)
                if nm and nm ~= "" then name = nm end
            end
            local runScore = e.runScoreInfo or e.runScore or {}
            local tier = (type(runScore) == "table" and runScore.tier) or (type(runScore) == "number" and runScore) or e.tier
            -- Derive timed flag from finishedSuccess first, then fallbacks
            local function truthy(x) return x == true or x == 1 or x == "true" end
            local timed = nil
            if type(e.finishedSuccess) == "boolean" then
                timed = e.finishedSuccess
            else
                timed = truthy(e.inTime) or truthy(e.withinTime) or truthy(e.finishedInTime) or truthy(e.onTime) or truthy(e.isTimed)
            end
            if not timed and type(runScore) == "table" then
                timed = truthy(runScore.inTime) or truthy(runScore.withinTime) or truthy(runScore.finishedInTime) or truthy(runScore.onTime) or truthy(runScore.isTimed)
            end
            if timed == nil and type(tier) == "string" then
                local t = tier:lower()
                if t == "d" or t == "depleted" then timed = false end
            end
            -- Best duration in milliseconds if provided by the API
            local durMs = tonumber(e.bestRunDurationMS or e.bestRunDurationMs or (type(runScore)=="table" and (runScore.bestRunDurationMS or runScore.bestRunDurationMs)) or 0) or 0
            out[#out+1] = {
                mapName = name,
                mapScore = e.mapScore or e.score or 0,
                bestRunLevel = (type(runScore) == "table" and runScore.bestRunLevel) or e.bestRunLevel or e.bestLevel or 0,
                runScoreInfo = (type(runScore) == "table" and runScore) or nil,
                numRuns = e.numRuns or e.runs or 0,
                mapChallengeModeID = mid,
                tier = tier,
                timed = (timed == true) and true or false,
                finishedSuccess = (type(e.finishedSuccess) == "boolean") and e.finishedSuccess or nil,
                bestRunDurationMS = durMs,
            }
        end
    end
    -- (silenced) previously: print("[GLOG] M+ API summary entries:", #out)
    local overall = tonumber(rawget(summary, "currentSeasonScore") or rawget(summary, "seasonScore") or rawget(summary, "overall") or 0) or 0
    return { list = out, overall = overall }
end

-- Determine current player's MAIN full name
local function myMainFullName()
    local me = (U and U.playerFullName and U.playerFullName()) or (UnitName and UnitName("player")) or nil
    if not me or me == "" then return nil end
    if GLOG and GLOG.GetMainOf then
        local m = GLOG.GetMainOf(me)
        if m and m ~= "" then return (GLOG.ResolveFullName and GLOG.ResolveFullName(m)) or m end
    end
    return (GLOG.ResolveFullName and GLOG.ResolveFullName(me)) or me
end

-- Only update if connected char is the main (to avoid overwriting main data from alts)
local function shouldCaptureForSelf()
    return GLOG and GLOG.IsConnectedMain and GLOG.IsConnectedMain()
end

-- Throttled updater
local _nextAt = 0
local _retryLeft = 3

-- Group / raid capture extension -----------------------------------------
local _lastCaptureByMain = {}
local MIN_INTERVAL = 300 -- seconds between captures per main (other than self)

local function resolveMainFullFromUnit(unit)
    if not UnitExists or not unit or not UnitName then return nil end
    local name, realm = UnitName(unit)
    if not name or name == "" then return nil end
    local full = (realm and realm ~= "" and (name.."-"..realm)) or name
    if GLOG and GLOG.GetMainOf then
        local m = GLOG.GetMainOf(full) or full
        full = (GLOG.ResolveFullName and GLOG.ResolveFullName(m)) or m
    elseif GLOG and GLOG.ResolveFullName then
        full = GLOG.ResolveFullName(full)
    end
    return full
end

local function captureForUnit(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return end
    if UnitIsUnit and UnitIsUnit(unit, "player") then return end
    local fullMain = resolveMainFullFromUnit(unit)
    if not fullMain or fullMain == "" then return end
    ensureDB()
    if not (GuildLogisticsDB and GuildLogisticsDB.players and GuildLogisticsDB.players[fullMain]) then return end
    local now = time and time() or 0
    local last = _lastCaptureByMain[fullMain] or 0
    if (now - last) < MIN_INTERVAL then return end
    local payload = readBestMapScores(unit)
    if not payload or type(payload) ~= "table" or type(payload.list) ~= "table" or #payload.list == 0 then return end
    setMainMapScores(fullMain, payload.list)
    if payload.overall then setMainScore(fullMain, payload.overall) end
    _lastCaptureByMain[fullMain] = now
end

local function captureGroupMembers()
    if IsInRaid and IsInRaid() then
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i=1,n do captureForUnit("raid"..i) end
    elseif IsInGroup and IsInGroup() then
        local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or (GetNumGroupMembers and (GetNumGroupMembers()-1) or 0)
        for i=1,n do captureForUnit("party"..i) end
    end
end

local function onGroupChanged()
    local now = (GetTimePreciseSec and GetTimePreciseSec()) or (debugprofilestop and (debugprofilestop()/1000)) or 0
    if now < (_nextAt or 0) then return end
    _nextAt = now + 2.0 -- throttle to 1 op per 2s
    -- (silenced) previously: print("[GLOG] M+ capture tick")

    if not shouldCaptureForSelf() then
        local me = (U and U.playerFullName and U.playerFullName()) or (UnitName and UnitName("player")) or "?"
        local mainDbg = myMainFullName() or "nil"
    -- (silenced) capture skipped (not main)
        return
    end

    local main = myMainFullName()
    -- (silenced) previously: print resolved main
    if not main then return end

    -- Ensure the main has an existing roster entry before persisting (create if allowed)
    ensureDB()
    if U and U.EnsureRosterLocal then
        U.EnsureRosterLocal(main)
    end
    if not (GuildLogisticsDB and GuildLogisticsDB.players and GuildLogisticsDB.players[main]) then
    -- (silenced) previously: print capture skipped (no roster entry)
        if GLOG and GLOG.DebugLocal and GLOG.IsDebugEnabled and GLOG.IsDebugEnabled() then
            GLOG.DebugLocal("MPLUS_CAPTURE_SKIP", { reason = "no_roster_entry", main = tostring(main) })
        end
        return
    end

    local payload = readBestMapScores("player")
    local scores, overall
    if type(payload) == "table" and payload.list then
        scores = payload.list
        overall = payload.overall
    else
        scores = payload -- backward
    end
    if scores and #scores > 0 then
        setMainMapScores(main, scores)
    if overall then setMainScore(main, overall) end
        _retryLeft = 3 -- reset on success
        -- After successful self capture, attempt capture of group/raid members (deferred slightly)
    if C_Timer and C_Timer.After then C_Timer.After(0.3, captureGroupMembers) else captureGroupMembers() end
    else
    -- (silenced) previously: print no scores returned
        if GLOG and GLOG.DebugLocal and GLOG.IsDebugEnabled and GLOG.IsDebugEnabled() then
            local ok = type(scores) == "table"
            GLOG.DebugLocal("MPLUS_CAPTURE_NONE", { ok = ok and true or false })
        end
        -- Retry with gentle backoff: 0.8s, 2s, 5s (once per stage)
        if (_retryLeft or 0) > 0 and C_Timer and C_Timer.After then
            local delay = (_retryLeft == 3 and 0.8) or (_retryLeft == 2 and 2.0) or 5.0
            -- (silenced) previously: print retry scheduling
            local function _retry()
                onGroupChanged()
            end
            _retryLeft = _retryLeft - 1
            C_Timer.After(delay, _retry)
        else
            _retryLeft = 0
        end
    end
end

-- Initial bind to group/raid roster changes
if ns and ns.Events and ns.Events.Register then
    ns.Events.Register("GROUP_ROSTER_UPDATE", GLOG, onGroupChanged)
    ns.Events.Register("PLAYER_LOGIN", GLOG, function()
        -- capture at login as well (API should be ready by now; small delay for safety)
        if C_Timer and C_Timer.After then C_Timer.After(0.5, onGroupChanged) else onGroupChanged() end
    end)
    ns.Events.Register("PLAYER_ENTERING_WORLD", GLOG, function()
        -- slight delay to allow API to be ready
        if C_Timer and C_Timer.After then C_Timer.After(0.8, onGroupChanged) else onGroupChanged() end
    end)
end
