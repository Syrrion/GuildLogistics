local ADDON, ns = ...
ns.Data = ns.Data or {}
ns.Data.POTIONS_SEED_VERSION = 3

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
            18499,  -- Rage de Berserker
            118038, -- Par le fil de l'épée
            184364, -- Régénération enragée
            31821,  -- Maîtrise des auras
            498,    -- Protection divine
            403876, -- Protection divine
            642,    -- Bouclier divin
            184662, -- Bouclier du vengeur
            186265, -- Aspect de la tortue
            109304, -- Enthousiasme
            264735, -- Survie du plus fort
            388035, -- Robustesse de l'ours
            392956, -- Robustesse de l'ours
            272679, -- Robustesse de l'ours
            31224,  -- Cape d'ombre
            185311, -- Fiole cramoisie
            5277,   -- Evasion
            1966,   -- Feinte
            19236,  -- Prière du déséspoir
            47585,  -- Dispersion
            586,    -- Disparition
            48707,  -- Carapace anti-magie
            48792,  -- Robustesse glaciale
            48743,  -- Pacte mortel
            108271, -- Transfert astral
            342245, -- Altérer le temps
            235313, -- Barrière flamboyante
            11426,  -- Barrière de glace
            45438,  -- Bloc de glace
            110959, -- Invisibilité supérieure
            55342,  -- Image miroir
            235450, -- Barrière prismatique
            104773, -- Résolution interminable
            108416, -- Sombre pacte
            115203, -- Boisson fortifiante
            122470, -- Toucher de karma
            122278, -- Atténuation du mal
            122783, -- Diffusion de la magie
            22812,  -- Ecorce
            61336,  -- Instincts de survie
            108238, -- Renouveau
            198589, -- Voile corrompu
            196555, -- Marche du néant
            374348, -- Brasier de rénovation
            363916, -- Ecailles d'obsidienne
        }
    },
}

ns.Data.CONSUMABLE_CATEGORY = ns.Data.CONSUMABLE_CATEGORY or {}

ns.Data.CONSUMABLE_EXCLUDE_SPELLS = ns.Data.CONSUMABLE_EXCLUDE_SPELLS or {
    [82326] = true, -- Holy Light (Paladin) : ne doit JAMAIS être compté comme potion/prépot
}
