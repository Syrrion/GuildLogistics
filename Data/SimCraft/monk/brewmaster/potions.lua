local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI
local UI = ns and ns.UI

ns.Consum_monk_brewmaster_potions = [[
{
    "class_id": 10,
    "data": {
        "Potion of Unwavering Focus": {
            "1": 3911574,
            "2": 3916213,
            "3": 3917505
        },
        "Tempered Potion": {
            "1": 3949081,
            "2": 3946594,
            "3": 3950666
        },
        "baseline": {
            "1": 3903270
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
        "timestamp": "2025-09-24 06:25:08.923250"
    },
    "profile": {
        "character": {
            "# source": "simulationcraft",
            "class": "monk",
            "level": "80",
            "position": "front",
            "race": "tauren",
            "role": "tank",
            "spec": "brewmaster",
            "talents": "CwQAAAAAAAAAAAAAAAAAAAAAAAAAAgxCmxMmlZegtxMzAAAAAAAw2CGxMDMDDMYbmZGzsMMjtZZmY2mtZMMbAAwysNtMbzsMAAgAYGWA"
        },
        "items": {
            "back": {
                "bonus_id": "9893/12401",
                "enchant": "chant_of_leeching_fangs_3",
                "gem_id": "238042",
                "id": "235499"
            },
            "chest": {
                "bonus_id": "7981/12052/5877/12361/12053",
                "enchant": "crystalline_radiance_3",
                "id": "237676"
            },
            "feet": {
                "bonus_id": "7981/12052/5877/12361/12053/13504",
                "enchant": "defenders_march_3",
                "id": "243306"
            },
            "finger1": {
                "bonus_id": "7981/12052/5877/12361/12053/10376/8781",
                "enchant": "cursed_critical_strike_3",
                "gem_id": "213461/213461",
                "id": "237567"
            },
            "finger2": {
                "bonus_id": "657/12052/5877/10390/12361/12053/10376/8781",
                "enchant": "cursed_critical_strike_3",
                "gem_id": "213461/213461",
                "id": "221141"
            },
            "hands": {
                "bonus_id": "7981/12052/5877/12361/12053",
                "id": "237674"
            },
            "head": {
                "bonus_id": "7981/12052/5877/12361/12053/1808",
                "gem_id": "213743",
                "id": "237673"
            },
            "legs": {
                "bonus_id": "657/12052/5877/10390/12361/12053",
                "enchant": "stormbound_armor_kit_3",
                "id": "185801"
            },
            "main_hand": {
                "bonus_id": "657/12052/5877/10390/12361/12053",
                "enchant": "stonebound_artistry_3",
                "id": "221159"
            },
            "neck": {
                "bonus_id": "657/12052/5877/10390/12361/12053/10376/8781",
                "gem_id": "213467/213497",
                "id": "252009"
            },
            "shoulders": {
                "bonus_id": "7981/12052/5877/12361/12053",
                "id": "237671"
            },
            "trinket1": {
                "bonus_id": "657/12052/5877/10390/12361/12053",
                "id": "219309"
            },
            "trinket2": {
                "bonus_id": "7981/12052/5877/12361/12053",
                "id": "242401"
            },
            "waist": {
                "bonus_id": "12050/9627/12053/11307",
                "gem_id": "213461",
                "id": "219502"
            },
            "wrists": {
                "bonus_id": "12050/12053/9627/11307/8795/11109",
                "enchant": "chant_of_armored_leech_3",
                "gem_id": "213479",
                "id": "219334"
            }
        },
        "metadata": {
            "base_dps": 3903270.752443322
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
    "spec_id": 268,
    "subtitle": "UTC 2025-09-24 06:25 | SimC build: <a href=\"https://github.com/simulationcraft/simc/commit/3945f09\" target=\"blank\">3945f09</a>",
    "timestamp": "2025-09-24 06:25",
    "title": "Potions | Brewmaster Monk | Castingpatchwerk",
    "translations": {}
}
]]
