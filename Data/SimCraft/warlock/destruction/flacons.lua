local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI
local UI = ns and ns.UI

ns.Consum_warlock_destruction_flacons = [[
{
    "class_id": 9,
    "data": {
        "Flask of Alchemical Chaos": {
            "1": 6069168,
            "2": 6075246,
            "3": 6095911
        },
        "Flask of Tempered Aggression": {
            "1": 6045594,
            "2": 6056852,
            "3": 6066173
        },
        "Flask of Tempered Mastery": {
            "1": 6040967,
            "2": 6062778,
            "3": 6073467
        },
        "Flask of Tempered Swiftness": {
            "1": 6046601,
            "2": 6066042,
            "3": 6076764
        },
        "Flask of Tempered Versatility": {
            "1": 6052067,
            "2": 6063575,
            "3": 6082345
        },
        "baseline": {
            "1": 5908197
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
        "SimulationCraft": "3945f09",
        "bloodytools": "8ee54970aa33896c2c888c8b1bd00e74de5cafc7",
        "timestamp": "2025-09-24 06:17:24.143589"
    },
    "profile": {
        "character": {
            "# source": "simulationcraft",
            "class": "warlock",
            "default_pet": "sayaad",
            "level": "80",
            "position": "ranged_back",
            "race": "Dwarf",
            "role": "spell",
            "spec": "destruction",
            "talents": "CsQAAAAAAAAAAAAAAAAAAAAAAAmZmZmZEziBmtZmZYWmFDzMzsMzYsYmBAAAAmZGLLzMLzAGzYYhMw2wCNWwAAAAAAAYYMDAA"
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
                "enchant_id": "7352",
                "gem_id": "213473/213494",
                "id": "237567"
            },
            "finger2": {
                "bonus_id": "1533/12361/12239/8781",
                "enchant_id": "7352",
                "gem_id": "213467/213482",
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
                "enchant_id": "7448",
                "id": "237728"
            },
            "neck": {
                "bonus_id": "1533/12361/12239/8781",
                "gem_id": "213461/213485",
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
                "bonus_id": "3215/12361/12239",
                "id": "242497"
            },
            "trinket2": {
                "bonus_id": "1533/12361/12239",
                "id": "242395"
            },
            "waist": {
                "bonus_id": "3215/12361/12239/1808",
                "gem_id": "213467",
                "id": "221121"
            },
            "wrists": {
                "bonus_id": "10421/9633/8902/12053/12050/1485/1808/11109/8960/8791",
                "crafted_stats": "36/49",
                "enchant_id": "7397",
                "gem_id": "213473",
                "id": "222815"
            }
        },
        "metadata": {
            "base_dps": 5908197.990272948
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
        "Flask of Alchemical Chaos",
        "Flask of Tempered Versatility",
        "Flask of Tempered Swiftness",
        "Flask of Tempered Mastery",
        "Flask of Tempered Aggression",
        "baseline"
    ],
    "spec_id": 267,
    "subtitle": "UTC 2025-09-24 06:17 | SimC build: <a href=\"https://github.com/simulationcraft/simc/commit/3945f09\" target=\"blank\">3945f09</a>",
    "timestamp": "2025-09-24 06:17",
    "title": "Phials | Destruction Warlock | Castingpatchwerk",
    "translations": {}
}
]]
