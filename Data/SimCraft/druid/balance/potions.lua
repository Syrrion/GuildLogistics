local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI
local UI = ns and ns.UI

ns.Consum_druid_balance_potions = [[
{
    "class_id": 11,
    "data": {
        "Potion of Unwavering Focus": {
            "1": 5869673,
            "2": 5890159,
            "3": 5901882
        },
        "Tempered Potion": {
            "1": 5999572,
            "2": 6019102,
            "3": 6031091
        },
        "baseline": {
            "1": 5849547
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
        "timestamp": "2025-09-24 06:21:14.485866"
    },
    "profile": {
        "character": {
            "# source": "simulationcraft",
            "class": "druid",
            "level": "80",
            "position": "back",
            "race": "night_elf",
            "role": "spell",
            "spec": "balance",
            "talents": "CYGAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAALUmtMGzMwDYWYZmZAzMGLzsNjlxMjZmFjZGzMjNswAMAbbjNMNzsMCAAAwmZmZMwmBG"
        },
        "items": {
            "back": {
                "bonus_id": "9886/12361/12239",
                "enchant_id": "7403",
                "gem_id": "238044",
                "id": "235499",
                "ilevel": "730"
            },
            "chest": {
                "bonus_id": "4795",
                "enchant_id": "7364",
                "id": "237685",
                "ilevel": "723"
            },
            "feet": {
                "bonus_id": "4795/13504",
                "enchant_id": "7424",
                "id": "243306",
                "ilevel": "723"
            },
            "finger1": {
                "bonus_id": "4795/8781",
                "enchant_id": "7334",
                "gem_id": "213482/213482",
                "id": "221200",
                "ilevel": "723"
            },
            "finger2": {
                "bonus_id": "4795/8781",
                "enchant_id": "7346",
                "gem_id": "213458/213458",
                "id": "221141",
                "ilevel": "723"
            },
            "hands": {
                "bonus_id": "4795",
                "id": "237683",
                "ilevel": "723"
            },
            "head": {
                "bonus_id": "4795/1808",
                "gem_id": "213743",
                "id": "237682",
                "ilevel": "723"
            },
            "legs": {
                "bonus_id": "4795",
                "enchant_id": "7534",
                "id": "237681",
                "ilevel": "723"
            },
            "main_hand": {
                "bonus_id": "4795",
                "enchant_id": "7448",
                "id": "237728",
                "ilevel": "723"
            },
            "neck": {
                "bonus_id": "4795/8781",
                "gem_id": "213497/213467",
                "id": "242406",
                "ilevel": "723"
            },
            "off_hand": {
                "bonus_id": "10421/9633/8902/12053/12050/1485/11300/8960",
                "crafted_stats": "49/40",
                "id": "222566",
                "ilevel": "720"
            },
            "shoulders": {
                "bonus_id": "4795",
                "id": "237552",
                "ilevel": "723"
            },
            "trinket1": {
                "bonus_id": "4795",
                "id": "242402",
                "ilevel": "723"
            },
            "trinket2": {
                "bonus_id": "1533/12361/12239",
                "id": "242395",
                "ilevel": "723"
            },
            "waist": {
                "bonus_id": "4795/1808",
                "gem_id": "213482",
                "id": "237557",
                "ilevel": "723"
            },
            "wrists": {
                "bonus_id": "10421/1599/1808/11109/8960/8791",
                "crafted_stats": "36/49",
                "enchant_id": "7385",
                "gem_id": "213458",
                "id": "219334"
            }
        },
        "metadata": {
            "base_dps": 5849547.2181762075
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
    "spec_id": 102,
    "subtitle": "UTC 2025-09-24 06:21 | SimC build: <a href=\"https://github.com/simulationcraft/simc/commit/3945f09\" target=\"blank\">3945f09</a>",
    "timestamp": "2025-09-24 06:21",
    "title": "Potions | Balance Druid | Castingpatchwerk",
    "translations": {}
}
]]
