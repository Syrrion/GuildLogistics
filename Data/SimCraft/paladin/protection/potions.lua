local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI
local UI = ns and ns.UI

ns.Consum_paladin_protection_potions = [[
{
    "class_id": 2,
    "data": {
        "Potion of Unwavering Focus": {
            "1": 3197748,
            "2": 3203332,
            "3": 3206070
        },
        "Tempered Potion": {
            "1": 3259675,
            "2": 3273186,
            "3": 3276300
        },
        "baseline": {
            "1": 3187417
        }
    },
    "data_type": "potions",
    "item_ids": {
        "Potion of Unwavering Focus": "212259",
        "Tempered Potion": "212265"
    },
    "metadata": {
        "SimulationCraft": "3945f09",
        "bloodytools": "8ee54970aa33896c2c888c8b1bd00e74de5cafc7",
        "timestamp": "2025-09-24 06:25:38.798208"
    },
    "profile": {
        "character": {
            "# source": "simulationcraft",
            "class": "paladin",
            "level": "80",
            "position": "front",
            "race": "human",
            "role": "tank",
            "spec": "protection",
            "talents": "CIEAAAAAAAAAAAAAAAAAAAAAAsMzMMzyYZMzMzM2mZmxMYGDAAwAAAAAAAQbZmZxwMYMzMbtBAjBGAGsNAAAIAzMLbLtNzYxAAYGMMG"
        },
        "items": {
            "back": {
                "bonus_id": "12401/9893",
                "enchant_id": "7409",
                "gem_id": "238045",
                "id": "235499"
            },
            "chest": {
                "bonus_id": "4800/4786/1527/11996",
                "enchant": "crystalline_radiance_3",
                "enchant_id": "7364",
                "id": "237622",
                "ilevel": "723"
            },
            "feet": {
                "id": "243307",
                "ilevel": "723"
            },
            "finger1": {
                "enchant": "radiant_haste_3",
                "gem_id": "213479/213479",
                "id": "237567",
                "ilevel": "723"
            },
            "finger2": {
                "enchant": "radiant_haste_3",
                "gem_id": "213479/213479",
                "id": "221136",
                "ilevel": "723"
            },
            "hands": {
                "bonus_id": "4800/4786/1527/11996",
                "id": "237620",
                "ilevel": "723"
            },
            "head": {
                "gem_id": "213743",
                "id": "246283",
                "ilevel": "723"
            },
            "legs": {
                "bonus_id": "4800/4786/1527/11996",
                "enchant": "stormbound_armor_kit_3",
                "enchant_id": "7601",
                "id": "237618",
                "ilevel": "723"
            },
            "main_hand": {
                "bonus_id": "4800/4786/1527/11996",
                "enchant": "authority_of_the_depths_3",
                "id": "237734",
                "ilevel": "723"
            },
            "neck": {
                "gem_id": "213470/213491",
                "id": "185820",
                "ilevel": "723"
            },
            "off_hand": {
                "bonus_id": "4800/4786/1527/11996",
                "id": "237723",
                "ilevel": "723"
            },
            "shoulders": {
                "bonus_id": "4800/4786/1527/11996",
                "id": "237617",
                "ilevel": "723"
            },
            "trinket1": {
                "bonus_id": "4800/4786/1527/11996",
                "id": "242402",
                "ilevel": "723"
            },
            "trinket2": {
                "bonus_id": "4800/4786/1527/11996",
                "id": "219309",
                "ilevel": "723"
            },
            "waist": {
                "bonus_id": "12043/1485/10222/10520/10878/8960",
                "crafted_stats": "36/32",
                "gem_id": "213479",
                "id": "222431",
                "ilevel": "720"
            },
            "wrists": {
                "bonus_id": "12043/1485/10222/10520/10878/8960",
                "crafted_stats": "36/32",
                "gem_id": "213494",
                "id": "222435",
                "ilevel": "720"
            }
        },
        "metadata": {
            "base_dps": 3187417.5811581505
        }
    },
    "simc_settings": {
        "fight_style": "castingpatchwerk",
        "iterations": "60000",
        "ptr": "0",
        "simc_hash": "3945f09",
        "target_error": "0.1",
        "tier": "TWW3"
    },
    "simulated_steps": [
        3,
        2,
        1
    ],
    "sorted_data_keys": [
        "Tempered Potion",
        "Potion of Unwavering Focus",
        "baseline"
    ],
    "spec_id": 66,
    "subtitle": "UTC 2025-09-24 06:25 | SimC build: <a href=\"https://github.com/simulationcraft/simc/commit/3945f09\" target=\"blank\">3945f09</a>",
    "timestamp": "2025-09-24 06:25",
    "title": "Potions | Protection Paladin | Castingpatchwerk",
    "translations": {}
}
]]
