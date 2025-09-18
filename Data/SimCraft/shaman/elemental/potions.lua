local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI
local UI = ns and ns.UI

ns.Consum_shaman_elemental_potions = [[
{
    "class_id": 7,
    "data": {
        "Potion of Unwavering Focus": {
            "1": 6285912,
            "2": 6290555,
            "3": 6311967
        },
        "Tempered Potion": {
            "1": 6384545,
            "2": 6395761,
            "3": 6406135
        },
        "baseline": {
            "1": 6272590
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
        "timestamp": "2025-09-17 02:42:56.896975"
    },
    "profile": {
        "character": {
            "# source": "simulationcraft",
            "class": "shaman",
            "level": "80",
            "position": "ranged_back",
            "race": "tauren",
            "role": "spell",
            "spec": "elemental",
            "talents": "CYQAAAAAAAAAAAAAAAAAAAAAAAAAAAAMbzyyMjZGzysMGMYmBAAAAwiZWgBMgZjJkZBAMbTzMw2CzMNMzMz2wyMmZYMMLjZGzMmZ2AA"
        },
        "items": {
            "back": {
                "bonus_id": "9893/12239",
                "enchant_id": "7403",
                "gem_id": "238046",
                "id": "235499"
            },
            "chest": {
                "bonus_id": "12361/10356/12229/6652/12676/1533/10255",
                "enchant_id": "7364",
                "id": "237640"
            },
            "feet": {
                "bonus_id": "1533/12361/12239/13504",
                "enchant_id": "7424",
                "id": "243308"
            },
            "finger1": {
                "bonus_id": "10035/12361/12239/8781",
                "enchant_id": "7352",
                "gem_id": "213458/213458",
                "id": "185813"
            },
            "finger2": {
                "bonus_id": "10035/12361/12239/8781",
                "enchant_id": "7352",
                "gem_id": "213458/213458",
                "id": "185840"
            },
            "hands": {
                "bonus_id": "12361/10356/12230/6652/12675/1533/10255",
                "id": "237638"
            },
            "head": {
                "bonus_id": "10032/12361/12239/1808",
                "gem_id": "213743",
                "id": "178816"
            },
            "legs": {
                "bonus_id": "12361/10356/12232/6652/12676/1533/10255",
                "enchant_id": "7534",
                "id": "237636"
            },
            "main_hand": {
                "bonus_id": "6652/10356/12361/1533/10255",
                "enchant_id": "7448",
                "id": "237728"
            },
            "neck": {
                "bonus_id": "1572/12361/12239/8781",
                "gem_id": "213473/213494",
                "id": "251880"
            },
            "off_hand": {
                "bonus_id": "10421/9633/8902/12053/12050/1485/11300/8960/8794",
                "crafted_stats": "49/36",
                "id": "222566"
            },
            "shoulders": {
                "bonus_id": "12361/10356/12233/6652/12675/1533/10255",
                "id": "237635"
            },
            "trinket1": {
                "bonus_id": "6652/10356/12361/1533/10255",
                "id": "242402"
            },
            "trinket2": {
                "bonus_id": "1533/12361/12239",
                "id": "242395"
            },
            "waist": {
                "bonus_id": "1533/12361/12239/1808",
                "gem_id": "213458",
                "id": "237554"
            },
            "wrists": {
                "bonus_id": "10421/9633/8902/12053/12050/1485/1808/11109/8960/8794",
                "crafted_stats": "49/36",
                "enchant_id": "7385",
                "gem_id": "213482",
                "id": "219342"
            }
        },
        "metadata": {
            "base_dps": 6272590.448016392
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
    "spec_id": 262,
    "subtitle": "UTC 2025-09-17 02:42 | SimC build: <a href=\"https://github.com/simulationcraft/simc/commit/6e59fdd\" target=\"blank\">6e59fdd</a>",
    "timestamp": "2025-09-17 02:42",
    "title": "Potions | Elemental Shaman | Castingpatchwerk",
    "translations": {}
}
]]
