local ADDON, ns = ...
ns.Data = ns.Data or {}

-- Catégories explicites : "heal" (potion de soins), "util" (autres potions), "stone" (pierre de soins)
-- Renseigne ici ce que tu veux suivre exactement (si vide, heuristique nom/icône).
ns.Data.CONSUMABLE_CATEGORY = ns.Data.CONSUMABLE_CATEGORY or {
    [211878] = "heal", -- Potion de soins algarie
    [211879] = "heal",
    [211880] = "heal",
    
    [244837] = "heal", -- Potion de soins revigorante
    [244838] = "heal", 
    [244839] = "heal",
    
    [212242] = "util", -- Délice cavernicole 
    [212243] = "util", 
    [212244] = "util",
    
    [212948] = "util", -- Délice cavernicole fugace
    [212949] = "util",
    [212950] = "util",

    [212263] = "util", -- Potion tempérée
    [212264] = "util",
    [212265] = "util",
    
    [212969] = "util", -- Potion tempérée fugace
    [212970] = "util", 
    [212971] = "util", 

    [212239] = "util", -- Potion de mana algarie
    [212240] = "util", 
    [212241] = "util", 
    
    [248584] = "util", -- Essence ombrale
    [248585] = "util",
    [248586] = "util",
    
    [212254] = "util", -- Flacon grotesque
    [212255] = "util",
    [212256] = "util", 
    
    [212257] = "util", -- Flacon de concentration inébranlable
    [212258] = "util", 
    [212259] = "util", 

    [212260] = "util", -- Potion de ligne de front
    [212261] = "util", 
    [212262] = "util", 

    [212266] = "util", -- Potion du guépard relevé
    [212267] = "util", 
    [212258] = "util", 

    [212263] = "util", -- Potion tempérée
    [212264] = "util", 
    [212265] = "util", 

    [212248] = "util", -- Breuvage de pas silencieux
    [212249] = "util", 
    [212250] = "util", 

    [212251] = "util", -- Breuvage de révélation choquantes
    [212252] = "util", 
    [212253] = "util", 

    [5512] = "stone", -- Pierre de soins
}

-- Healthstones explicites (si connus)
ns.Data.HEALTHSTONE_SPELLS = ns.Data.HEALTHSTONE_SPELLS or {
    -- [6262] = true, -- exemple historique "Healthstone"
}
