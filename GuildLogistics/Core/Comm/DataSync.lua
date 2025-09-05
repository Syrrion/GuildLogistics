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
    local function normRealm(realm)
        realm = tostring(realm or "")
        if realm == "" then return realm end
        local first, allsame
        for seg in realm:gmatch("[^%-]+") do
            if not first then first=seg; allsame=true
            elseif seg ~= first then allsame=false end
        end
        if allsame and first then return first end
        return realm
    end
    local function splitName(full)
        local base, realm = tostring(full):match("^([^%-]+)%-(.+)$")
        return base or tostring(full), realm or ""
    end
    local function uidNumFor(full)
        local uid = (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or nil
        local n = tonumber(uid) or 0
        return n
    end
    local function aliasFor(full, baseName)
        local a = (GLOG.GetAliasFor and GLOG.GetAliasFor(full)) or baseName
        return a or baseName
    end

    -- ===== joueurs et royaumes SANS fusion =====
    -- On exporte chaque personnage tel quel (Nom-Complet), sans regroupement par baseName.

    -- 1) Construire l'ensemble des royaumes utilisés
    local realmSet = {}
    for full, rec in pairs(GuildLogisticsDB.players) do
        local base, realm = splitName(full)
        local nrealm = normRealm(realm)
        if nrealm ~= "" then realmSet[nrealm] = true end
    end

    -- 2) Construire R (réalms) trié alpha
    local realms = {}
    for r,_ in pairs(realmSet) do realms[#realms+1]=r end
    table.sort(realms, function(a,b) return a:lower() < b:lower() end)
    local ridByRealm = {}
    local R = {}
    for i,r in ipairs(realms) do
        ridByRealm[r]=i
        R[#R+1]=tostring(i)..":"..escText(r)
    end

    -- 3) Construire P sans fusion (une entrée par personnage complet)
    local P = {}
    for full, rec in pairs(GuildLogisticsDB.players) do
        local base, realm = splitName(full)
        local nrealm = normRealm(realm)
        local rid = (nrealm ~= "" and ridByRealm[nrealm]) or 0
        local aliasText = (aliasFor(full, base) or base)
        if aliasText == base then aliasText = "@" end
        local uidN = uidNumFor(full)
        local balance = safenum(rec.solde, 0)
        local res = rec.reserved and 1 or 0

        P[#P+1] = table.concat({
            tostring(uidN), tostring(rid), escText(base), escText(aliasText),
            tostring(balance), tostring(res)
        }, ":")
    end
    table.sort(P, function(a,b) return a:lower() < b:lower() end)

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

    -- ===== Historique =====
    local H = {}
    for _, h in ipairs(GuildLogisticsDB.history or {}) do
        local ts      = safenum(h.ts, 0)
        local total   = safenum(h.total, 0)
        local count   = safenum(h.count, (h.participants and #h.participants) or 0)
        local refund  = (h.refunded and 1 or 0)

        local pidsSet, pids = {}, {}
        for _, name in ipairs(h.participants or {}) do
            -- Utilise l'UID du personnage complet, sans passage par un « canon »
            local uidNum = uidNumFor(tostring(name))
            if uidNum and uidNum > 0 and not pidsSet[uidNum] then
                pidsSet[uidNum] = true
                pids[#pids+1] = tostring(uidNum)
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

    -- ===== KV final =====
    return {
        sv = 3,
        rv = safenum(meta.rev, 0),
        lm = safenum(meta.lastModified, now()),
        fs = safenum(meta.fullStamp, now()),
        R  = R,
        P  = P,
        T  = T,
        L  = L,
        E  = E,
        LE = LE,
        H  = H,
    }
end

-- ===== Import de snapshot =====
function GLOG.SnapshotApply(kv)
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta     = GuildLogisticsDB.meta     or {}
    GuildLogisticsDB.players  = {}
    GuildLogisticsDB.expenses = { list = {}, nextId = 1 }
    GuildLogisticsDB.lots     = { list = {}, nextId = 1 }

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
    local function normRealm(realm)
        realm = tostring(realm or "")
        if realm == "" then return realm end
        local first, allsame
        for seg in realm:gmatch("[^%-]+") do
            if not first then first=seg; allsame=true
            elseif seg ~= first then allsame=false end
        end
        if allsame and first then return first end
        return realm
    end

    local sv = tostring(kv.sv or "")
    if sv ~= "3" and sv ~= "3.0" then return end

    -- 1) R (réalms) avec normalisation anti-duplication
    local realmById = {}
    for _, s in ipairs(kv.R or {}) do
        local rid, label = s:match("^(%-?%d+):(.*)$")
        if rid then
            local realm = unescText(label)
            realmById[tonumber(rid) or 0] = normRealm(realm)
        end
    end

    -- 2) P (brut par PERSONNAGE COMPLET, pas de fusion)
    -- uid:rid:name:alias:balance:res
    for _, s in ipairs(kv.P or {}) do
        local uid, rid, name, alias, bal, res = s:match("^([%-%d]+):([%-%d]+):(.-):(.-):([%-%d]+):([%-%d]+)$")
        if uid then
            local uidNum = tonumber(uid) or 0
            local ridNum = tonumber(rid) or 0
            local base   = unescText(name)
            local aliasS = unescText(alias)
            if aliasS == "@" then aliasS = base end
            local realm  = realmById[ridNum] or ""
            local full   = (U and U.NormalizeFull and U.NormalizeFull(base, realm))
                        or (realm ~= "" and (base.."-"..realm) or base)
            local balance= safenum(bal,0)

            GuildLogisticsDB.players[full] = {
                uid      = safenum(uidNum,0),
                solde    = safenum(balance,0),
                reserved = (safenum(res,0) == 1),
                alias    = aliasS,
            }
        end
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
            local n = tonumber(pid)
            if n and n > 0 then
                local full = (GLOG.GetNameByUID and GLOG.GetNameByUID(n))
                if full and not seenP[full] then
                    seenP[full] = true
                    participants[#participants+1] = full
                end
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

    if ns and ns.Emit then
        ns.Emit("players:changed")
        ns.Emit("expenses:changed")
        ns.Emit("lots:changed")
        ns.Emit("history:changed")
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
