local ADDON, ns = ...
local Tr = ns and ns.Tr
local UI = ns and ns.UI
local GLOG = ns and ns.GLOG

local panel, footer, dt
local noGuildMsg
local content -- container for header + table (to toggle as a whole)

-- ==== Helpers (mirroring Guild tab, simplified) ====
local function _DBKey(name)
    if GLOG and GLOG.NormalizeDBKey then return GLOG.NormalizeDBKey(name) end
    return tostring(name or "")
end

local function FindGuildInfo(playerName)
    return (GLOG and GLOG.GetMainAggregatedInfo and GLOG.GetMainAggregatedInfo(playerName or "")) or {}
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

local function _GetMeFull()
    local name = UnitName and UnitName("player") or nil
    local realm = GetRealmName and GetRealmName() or nil
    if name and name ~= "" then
        if ns and ns.Util and ns.Util.NormalizeFull then
            return ns.Util.NormalizeFull(name, realm)
        end
        return (realm and realm ~= "") and (name.."-"..realm) or name
    end
    return ""
end

-- ==== Ping (notification cloche) – même logique que l'onglet Guilde ====
local _pingCooldown = {}
local function _normalizeName(full)
    local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
    local s = nf(full or "")
    return tostring(s):lower()
end
local function _pingRemaining(full)
    local key = _normalizeName(full)
    local t = (GetTimePreciseSec and GetTimePreciseSec()) or (GetTime and GetTime()) or 0
    local untilT = tonumber(_pingCooldown[key] or 0) or 0
    local left = math.ceil(math.max(0, untilT - t))
    return left
end
-- Expose helper for LiveMappings/Updater
ns._guildDynTable_pingRemaining = _pingRemaining
local function _setPingCooldown(full, seconds)
    local key = _normalizeName(full)
    local t = (GetTimePreciseSec and GetTimePreciseSec()) or (GetTime and GetTime()) or 0
    _pingCooldown[key] = t + (seconds or 90)
end

local function _SortMembers(items)
    local online, offline = {}, {}
    for i = 1, #(items or {}) do
        local it = items[i]
        local gi = it._gi or FindGuildInfo(it.name or "")
        it._gi = gi
        local alias = (GLOG and GLOG.GetAliasFor and GLOG.GetAliasFor(it.name)) or ""
        if not alias or alias == "" then
            alias = (tostring(it.name):match("^([^%-]+)") or tostring(it.name) or "")
        end
        it._sortAlias = tostring(alias):lower()

        local hrs = nil
        if gi and (gi.days ~= nil or gi.hours ~= nil) then
            local d = tonumber(gi.days or 0)  or 0
            local h = tonumber(gi.hours or 0) or 0
            hrs = d * 24 + h
        end
        it._sortHrs = hrs or math.huge

        if gi and gi.online then table.insert(online, it) else table.insert(offline, it) end
    end
    table.sort(online,  function(a,b)
        if a._sortAlias ~= b._sortAlias then return a._sortAlias < b._sortAlias end
        local an, bn = (a.name or ""):lower(), (b.name or ""):lower()
        return an < bn
    end)
    table.sort(offline, function(a,b)
        if a._sortHrs ~= b._sortHrs then return a._sortHrs < b._sortHrs end
        if a._sortAlias ~= b._sortAlias then return a._sortAlias < b._sortAlias end
        local an, bn = (a.name or ""):lower(), (b.name or ""):lower()
        return an < bn
    end)
    local out = {}
    for _, x in ipairs(online)  do out[#out+1] = x end
    for _, x in ipairs(offline) do out[#out+1] = x end
    return out
end

-- ==== Data builder for DynamicTable ====
local function BuildRows()
    -- Ensure cache ready or trigger refresh
    local need = (not GLOG or not GLOG.IsGuildCacheReady or not GLOG.IsGuildCacheReady())
    if not need and GLOG and GLOG.GetGuildCacheTimestamp then
        local age = time() - (GLOG.GetGuildCacheTimestamp() or 0)
        if age > 60 then need = true end
    end
    if need and GLOG and GLOG.RefreshGuildCache then
        GLOG.RefreshGuildCache(function()
            if ns and ns.RefreshAll then ns.RefreshAll() elseif UI and UI.RefreshAll then UI.RefreshAll() end
        end)
        return {}
    end

    local agg = (GLOG and (GLOG.GetGuildMainsAggregated and GLOG.GetGuildMainsAggregated() or GLOG.GetGuildMainsAggregatedCached and GLOG.GetGuildMainsAggregatedCached())) or {}
    local base = {}
    local resolve = GLOG and GLOG.ResolveFullName
    for i = 1, #agg do
        local e = agg[i]
        local full = (resolve and resolve(e.main)) or e.mostRecentChar or e.main
        local gi = FindGuildInfo(full or "")
        base[#base+1] = { name = full, _gi = gi }
    end

    local sorted = _SortMembers(base)

    -- Pre-compute top-3 ranks for M+ (score) and iLvl MAX (ex aequo share same place)
    local function computeTopMap(pairs)
        table.sort(pairs, function(a,b) return (tonumber(a.v) or 0) > (tonumber(b.v) or 0) end)
        local topVals, seen = {}, {}
        for i = 1, #pairs do
            local v = tonumber(pairs[i].v) or 0
            if not seen[v] then
                topVals[#topVals+1] = v
                seen[v] = true
                if #topVals >= 3 then break end
            end
        end
        local valToPlace = {}
        for idx, v in ipairs(topVals) do valToPlace[v] = idx end
        local out = {}
        if #topVals > 0 then
            for i = 1, #pairs do
                local v = tonumber(pairs[i].v) or 0
                local place = valToPlace[v]
                if place then out[pairs[i].key] = place end
            end
        end
        return out
    end
    local arrMplus, arrIlvlMax = {}, {}
    do
        for i = 1, #sorted do
            local it = sorted[i]
            local key = _DBKey(it.name)
            local score = (GLOG and GLOG.GetMPlusScore and GLOG.GetMPlusScore(key)) or 0
            local ilvlMax = (GLOG and GLOG.GetIlvlMax and GLOG.GetIlvlMax(key)) or 0
            arrMplus[#arrMplus+1]   = { key = it.name, v = tonumber(score) or 0 }
            arrIlvlMax[#arrIlvlMax+1] = { key = it.name, v = tonumber(ilvlMax) or 0 }
        end
    end
    local mplusRanks = computeTopMap(arrMplus)
    local ilvlRanks  = computeTopMap(arrIlvlMax)

    -- Build data rows first (no categories yet)
    local rows = {}
    local me = _GetMeFull()
    for i = 1, #sorted do
        local it = sorted[i]
        local gi = it._gi or FindGuildInfo(it.name or "")
        local key = _DBKey(it.name)
        local alias = (GLOG and GLOG.GetAliasFor and GLOG.GetAliasFor(it.name)) or ""
        if not alias or alias == "" then
            alias = (tostring(it.name):match("^([^%-]+)") or tostring(it.name) or "")
        end

        local online = gi and gi.online and true or false
        local lvl = tonumber(gi and gi.level or 0) or 0
        local score = (GLOG and GLOG.GetMPlusScore and GLOG.GetMPlusScore(key)) or 0
        local mkeyTxt = (GLOG and GLOG.GetMKeyText and GLOG.GetMKeyText(key)) or ""
        local ilvl    = (GLOG and GLOG.GetIlvl    and GLOG.GetIlvl(key))    or 0
        local ilvlMax = (GLOG and GLOG.GetIlvlMax and GLOG.GetIlvlMax(key)) or 0
    local ver     = (GLOG and GLOG.GetPlayerAddonVersion and GLOG.GetPlayerAddonVersion(key)) or ""

        local lastTxt
        if online then
            local loc = _GetLiveZoneForMember(it.name, gi)
            lastTxt = (loc and loc ~= "" and loc) or Tr("status_online")
        else
            if gi and (gi.days or gi.hours) and ns and ns.Format and ns.Format.LastSeen then
                lastTxt = ns.Format.LastSeen(gi.days, gi.hours)
            else
                lastTxt = Tr("status_empty")
            end
        end

        -- Build name value with alt short and a signature including both
        local altShort
        if gi and gi.onlineAltBase then
            altShort = (ns and ns.Util and ns.Util.ShortenFullName and ns.Util.ShortenFullName(gi.onlineAltFull or gi.onlineAltBase)) or gi.onlineAltBase
        end

        -- Prépare la signature ping pour forcer le rafraîchissement quand l'état change
        local isSelf = false
        if me and me ~= "" then
            if ns and ns.Util and ns.Util.SamePlayer then
                isSelf = ns.Util.SamePlayer(it.name, me)
            else
                local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
                isSelf = tostring(nf(it.name)):lower() == tostring(nf(me)):lower()
            end
        end
        local versionOk = false
        do
            if ver ~= "" then
                local cmp = ns and ns.Util and ns.Util.CompareVersions
                versionOk = (not cmp) or (cmp(ver, "4.2.4") >= 0)
            end
        end
        local recipient = (gi and gi.onlineAltFull) or it.name
        local cdLeft = _pingRemaining and _pingRemaining(recipient) or 0
        -- bucket pour limiter les rafraîchissements: tranche de 5s
        local cdBucket = math.floor((tonumber(cdLeft) or 0) / 5)

        local row = {
            key = it.name,
            _meta = { gi = gi, online = online, me = me },
            cells = {
                accent = true,
                -- valeur table + signature dynamique pour update fiable
                ping   = { name = it.name, sig = table.concat({ tostring(it.name or ""), online and 1 or 0, isSelf and 1 or 0, versionOk and 1 or 0, cdBucket }, "|") },
                alias  = alias,
                lvl    = lvl,
                name   = { text = it.name, alt = altShort, sig = tostring(it.name or "") .. "|" .. tostring(altShort or "") },
                last   = lastTxt,
                ilvl   = { ilvl, ilvlMax, online, rank = ilvlRanks[it.name], sig = table.concat({ tostring(ilvl or 0), tostring(ilvlMax or 0), online and 1 or 0, tostring(ilvlRanks[it.name] or 0) }, "|") },
                ilvlNum= ilvl,
                mplus  = { score = score, rank = mplusRanks[it.name], sig = table.concat({ tostring(score or 0), tostring(mplusRanks[it.name] or 0) }, "|") },
                mkey   = mkeyTxt,
                ver    = (ver ~= "" and ("v"..ver) or "—"),
            },
        }
        rows[#rows+1] = row
    end
    -- Group into categories (In group → Online → Offline)
    local grouped = (IsInGroup and IsInGroup()) or (IsInRaid and IsInRaid()) or ((GetNumGroupMembers and (GetNumGroupMembers() or 0) > 0) and true) or false
    local cats = {
        ingrp  = grouped and { key = "__cat_group",  isCategory = true, expanded = true, title = (Tr and Tr("lbl_sep_ingroup")) or "Dans le groupe", children = {} } or nil,
        online = { key = "__cat_online",  isCategory = true, expanded = true, title = Tr and Tr("status_online")  or "Online",  children = {} },
        offline= { key = "__cat_offline", isCategory = true, expanded = true, title = Tr and Tr("status_offline") or "Offline", children = {} },
    }
    for i = 1, #rows do
        local r = rows[i]
        local gi = r._meta and r._meta.gi
        local online = gi and gi.online and true or false
        local same = (grouped and GLOG and GLOG.IsInMyGroup and GLOG.IsInMyGroup(r.key)) or false
        r._meta = r._meta or {}; r._meta.online = online; r._meta.ingrp = same
        if grouped and same and cats.ingrp then
            table.insert(cats.ingrp.children, r)
        else
            if online then table.insert(cats.online.children, r) else table.insert(cats.offline.children, r) end
        end
    end
    if cats.ingrp then cats.ingrp.count = #cats.ingrp.children end
    cats.online.count = #cats.online.children; cats.offline.count = #cats.offline.children
    if cats.ingrp then return { cats.ingrp, cats.online, cats.offline } else return { cats.online, cats.offline } end
end

-- ==== Column defs ====
local function BuildColumns()
    return UI.NormalizeColumns({
                { key = "accent", leftAccent = true, w = 3, vsep = false, sortable = false,
                    accentOf = function(row)
                        -- Requested: remove group liserai (always disable accent)
                        return false
                    end
                },
        -- Colonne cloche (ping) : identique à l'onglet Guilde
        (function()
            local isStandalone = (GLOG and GLOG.IsStandaloneMode and GLOG.IsStandaloneMode()) or false
            if isStandalone then return nil end
            return {
                key = "ping", title = "", w = 28, justify = "CENTER", vsep = true, sortable = false,
                forceUpdate = true,
                buildCell = function(parent)
                    local ICON = "Interface\\ICONS\\INV_Misc_Bell_01"
                    -- force square icon regardless of cell aspect: fit within button, aspect=1, no padding
                    local btn = UI.IconButton(parent, ICON, { size = 18, tooltip = Tr and Tr("tip_ping") or "Ping", fit = true, aspect = 1, pad = 0 })
                    if btn.SetMotionScriptsWhileDisabled then btn:SetMotionScriptsWhileDisabled(true) end
                    btn:EnableMouse(true)
                    return btn
                end,
                updateCell = function(cell, v)
                    -- v can be string (full name) or table { name=full, sig=... }
                    if not cell then return end
                    local name = (type(v) == 'table' and v.name) or (type(v) == 'string' and v) or nil
                    -- Hide on category rows (no value) or missing name
                    if not name or name == "" then cell:Hide(); return end

                    local gi = FindGuildInfo(name)
                    local online = gi and gi.online and true or false

                    -- self-check
                    local me = _GetMeFull()
                    local isSelf = false
                    if me and me ~= "" then
                        if ns and ns.Util and ns.Util.SamePlayer then
                            isSelf = ns.Util.SamePlayer(name, me)
                        else
                            local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
                            isSelf = tostring(nf(name)):lower() == tostring(nf(me)):lower()
                        end
                    end

                    -- Version gate (hide if missing or < 4.2.4)
                    local hideForVersion = false
                    if not isSelf then
                        local key = _DBKey(name)
                        local ver = (GLOG and GLOG.GetPlayerAddonVersion and GLOG.GetPlayerAddonVersion(key)) or ""
                        if ver == "" then
                            hideForVersion = true
                        else
                            local cmp = ns and ns.Util and ns.Util.CompareVersions
                            if cmp and cmp(ver, "4.2.4") < 0 then hideForVersion = true end
                        end
                    end

                    if isSelf or hideForVersion or not online then
                        cell:Hide()
                        return
                    end

                    cell:Show()

                    -- Determine recipient (prefer online alt full if present)
                    local recipient = (gi and gi.onlineAltFull) or name

                    -- Privileged users bypass cooldown
                    local isPrivileged = false
                    if GLOG then
                        if GLOG.CanModifyGuildData and GLOG.CanModifyGuildData() then
                            isPrivileged = true
                        elseif GLOG.IsOfficer and GLOG.IsOfficer() then
                            isPrivileged = true
                        end
                    end
                    local cdLeft = isPrivileged and 0 or _pingRemaining(recipient)
                    local enabled = online and (cdLeft <= 0)
                    if cell.SetEnabled then cell:SetEnabled(enabled) end
                    if cell.SetAlpha then cell:SetAlpha(enabled and 1 or 0.45) end

                    -- Tooltip reflecting state
                    cell:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        if not self:IsEnabled() then
                            local left = isPrivileged and 0 or _pingRemaining(recipient)
                            if left > 0 then
                                GameTooltip:SetText((Tr and Tr("tip_disabled_ping_cd_fmt") or "On cooldown: %ds remaining"):format(left))
                            else
                                GameTooltip:SetText((Tr and Tr("tip_disabled_offline_group")) or "Disabled: none of this player's characters are online")
                            end
                        else
                            GameTooltip:SetText((Tr and Tr("tip_ping")) or "Ping this player")
                        end
                        GameTooltip:Show()
                    end)
                    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)

                    -- Click handler
                    if cell.SetOnClick then
                        cell:SetOnClick(function()
                            if not enabled then return end
                            local function send(msg)
                                if not (GLOG and GLOG.Comm_Whisper) then return end
                                local payload = { ts = (GetTime and GetTime()) or 0 }
                                if type(msg) == "string" then
                                    local trimmed = (msg:gsub("^%s+", "")):gsub("%s+$", "")
                                    if trimmed ~= "" then payload.msg = trimmed end
                                end
                                GLOG.Comm_Whisper(recipient, "PING", payload)
                                if not isPrivileged then _setPingCooldown(recipient, 90) end
                                if dt and dt.UpdateVisibleRows then dt:UpdateVisibleRows() elseif ns and ns.RefreshAll then ns.RefreshAll() end
                            end

                            if UI and UI.PopupPromptText then
                                UI.PopupPromptText(Tr and Tr("popup_ping_title") or "Ping", Tr and Tr("lbl_ping_message") or "Message (optionnel)", function(text)
                                    local t = type(text) == "string" and text or ""
                                    t = (t:gsub("^%s+", "")):gsub("%s+$", "")
                                    if #t > 120 then t = string.sub(t, 1, 120) end
                                    send(t)
                                end, { width = 420, placeholder = Tr and Tr("ph_ping_message") or "Ex: besoin d'un coup de main?", maxLen = 120 })
                            else
                                send(nil)
                            end
                        end)
                    else
                        -- Fallback
                        cell:SetScript("OnClick", function()
                            if not enabled then return end
                            local payload = { ts = (GetTime and GetTime()) or 0 }
                            if GLOG and GLOG.Comm_Whisper then GLOG.Comm_Whisper(recipient, "PING", payload) end
                            if not isPrivileged then _setPingCooldown(recipient, 90) end
                            if dt and dt.UpdateVisibleRows then dt:UpdateVisibleRows() end
                        end)
                    end
                end
            }
        end)(),
        { key = "alias",  title = Tr("col_alias"),          w = 90,  justify = "LEFT",   vsep = true,  sortValue = "alias" },
        { key = "lvl",    title = Tr("col_level_short"),    w = 44,  justify = "CENTER", vsep = true,  sortNumeric = true, sortValue = "lvl" },
        { key = "name",   title = Tr("col_name"),           flex = 1, min = 120, justify = "LEFT",  vsep = true,
          buildCell = function(parent) return UI.CreateNameTag(parent) end,
          updateCell = function(cell, v)
              local full = type(v) == 'table' and v.text or v
              if UI and UI.SetNameTagShort then UI.SetNameTagShort(cell, full or "") else if cell and cell.SetText then cell:SetText(full or "") end end
              local altShort = type(v) == 'table' and v.alt or nil
              if altShort and altShort ~= "" and cell and cell.text and cell.text.GetText then
                  local baseText = cell.text:GetText() or ""
                  local altPart = (" |cffaaaaaa( %s )|r"):format(altShort)
                  cell.text:SetText(baseText .. altPart)
              end
          end
        },
        { key = "last",   title = Tr("col_attendance"),     w = 200, justify = "LEFT",   vsep = true },
        { key = "ilvl",   title = Tr("col_ilvl"),           w = 120, justify = "CENTER", vsep = true,
          sortNumeric = true, sortValue = "ilvlNum",
          buildCell = function(parent)
              local host = CreateFrame("Frame", nil, parent)
              host.txt = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
              if UI and UI.ApplyFont then UI.ApplyFont(host.txt) end
              host.txt:SetJustifyH("CENTER")
              host.txt:SetPoint("CENTER", host, "CENTER", 0, 0)
              host.medal = host:CreateTexture(nil, "ARTWORK")
              host.medal:SetSize(18,18)
              host.medal:SetPoint("LEFT", host, "LEFT", 0, 0)
              host.medal:Hide()
              return host
          end,
          updateCell = function(cell, v)
              local il, mx, online, rank = 0, 0, false, nil
              if type(v) == 'table' then
                  il, mx, online, rank = (v[1] or 0), (v[2] or 0), (v[3] and true or false), v.rank
              end
              local function gray(t)
                  local GHX = (UI and UI.GRAY_OFFLINE_HEX) or "999999"
                  return "|cff"..GHX..tostring(t).."|r"
              end
              if online then
                  if il and il > 0 then
                      if mx and mx > 0 then
                          cell.txt:SetText(('%d '..gray('('..mx..')')):format(il))
                      else
                          cell.txt:SetText(tostring(il))
                      end
                  else
                      cell.txt:SetText(gray(Tr("status_empty")))
                  end
              else
                  if il and il > 0 then
                      if mx and mx > 0 then
                          cell.txt:SetText(gray(('%d (%d)'):format(il, mx)))
                      else
                          cell.txt:SetText(gray(il))
                      end
                  else
                      cell.txt:SetText(gray(Tr("status_empty")))
                  end
              end
              -- Medal atlas based on rank (top-3 on ilvl MAX)
              if rank == 1 then cell.medal:SetAtlas("challenges-medal-gold"); cell.medal:Show()
              elseif rank == 2 then cell.medal:SetAtlas("challenges-medal-silver"); cell.medal:Show()
              elseif rank == 3 then cell.medal:SetAtlas("challenges-medal-bronze"); cell.medal:Show()
              else cell.medal:Hide() end
          end
        },
        { key = "mplus",  title = Tr("col_mplus_score"),    w = 120, justify = "CENTER", vsep = true, sortNumeric = true,
          -- Sort by numeric score regardless of value shape
          sortValue = function(row)
              local v = row and row.cells and row.cells.mplus
              if type(v) == 'table' then return tonumber(v.score or 0) or 0 end
              return tonumber(v or 0) or 0
          end,
          buildCell = function(parent)
              local host = CreateFrame("Frame", nil, parent)
              host.txt = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
              if UI and UI.ApplyFont then UI.ApplyFont(host.txt) end
              host.txt:SetJustifyH("CENTER")
              host.txt:SetPoint("CENTER", host, "CENTER", 0, 0)
              host.medal = host:CreateTexture(nil, "ARTWORK")
              host.medal:SetSize(18,18)
              host.medal:SetPoint("LEFT", host, "LEFT", 0, 0)
              host.medal:Hide()
              return host
          end,
          updateCell = function(cell, v)
              local score, rank = 0, nil
              if type(v) == 'table' then score = tonumber(v.score or 0) or 0; rank = v.rank else score = tonumber(v or 0) or 0 end
              cell.txt:SetText(tostring(score > 0 and score or ("|cff"..((UI and UI.GRAY_OFFLINE_HEX) or "999999")..Tr("status_empty").."|r")))
              if rank == 1 then cell.medal:SetAtlas("challenges-medal-gold"); cell.medal:Show()
              elseif rank == 2 then cell.medal:SetAtlas("challenges-medal-silver"); cell.medal:Show()
              elseif rank == 3 then cell.medal:SetAtlas("challenges-medal-bronze"); cell.medal:Show()
              else cell.medal:Hide() end
          end
        },
        { key = "mkey",   title = Tr("col_mplus_key"),      w = 240, justify = "LEFT",   vsep = true },
        { key = "ver",    title = Tr("col_version_short"),  w = 60,  justify = "CENTER", vsep = true },
    })
end

-- ==== Build / Refresh ====
local _ticker, _lastRoster = nil, 0
local function _ensureTicker(owner)
    if _ticker or not C_Timer then return end
    _ticker = C_Timer.NewTicker(10, function()
        if UI and UI.ShouldRefreshUI and not UI.ShouldRefreshUI() then return end
        local now = time()
        if now - (_lastRoster or 0) >= 5 then
            _lastRoster = now
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        end
    end)
end
local function _stopTicker()
    if _ticker then _ticker:Cancel(); _ticker = nil end
end

local function _DoRefresh()
    local inGuild = (IsInGuild and IsInGuild()) and true or false
    -- Toggle whole content (header + table) via content container
    if content and content.SetShown then content:SetShown(inGuild) end
    if noGuildMsg then noGuildMsg:SetShown(not inGuild) end
    if not inGuild then
        if dt and dt.SetData then dt:SetData({}) end
        return
    end
    local rows = BuildRows()
    if dt and dt.DiffAndApply then dt:DiffAndApply(rows) elseif dt and dt.SetData then dt:SetData(rows) end
end

local function Refresh()
    if ns and ns.Util and ns.Util.Debounce then
        ns.Util.Debounce("guild:dyntable", 0.1, _DoRefresh)
    else
        _DoRefresh()
    end
end

local function Build(container)
    panel, footer = UI.CreateMainContainer(container, { footer = false })

    local cols = BuildColumns()
    -- Create a content container so we can hide header+table together when guildless
    content = CreateFrame("Frame", nil, panel)
    content:SetAllPoints(panel)
    -- Section header at the top of the tab (within content)
    UI.SectionHeader(content, Tr("lbl_guild_members"))

    -- Dynamic table shifted down to leave space for the section header
    dt = UI.DynamicTable(content, cols, { topOffset = (UI.SECTION_HEADER_H or 26), headerBGColor = {0.10, 0.10, 0.10, 1.0} })
    -- Expose instance for the live-updater module
    ns._guildDynTable = dt

    -- No-guild message (moved here from Raids), fully replaces content when shown
    noGuildMsg = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    noGuildMsg:SetPoint("CENTER", panel, "CENTER", 0, 0)
    noGuildMsg:SetJustifyH("CENTER"); noGuildMsg:SetJustifyV("MIDDLE")
    noGuildMsg:SetText(Tr and Tr("msg_no_guild") or "")
    noGuildMsg:Hide()

    -- Initial data (debounced refresh); schedule medal recompute after rows are set
    Refresh()
    if ns and ns.LiveCellUpdater and ns.LiveCellUpdater.RecomputeMedals then
        if ns.Util and ns.Util.Debounce then
            ns.Util.Debounce("guild:dyntable:medals:init", 0.20, function()
                ns.LiveCellUpdater.RecomputeMedals("guild")
            end)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0.20, function() ns.LiveCellUpdater.RecomputeMedals("guild") end)
        end
    end

    -- Live events: targeted per-cell updates via LiveCellUpdater
    if ns and ns.LiveCellUpdater then
        if ns.LiveCellUpdater.Bind then ns.LiveCellUpdater.Bind(dt) end
        if ns.LiveCellUpdater.AttachInstance then ns.LiveCellUpdater.AttachInstance("guild", dt) end
    end
    local function _onZoneChange()
        if ns and ns.Util and ns.Util.Debounce then
            ns.Util.Debounce("guild:dyntable:zone", 0.2, function()
                local me = (GetUnitName and GetUnitName("player", true)) or (UnitName and UnitName("player")) or nil
                if me and ns and ns.LiveCellUpdater and ns.LiveCellUpdater.Notify then
                    ns.LiveCellUpdater.Notify('zone', { player = me })
                end
                if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
            end)
        else
            local me = (GetUnitName and GetUnitName("player", true)) or (UnitName and UnitName("player")) or nil
            if me and ns and ns.LiveCellUpdater and ns.LiveCellUpdater.Notify then
                ns.LiveCellUpdater.Notify('zone', { player = me })
            end
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        end
    end
    local function _bulk()
        -- Do nothing if UI is hidden or this panel isn't visible
        if UI and UI.ShouldRefreshUI and not UI.ShouldRefreshUI() then return end
        if panel and panel.IsShown and (not panel:IsShown()) then return end
        -- First rebuild base rows (includes in-group category when applicable)
        Refresh()
        -- Then apply minimal live relocations/diffs
        if ns and ns.LiveCellUpdater and ns.LiveCellUpdater.BulkFromRoster then
            ns.LiveCellUpdater.BulkFromRoster()
        end
        if ns and ns.LiveCellUpdater and ns.LiveCellUpdater.RecomputeMedals then
            ns.LiveCellUpdater.RecomputeMedals("guild")
        end
    end
    ns.Events.Register("GUILD_ROSTER_UPDATE", "guild-dyntable", _bulk)
    ns.Events.Register("PLAYER_GUILD_UPDATE", "guild-dyntable", _bulk)
    ns.Events.Register("GROUP_ROSTER_UPDATE",  "guild-dyntable", _bulk)
    -- Refresh localisation on zone changes: targeted local update + prompt a roster scan
    ns.Events.Register("ZONE_CHANGED",             "guild-dyntable", _onZoneChange)
    ns.Events.Register("ZONE_CHANGED_INDOORS",     "guild-dyntable", _onZoneChange)
    ns.Events.Register("ZONE_CHANGED_NEW_AREA",    "guild-dyntable", _onZoneChange)

    if panel then
        panel:HookScript("OnShow", function() _ensureTicker(panel) end)
        panel:HookScript("OnHide", function() _stopTicker() end)
    end
end

local function Layout() end

-- Official Guild tab
UI.RegisterTab(Tr("tab_guild_members"), Build, Refresh, Layout, { category = Tr("cat_guild") })