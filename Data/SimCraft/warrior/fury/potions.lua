local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI
local UI = ns and ns.UI

ns.Consum_warrior_fury_potions = [[
{
    "class_id": 1,
    "data": {
        "Potion of Unwavering Focus": {
            "1": 5844064,
            "2": 5850579,
            "3": 5858096
        },
        "Tempered Potion": {
            "1": 5908703,
            "2": 5917468,
            "3": 5921065
        },
        "baseline": {
            "1": 5832792
        }
    },
    "data_type": "potions",
    "item_ids": {
        "Potion of Unwavering Focus": "212259",
        "Tempered Potion": "212265"
    },
    "metadata": {
        "SimulationCraft": "6e59fdd",
        "bloodytools": "8ee54970aa33896c2c888c8b1bd00e74de5cafc7",
        "timestamp": "2025-09-17 02:44:56.039487"
    },
    "profile": {
        "character": {
            "# source": "simulationcraft",
            "class": "warrior",
            "level": "80",
            "position": "back",
            "race": "void_elf",
            "role": "attack",
            "spec": "fury",
            "talents": "CgEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQjhZmNzMMjBzswMzMmhZYmttxYmZWwMmZmxMzsMM8AmZAAAQM22GYBMBzwEYwGA"
        },
        "items": {
            "back": {
                "bonus_id": "12401/9893",
                "enchant": "chant_of_winged_grace_3",
                "gem_id": "238045",
                "id": "235499"
            },
            "chest": {
                "bonus_id": "10356",
                "enchant": "crystalline_radiance_3",
                "id": "237613",
                "ilevel": "723"
            },
            "feet": {
                "bonus_id": "10356/13504",
                "enchant": "defenders_march_3",
                "id": "243307",
                "ilevel": "723"
            },
            "finger1": {
                "bonus_id": "657/12052/5877/10390/12361/12053/8781",
                "enchant": "radiant_haste_3",
                "gem_id": "213497/213482",
                "id": "221200",
                "ilevel": "723"
            },
            "finger2": {
                "bonus_id": "657/12052/5877/10390/12361/12053/8781",
                "enchant": "radiant_haste_3",
                "gem_id": "213485/213461",
                "id": "178824",
                "ilevel": "723"
            },
            "hands": {
                "bonus_id": "10356",
                "id": "237611",
                "ilevel": "723"
            },
            "head": {
                "bonus_id": "523/10356",
                "gem_id": "213743",
                "id": "237610",
                "ilevel": "723"
            },
            "legs": {
                "bonus_id": "10356",
                "enchant": "defenders_armor_kit_3",
                "id": "237609",
                "ilevel": "723"
            },
            "main_hand": {
                "bonus_id": "10356",
                "enchant": "stormriders_fury_3",
                "id": "234490",
                "ilevel": "723"
            },
            "neck": {
                "bonus_id": "10356/8781",
                "gem_id": "213470/213473",
                "id": "237568",
                "ilevel": "723"
            },
            "off_hand": {
                "bonus_id": "9627/12053/12050/11300/8960/8793",
                "crafted_stats": "36/40",
                "enchant": "oathsworns_tenacity_3",
                "id": "222443"
            },
            "shoulders": {
                "bonus_id": "10356",
                "id": "237608",
                "ilevel": "723"
            },
            "trinket1": {
                "bonus_id": "10356",
                "id": "242395",
                "ilevel": "723"
            },
            "trinket2": {
                "bonus_id": "10356",
                "id": "242394",
                "ilevel": "723"
            },
            "waist": {
                "bonus_id": "523/10356",
                "gem_id": "213497",
                "id": "237607",
                "ilevel": "723"
            },
            "wrists": {
                "bonus_id": "9627/12053/12050/8960/1808/11109/8793",
                "crafted_stats": "36/40",
                "gem_id": "213497",
                "id": "222435"
            }
        },
        "metadata": {
            "base_dps": 5832792.258976077
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
        "Tempered Potion",
        "Potion of Unwavering Focus",
        "baseline"
    ],
    "spec_id": 72,
    "subtitle": "UTC 2025-09-17 02:44 | SimC build: <a href=\"https://github.com/simulationcraft/simc/commit/6e59fdd\" target=\"blank\">6e59fdd</a>",
    "timestamp": "2025-09-17 02:44",
    "title": "Potions | Fury Warrior | Castingpatchwerk",
    "translations": {}
}
]]
