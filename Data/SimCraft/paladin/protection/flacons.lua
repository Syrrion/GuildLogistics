local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI
local UI = ns and ns.UI

ns.Consum_paladin_protection_flacons = [[
{
    "class_id": 2,
    "data": {
        "Flask of Alchemical Chaos": {
            "1": 3271925,
            "2": 3278754,
            "3": 3288901
        },
        "Flask of Tempered Aggression": {
            "1": 3252020,
            "2": 3265175,
            "3": 3268953
        },
        "Flask of Tempered Mastery": {
            "1": 3243909,
            "2": 3247938,
            "3": 3257928
        },
        "Flask of Tempered Swiftness": {
            "1": 3247017,
            "2": 3261540,
            "3": 3265392
        },
        "Flask of Tempered Versatility": {
            "1": 3248058,
            "2": 3259943,
            "3": 3267311
        },
        "baseline": {
            "1": 3177151
        }
    },
    "data_type": "phials",
    "item_ids": {
        "Flask of Alchemical Chaos": "212283",
        "Flask of Tempered Aggression": "212271",
        "Flask of Tempered Mastery": "212280",
        "Flask of Tempered Swiftness": "212274",
        "Flask of Tempered Versatility": "212277"
    },
    "metadata": {
        "SimulationCraft": "6e59fdd",
        "bloodytools": "8ee54970aa33896c2c888c8b1bd00e74de5cafc7",
        "timestamp": "2025-09-17 02:31:17.559642"
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
            "base_dps": 3177151.2276493553
        }
    },
    "simc_settings": {
        "fight_style": "castingpatchwerk",
        "iterations": "60000",
        "ptr": "0",
        "simc_hash": "6e59fdd",
        "target_error": "0.1",
        "tier": "TWW3"
    },
    "simulated_steps": [
        3,
        2,
        1
    ],
    "sorted_data_keys": [
        "Flask of Alchemical Chaos",
        "Flask of Tempered Aggression",
        "Flask of Tempered Versatility",
        "Flask of Tempered Swiftness",
        "Flask of Tempered Mastery",
        "baseline"
    ],
    "spec_id": 66,
    "subtitle": "UTC 2025-09-17 02:31 | SimC build: <a href=\"https://github.com/simulationcraft/simc/commit/6e59fdd\" target=\"blank\">6e59fdd</a>",
    "timestamp": "2025-09-17 02:31",
    "title": "Phials | Protection Paladin | Castingpatchwerk",
    "translations": {}
}
]]
