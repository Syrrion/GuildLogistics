local ADDON, ns = ...
local UI = ns and ns.UI
local GLOG = ns and ns.GLOG
local Tr = ns and ns.Tr

-- LiveCellUpdater: Diff-only per-cell refresh for DynamicTable (Guild)
-- Maps WoW roster-ish events to just-in-time updates of changed values.

local M = {}
ns.LiveCellUpdater = M

-- Small cache of last seen values to avoid unnecessary updates
local last = {
  ilvl = {},      -- [full] = { ilvl, max, online }
  pingCD = {},    -- [full] = bucket (5s)
  online = {},    -- [full] = true/false
  version = {},   -- [full] = string
}

-- Simple signature function (do not import UI module sig)
local function Sig(v)
  local t = type(v)
  if t == 'string' or t == 'number' or t == 'boolean' then return tostring(v) end
  if t == 'table' then
    if v.sig ~= nil then return tostring(v.sig) end
    if v.key ~= nil then return tostring(v.key) end
    if v.id  ~= nil then return tostring(v.id)  end
    local a = rawget(v, 1); if a ~= nil then return "#"..tostring(a) end
  end
  return tostring(v)
end

-- Declarative registry: tables and effects
-- M._tables[name] = {
--   dt   = DynamicTable instance,
--   cols = { [logicKey] = { colKey = "ilvl", valueFn = function(full) -> valueWithSig or primitive end } , ... },
--   relocate = { onlineCategories = { onlineKey = "__cat_online", offlineKey = "__cat_offline" } },
-- }
-- M._effects[changeKey] = array of actions
--   action = { table = name, col = logicKey } or { table = name, relocate = "onlineCategories" }
M._tables  = {}
M._effects = {}
M._lastSig = {}   -- per-table, per-col, per-player
M._dirty   = {}   -- per-table dirty relocation
-- Per-table medal maps (computed ranks)
-- M._tables[name]._medals = { ilvl = { [full]=place? }, mplus = { [full]=place? } }

local function keyOf(name)
  if GLOG and GLOG.NormalizeDBKey then return GLOG.NormalizeDBKey(name) end
  return tostring(name or "")
end

local function getIlvlTuple(full)
  local k = keyOf(full)
  local il = (GLOG and GLOG.GetIlvl and GLOG.GetIlvl(k)) or 0
  local mx = (GLOG and GLOG.GetIlvlMax and GLOG.GetIlvlMax(k)) or 0
  local gi = (GLOG and GLOG.GetMainAggregatedInfo and GLOG.GetMainAggregatedInfo(full)) or {}
  local on = gi and gi.online and true or false
  return il, mx, on
end

local function getVersion(full)
  local k = keyOf(full)
  return (GLOG and GLOG.GetPlayerAddonVersion and GLOG.GetPlayerAddonVersion(k)) or ""
end

local function getOnline(full)
  local gi = (GLOG and GLOG.GetMainAggregatedInfo and GLOG.GetMainAggregatedInfo(full)) or {}
  return gi and gi.online and true or false
end

-- Fallback group check: if main/alt mapping is missing, detect exact toon presence in current group/raid
local function _IsInMyGroupSmart(full)
  -- Prefer authoritative API
  if GLOG and GLOG.IsInMyGroup and GLOG.IsInMyGroup(full) then return true end
  local nf = ns and ns.Util and ns.Util.NormalizeFull
  local target = nf and nf(full) or tostring(full or "")
  if target == "" then return false end
  local function same(unit)
    if UnitExists and UnitExists(unit) then
      local n, r = nil, nil
      if UnitFullName then n, r = UnitFullName(unit) end
      if n and n ~= "" then
        local s = nf and nf(n, r) or ((r and r ~= "" and (n.."-"..r)) or n)
        if s and s ~= "" and tostring(s):lower() == tostring(target):lower() then return true end
      end
    end
    return false
  end
  if IsInRaid and IsInRaid() then
    for i = 1, 40 do if same("raid"..i) then return true end end
    return false
  end
  if IsInGroup and IsInGroup() then
    if same("player") then return true end
    for i = 1, 4 do if same("party"..i) then return true end end
    return false
  end
  return false
end

-- Caller provides the table instance to operate on
function M.Bind(dt)
  M.dt = dt
end

-- Relocate a row between Online/Offline categories if needed
M._dirtyRelocations = false

-- Register a table with columns mapping and optional relocation spec
function M.RegisterTable(name, spec)
  if not name or type(name) ~= 'string' then return end
  M._tables[name] = spec or {}
  M._lastSig[name] = M._lastSig[name] or {}
  -- init medals container
  M._tables[name]._medals = M._tables[name]._medals or { ilvl = {}, mplus = {} }
end

-- Register an effect (changeKey -> actions)
-- actions: array of { table = name, col = logicKey } or { table = name, relocate = "onlineCategories" }
function M.RegisterEffect(changeKey, actions)
  if not changeKey then return end
  M._effects[changeKey] = actions or {}
end

-- Attach a DynamicTable instance to a registered table (or replace)
function M.AttachInstance(name, dt)
  if not (name and M._tables[name]) then return end
  M._tables[name].dt = dt
  -- Kick an initial medal computation when attaching a visual instance
  if M.RecomputeMedals then M.RecomputeMedals(name) end
end

local function _updateCellFor(name, logicKey, full)
  local T = M._tables[name]; if not T then return end
  local dt, cols = T.dt, T.cols or {}
  if not (dt and cols[logicKey]) then return end
  local col = cols[logicKey]
  local value
  local ok, res = pcall(function() return col.valueFn(full) end)
  if ok then value = res end
  if value == nil then return end
  -- compute signature to avoid unnecessary UpdateCell
  local sig = Sig(value)
  M._lastSig[name][full] = M._lastSig[name][full] or {}
  if M._lastSig[name][full][logicKey] == sig then return end
  -- apply
  local colKey = col.colKey or logicKey
  dt:UpdateCell(full, colKey, value)
  M._lastSig[name][full][logicKey] = sig
  -- debug trace (lightweight): log cell change when debug enabled
  if GLOG and GLOG.DebugLocal and GLOG.IsDebugEnabled and GLOG.IsDebugEnabled() then
    GLOG.DebugLocal("ui:cell:update", { table=name, row=full, col=colKey, sig=tostring(sig or "") })
  end
end

local function _relocateIfNeeded(name, mode, full)
  local T = M._tables[name]; if not T then return end
  local dt = T.dt; if not (dt and dt._rawData) then return end
  if mode == 'onlineCategories' then
    local spec = T.relocate and T.relocate.onlineCategories or nil
    if not spec then return end
    local onlineKey  = spec.onlineKey or "__cat_online"
    local offlineKey = spec.offlineKey or "__cat_offline"
    local top = dt._rawData
    local catOn, catOff
    for i = 1, #top do local c = top[i]; if c and c.isCategory then if c.key == onlineKey then catOn = c elseif c.key == offlineKey then catOff = c end end end
    if not (catOn and catOff) then return end
    local nowOnline = getOnline(full)
    -- Find row and its current category/index
    local row, curCat, curIdx
    local function search(cat)
      if not (cat and type(cat.children) == 'table') then return end
      for i = 1, #cat.children do
        local r = cat.children[i]
        if r and r.key == full then row, curCat, curIdx = r, cat, i; return end
      end
    end
    search(catOn); if not row then search(catOff) end
    if not row then return end
    local target = nowOnline and catOn or catOff
    local metaOnline = row._meta and row._meta.online or false
    if curCat == target and metaOnline == nowOnline then return end
    if curCat and curIdx then table.remove(curCat.children, curIdx) end
    table.insert(target.children, row)
    row._meta = row._meta or {}; row._meta.online = nowOnline and true or false
    if catOn then catOn.count = #catOn.children end
    if catOff then catOff.count = #catOff.children end
    M._dirty[name] = true
    if GLOG and GLOG.DebugLocal and GLOG.IsDebugEnabled and GLOG.IsDebugEnabled() then
      local fromKey = (curCat and curCat.key) or "?"; local toKey = (target and target.key) or "?"
      GLOG.DebugLocal("ui:row:relocate", { table=name, row=full, from=fromKey, to=toKey })
    end
    return
  end
  if mode == 'groupCategories' then
    local spec = T.relocate and T.relocate.groupCategories or nil
    if not spec then return end
    local groupKey  = spec.groupKey  or "__cat_group"
    local onlineKey = spec.onlineKey or "__cat_online"
    local offlineKey= spec.offlineKey or "__cat_offline"
    local top = dt._rawData
    local catGrp, catOn, catOff
    for i = 1, #top do local c = top[i]; if c and c.isCategory then if c.key == groupKey then catGrp = c elseif c.key == onlineKey then catOn = c elseif c.key == offlineKey then catOff = c end end end
  local grouped = (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) or ((GetNumGroupMembers and (GetNumGroupMembers() or 0) > 0) and true) or false
  local inGrpNow = _IsInMyGroupSmart(full)
    -- Create group category on demand if grouped and missing
    if grouped and (inGrpNow or true) and (not catGrp) then
      local title = (Tr and Tr("lbl_sep_ingroup")) or "Dans le groupe"
      catGrp = { key = groupKey, isCategory = true, expanded = true, title = title, children = {}, count = 0 }
      -- Insert before online category if present, else at start
      local inserted = false
      for i = 1, #top do if top[i] and top[i].key == onlineKey then table.insert(top, i, catGrp); inserted = true; break end end
      if not inserted then table.insert(top, 1, catGrp) end
    end
    -- Find current row and where it sits
    local row, curCat, curIdx
    local function search(cat)
      if not (cat and type(cat.children) == 'table') then return end
      for i = 1, #cat.children do local r = cat.children[i]; if r and r.key == full then row, curCat, curIdx = r, cat, i; return end end
    end
    if catGrp then search(catGrp) end
    if not row then if catOn then search(catOn) end end
    if not row then if catOff then search(catOff) end end
    if not row then return end
    -- Pick target
    local nowOnline = getOnline(full)
    local target
    if grouped and inGrpNow and catGrp then target = catGrp else target = (nowOnline and catOn) or catOff end
    if not target then return end
    local metaIn = row._meta and row._meta.ingrp or false
    local already = (curCat == target) and (metaIn == (grouped and inGrpNow))
    if already then return end
    if curCat and curIdx then table.remove(curCat.children, curIdx) end
    table.insert(target.children, row)
    row._meta = row._meta or {}
    row._meta.ingrp = (grouped and inGrpNow) and true or false
    row._meta.online = nowOnline and true or false
    if catGrp then catGrp.count = #catGrp.children end
    if catOn  then catOn.count  = #catOn.children end
    if catOff then catOff.count = #catOff.children end
    M._dirty[name] = true
    if GLOG and GLOG.DebugLocal and GLOG.IsDebugEnabled and GLOG.IsDebugEnabled() then
      local fromKey = (curCat and curCat.key) or "?"; local toKey = (target and target.key) or "?"
      GLOG.DebugLocal("ui:row:relocate", { table=name, row=full, from=fromKey, to=toKey })
    end
    return
  end
end

-- Public: get current medal rank for a player (1|2|3 or nil)
function M.GetMedalRank(name, kind, full)
  local T = M._tables[name]
  if not (T and T._medals and kind and full) then return nil end
  local m = T._medals[kind]
  return m and m[full] or nil
end

-- Internal helper: compute top-3 unique values and map players to place
local function _computeTopMap(pairsArray)
  -- pairsArray: { { key=full, v=number }, ... }
  table.sort(pairsArray, function(a,b) return (tonumber(a.v) or 0) > (tonumber(b.v) or 0) end)
  local topVals, seen = {}, {}
  for i=1,#pairsArray do
    local v = tonumber(pairsArray[i].v) or 0
    if not seen[v] then
      topVals[#topVals+1] = v; seen[v] = true
      if #topVals >= 3 then break end
    end
  end
  local valToPlace = {}
  for idx, v in ipairs(topVals) do valToPlace[v] = idx end
  local out = {}
  if #topVals > 0 then
    for i=1,#pairsArray do
      local v = tonumber(pairsArray[i].v) or 0
      local place = valToPlace[v]
      if place then out[pairsArray[i].key] = place end
    end
  end
  return out
end

-- Recompute medal rankings for a registered table and push targeted updates for changes
function M.RecomputeMedals(name)
  local T = M._tables[name]; if not T then return end
  local dt = T.dt; if not (dt and dt._rawData) then return end

  -- Enumerate all player rows from top-level categories if present, else flat rows
  local players = {}
  local rowByFull = {}
  local function addRow(r)
    if r and not r.isCategory and r.key then players[#players+1] = r.key; rowByFull[r.key] = r end
  end
  local raw = dt._rawData or {}
  if #raw > 0 and raw[1] and raw[1].isCategory then
    for i=1,#raw do
      local cat = raw[i]
      if cat and type(cat.children) == 'table' then
        for j=1,#cat.children do addRow(cat.children[j]) end
      end
    end
  else
    for i=1,#raw do addRow(raw[i]) end
  end

  -- Build arrays for ilvlMax and mplus
  local arrIlvl, arrMplus = {}, {}
  local scoreByFull, ilvlMaxByFull = {}, {}
  for i=1,#players do
    local full = players[i]
    local k = keyOf(full)
    local mx = (GLOG and GLOG.GetIlvlMax and GLOG.GetIlvlMax(k)) or 0
    local sc = (GLOG and GLOG.GetMPlusScore and GLOG.GetMPlusScore(k)) or 0
    arrIlvl[#arrIlvl+1] = { key = full, v = mx or 0 }
    arrMplus[#arrMplus+1] = { key = full, v = sc or 0 }
    scoreByFull[full] = tonumber(sc) or 0
    ilvlMaxByFull[full] = tonumber(mx) or 0
  end

  local newIl = _computeTopMap(arrIlvl)
  local newMp = _computeTopMap(arrMplus)

  T._medals = T._medals or { ilvl = {}, mplus = {} }
  local oldIl, oldMp = T._medals.ilvl or {}, T._medals.mplus or {}
  local changedIl, changedMp = {}, {}
  -- Compare old/new to detect changes, including removals
  local seen = {}
  for _, full in ipairs(players) do
    local a, b = oldIl[full], newIl[full]
    if a ~= b then changedIl[#changedIl+1] = full end
    local c, d = oldMp[full], newMp[full]
    if c ~= d then changedMp[#changedMp+1] = full end
    seen[full] = true
  end
  -- If some players left the table, they implicitly lose medals; account for that
  for full,_ in pairs(oldIl) do if not seen[full] then changedIl[#changedIl+1] = full end end
  for full,_ in pairs(oldMp) do if not seen[full] then changedMp[#changedMp+1] = full end end

  -- Store new maps
  T._medals.ilvl  = newIl
  T._medals.mplus = newMp

  -- Persist ranks into raw data so future full re-renders keep medals
  local function _injectIlvl(full)
    local r = rowByFull[full]
    if not (r and r.cells) then return end
    local v = r.cells.ilvl
    if type(v) ~= 'table' then return end
    local il  = tonumber(v[1] or 0) or 0
    local mx  = tonumber(v[2] or 0) or 0
    local on  = (v[3] and true) or false
    local rank= newIl[full]
    v.rank = rank
    v.sig  = table.concat({ tostring(il or 0), tostring(mx or 0), on and 1 or 0, tostring(rank or 0) }, "|")
  end
  local function _injectMplus(full)
    local r = rowByFull[full]
    if not (r and r.cells) then return end
    local sc = scoreByFull[full] or 0
    local rank = newMp[full]
    r.cells.mplus = { score = sc, rank = rank, sig = table.concat({ tostring(sc or 0), tostring(rank or 0) }, "|") }
  end
  for i=1,#changedIl do _injectIlvl(changedIl[i]) end
  for i=1,#changedMp do _injectMplus(changedMp[i]) end

  -- Emit targeted cell updates for impacted rows only (reflect changes immediately)
  for i=1,#changedIl do _updateCellFor(name, 'ilvl', changedIl[i]) end
  for i=1,#changedMp do _updateCellFor(name, 'mplus', changedMp[i]) end
end

-- Update a single player's iLvl cell if changed
function M.UpdateIlvl(full)
  local dt = M.dt; if not dt then return end
  local il, mx, on = getIlvlTuple(full)
  local prev = last.ilvl[full]
  if not prev or prev[1] ~= il or prev[2] ~= mx or prev[3] ~= on then
    last.ilvl[full] = { il, mx, on }
    -- Try include current medal rank if available to preserve icon
    local rank = nil
  if M.GetMedalRank then rank = M.GetMedalRank("guild", 'ilvl', full) end
      dt:UpdateCell(full, "ilvl", { il, mx, on, rank = rank, sig = table.concat({ tostring(il or 0), tostring(mx or 0), on and 1 or 0, tostring(rank or 0) }, "|") })
  end
end

-- Update a single player's ping cell if cooldown/online/version changed
function M.UpdatePing(full)
  local dt = M.dt; if not dt then return end
  local on = getOnline(full)
  local ver = getVersion(full)
  local gi = (GLOG and GLOG.GetMainAggregatedInfo and GLOG.GetMainAggregatedInfo(full)) or {}
  local recipient = (gi and gi.onlineAltFull) or full
  local cdFn = ns and ns._guildDynTable and ns._guildDynTable._pingRemaining or nil
    -- we don't directly access private; recompute bucket using the Guild table helper when available
  local cdLeft = 0
  if ns and ns._guildDynTable_pingRemaining then cdLeft = ns._guildDynTable_pingRemaining(recipient) end
  local bucket = math.floor((tonumber(cdLeft) or 0)/5)
  local pv = last.pingCD[full]
  local pvO = last.online[full]
  local pvV = last.version[full]
  if pv ~= bucket or pvO ~= on or pvV ~= ver then
    last.pingCD[full] = bucket
    last.online[full] = on
    last.version[full] = ver
    dt:UpdateCell(full, "ping", { name = full, sig = table.concat({ full, on and 1 or 0, 0, 0, bucket }, "|") })
  end
end

-- Notify data changes in a declarative way
-- changeKey: e.g., "ilvl", "level", "online", "version"
-- payload: { player = fullKey }
function M.Notify(changeKey, payload)
  -- Skip any UI work if not visible; we only perform targeted per-cell updates when the UI is active
  if UI and UI.ShouldRefreshUI and not UI.ShouldRefreshUI() then return end
  local p = payload or {}
  local full = p.player or p.name or p.full
  if not full then return end
  -- Built-in fallbacks if no registry is set
  local actions = M._effects[changeKey]
  if type(actions) ~= 'table' or #actions == 0 then
  -- Legacy direct updates
    if changeKey == 'ilvl' then M.UpdateIlvl(full) end
    if changeKey == 'ping' or changeKey == 'version' or changeKey == 'online' then M.UpdatePing(full) end
    return
  end
  -- Execute declarative actions
  for i = 1, #actions do
    local a = actions[i]
    if a and a.table then
      if a.col then
        _updateCellFor(a.table, a.col, full)
      end
      if a.relocate then
        _relocateIfNeeded(a.table, a.relocate, full)
      end
    end
  end
  -- If score/ilvl changed, recompute medals once per table (cheap O(n log n))
  if changeKey == 'ilvl' or changeKey == 'mplus' then
    for name, T in pairs(M._tables) do
      if T and T.dt and T.dt._rawData then M.RecomputeMedals(name) end
    end
  end
  -- Apply batched minimal re-renders for tables marked dirty
  for name, dirty in pairs(M._dirty) do
    if dirty then
      local T = M._tables[name]
      if T and T.dt then
        if T.dt.DiffAndApply then T.dt:DiffAndApply(T.dt._rawData) else T.dt:SetData(T.dt._rawData) end
      end
      M._dirty[name] = false
    end
  end
end

-- Bulk helpers from event handlers
function M.BulkFromRoster()
  local dt = M.dt; if not dt then return end
  -- Skip updates when UI is not visible (performance + avoid unnecessary work)
  if UI and UI.ShouldRefreshUI and not UI.ShouldRefreshUI() then return end
  if dt.parent and dt.parent.IsShown and (not dt.parent:IsShown()) then return end
  -- Remove group category entirely if player is no longer grouped
  do
    local grouped = (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) or ((GetNumGroupMembers and (GetNumGroupMembers() or 0) > 0) and true) or false
    local raw = dt._rawData or {}
    local specTbl
    for name, sp in pairs(M._tables) do if sp and sp.dt == dt then specTbl = sp; break end end
    if specTbl and specTbl.relocate and specTbl.relocate.groupCategories then
      local gk = specTbl.relocate.groupCategories.groupKey or "__cat_group"
      local ok = specTbl.relocate.groupCategories.onlineKey or "__cat_online"
      local fk = specTbl.relocate.groupCategories.offlineKey or "__cat_offline"
      local catIdx, catGrp, catOn, catOff
      for i = 1, #raw do local c = raw[i]; if c and c.isCategory then if c.key == gk then catIdx, catGrp = i, c elseif c.key == ok then catOn = c elseif c.key == fk then catOff = c end end end
      if not grouped and catGrp and catIdx then
        -- move all children back to online/offline then remove the group category
        local moved = false
        for i = #catGrp.children, 1, -1 do
          local r = catGrp.children[i]
          table.remove(catGrp.children, i)
          local on = getOnline(r.key)
          local tgt = on and catOn or catOff
          if tgt then table.insert(tgt.children, r); moved = true end
          r._meta = r._meta or {}; r._meta.ingrp = false; r._meta.online = on and true or false
        end
        table.remove(raw, catIdx)
        if catOn then catOn.count = #catOn.children end
        if catOff then catOff.count = #catOff.children end
        M._dirty[ (function() for nm, sp in pairs(M._tables) do if sp and sp.dt == dt then return nm end end end)() or "" ] = true
      end
    end
  end

  -- Iterate visible rows for efficiency
  for i = 1, dt:Count() do
    local row = dt._flatData and dt._flatData[i]
    if row and not row.isCategory then
      local full = row.key
      -- Detect change by comparing live state vs current category
      local on = getOnline(full)
      local catState = (row._meta and row._meta.online) or false
      if catState ~= on then
        -- Perform full online-change handling once per affected row
        if M._effects and M._effects.online then
          M.Notify('online', { player = full })
        else
          -- Fallback: relocate + minimal cell updates
          _relocateIfNeeded("guild", 'onlineCategories', full)
          M.UpdateIlvl(full)
          M.UpdatePing(full)
        end
        last.online[full] = on
      end
      -- Detect group membership changes and relocate accordingly
      local ing = (GLOG and GLOG.IsInMyGroup and GLOG.IsInMyGroup(full)) or false
      local metaIn = (row._meta and row._meta.ingrp) or false
      if ing ~= metaIn then
        if M._effects and M._effects.group then
          M.Notify('group', { player = full })
        else
          _relocateIfNeeded("guild", 'groupCategories', full)
        end
      end
      -- Also refresh the localisation (zone) cell opportunistically on roster ticks
      -- Only meaningful for online players; diffed via signatures to avoid redundant work.
      if on and M._effects and M._effects.zone then
        M.Notify('zone', { player = full })
      end
    end
  end
  -- After the first visible bulk pass, ensure medals reflect current data
  if M.RecomputeMedals then
    for name, T in pairs(M._tables) do
      if T and T.dt == dt then M.RecomputeMedals(name) end
    end
  end
  -- Apply batched diffs for declarative dirty tables
  local anyDirty = false
  for name, d in pairs(M._dirty) do if d then anyDirty = true; break end end
  if anyDirty then
    for name, d in pairs(M._dirty) do
      if d then
        local T = M._tables[name]
        if T and T.dt then if T.dt.DiffAndApply then T.dt:DiffAndApply(T.dt._rawData) else T.dt:SetData(T.dt._rawData) end end
        M._dirty[name] = false
      end
    end
  elseif M._dirtyRelocations then
    M._dirtyRelocations = false
    if dt.DiffAndApply then dt:DiffAndApply(dt._rawData) else dt:SetData(dt._rawData) end
  end
end

return M
