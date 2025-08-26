-- Data/UpgradeTracks.lua
local ADDON, ns = ...
ns.Data = ns.Data or {}
local L = ns and ns.L or {}
local function Step(fmtKey, n) return string.format(L[fmtKey] or fmtKey, n) end

ns.Data.UpgradeTracks = {
    headers = {
        itemLevel = L["upgrade_header_itemlevel"],
        crests    = L["upgrade_header_crests"],
        aventurier= L["upgrade_track_adventurer"],
        veteran   = L["upgrade_track_veteran"],
        champion  = L["upgrade_track_champion"],
        heros     = L["upgrade_track_hero"],
        mythe     = L["upgrade_track_myth"],
    },

    -- Palette (proche de l’image fournie ; ajuste ici si besoin)
    palette = {
        headers = {
            itemLevel = {0.35, 0.23, 0.10}, -- brun
            crests    = {0.35, 0.23, 0.10}, -- brun orangé
            aventurier= {0.35, 0.23, 0.10}, -- bleu-vert
            veteran   = {0.35, 0.23, 0.10}, -- vert
            champion  = {0.35, 0.23, 0.10}, -- olive/jaune
            heros     = {0.35, 0.23, 0.10}, -- rouge
            mythe     = {0.35, 0.23, 0.10}, -- violet
        },
        -- Teinte des cellules remplies (fond sous le texte du palier)
        cells = {
            aventurier= {0.00, 0.55, 0.67, 0.25},
            veteran   = {0.15, 0.58, 0.20, 0.25},
            champion  = {0.64, 0.60, 0.07, 0.25},
            heros     = {0.55, 0.05, 0.05, 0.25},
            mythe     = {0.39, 0.13, 0.65, 0.25},
        },
    },

    -- Lignes (édition simple)
    rows = {
        { ilvl = 655, was = 610, crest = L["crest_valor"],   aventurier = Step("upgrade_step_adventurer", 1) },
        { ilvl = 658, was = 613, crest = L["crest_valor"],   aventurier = Step("upgrade_step_adventurer", 2) },
        { ilvl = 662, was = 613, crest = L["crest_valor"],   aventurier = Step("upgrade_step_adventurer", 3) },
        { ilvl = 665, was = 619, crest = L["crest_valor"],   aventurier = Step("upgrade_step_adventurer", 4) },

        { ilvl = 668, was = 623, crest = L["crest_worn"],    aventurier = Step("upgrade_step_adventurer", 5), veteran = Step("upgrade_step_veteran", 1) },
        { ilvl = 671, was = 626, crest = L["crest_worn"],    aventurier = Step("upgrade_step_adventurer", 6), veteran = Step("upgrade_step_veteran", 2) },
        { ilvl = 675, was = 629, crest = L["crest_worn"],    aventurier = Step("upgrade_step_adventurer", 7), veteran = Step("upgrade_step_veteran", 3) },
        { ilvl = 678, was = 632, crest = L["crest_worn"],    aventurier = Step("upgrade_step_adventurer", 8), veteran = Step("upgrade_step_veteran", 4) },

        { ilvl = 681, was = 636, crest = L["crest_carved"],  veteran = Step("upgrade_step_veteran", 5), champion = Step("upgrade_step_champion", 1) },
        { ilvl = 684, was = 639, crest = L["crest_carved"],  veteran = Step("upgrade_step_veteran", 6), champion = Step("upgrade_step_champion", 2) },
        { ilvl = 688, was = 642, crest = L["crest_carved"],  veteran = Step("upgrade_step_veteran", 7), champion = Step("upgrade_step_champion", 3) },
        { ilvl = 691, was = 645, crest = L["crest_carved"],  veteran = Step("upgrade_step_veteran", 8), champion = Step("upgrade_step_champion", 4) },

        { ilvl = 694, was = 649, crest = L["crest_runic"],   champion = Step("upgrade_step_champion", 5), heros = Step("upgrade_step_hero", 1) },
        { ilvl = 697, was = 652, crest = L["crest_runic"],   champion = Step("upgrade_step_champion", 6), heros = Step("upgrade_step_hero", 2) },
        { ilvl = 701, was = 655, crest = L["crest_runic"],   champion = Step("upgrade_step_champion", 7), heros = Step("upgrade_step_hero", 3) },
        { ilvl = 704, was = 658, crest = L["crest_runic"],   champion = Step("upgrade_step_champion", 8), heros = Step("upgrade_step_hero", 4) },

        { ilvl = 707, was = 662, crest = L["crest_golden"],  heros = Step("upgrade_step_hero", 5),  mythe = Step("upgrade_step_myth", 1) },
        { ilvl = 710, was = 665, crest = L["crest_golden"],  heros = Step("upgrade_step_hero", 6),  mythe = Step("upgrade_step_myth", 2) },
        { ilvl = 714, was = 668, crest = L["crest_golden"],  mythe = Step("upgrade_step_myth", 3) },
        { ilvl = 717, was = 671, crest = L["crest_golden"],  mythe = Step("upgrade_step_myth", 4) },
        { ilvl = 720, was = 675, crest = L["crest_golden"],  mythe = Step("upgrade_step_myth", 5) },
        { ilvl = 723, was = 678, crest = L["crest_golden"],  mythe = Step("upgrade_step_myth", 6) },
    }
}

-- =========================================================
--   Sources d'Écus (tableau Helpers_Crests)
--   On centralise ici pour éviter un nouveau fichier Data.
-- =========================================================
ns.Data.Crests = {
    headers = {
        crest   = L["crests_header_crest"],
        chasms  = L["crests_header_chasms"],
        dungeons= L["crests_header_dungeons"],
        raids   = L["crests_header_raids"],
        outdoor = L["crests_header_outdoor"],
    },

    -- Couleurs d’entête (proches de la capture)
    palette = {
        headers = {
            crest   = {0.35, 0.23, 0.10}, -- brun
            chasms  = {0.62, 0.33, 0.04}, -- orangé
            dungeons= {0.13, 0.31, 0.54}, -- bleu
            raids   = {0.08, 0.42, 0.19}, -- vert
            outdoor = {0.31, 0.08, 0.46}, -- violet
        },
    },
    -- Données brutes (on formatera le texte côté UI pour gérer la localisation)
    rows = {
        -- Abîmé (668 à 678)
        {
            crest   = { key="worn",   name=L["crest_worn"],   min=668, max=678 },
            chasms  = {
                { kind="classic", levels = { {4,5}, {5,6} } } -- Niveau 4:5 écus ; 5:6 écus
            },
            dungeons= {
                { kind="heroic",   perBoss=15 }               -- Héroïque : 15/boss
            },
            raids   = {
                { kind="lfr",      perBoss=15 }               -- Outils raids : 15/boss
            },
            outdoor = {
                { kind="treasures_quests", range = {2,3} }    -- Trésors/Quêtes : 2 à 3 écus
            },
        },

        -- Gravé (681 à 691)
        {
            crest   = { key="carved", name=L["crest_carved"], min=681, max=691 },
            chasms  = {
                { kind="classic", levels = { {6,3}, {7,5} } } -- Niveau 6:3 ; 7:5
            },
            dungeons= {
                { kind="m0",      perBoss=15 }                -- Mythique 0 : 15/boss
            },
            raids   = {
                { kind="normal",  perBoss=15, noFinal=true }  -- Normal : 15/boss (hors boss final)
            },
            outdoor = {
                { kind="weekly_event", perCache=15 }          -- Événement hebdo : 15/cache
            },
        },

        -- Runique (694 à 704)
        {
            crest   = { key="runic",  name=L["crest_runic"],  min=694, max=704 },
            chasms  = {
                { kind="classic", levels = { {8,3},{9,5},{10,5},{11,6} } }
            },
            dungeons= {
                { kind="mplus",   levels = { {2,10},{3,12},{4,14},{5,16},{6,18} } } -- Clé 2..6
            },
            raids   = {
                { kind="heroic",  perBoss=15, noFinal=true }  -- Héroïque : 15/boss (hors boss final)
            },
            outdoor = {
                { kind="na" }                                  -- N/A
            },
        },

        -- Doré (707 à 723)
        {
            crest   = { key="golden", name=L["crest_golden"], min=707, max=723 },
            chasms  = {
                { kind="archaeologist_loot", levels = { {8,4},{9,6},{10,8},{11,10} } }, -- Butin archéo
                { kind="abundant",           levels = { {11,7} } },                     -- Gouffre abondant
            },
            dungeons= {
                { kind="mplus",   levels = { {7,10},{8,12},{9,14},{10,16},{11,18},{12,20} } }
            },
            raids   = {
                { kind="mythic",  perBoss=15 }                 -- Mythique : 15/boss
            },
            outdoor = {
                { kind="na" }                                   -- N/A
            },
        },
    },
}

-- === Raids : paliers iLvl par difficulté (tableau) ===========================
-- On reste dans Upgrades.lua pour centraliser (pas de duplication de Data)
ns.Data.UpgradeTracks.raids = {
    headers = {
        difficulty = L["raid_header_difficulty"], -- DIFFICULTÉ / DIFFICULTY
        lfr        = L["difficulty_lfr"],
        normal     = L["difficulty_normal"],
        heroic     = L["difficulty_heroic"],
        mythic     = L["difficulty_mythic"],
    },
    text = {
        L["raid_intro_b1"],
        L["raid_intro_b2"], 
        L["raid_intro_b3"], 
        L["raid_intro_b4"], 
    },
    -- Couleurs proches de la capture (header et cellules)
    palette = {
        headers = {
            difficulty = {0.35, 0.23, 0.10}, -- brun
            lfr        = {0.02, 0.45, 0.21}, -- vert
            normal     = {0.64, 0.60, 0.07}, -- jaune/olive
            heroic     = {0.55, 0.05, 0.05}, -- rouge
            mythic     = {0.39, 0.13, 0.65}, -- violet
        },
        cells = {
            lfr        = {0.02, 0.45, 0.21, 0.25},
            normal     = {0.64, 0.60, 0.07, 0.25},
            heroic     = {0.55, 0.05, 0.05, 0.25},
            mythic     = {0.39, 0.13, 0.65, 0.25},
        },
    },

    -- Lignes visibles dans le tableau (texte = "ilvl : Etape")
    rows = {
        {
            label  = L["raid_row_group1"], -- Plexus, Rou'ethar, Naazindhri
            lfr    = string.format("|cffaaaaaa(%d)|r %s", 671, Step("upgrade_step_veteran",  2)),
            normal = string.format("|cffaaaaaa(%d)|r %s", 684, Step("upgrade_step_champion", 2)),
            heroic = string.format("|cffaaaaaa(%d)|r %s", 697, Step("upgrade_step_hero",     2)),
            mythic = string.format("|cffaaaaaa(%d)|r %s", 710, Step("upgrade_step_myth",     2)),
        },
        {
            label  = L["raid_row_group2"], -- Araz, Chasseurs et Fractillus
            lfr    = string.format("|cffaaaaaa(%d)|r %s", 675, Step("upgrade_step_veteran",  3)),
            normal = string.format("|cffaaaaaa(%d)|r %s", 688, Step("upgrade_step_champion", 3)),
            heroic = string.format("|cffaaaaaa(%d)|r %s", 701, Step("upgrade_step_hero",     3)),
            mythic = string.format("|cffaaaaaa(%d)|r %s", 714, Step("upgrade_step_myth",     3)),
        },
        {
            label  = L["raid_row_group3"], -- Roi-nexus et Dimensius
            lfr    = string.format("|cffaaaaaa(%d)|r %s", 678, Step("upgrade_step_veteran",  4)),
            normal = string.format("|cffaaaaaa(%d)|r %s", 691, Step("upgrade_step_champion", 4)),
            heroic = string.format("|cffaaaaaa(%d)|r %s", 704, Step("upgrade_step_hero",     4)),
            mythic = string.format("|cffaaaaaa(%d)|r %s", 717, Step("upgrade_step_myth",     4)),
        },

        -- Ligne "récap" de la capture : NIVEAU D'OBJET MAX
        {
            label  = L["raid_footer_ilvl_max"],
            lfr    = string.format("|cffaaaaaa(%d)|r %s", 691, Step("upgrade_step_veteran",  8)),
            normal = string.format("|cffaaaaaa(%d)|r %s", 704, Step("upgrade_step_champion", 8)),
            heroic = string.format("|cffaaaaaa(%d)|r %s", 710, Step("upgrade_step_hero",     6)),
            mythic = string.format("|cffaaaaaa(%d)|r %s", 723, Step("upgrade_step_myth",     6)),
        },
    },
}

-- ================================
-- ==  Delves / Gouffres (DATA) ==
-- ================================
ns.Data.Delves = {
    headers = {
        level = L["delves_header_level"],
        chest = L["delves_header_chest"],
        map   = L["delves_header_map"],
        vault = L["delves_header_vault"],
    },
    text = {
        L["delves_intro_b1"],
        L["delves_intro_b2"], 
        L["delves_intro_b3"], 
    },
    -- Couleurs entêtes (issues de la capture) + palette cellules (réutilise UpgradeTracks si dispo)
    palette = {
        headers = {
            level = {0.35, 0.23, 0.10},
            chest = {0.75, 0.53, 0.18},
            map   = {0.92, 0.52, 0.09},
            vault = {0.60, 0.38, 0.12},
        },
        cells = (ns.Data.UpgradeTracks and ns.Data.UpgradeTracks.palette and ns.Data.UpgradeTracks.palette.cells) or {
            aventurier= {0.00, 0.55, 0.67, 0.25},
            veteran   = {0.15, 0.58, 0.20, 0.25},
            champion  = {0.64, 0.60, 0.07, 0.25},
            heros     = {0.55, 0.05, 0.05, 0.25},
            mythe     = {0.39, 0.13, 0.65, 0.25},
        },
    },

    fmt = {
        level = L["delves_level_prefix"] or "Niveau %s",
        cell  = L["delves_cell_fmt"]     or "%d : %s (%d max)",
    },

    -- Lignes
    rows = (function()
        local F = function(ilvl, tierKey, step, max)
            if not ilvl or not tierKey or not step or not max then return { text="---" } end
            local label = string.format("|cffaaaaaa(%d)|r %s", ilvl, Step("upgrade_step_"..tierKey, step), max)
            return { text = label, tier = tierKey }
        end
        return {
            { level = "1",     chest = F(655, "adventurer", 1, 678),      map = { text="" },              vault = F(668, "veteran",   1, 691) },
            { level = "2",     chest = F(658, "adventurer", 2, 678),      map = { text="" },              vault = F(668, "veteran",   1, 691) },
            { level = "3",     chest = F(662, "adventurer", 3, 678),      map = { text="" },              vault = F(671, "veteran",   2, 691) },
            { level = "4",     chest = F(665, "adventurer", 4, 678),      map = F(671, "veteran",   2, 691), vault = F(678, "veteran",  4, 691) },
            { level = "5",     chest = F(668, "veteran",    1, 691),      map = F(678, "veteran",   4, 691), vault = F(681, "champion", 1, 704) },
            { level = "6",     chest = F(671, "veteran",    2, 691),      map = F(684, "champion",  2, 704), vault = F(688, "champion", 3, 704) },
            { level = "7",     chest = F(681, "champion",   1, 704),      map = F(691, "champion",  4, 704), vault = F(691, "champion", 4, 704) },
            { level = "8–11",  chest = F(684, "champion",   2, 704),      map = F(694, "hero",      1, 710), vault = F(694, "hero",     1, 710) },
        }
    end)(),
}

-- ====== Donjons (butin / chambre-forte / écus + texte d’intro) ======
do
    local L = ns and ns.L or {}
    local function Step(fmtKey, n) return string.format(L[fmtKey] or fmtKey, n) end
    local function MaxILvl(n) return string.format("(%d %s)", n, (L["max_short"] or "max")) end

    ns.Data.Dungeons = {
        headers = {
            activity    = L["dungeons_header_activity"]      or "— — —",
            dungeonLoot = L["dungeons_header_dungeon_loot"]  or "BUTIN DE DONJON",
            vault       = L["dungeons_header_vault"]         or "CHAMBRE-FORTE",
            crests      = L["dungeons_header_crests"]        or (L["upgrade_header_crests"] or "ÉCUS"),
        },
        text = {
            L["dng_note_intro"],
            L["dng_note_keystone_scaling"], 
        },

        -- Palette d’entête + palette des badges d’écus
        palette = {
            headers = {
                activity    = {0.35, 0.23, 0.10}, -- brun
                dungeonLoot = {0.35, 0.23, 0.10}, -- brun
                vault       = {0.10, 0.35, 0.12}, -- vert
                crests      = {0.35, 0.23, 0.10}, -- brun
            },
            crests = {
                -- couleurs badges (mêmes familles que le code couleur du jeu)
                valor  = {0.70, 0.70, 0.70},  -- Vaillance (gris clair)
                worn   = {0.55, 0.55, 0.55},  -- Abîmé (gris)
                carved = {0.20, 0.82, 0.30},  -- Gravé (vert)
                runic  = {0.17, 0.52, 0.95},  -- Runique (bleu)
                golden = {1.00, 0.75, 0.15},  -- Doré (or)
            },
        },

        -- Lignes du tableau
        -- Remarque : on structure les écus sous forme d’objet { count=nombre, key="runic|golden|..." } pour un rendu badge.
        rows = {
            { label = L["dng_row_timewalking"],
              loot  = ("|cffaaaaaa(655)|r %s"):format(Step("upgrade_step_adventurer", 1), MaxILvl(678)),
              vault = ("|cffaaaaaa(668)|r %s"):format(Step("upgrade_step_veteran",    1), MaxILvl(691)),
              crest = nil },

            { label = L["dng_row_heroic"],
              loot  = ("|cffaaaaaa(665)|r %s"):format(Step("upgrade_step_adventurer", 4), MaxILvl(678)),
              vault = ("|cffaaaaaa(678)|r %s"):format(Step("upgrade_step_veteran",    4), MaxILvl(691)),
              crest = { count = 15, key = "worn" } },

            { label = L["dng_row_m0"],
              loot  = ("|cffaaaaaa(681)|r %s"):format(Step("upgrade_step_champion", 1),   MaxILvl(704)),
              vault = ("|cffaaaaaa(691)|r %s"):format(Step("upgrade_step_champion", 4),   MaxILvl(704)),
              crest = { count = 15, key = "carved" } },

            { label = string.format(L["dng_row_key_fmt"] or "Clé de niveau %d", 2),
              loot  = ("|cffaaaaaa(684)|r %s"):format(Step("upgrade_step_champion", 2),   MaxILvl(704)),
              vault = ("|cffaaaaaa(694)|r %s"):format(Step("upgrade_step_hero",     1),   MaxILvl(710)),
              crest = { count = 10, key = "runic" } },

            { label = string.format(L["dng_row_key_fmt"] or "Clé de niveau %d", 3),
              loot  = ("|cffaaaaaa(684)|r %s"):format(Step("upgrade_step_champion", 2),   MaxILvl(704)),
              vault = ("|cffaaaaaa(694)|r %s"):format(Step("upgrade_step_hero",     1),   MaxILvl(710)),
              crest = { count = 12, key = "runic" } },

            { label = string.format(L["dng_row_key_fmt"] or "Clé de niveau %d", 4),
              loot  = ("|cffaaaaaa(688)|r %s"):format(Step("upgrade_step_champion", 3),   MaxILvl(704)),
              vault = ("|cffaaaaaa(697)|r %s"):format(Step("upgrade_step_hero",     2),   MaxILvl(710)),
              crest = { count = 14, key = "runic" } },

            { label = string.format(L["dng_row_key_fmt"] or "Clé de niveau %d", 5),
              loot  = ("|cffaaaaaa(688)|r %s"):format(Step("upgrade_step_champion", 3),   MaxILvl(704)),
              vault = ("|cffaaaaaa(697)|r %s"):format(Step("upgrade_step_hero",     2),   MaxILvl(710)),
              crest = { count = 16, key = "runic" } },

            { label = string.format(L["dng_row_key_fmt"] or "Clé de niveau %d", 6),
              loot  = ("|cffaaaaaa(691)|r %s"):format(Step("upgrade_step_champion", 4),   MaxILvl(704)),
              vault = ("|cffaaaaaa(701)|r %s"):format(Step("upgrade_step_hero",     3),   MaxILvl(710)),
              crest = { count = 18, key = "runic" } },

            { label = string.format(L["dng_row_key_fmt"] or "Clé de niveau %d", 7),
              loot  = ("|cffaaaaaa(694)|r %s"):format(Step("upgrade_step_hero",     1),   MaxILvl(710)),
              vault = ("|cffaaaaaa(704)|r %s"):format(Step("upgrade_step_hero",     4),   MaxILvl(710)),
              crest = { count = 10, key = "golden" } },

            { label = string.format(L["dng_row_key_fmt"] or "Clé de niveau %d", 8),
              loot  = ("|cffaaaaaa(697)|r %s"):format(Step("upgrade_step_hero",     2),   MaxILvl(710)),
              vault = ("|cffaaaaaa(704)|r %s"):format(Step("upgrade_step_hero",     4),   MaxILvl(710)),
              crest = { count = 12, key = "golden" } },

            { label = string.format(L["dng_row_key_fmt"] or "Clé de niveau %d", 9),
              loot  = ("|cffaaaaaa(697)|r %s"):format(Step("upgrade_step_hero",     2),   MaxILvl(710)),
              vault = ("|cffaaaaaa(704)|r %s"):format(Step("upgrade_step_hero",     4),   MaxILvl(710)),
              crest = { count = 14, key = "golden" } },

            { label = string.format(L["dng_row_key_fmt"] or "Clé de niveau %d", 10),
              loot  = ("|cffaaaaaa(701)|r %s"):format(Step("upgrade_step_hero",     3),   MaxILvl(710)),
              vault = ("|cffaaaaaa(707)|r %s"):format(Step("upgrade_step_myth",     1),   MaxILvl(723)),
              crest = { count = 16, key = "golden" } },

            { label = string.format(L["dng_row_key_fmt"] or "Clé de niveau %d", 11),
              loot  = ("|cffaaaaaa(701)|r %s"):format(Step("upgrade_step_hero",     3),   MaxILvl(710)),
              vault = ("|cffaaaaaa(707)|r %s"):format(Step("upgrade_step_myth",     1),   MaxILvl(723)),
              crest = { count = 18, key = "golden" } },

            { label = string.format(L["dng_row_key_fmt"] or "Clé de niveau %d", 12),
              loot  = ("|cffaaaaaa(701)|r %s"):format(Step("upgrade_step_hero",     3),   MaxILvl(710)),
              vault = ("|cffaaaaaa(707)|r %s"):format(Step("upgrade_step_myth",     1),   MaxILvl(723)),
              crest = { count = 20, key = "golden" } },
        }
    }
end