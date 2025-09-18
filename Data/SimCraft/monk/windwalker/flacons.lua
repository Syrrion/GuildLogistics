local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI
local UI = ns and ns.UI

ns.Consum_monk_windwalker_flacons = [[
{
    "class_id": 10,
    "data": {
        "Flask of Alchemical Chaos": {
            "1": 5581564,
            "2": 5592507,
            "3": 5609378
        },
        "Flask of Tempered Aggression": {
            "1": 5545092,
            "2": 5551920,
            "3": 5568743
        },
        "Flask of Tempered Mastery": {
            "1": 5543352,
            "2": 5553153,
            "3": 5561363
        },
        "Flask of Tempered Swiftness": {
            "1": 5557469,
            "2": 5566486,
            "3": 5586323
        },
        "Flask of Tempered Versatility": {
            "1": 5546119,
            "2": 5553113,
            "3": 5566388
        },
        "baseline": {
            "1": 5433632
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
        "timestamp": "2025-09-17 02:30:51.832199"
    },
    "profile": {
        "character": {
            "# source": "simulationcraft",
            "class": "monk",
            "level": "80",
            "position": "back",
            "race": "void_elf",
            "role": "attack",
            "spec": "windwalker",
            "talents": "C0QAAAAAAAAAAAAAAAAAAAAAAMzYmBzYGzyMDGAAAAAAAAAAAYZZYmYmBzMMsNzw2MGMbYGmlZCAAmZGzMzMbzAAYZZWWmlZmJIAYA"
        },
        "items": {
            "back": {
                "bonus_id": "9893",
                "enchant_id": "7403",
                "gem_id": "238046",
                "id": "235499"
            },
            "chest": {
                "enchant": "crystalline_radiance_3",
                "id": "237676",
                "ilevel": "723"
            },
            "feet": {
                "bonus_id": "13504/4800/4786/1533/12361",
                "enchant": "defenders_march_3",
                "id": "243306"
            },
            "finger1": {
                "bonus_id": "4786/10032/12361/8781",
                "enchant": "radiant_haste_3",
                "gem_id": "213455/213494",
                "id": "178824"
            },
            "finger2": {
                "bonus_id": "4786/3215/12361/8781",
                "enchant": "radiant_haste_3",
                "gem_id": "213494/213494",
                "id": "242491"
            },
            "hands": {
                "id": "237674",
                "ilevel": "723"
            },
            "head": {
                "bonus_id": "11307",
                "gem_id": "213743",
                "id": "237673",
                "ilevel": "723"
            },
            "legs": {
                "bonus_id": "4786/3215/12361",
                "enchant": "stormbound_armor_kit_3",
                "id": "242473"
            },
            "main_hand": {
                "bonus_id": "4786/3215/12361",
                "enchant": "stonebound_artistry_3",
                "id": "221159"
            },
            "neck": {
                "bonus_id": "4786/10032/12361/8781",
                "gem_id": "213467/213470",
                "id": "178827"
            },
            "shoulders": {
                "id": "237671",
                "ilevel": "723"
            },
            "trinket1": {
                "bonus_id": "4800/4786/1533/12361",
                "id": "242396"
            },
            "trinket2": {
                "bonus_id": "4800/4786/1533/12361",
                "id": "242395"
            },
            "waist": {
                "bonus_id": "3524/10520/8960/11307",
                "crafted_stats": "40/49",
                "gem_id": "213461",
                "id": "219331",
                "ilevel": "720"
            },
            "wrists": {
                "bonus_id": "3524/10520/8960/11307",
                "crafted_stats": "40/49",
                "enchant": "chant_of_armored_leech_3",
                "gem_id": "213485",
                "id": "219334",
                "ilevel": "720"
            }
        },
        "metadata": {
            "base_dps": 5433632.458572749
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
        "Flask of Tempered Aggression",
        "Flask of Tempered Versatility",
        "Flask of Tempered Mastery",
        "baseline"
    ],
    "spec_id": 269,
    "subtitle": "UTC 2025-09-17 02:30 | SimC build: <a href=\"https://github.com/simulationcraft/simc/commit/6e59fdd\" target=\"blank\">6e59fdd</a>",
    "timestamp": "2025-09-17 02:30",
    "title": "Phials | Windwalker Monk | Castingpatchwerk",
    "translations": {}
}
]]
