local ADDON, ns = ...
ns.Data = ns.Data or {}
ns.Data.POTIONS_SEED_VERSION = 8

-- Catégories explicites : "heal" (potion de soins), "util" (autres potions), "stone" (pierre de soins)
-- Renseigne ici ce que tu veux suivre exactement (si vide, heuristique nom/icône).
ns.Data.CONSUMABLES_TYPED = ns.Data.CONSUMABLES_TYPED or {
    util  = { 
        items = {
            212242, -- Délice cavernicole
            212243, -- Délice cavernicole
            212244, -- Délice cavernicole
            212948, -- Délice cavernicole fugace
            212949, -- Délice cavernicole fugace
            212950, -- Délice cavernicole fugace
            212263, -- Potion tempérée
            212264, -- Potion tempérée
            212265, -- Potion tempérée
            212969, -- Potion tempérée fugace
            212970, -- Potion tempérée fugace
            212971, -- Potion tempérée fugace
            212239, -- Potion de mana algarie
            212240, -- Potion de mana algarie
            212241, -- Potion de mana algarie
            212945, -- Potion de mana algarie fugace
            212946, -- Potion de mana algarie fugace
            212947, -- Potion de mana algarie fugace
            248331, -- Essence ombrale
            248585, -- Essence ombrale
            248586, -- Essence ombrale
            212254, -- Flacon grotesque
            212255, -- Flacon grotesque
            212256, -- Flacon grotesque
            212257, -- Flacon de concentration inébranlable
            212258, -- Flacon de concentration inébranlable
            212259, -- Flacon de concentration inébranlable
            212963, -- Flacon fugace de concentration inébranlable
            212964, -- Flacon fugace de concentration inébranlable
            212965, -- Flacon fugace de concentration inébranlable
            212260, -- Potion de ligne de front
            212261, -- Potion de ligne de front
            212262, -- Potion de ligne de front
            212966, -- Potion de ligne de front fugace
            212967, -- Potion de ligne de front fugace
            212968, -- Potion de ligne de front fugace
            212266, -- Potion du guépard relevé
            212267, -- Potion du guépard relevé
            212268, -- Potion du guépard relevé
            212972, -- Potion du guépard relevé fugace
            212973, -- Potion du guépard relevé fugace
            212974, -- Potion du guépard relevé fugace
            212248, -- Breuvage de pas silencieux
            212249, -- Breuvage de pas silencieux
            212250, -- Breuvage de pas silencieux
            212954, -- Breuvage de pas silencieux fugace
            212955, -- Breuvage de pas silencieux fugace
            212956, -- Breuvage de pas silencieux fugace
            212251, -- Breuvage de révélation choquantes
            212252, -- Breuvage de révélation choquantes
            212253, -- Breuvage de révélation choquantes
            212957, -- Breuvage fugace de révélation choquantes
            212958, -- Breuvage fugace de révélation choquantes
            212959, -- Breuvage fugace de révélation choquantes
        }, 
        spells = {
        }
    },
    heal  = { 
        items = {
            211878, -- Potion de soins algarie
            211879, -- Potion de soins algarie
            211880, -- Potion de soins algarie
            212942, -- Potion de soins algarie fugace
            212943, -- Potion de soins algarie fugace
            212944, -- Potion de soins algarie fugace
            244835, -- Potion de soins revigorante
            244838, -- Potion de soins revigorante
            244839, -- Potion de soins revigorante
            244849, -- Potion de soins revigorante fugace
        }, 
        spells = {
        }
    },
    stone = { 
        items = {
            5512, -- Pierre de soins
        }, 
        spells = {
        }
    },
    cddef = { 
        items = {
        }, 
        spells = {
            66, 498, 586, 642, 781, 1856, 1966, 5277, 5384, 11426, 18499, 19236, 22812, 31224, 45438, 47585, 48707, 48743, 48792, 51271, 55342, 61336, 104773, 108238, 108271, 108416, 109304, 110959, 115176, 115203, 118038, 122278, 122470, 122783, 184364, 184662, 185311, 186265, 196555, 198589, 199483, 202168, 235313, 235450, 342245, 363916, 374348, 403876, 633, 1022, 1044, 2050, 3411, 6940, 33206, 47788, 102342, 108968, 204018, 357170, 363534, 66, 498, 586, 642, 781, 1856, 1966, 5277, 5384, 11426, 18499, 19236, 22812, 31224, 45438, 47585, 48707, 48743, 48792, 51271, 55342, 61336, 104773, 108238, 108271, 108416, 109304, 110959, 115176, 115203, 118038, 122278, 122470, 122783, 184364, 184662, 185311, 186265, 196555, 198589, 199483, 202168, 235313, 235450, 342245, 363916, 374348, 403876, 31821
        }
    },
    dispel = { 
        items = {
        }, 
        spells = {
            475, 527, 2782, 4987, 32375, 51886, 77130, 88423, 213634, 213644, 218164, 365585, 383013
        }
    },
    taunt = { 
        items = {
        }, 
        spells = {
            355, 1161, 6795, 56222, 62124, 115546, 185245, 386071
        }
    },
    move = { 
        items = {
        }, 
        spells = {
            106898, 116841, 192077, 374227, 374968, 1850, 1953, 2983, 6544, 36554, 48265, 52174, 58875, 79206, 101545, 102401, 107428, 109132, 115008, 119996, 121536, 186257, 189110, 190784, 190925, 192063, 195072, 195457, 212552, 212653, 252216, 358267, 370665
        }
    },
    kick = { 
        items = {
        }, 
        spells = {
            1766, 2139, 6552, 15487, 31935, 47528, 57994, 78675, 96231, 106839, 116705, 132409, 147362, 183752, 187707, 351338, 115750, 853
        }
    },
    cc = { 
        items = {
        }, 
        spells = {
            99, 408, 1776, 2094, 5211, 5484, 6789, 10326, 15487, 19577, 20066, 51514, 64044, 107570, 109248, 115078, 187650, 205364, 211881, 217832, 221562, 305483, 358385, 2484, 5246, 8122, 30283, 46968, 51485, 108920, 113724, 119381, 179057, 192058, 197214, 207167, 207684, 383121
        }
    },
    special = { 
        items = {
        }, 
        spells = {
            2825, 8143, 10060, 19801, 32182, 49576, 51490, 61391, 64382, 73325, 80353, 102359, 102793, 108199, 114018, 116841, 116844, 132469, 198103, 202137, 202138, 205636, 370665, 384100, 16191, 29166, 64901
        }
    },
}

ns.Data.CONSUMABLE_CATEGORY = ns.Data.CONSUMABLE_CATEGORY or {}

ns.Data.CONSUMABLE_EXCLUDE_SPELLS = ns.Data.CONSUMABLE_EXCLUDE_SPELLS or {
    105421
}