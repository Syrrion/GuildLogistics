local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI
local UI = ns and ns.UI

ns.Consum_warlock_affliction_flacons = [[
{
    "class_id": 9,
    "data": {
        "Flask of Alchemical Chaos": {
            "1": 5426361,
            "2": 5432308,
            "3": 5451074
        },
        "Flask of Tempered Aggression": {
            "1": 5378437,
            "2": 5389811,
            "3": 5405754
        },
        "Flask of Tempered Mastery": {
            "1": 5384888,
            "2": 5395140,
            "3": 5402523
        },
        "Flask of Tempered Swiftness": {
            "1": 5396906,
            "2": 5407293,
            "3": 5426934
        },
        "Flask of Tempered Versatility": {
            "1": 5394023,
            "2": 5404224,
            "3": 5419678
        },
        "baseline": {
            "1": 5281370
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
        "timestamp": "2025-09-17 02:33:42.726782"
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
            "base_dps": 5281370.050004312
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
        "Flask of Tempered Swiftness",
        "Flask of Tempered Versatility",
        "Flask of Tempered Aggression",
        "Flask of Tempered Mastery",
        "baseline"
    ],
    "spec_id": 265,
    "subtitle": "UTC 2025-09-17 02:33 | SimC build: <a href=\"https://github.com/simulationcraft/simc/commit/6e59fdd\" target=\"blank\">6e59fdd</a>",
    "timestamp": "2025-09-17 02:33",
    "title": "Phials | Affliction Warlock | Castingpatchwerk",
    "translations": {}
}
]]
