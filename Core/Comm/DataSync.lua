-- Module de gestion des snapshots pour GuildLogistics
-- Gère l'export et import des données complètes de la base de données

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}
local safenum = U.safenum
local now = U.now

-- ===== Export de snapshot =====
function GLOG.SnapshotExport()
    -- ==== DB minimale ====
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta     = GuildLogisticsDB.meta     or {}
    GuildLogisticsDB.players  = GuildLogisticsDB.players  or {}
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }
    GuildLogisticsDB.lots     = GuildLogisticsDB.lots     or { list = {}, nextId = 1 }

    local meta = GuildLogisticsDB.meta

    -- ==== helpers ====
    local function escText(s)
        s = tostring(s or "")
        return (s:gsub("[:,%|%[%]]", function(ch) return string.format("%%%02X", string.byte(ch)) end))
    end

    -- In sv=4, R (realms) is omitted. P is also omitted by default,
    -- but we now include a compact mapping for NON-GUILD players to allow UID→Name resolution on receivers.
    -- P carries entries formatted as "uid:FullName-Realm" only for players not in the guild.
    local P = {}
    do
        local pdb = GuildLogisticsDB.players or {}
        local isGuildChar = (GLOG.IsGuildCharacter and GLOG.IsGuildCharacter)
        for full, prec in pairs(pdb) do
            local uid = tostring(prec and prec.uid or "")
            local name = tostring(full or "")
            if uid ~= "" and name ~= "" then
                local inGuild = false
                if isGuildChar then
                    local ok, res = pcall(isGuildChar, name)
                    inGuild = ok and res or false
                end
                if not inGuild then
                    P[#P+1] = tostring(uid)..":"..escText(name)
                end
            end
        end
        table.sort(P) -- stable order for wire diffs
        if #P == 0 then P = nil end
    end

    -- ===== Lots & labels =====
    local T, L = {}, {}
    for _,l in ipairs(GuildLogisticsDB.lots.list or {}) do
        local lid = safenum(l.id,0)
        T[#T+1] = tostring(lid) .. ":" .. escText(tostring(l.name or ("Lot "..lid)))
        L[#L+1] = table.concat({
            tostring(lid),
            tostring(safenum(l.sessions,1)),
            tostring(safenum(l.used,0)),
            tostring(safenum(l.totalCopper,0))
        }, ":")
    end

    -- ===== Dépenses & LE =====
    local E, LE = {}, {}
    for _, e in ipairs(GuildLogisticsDB.expenses.list or {}) do
        local srcId = safenum(e.sourceId or 0, 0)
        E[#E+1] = table.concat({
            tostring(safenum(e.id,0)),
            tostring(safenum(e.qty,0)),
            tostring(safenum(e.copper,0)),
            tostring(srcId),
            tostring(safenum(e.itemID,0))
        }, ":")
        local lid = safenum(e.lotId, 0)
        if lid > 0 then
            LE[#LE+1] = tostring(lid) .. ":" .. tostring(safenum(e.id,0))
        end
    end

    -- ===== Main/Alt (compact) =====
    local MAv = 3
    local MA, AM = {}, {}
    do
    local t = GuildLogisticsDB.account
        if type(t) == "table" then
            -- mains set
            for uid, flag in pairs(t.mains or {}) do
                if flag then MA[#MA+1] = tostring(uid) end
            end
            -- alt→main mapping
            for a, m in pairs(t.altToMain or {}) do
                local au, mu = tostring(a or ""), tostring(m or "")
                if au ~= "" and mu ~= "" then AM[#AM+1] = au..":"..mu end
            end
            table.sort(MA)
            table.sort(AM)
        end
    end

    -- ===== Historique =====
    local H = {}
    for _, h in ipairs(GuildLogisticsDB.history or {}) do
        local ts      = safenum(h.ts, 0)
        local total   = safenum(h.total, 0)
    local count   = safenum(h.count, (h.participants and #h.participants) or 0)
        local refund  = (h.refunded and 1 or 0)

        local pidsSet, pids = {}, {}
        for _, tok in ipairs(h.participants or {}) do
            local uidTok = tostring(tok or "")
            if uidTok ~= "" and not pidsSet[uidTok] then
                pidsSet[uidTok] = true
                pids[#pids+1] = uidTok
            end
        end

        local lots = {}
        for _, li in ipairs(h.lots or {}) do
            if type(li) == "table" then
                local lid = safenum(li.id, 0)
                if lid > 0 then lots[#lots+1] = tostring(lid) end
            end
        end

        local head = table.concat({ tostring(ts), tostring(total), tostring(count), tostring(refund) }, ":")
        local rec  = head .. "|" .. table.concat(pids, ",") .. "|" .. table.concat(lots, ",")
        H[#H+1] = rec
    end

    -- ===== AS (Account State) =====
    -- Export main-level data per main UID (ShortId string): uid:alias:solde:res:addonVersion
    -- res bit: 0 = not reserved (explicit false at main-level), 1 = reserved (implicit)
    local AS, ASv = {}, 2
    do
        local acc = GuildLogisticsDB.account or {}
        local mains = (acc and acc.mains) or {}
        -- Export ONLY mains; importer will map alts via AM
        local uids = {}
        for uid, _ in pairs(mains) do uids[#uids+1] = tostring(uid) end
        table.sort(uids)
        for _, uid in ipairs(uids) do
            local mrec = mains[uid] or mains[tostring(uid)] or {}
            local resBit = (mrec.reserve == false) and 0 or 1
            local aliasText = tostring(mrec.alias or "")
            local av = tostring(mrec.addonVersion or "")
            AS[#AS+1] = table.concat({
                tostring(uid),
                escText(aliasText),
                tostring(safenum(mrec.solde,0)),
                tostring(resBit),
                escText(av),
            }, ":")
        end
    end

    -- ===== Editors allowlist (main UIDs) =====
    local EDR
    do
        local acc = GuildLogisticsDB.account or {}
        local editors = acc.editors or {}
        local list = {}
        for mu, flag in pairs(editors) do if flag then list[#list+1] = tostring(mu) end end
        table.sort(list)
        if #list > 0 then EDR = list end
    end

    -- ===== Mythic+ per-dungeon maps (compact per player) =====
    -- MP entries formatted as: "uid:ts|mid,score,best,timed,durMS;mid,..." (MPv=2)
    local MP
    do
        local pdb = GuildLogisticsDB.players or {}
        local items = {}
        for full, rec in pairs(pdb) do
            local maps = rec and rec.mplusMaps
            local ts   = rec and rec.mplusMapsTs
            local uid  = tostring(rec and rec.uid or (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or "")
            if uid ~= "" and type(maps) == "table" then
                local count = 0; for _ in pairs(maps) do count = count + 1 end
                if count > 0 and safenum(ts,0) > 0 then
                    local mids = {}
                    for mid,_ in pairs(maps) do mids[#mids+1] = tonumber(mid) or 0 end
                    table.sort(mids)
                    local parts = {}
                    for i=1,#mids do
                        local mid = mids[i]
                        local r = maps[mid] or {}
                        parts[#parts+1] = table.concat({
                            tostring(mid),
                            tostring(safenum(r.score,0)),
                            tostring(safenum(r.best,0)),
                            tostring((r.timed and 1 or 0)),
                            tostring(safenum(r.durMS or r.durMs,0)),
                        }, ",")
                    end
                    items[#items+1] = tostring(uid)..":"..tostring(ts).."|"..table.concat(parts, ";")
                end
            end
        end
        table.sort(items)
        if #items > 0 then MP = items end
    end

    -- ===== KV final =====
    return {
        sv = 4,
        rv = safenum(meta.rev, 0),
        lm = safenum(meta.lastModified, now()),
        fs = safenum(meta.fullStamp, now()),
        T  = T,
        L  = L,
        E  = E,
        LE = LE,
        -- Main/Alt
        MAv = MAv,
        MA  = MA,
        AM  = AM,
        -- Shared per UID
        ASv = ASv,
        AS  = AS,
        H  = H,
        P  = P,
        -- Editors allowlist
        EDR = EDR,
        -- Mythic+ per-dungeon maps
        MP  = MP,
        MPv = 2,
    }
end

-- ===== Import de snapshot =====
function GLOG.SnapshotApply(kv)
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta     = GuildLogisticsDB.meta     or {}
    GuildLogisticsDB.players  = {}
    GuildLogisticsDB.expenses = { list = {}, nextId = 1 }
    GuildLogisticsDB.lots     = { list = {}, nextId = 1 }
    -- Initialise/flush account; sera rempli si présent dans le snapshot
    GuildLogisticsDB.account  = { mains = {}, altToMain = {} }

    local meta = GuildLogisticsDB.meta
    meta.rev         = safenum(kv.rv, 0)
    meta.lastModified= safenum(kv.lm, now())
    meta.fullStamp   = safenum(kv.fs, now())
    -- helpers
    local function unescText(s)
        s = tostring(s or "")
        return (s:gsub("%%(%x%x)", function(h)
            local n = tonumber(h, 16); return n and string.char(n) or ("%")..h
        end))
    end

    local sv = tostring(kv.sv or "")
    if sv ~= "4" and sv ~= "3" and sv ~= "3.0" then return end

    -- Pre-parse AS/MS (Account State per UID): uid:alias:solde:res:addonVersion
    -- Compatibility: prefer AS if both exist; otherwise accept MS used by older exporters
    local asByUID = {}
    do
        local srcList = nil
        local ASv = safenum(kv.ASv, nil)
        local MSv = safenum(kv.MSv, nil)
        if type(kv.AS) == "table" and (ASv == 2 or ASv == 1 or ASv == 0) then
            srcList = kv.AS
        elseif type(kv.MS) == "table" and (MSv == 1 or MSv == 0) then
            srcList = kv.MS
        elseif type(kv.AS) == "table" and ASv == nil then
            srcList = kv.AS -- tolerate missing version
        elseif type(kv.MS) == "table" and MSv == nil then
            srcList = kv.MS -- tolerate missing version
        end
        if type(srcList) == "table" then
            for _, s in ipairs(srcList or {}) do
                -- Accept both string and numeric UID tokens in exports
                local uid, alias, bal, res, av = s:match("^([^:]+):(.-):([%-%d]+):([%-%d]+):(.-)$")
                if uid then
                    local u = tostring(uid)
                    local a = unescText(alias)
                    local b = safenum(bal,0)
                    local r = safenum(res,1)
                    local v = unescText(av)
                    asByUID[u] = { alias = a, bal = b, res = (r ~= 0), av = v }
                end
            end
        end
    end

    -- In sv=4, snapshot does not carry Realms (R).
    -- Players (P) may carry non-guild mapping entries in the form uid:FullName.
    local aliasByUID, resByUID = {}, {}
    do
        local pdb = GuildLogisticsDB.players or {}
        for _, s in ipairs(kv.P or {}) do
            local uid, encName = tostring(s):match("^([^:]+):(.*)$")
            if uid and encName then
                local full = unescText(encName)
                if full and full ~= "" then
                    pdb[full] = pdb[full] or {}
                    pdb[full].uid = tostring(uid)
                end
            end
        end
        GuildLogisticsDB.players = pdb
    end

    -- 3) T (id→nom)
    local LotNameById = {}
    for _, s in ipairs(kv.T or {}) do
        local lid, label = s:match("^(%-?%d+):(.*)$")
        if lid then
            LotNameById[safenum(lid,0)] = unescText(label)
        end
    end

    -- 4) L (lots)
    local LotsById = {}
    for _, s in ipairs(kv.L or {}) do
        local lid, sessions, used, tot = s:match("^([%-%d]+):([%-%d]+):([%-%d]+):([%-%d]+)$")
        if lid then
            local id = safenum(lid,0)
            local rec = {
                id = id,
                name = LotNameById[id] or ("Lot "..tostring(id)),
                sessions = safenum(sessions,1),
                used = safenum(used,0),
                totalCopper = safenum(tot,0),
                itemIds = {},
            }
            table.insert(GuildLogisticsDB.lots.list, rec)
            LotsById[id] = rec
            GuildLogisticsDB.lots.nextId = math.max(GuildLogisticsDB.lots.nextId or 1, id + 1)
        end
    end

    -- 5) E (dépenses)
    local ExpensesById = {}
    for _, s in ipairs(kv.E or {}) do
        local id, qty, copper, srcId, itemId = s:match("^([%-%d]+):([%-%d]+):([%-%d]+):([%-%d]+):([%-%d]+)$")
        if id then
            local e = {
                id     = safenum(id,0),
                qty    = safenum(qty,0),
                copper = safenum(copper,0),
                itemID = safenum(itemId,0),
            }
            local sid = safenum(srcId,0)
            if sid > 0 then e.sourceId = sid end
            table.insert(GuildLogisticsDB.expenses.list, e)
            GuildLogisticsDB.expenses.nextId = math.max(GuildLogisticsDB.expenses.nextId or 1, e.id + 1)
            ExpensesById[e.id] = e
        end
    end

    -- 6) LE (liaison et itemIds)
    for _, s in ipairs(kv.LE or {}) do
        local lid, eid = s:match("^([%-%d]+):([%-%d]+)$")
        if lid and eid then
            local Lrec = LotsById[safenum(lid,0)]
            local Erec = ExpensesById[safenum(eid,0)]
            if Lrec and Erec then
                Erec.lotId = Lrec.id
                -- IMPORTANT : Resources.lua attend des EXPENSE IDs dans lot.itemIds
                Lrec.itemIds = Lrec.itemIds or {}
                table.insert(Lrec.itemIds, Erec.id)
            end
        end
    end
    
    -- Backfill : si un lot n'a pas d'itemIds via LE, le reconstituer depuis les dépenses
    do
        -- Prépare un set par lot pour éviter les doublons
        local seenPerLot = {}
        for lid, Lrec in pairs(LotsById or {}) do
            seenPerLot[lid] = {}
            for _, eid in ipairs(Lrec.itemIds or {}) do
                seenPerLot[lid][eid] = true
            end
        end
        -- Balayer toutes les dépenses et rattacher par lotId
        for _, Erec in pairs(ExpensesById or {}) do
            local lid = tonumber(Erec.lotId or 0) or 0
            local Lrec = LotsById and LotsById[lid]
            if Lrec then
                Lrec.itemIds = Lrec.itemIds or {}
                local seen = seenPerLot[lid]
                if not seen[Erec.id] then
                    table.insert(Lrec.itemIds, Erec.id)
                    seen[Erec.id] = true
                end
            end
        end
    end

    -- 7) H (historique) : ts:total:count:refund|pids|lotIds
    GuildLogisticsDB.history = {}
    for _, s in ipairs(kv.H or {}) do
        local line = tostring(s):gsub("%|%|", "|")
        local header, plist, llist = line:match("^(.-)%|(.-)%|(.*)$")
        if not header then
            header, plist = line:match("^(.-)%|(.*)$")
            llist = ""
        end
        local ts, total, count, refund = (header or ""):match("^([%-%d]+):([%-%d]+):([%-%d]+):([%-%d]+)$")
        local _ts     = safenum(ts,0)
        local _total  = safenum(total,0)
        local _count  = safenum(count,0)
        local _ref    = safenum(refund,0) == 1

        local participants = {}
        local seenP = {}
        for pid in tostring(plist or ""):gmatch("([^,]+)") do
            local tok = tostring(pid or "")
            if tok ~= "" and not seenP[tok] then
                seenP[tok] = true
                participants[#participants+1] = tok -- store UID directly
            end
        end

        local lots = {}
        for tok in tostring(llist or ""):gmatch("([^,]+)") do
            local lid = tonumber(tok)
            if lid and lid > 0 then
                local name = LotNameById[lid] or ("Lot "..tostring(lid))
                table.insert(lots, { id = lid, name = name })
            end
        end

        local per = (_count > 0) and math.floor(_total / _count) or 0
        if _ts > 0 then
            table.insert(GuildLogisticsDB.history, {
                ts = _ts, total = _total, perHead = per,
                count = _count, participants = participants, refunded = _ref,
                lots = lots,
            })
        end
    end

    -- 8) Main/Alt (si présent)
    do
    local t = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
    -- account.version removed; accept kv.MAv for wire compatibility only
        t.mains = {}
        t.altToMain = {}
        if type(kv.MA) == "table" then
            for _, s in ipairs(kv.MA) do
                local u = tostring(s or "")
                if u ~= "" then t.mains[u] = {} end
            end
        end
        if type(kv.AM) == "table" then
            for _, s in ipairs(kv.AM) do
                local a, m = tostring(s):match("^([^:]+):([^:]+)$")
                local au, mu = tostring(a or ""), tostring(m or "")
                if au ~= "" and mu ~= "" then t.altToMain[au] = mu end
            end
        end
    GuildLogisticsDB.account = t
    -- ✨ Consolidate alias, reserve, balances, and addonVersion at main-level after MA mapping is known
    do
    local players = GuildLogisticsDB.players or {}
        local mainRes, mainAlias = {}, {}
        local mainBal, mainAV = {}, {}
        local muByUID = {}
        -- Build per-main aggregations using the per-UID captures
        for full, prec in pairs(players) do
            local uid = tostring(prec.uid or "")
            if uid ~= "" then
                local mu = tostring(t.altToMain[uid] or uid)
                muByUID[uid] = mu
                -- Reserve: if any character under this main is explicitly not reserved (res=false), mark main not reserved
                local r = resByUID[uid]
                if r ~= nil then
                    if mainRes[mu] == nil then mainRes[mu] = true end -- default reserved
                    if r == false then mainRes[mu] = false end
                end
                -- Alias: prefer alias defined on the main UID; else take first seen
                local a = aliasByUID[uid]
                if a and a ~= "" then
                    if uid == mu then
                        mainAlias[mu] = a
                    elseif mainAlias[mu] == nil then
                        mainAlias[mu] = a
                    end
                end
            end
        end
        -- Fold in AS-only data (UIDs that may not be present in P)
        do
            for uid, as in pairs(asByUID or {}) do
                local u = tostring(uid or "")
                if u ~= "" then
                    local mu = tostring(t.altToMain[u] or u)
                    if as.res ~= nil then
                        if mainRes[mu] == nil then mainRes[mu] = true end
                        if as.res == false then mainRes[mu] = false end
                    end
                    local a = as.alias
                    if a and a ~= "" then
                        if u == mu then
                            mainAlias[mu] = a
                        elseif mainAlias[mu] == nil then
                            mainAlias[mu] = a
                        end
                    end
                    -- Balances and addonVersion preference: prefer main's own AS row; otherwise, take first seen
                    if u == mu then
                        mainBal[mu] = safenum(as.bal, 0)
                        if as.av and as.av ~= "" then mainAV[mu] = tostring(as.av) end
                    else
                        if mainBal[mu] == nil then mainBal[mu] = safenum(as.bal, 0) end
                        if (not mainAV[mu]) and as.av and as.av ~= "" then mainAV[mu] = tostring(as.av) end
                    end
                end
            end
        end
        -- Write consolidated flags to account.mains
        for mu, r in pairs(mainRes) do
            t.mains[mu] = (type(t.mains[mu]) == "table") and t.mains[mu] or {}
            t.mains[mu].reserve = (r == false) and false or nil -- only explicit false stored
        end
        -- Defensive: enforce reserve=false for any UID explicitly flagged in AS/MS with res=0
        do
            for uid, as in pairs(asByUID or {}) do
                local u = tostring(uid or "")
                if u ~= "" and as.res == false then
                    local mu = tostring(t.altToMain[u] or u)
                    t.mains[mu] = (type(t.mains[mu]) == "table") and t.mains[mu] or {}
                    t.mains[mu].reserve = false
                end
            end
        end
        -- Write balances and addonVersion to account.mains
        for mu, bal in pairs(mainBal) do
            t.mains[mu] = (type(t.mains[mu]) == "table") and t.mains[mu] or {}
            t.mains[mu].solde = safenum(bal, 0)
        end
        for mu, av in pairs(mainAV) do
            t.mains[mu] = (type(t.mains[mu]) == "table") and t.mains[mu] or {}
            t.mains[mu].addonVersion = tostring(av)
        end
        -- Compatibility mirror: write per-character reserved=false when main is explicitly not reserved; otherwise remove the field
        for full, prec in pairs(players) do
            local uid = tostring(prec.uid or "")
            if uid ~= "" then
                local mu = muByUID[uid] or uid
                local mrec = t.mains[mu]
                if mrec and mrec.reserve == false then
                    prec.reserved = false -- explicit bench mirror for legacy readers
                else
                    prec.reserved = nil   -- absence means reserved
                end
            end
        end
        -- Write consolidated alias under account.mains[mu].alias
        for mu, a in pairs(mainAlias) do
            if a and a ~= "" then
                t.mains[mu] = (type(t.mains[mu]) == "table") and t.mains[mu] or {}
                t.mains[mu].alias = a
            end
        end
    end
    end

    -- 9) Editors allowlist (if present)
    do
        local acc = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
        local ed = {}
        if type(kv.EDR) == "table" then
            for _, s in ipairs(kv.EDR) do
                local mu = tostring(s or "")
                if mu ~= "" then ed[mu] = true end
            end
        end
        acc.editors = ed
        GuildLogisticsDB.account = acc
        if ns and ns.Emit then ns.Emit("editors:changed", "sync") end
    end

    -- 10) Mythic+ per-dungeon maps (if present)
    do
        local function _applyMPLine(line)
            local uid, rest = tostring(line or ""):match("^([^:]+):(.+)$")
            if not uid then return end
            local tsStr, body = tostring(rest or ""):match("^([%-%d]+)|(.+)$")
            if not tsStr then return end
            local ts = safenum(tsStr, 0)
            local name = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or nil
            if not name or name == "" then return end
            GuildLogisticsDB.players = GuildLogisticsDB.players or {}
            local p = GuildLogisticsDB.players[name]
            if not p then return end
            local prev = safenum(p.mplusMapsTs, 0)
            if ts <= prev then return end
            local newMap = {}
            for tok in tostring(body or ""):gmatch("([^;]+)") do
                -- Try MPv=2 first (no runs)
                local mid,s,b,t,d = tok:match("^(%-?%d+),([%-%d]+),([%-%d]+),([%-%d]+),([%-%d]+)$")
                local ok = false
                if mid then ok = true else
                    -- Fallback MPv=1 (includes runs we ignore)
                    local _mid,_s,_b,_r,_t,_d = tok:match("^(%-?%d+),([%-%d]+),([%-%d]+),([%-%d]+),([%-%d]+),([%-%d]+)$")
                    if _mid then mid,s,b,t,d = _mid,_s,_b,_t,_d; ok = true end
                end
                if ok and mid then
                    local id = tonumber(mid) or 0
                    if id > 0 then
                        newMap[id] = {
                            score = safenum(s,0),
                            best  = safenum(b,0),
                            timed = (safenum(t,0) ~= 0),
                            durMS = safenum(d,0),
                        }
                    end
                end
            end
            if next(newMap) then
                p.mplusMaps = newMap
                p.mplusMapsTs = ts
                if ns.Emit then ns.Emit("mplus:maps-updated", name) end
            end
        end
        if type(kv.MP) == "table" then
            for _, item in ipairs(kv.MP) do
                if type(item) == "string" then
                    _applyMPLine(item)
                elseif type(item) == "table" then
                    -- Allow object form if ever used in future
                    local uid = tostring(item.uid or item.u or "")
                    local ts  = safenum(item.ts or item.t, 0)
                    if uid ~= "" and ts > 0 then
                        local parts = {}
                        if type(item.M) == "table" then
                            for _, r in ipairs(item.M) do
                                local mid = safenum(r.mid or r.id, 0)
                                if mid > 0 then
                                    local s = safenum(r.score or r.s, 0)
                                    local b = safenum(r.best or r.b, 0)
                                    local t = (r.timed and 1 or safenum(r.t, 0))
                                    local d = safenum(r.durMS or r.d or 0)
                                    parts[#parts+1] = table.concat({ tostring(mid), tostring(s), tostring(b), tostring(t), tostring(d) }, ",")
                                end
                            end
                        end
                        _applyMPLine(uid..":"..tostring(ts).."|"..table.concat(parts, ";"))
                    end
                end
            end
        end
    end

    -- No migration step: DB now uses ShortId strings natively

    if ns and ns.Emit then
        ns.Emit("players:changed")
        ns.Emit("expenses:changed")
        ns.Emit("lots:changed")
        ns.Emit("history:changed")
        ns.Emit("mainalt:changed", "sync")
    end
end

-- ===== Estimation de la taille d'un snapshot =====
function GLOG.EstimateSnapshotSize()
    local ok, snap = pcall(function() return GLOG.SnapshotExport() end)
    if not ok then return 0 end
    
    local enc = ""
    if GLOG.EncodeKV then
        enc = GLOG.EncodeKV(snap) or ""
    end
    
    local comp = nil
    if GLOG.PackPayloadStr then
        local packed = GLOG.PackPayloadStr(snap)
        -- Si c'est compressé, on peut extraire la taille compressée
        if packed:find("^c=z|") then
            comp = packed:sub(5)
        end
    end
    
    return comp and #comp or #enc
end

-- ===== Aliases pour compatibilité =====
GLOG._SnapshotExport = GLOG.SnapshotExport
GLOG._SnapshotApply = GLOG.SnapshotApply
GLOG._estimateSnapshotSize = GLOG.EstimateSnapshotSize

-- Fonctions globales pour compatibilité
_estimateSnapshotSize = GLOG.EstimateSnapshotSize
