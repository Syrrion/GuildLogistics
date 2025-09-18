local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI
local UI = ns and ns.UI

ns.Consum_warlock_affliction_potions = [[
{
    "class_id": 9,
    "data": {
        "Potion of Unwavering Focus": {
            "1": 5316533,
            "2": 5327612,
            "3": 5335515
        },
        "Tempered Potion": {
            "1": 5421660,
            "2": 5437315,
            "3": 5450804
        },
        "baseline": {
            "1": 5300267
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
        "timestamp": "2025-09-17 02:43:42.824904"
    },
    "profile": {
        "character": {
            "# source": "simulationcraft",
            "class": "warlock",
            "default_pet": "sayaad",
            "level": "80",
            "position": "back",
            "race": "maghar_orc",
            "role": "spell",
            "spec": "affliction",
            "talents": "CkQAAAAAAAAAAAAAAAAAAAAAAAzMzMzMjYWMwsNzMDzyAAAAmZmZWMzMWmZmZDmZAAzYBGYWMaMDIzGYZGAAAAAAAAMjZD"
        },
        "items": {
            "back": {
                "bonus_id": "9893/12239",
                "enchant_id": "7403",
                "gem_id": "238042",
                "id": "235499"
            },
            "chest": {
                "bonus_id": "12676/12361/1533",
                "enchant_id": "7364",
                "id": "237703"
            },
            "feet": {
                "bonus_id": "1533/12361/12239/13504",
                "enchant_id": "7424",
                "id": "243305"
            },
            "finger1": {
                "bonus_id": "1533/12361/12239/8781",
                "enchant_id": "7334",
                "gem_id": "213491/213491",
                "id": "237567"
            },
            "finger2": {
                "bonus_id": "1533/12361/12239/8781",
                "enchant_id": "7346",
                "gem_id": "213479/213455",
                "id": "242405"
            },
            "hands": {
                "bonus_id": "12675/1533/12361",
                "id": "237701"
            },
            "head": {
                "bonus_id": "3215/12361/12239/1808",
                "gem_id": "213743",
                "id": "221131"
            },
            "legs": {
                "bonus_id": "12676/1533/12361",
                "enchant_id": "7534",
                "id": "237699"
            },
            "main_hand": {
                "bonus_id": "1533/12361/12239",
                "enchant_id": "7445",
                "id": "237728"
            },
            "neck": {
                "bonus_id": "1533/12361/12239/8781",
                "gem_id": "213470/213491",
                "id": "242406"
            },
            "off_hand": {
                "bonus_id": "10421/9633/8902/12053/12050/1485/11300/8960/8795",
                "crafted_stats": "36/49",
                "id": "222566"
            },
            "shoulders": {
                "bonus_id": "12675/1533/12361",
                "id": "237698"
            },
            "trinket1": {
                "bonus_id": "1533/12361/12239",
                "id": "242402"
            },
            "trinket2": {
                "bonus_id": "1533/12361/12239",
                "id": "242395"
            },
            "waist": {
                "bonus_id": "1489/12352/12239",
                "gem_id": "213491",
                "id": "242664"
            },
            "wrists": {
                "bonus_id": "10421/9633/8902/12053/12050/1485/1808/11109/8960/8791",
                "crafted_stats": "36/49",
                "enchant_id": "7397",
                "gem_id": "213491",
                "id": "222815"
            }
        },
        "metadata": {
            "base_dps": 5300267.858424926
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
    "spec_id": 265,
    "subtitle": "UTC 2025-09-17 02:43 | SimC build: <a href=\"https://github.com/simulationcraft/simc/commit/6e59fdd\" target=\"blank\">6e59fdd</a>",
    "timestamp": "2025-09-17 02:43",
    "title": "Potions | Affliction Warlock | Castingpatchwerk",
    "translations": {}
}
]]
