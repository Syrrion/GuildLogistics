local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI
local UI = ns and ns.UI

ns.Consum_warrior_protection_potions = [[
{
    "class_id": 1,
    "data": {
        "Potion of Unwavering Focus": {
            "1": 3712268,
            "2": 3712731,
            "3": 3720063
        },
        "Tempered Potion": {
            "1": 3757754,
            "2": 3765178,
            "3": 3763300
        },
        "baseline": {
            "1": 3701881
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
        "timestamp": "2025-09-24 06:29:48.363466"
    },
    "profile": {
        "character": {
            "# source": "simulationcraft",
            "class": "warrior",
            "level": "80",
            "position": "front",
            "race": "mechagnome",
            "role": "tank",
            "spec": "protection",
            "talents": "CkEAAAAAAAAAAAAAAAAAAAAAA02AAAAwMzYmZmZYmNzMLDGjRzMLjZYmFww2MzwMMjZAAAAAAglBAYGLAGYDWWMaMDgZJYDzMA"
        },
        "items": {
            "back": {
                "bonus_id": "12401/9893",
                "enchant": "chant_of_winged_grace_3",
                "gem_id": "238042",
                "id": "235499"
            },
            "chest": {
                "bonus_id": "12361/10356/12229/40/12676/1533/10255",
                "enchant": "crystalline_radiance_3",
                "id": "237613"
            },
            "feet": {
                "bonus_id": "40/10356/12361/1533/10255/13504",
                "enchant": "defenders_march_3",
                "id": "243307"
            },
            "finger1": {
                "bonus_id": "4786/3215/12361/8781",
                "enchant": "radiant_critical_strike_3",
                "gem_id": "213470/213470",
                "id": "221136"
            },
            "finger2": {
                "bonus_id": "4786/3215/12361/8781",
                "enchant": "radiant_critical_strike_3",
                "gem_id": "213470/213470",
                "id": "221141"
            },
            "hands": {
                "bonus_id": "4800/4786/1533/12361",
                "id": "237526"
            },
            "head": {
                "bonus_id": "12361/10356/12231/40/12921/12676/1533/10255",
                "id": "237610"
            },
            "legs": {
                "bonus_id": "12361/10356/12232/40/12676/1533/10255",
                "enchant": "defenders_armor_kit_3",
                "id": "237609"
            },
            "main_hand": {
                "bonus_id": "1533/12361/12239",
                "enchant": "oathsworns_tenacity_3",
                "id": "237813"
            },
            "neck": {
                "bonus_id": "4800/4786/1533/12361/8781",
                "gem_id": "213470/213470",
                "id": "237569"
            },
            "off_hand": {
                "bonus_id": "1533/12361/12239",
                "id": "237723"
            },
            "shoulders": {
                "bonus_id": "12361/10356/12233/40/12675/1533/10255",
                "id": "237608"
            },
            "trinket1": {
                "bonus_id": "4786/10035/12361",
                "id": "190652"
            },
            "trinket2": {
                "bonus_id": "4800/4786/1533/12361",
                "id": "242395"
            },
            "waist": {
                "bonus_id": "12053/12050/11307/9627/11304",
                "crafted_stats": "32/36",
                "gem_id": "213470",
                "id": "222431"
            },
            "wrists": {
                "bonus_id": "12053/12050/11307/9627/11304",
                "crafted_stats": "32/36",
                "gem_id": "213470",
                "id": "222435"
            }
        },
        "metadata": {
            "base_dps": 3701881.6566438954
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
    "spec_id": 73,
    "subtitle": "UTC 2025-09-24 06:29 | SimC build: <a href=\"https://github.com/simulationcraft/simc/commit/3945f09\" target=\"blank\">3945f09</a>",
    "timestamp": "2025-09-24 06:29",
    "title": "Potions | Protection Warrior | Castingpatchwerk",
    "translations": {}
}
]]
