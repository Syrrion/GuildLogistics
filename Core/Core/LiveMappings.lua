local ADDON, ns = ...
local Tr  = ns and ns.Tr
local UI  = ns and ns.UI
local GLOG= ns and ns.GLOG

-- Central declarations for LiveCellUpdater
-- Register all tables/columns + effects in one place so tabs only attach instances.

local M = {}

local function _DBKey(name)
  if GLOG and GLOG.NormalizeDBKey then return GLOG.NormalizeDBKey(name) end
  return tostring(name or "")
end

local function FindGuildInfo(playerName)
  return (GLOG and GLOG.GetMainAggregatedInfo and GLOG.GetMainAggregatedInfo(playerName or "")) or {}
end

local function _pingRemaining(full)
  if ns and ns._guildDynTable_pingRemaining then return ns._guildDynTable_pingRemaining(full) end
  return 0
end

local function _GetLiveZoneForMember(playerName, gi)
  gi = gi or FindGuildInfo(playerName or "")
  if gi then
    local idx = gi.onlineAltIdx or gi.idx
    if idx and GetGuildRosterInfo then
      local name, rank, rankIndex, level, classDisplayName, zone, note, officerNote, online = GetGuildRosterInfo(idx)
      if online and zone and zone ~= "" then
        return zone
      end
    end
  end
  return (GLOG and GLOG.GetAnyOnlineZone and GLOG.GetAnyOnlineZone(playerName)) or nil
end

function M.RegisterAll()
  if not (ns and ns.LiveCellUpdater) then return end
  local LCU = ns.LiveCellUpdater

  -- Guild logical columns
  LCU.RegisterTable("guild", {
    cols = {
      ilvl = {
        colKey = "ilvl",
        valueFn = function(full)
          local key = _DBKey(full)
          local il  = (GLOG and GLOG.GetIlvl    and GLOG.GetIlvl(key))    or 0
          local mx  = (GLOG and GLOG.GetIlvlMax and GLOG.GetIlvlMax(key)) or 0
          local gi  = FindGuildInfo(full)
          local on  = gi and gi.online and true or false
          local rank = ns and ns.LiveCellUpdater and ns.LiveCellUpdater.GetMedalRank and ns.LiveCellUpdater.GetMedalRank("guild", 'ilvl', full) or nil
          return { il, mx, on, rank = rank, sig = table.concat({ tostring(il or 0), tostring(mx or 0), on and 1 or 0, tostring(rank or 0) }, "|") }
        end,
      },
      ping = {
        colKey = "ping",
        valueFn = function(full)
          local gi = FindGuildInfo(full)
          local recipient = (gi and gi.onlineAltFull) or full
          local cd = _pingRemaining(recipient)
          local bucket = math.floor((tonumber(cd) or 0)/5)
          local on = gi and gi.online and true or false
          return { name = full, sig = table.concat({ full, on and 1 or 0, 0, 0, bucket }, "|") }
        end,
      },
      lvl = {
        colKey = "lvl",
        valueFn = function(full)
          local gi = FindGuildInfo(full)
          local lvl = tonumber(gi and gi.level or 0) or 0
          return lvl
        end,
      },
      last = {
        colKey = "last",
        valueFn = function(full)
          local gi = FindGuildInfo(full)
          local online = gi and gi.online and true or false
          if online then
            local loc = _GetLiveZoneForMember(full, gi)
            return (loc and loc ~= "" and loc) or (Tr and Tr("status_online")) or "Online"
          else
            if gi and (gi.days or gi.hours) and ns and ns.Format and ns.Format.LastSeen then
              return ns.Format.LastSeen(gi.days, gi.hours)
            else
              return (Tr and Tr("status_empty")) or "—"
            end
          end
        end,
      },
      mplus = {
        colKey = "mplus",
        valueFn = function(full)
          local key = _DBKey(full)
          local score = (GLOG and GLOG.GetMPlusScore and GLOG.GetMPlusScore(key)) or 0
          local rank = ns and ns.LiveCellUpdater and ns.LiveCellUpdater.GetMedalRank and ns.LiveCellUpdater.GetMedalRank("guild", 'mplus', full) or nil
          return { score = tonumber(score) or 0, rank = rank, sig = table.concat({ tostring(score or 0), tostring(rank or 0) }, "|") }
        end,
      },
      mkey = {
        colKey = "mkey",
        valueFn = function(full)
          local key = _DBKey(full)
          local txt = (GLOG and GLOG.GetMKeyText and GLOG.GetMKeyText(key)) or ""
          return txt
        end,
      },
      ver = {
        colKey = "ver",
        valueFn = function(full)
          local key = _DBKey(full)
          local ver = (GLOG and GLOG.GetPlayerAddonVersion and GLOG.GetPlayerAddonVersion(key)) or ""
          return (ver ~= "" and ("v"..ver) or "—")
        end,
      },
    },
    relocate = {
      onlineCategories = { onlineKey = "__cat_online", offlineKey = "__cat_offline" },
      groupCategories  = { groupKey  = "__cat_group",  onlineKey = "__cat_online", offlineKey = "__cat_offline" },
    },
  })

  -- Effects mapping (extend here as needed)
  LCU.RegisterEffect("ilvl",   { { table = "guild", col = "ilvl" } })
  LCU.RegisterEffect("version",{ { table = "guild", col = "ping" }, { table = "guild", col = "ver" } })
  LCU.RegisterEffect("online", { { table = "guild", relocate = "onlineCategories" }, { table = "guild", col = "ping" }, { table = "guild", col = "ilvl" }, { table = "guild", col = "last" } })
  LCU.RegisterEffect("level",  { { table = "guild", col = "lvl" } })
  LCU.RegisterEffect("zone",   { { table = "guild", col = "last" } })
  LCU.RegisterEffect("mplus",  { { table = "guild", col = "mplus" }, { table = "guild", col = "mkey" } })
  -- New: group membership change → relocate row into In-Group category or back to Online/Offline
  LCU.RegisterEffect("group",  { { table = "guild", relocate = "groupCategories" } })

  -- Medal recompute triggers: when iLvlMax changes or M+ score changes, refresh medal maps
  if ns and ns.LiveCellUpdater and ns.LiveCellUpdater.RecomputeMedals then
    local _oldIlvl = LCU._onIlvl
    LCU._onIlvl = function(full)
      if _oldIlvl then _oldIlvl(full) end
      ns.LiveCellUpdater.RecomputeMedals("guild")
    end
  end

  -- =========================
  -- Roster logical table
  -- =========================
  LCU.RegisterTable("roster", {
    cols = {
      solde = {
        colKey = "solde",
        valueFn = function(full)
          local bal = (GLOG and GLOG.GetSolde and GLOG.GetSolde(full)) or 0
          return tonumber(bal) or 0
        end,
      },
      lvl = {
        colKey = "lvl",
        valueFn = function(full)
          local gi = (GLOG and GLOG.GetMainAggregatedInfo and GLOG.GetMainAggregatedInfo(full)) or {}
          return tonumber(gi and gi.level or 0) or 0
        end,
      },
      alias = {
        colKey = "alias",
        valueFn = function(full)
          local a = (GLOG and GLOG.GetAliasFor and GLOG.GetAliasFor(full)) or ""
          if a == "" then a = (tostring(full):match("^([^%-]+)") or tostring(full) or "") end
          return a
        end,
      },
    },
    relocate = {
      reserveCategories = { activeKey = "__cat_active", reserveKey = "__cat_reserve" },
    },
  })

  -- Effects for roster: balance change updates solde cell; reserve toggles relocate between categories
  LCU.RegisterEffect("balance", { { table = "roster", col = "solde" } })
  LCU.RegisterEffect("reserve", { { table = "roster", relocate = "reserveCategories" } })
end

-- Auto-register on load
M.RegisterAll()

ns.LiveMappings = M
