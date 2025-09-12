local ADDON, ns = ...
ns.L = ns.L or {}
local L = ns.L



-- ============================================== --
-- ===           LOCALISATION (enUS)           === --
-- ============================================== --


-- ============================================== --
-- ===                 TABS                   === --
-- ============================================== --
L["tab_roster"]           = "Roster"
L["tab_start_raid"]       = "Start a raid"
L["tab_history"]          = "Raid history"
L["tab_resources"]        = "Resources"
L["tab_requests"]         = "Pending transactions"
L["tab_debug"]            = "Data broadcast"
L["tab_settings"]         = "Options"
-- Main/Alt
L["tab_main_alt"] = "Main/Alt"
L["lbl_player"] = "Player"
L["lbl_note"] = "Note"
L["lbl_guild_note"] = "Guild note"
L["lbl_actions"] = "Actions"
L["lbl_mains"] = "Confirmed Mains"
L["lbl_associated_alts"] = "Associated Alts"
L["lbl_available_pool"] = "Available Pool"
L["lbl_suggested"] = "Suggested"
L["lbl_main_prefix"] = "Main: "
L["tip_set_main"] = "Mark as main"
L["tip_assign_alt"] = "Assign as alt to selected main"
L["tip_remove_main"] = "Remove main (keeps characters in pool)"
L["tip_unassign_alt"] = "Unlink alt (back to pool)"
-- Merge balance popup
L["msg_merge_balance_title"] = "Merge balance?"
L["msg_merge_balance_body"]  = "Transfer %s from %s to %s and set %s to 0?"
L["lbl_equippable_only"]   = "Equippable only"
L["tab_guild_members"]    = "Guild members"
L["tab_mythic_plus"]      = "Mythic+ Rotation"


-- ============================================== --
-- ===     TITLES / APPLICATION / SYNC         === --
-- ============================================== --
L["msg_no_guild"]         = "You don't belong to any guild on this character"
L["app_title"]            = "Guild Logistics"
L["main_title_guild"]     = "Guild"
L["sync_data"]            = "Synchronizing..."

-- ============================================== --
-- ===            MYTHIC+ ROTATION             === --
-- ============================================== --
L["mythicplus_title"]     = "Mythic+ Affix Rotation"
L["mythicplus_current"]   = "Current"
L["mythicplus_next"]      = "Next"
L["mythicplus_previous"]  = "Previous"
L["mythicplus_week"]      = "Week %d (%s%d)"
L["mythicplus_affix"]     = "Affix %d"
L["btn_reload"]           = "Reload"

-- ➕ Outdated version
L["popup_outdated_title"] = "Outdated version"
L["msg_outdated_line1"]   = "Your version of "..L["app_title"].." (%s) is outdated."
L["msg_outdated_line2"]   = "A newer version is available: %s."
L["msg_outdated_hint"]    = "Please update the addon to ensure compatibility."
L["msg_outdated_from"]    = "Reported by: %s"


-- ============================================== --
-- ===          COLUMNS / LABELS              === --
-- ============================================== --
L["col_time"]             = "Time"
L["col_dir"]              = "Direction"
L["col_status"]           = "Status"
L["col_type"]             = "Type"
L["col_version_short"]    = "Addon"
L["col_size"]             = "Size"
L["col_channel"]          = "Channel"
L["col_sender"]           = "Sender"
L["col_frag"]             = "Frag"
L["col_date"]             = "Date"
L["col_player"]           = "Player"
L["col_operation"]        = "Operation"
L["col_actions"]          = "Actions"
L["col_name"]             = "Name"
L["col_balance"]          = "Balance"
L["col_invidual"]         = "Individual"
L["col_after"]            = "After"
L["col_remaining"]        = "Remaining"
L["col_amount"]           = "Amount"
L["col_unit_amount"]      = "Amount/item"
L["col_qty_short"]        = "Qty"
L["col_item"]             = "Item"
L["col_source"]           = "Source"
L["col_bundle"]           = "Bundle"
L["col_content"]          = "Content"
L["col_uses"]             = "Uses"
L["col_total_value"]      = "Total value"
L["col_level_short"]      = "Lvl"
L["col_ilvl"]             = "iLvl (Max)\rfrom main"
L["col_attendance"]       = "Location"
L["col_participants"]     = "Participants"
L["col_value"]            = "Value"
L["col_price"]            = "Price"
L["col_total"]            = "Total"
L["col_last_seen"]        = "Last seen"
L["col_rerolls"]          = "Rerolls"
L["col_mplus_score"]      = "M+ Score\rfrom main"
L["col_mplus_key"]        = "Main Mythic+ Key"
L["col_state"]            = "State"
L["col_request"]          = "Request"
L["col_version"]          = "Addon version"
L["lbl_of_main"]          = "of main"


-- ============================================== --
-- ===           BUTTONS / ACTIONS            === --
-- ============================================== --
L["btn_view"]             = "View"
L["btn_purge_all"]        = "Full purge"
L["btn_purge_bundles_exhausted"] = "Purge bundles & exhausted items"
L["btn_purge_resources"]  = "Purge resources"
L["btn_force_version_gm"] = "Force my version (GM)"
L["btn_approve"]          = "Approve"
L["btn_refuse"]           = "Refuse"
L["btn_make_free"]        = "Make free"
L["btn_remove_free"]      = "Remove free"
L["btn_back"]             = "< Back"
L["btn_add_to_roster"]    = "Add to Roster"
L["btn_remove_from_roster"] = "Remove from Roster"
L["btn_add_player"]       = "Add player"
L["btn_clear_all_free"]   = "Clear all (free)"
L["btn_close"]            = "Close"
L["btn_delete_short"]     = "X"
L["btn_enable_debug"]     = "Enable debug"
L["btn_create_bundle"]    = "Create bundle"
L["btn_deposit_gold"]     = "Deposit"
L["btn_withdraw_gold"]    = "Withdraw"
L["btn_stop_recording"]   = "Stop recording"
L["btn_start_recording_expenses"] = "Start recording expenses"
L["add_guild_member"]     = "Roster management"
L["guild_members"]        = "Guild members"
L["btn_purge_full"]       = "Full purge"
L["btn_purge_free_items_lots"] = "Purge bundles & exhausted items"
L["btn_purge_all_items_lots"]  = "Purge all bundles & items"
L["btn_notify_players"]   = "Notify players"
L["btn_confirm"]          = "Confirm"
L["btn_cancel"]           = "Cancel"
L["btn_create"]           = "Create"
L["btn_split"]            = "Split"
L["btn_show_hidden_reserve"] = "Show hidden players"
L["btn_purge_debug"]      = "Purge Debug" -- (deduplication: keep 2nd occurrence)


-- ============================================== --
-- ===               ALIAS / UI               === --
-- ============================================== --
L["col_alias"]            = "Alias"
L["btn_set_alias"]        = "Alias…"
L["popup_set_alias_title"]= "Set alias"
L["lbl_alias"]            = "Alias:"


-- ============================================== --
-- ===      LISTS / BADGES / LABELS           === --
-- ============================================== --
L["lbl_bundles"]          = "Bundles"
L["lbl_in_roster"]        = "In roster"
L["lbl_in_reserve"]       = "In reserve"
L["lbl_guild_members"]    = "Guild members"
L["lbl_usable_bundles"]   = "Usable bundles"
L["lbl_used_bundles"]     = "Used bundles"
L["lbl_item_reserve"]     = "Item reserve"
L["lbl_usable_bundles_raids"] = "Usable raid bundles"
L["lbl_participating_players"] = "Participating players"
L["lbl_reserved_players"] = "Reserved players"
L["lbl_bundle"]           = "Bundle"
L["lbl_no_data"]          = "No data..."
L["opt_ui_theme"]         = "UI theme"
L["opt_open_on_login"]    = "Open automatically at login"
L["lbl_active_roster"]    = "Active roster"
L["lbl_message"]          = "Message"
L["lbl_message_received"] = "Message received"
L["lbl_message_sent"]     = "Message sent"
L["lbl_shop"]             = "Shop"
L["lbl_ah"]               = "AH"
L["lbl_incoming_packets"] = "Incoming packets list"
L["lbl_outgoing_packets"]= "Outgoing packets list"
L["lbl_pending_queue"]  = "Pending packets list"
L["lbl_diffusing_snapshot"] = "Immediately diffuse a full snapshot"
L["lbl_diffusing_snapshot_confirm"] = "Diffuse and FORCE GM version?"
L["lbl_status_sent"]      = "SENT"
L["lbl_status_waiting"]   = "Waiting"
L["lbl_status_inprogress"]= "In progress"
L["lbl_status_transmitted"]= "Transmitted"
L["lbl_status_discovering"]= "Discovering..."
L["lbl_status_elected"]   = "Elected: "
L["lbl_status_assembling"]= "Assembling"
L["lbl_empty_payload"]    = "(empty payload)"
L["lbl_empty_raw"]        = "(raw unavailable)"
L["lbl_raw"]              = "RAW"
L["lbl_uses"]             = " uses"
L["lbl_use"]              = " use"
L["lbl_lot"]              = "Bundle "
L["lbl_left_short"]       = "rem."
L["lbl_refunded"]         = "Refunded"
L["lbl_closed"]           = "Closed"
L["lbl_used_charges"]     = "Charges used"
L["lbl_bundle_gold_only"] = "Gold"
L["lbl_recent_online"]    = "Online < 1 month (most recent char)"
L["lbl_old_online"]       = "Last login ≥ 1 month"
L["lbl_no_player_found"]  = "No player found"
L["lbl_out_of_guild"]     = "Players outside guild"
L["confirm_delete"]       = "Delete this player?"
L["lbl_scan_roster_progress"] = "Scanning roster..."
L["lbl_from_roster_question"] = "From roster?"
L["lbl_total_balance"]    = "Total balances"
L["lbl_total_resources"]  = "Total resources"
L["lbl_total_both"]       = "Remaining balance"
L["lbl_status_recieved"]  = "Received" 
L["lbl_guild_members"]    = "Guild members"
L["lbl_sep_online"]       = "Online"
L["lbl_sep_offline"]      = "Offline"
L["btn_clear"]            = "Clear log"


-- ============================================== --
-- ===           POPUPS / PROMPTS             === --
-- ============================================== --
L["popup_info_title"]     = "Information"
L["popup_confirm_title"]  = "Confirmation"
L["popup_input_title"]    = "Input"
L["popup_tx_request"]     = "Transaction Request"
L["popup_raid_ok"]        = "Raid participation confirmed!"
L["msg_good_raid"]        = "Have a good raid!"
L["lbl_total_amount_gold"] = "Total Amount (g):"
L["btn_confirm_participants"] = "Confirm Participants"
L["lbl_bundle_name"]      = "Bundle Name:"
L["lbl_num_uses"]         = "Number of Uses"
L["lbl_amount_gold"]      = "Amount (g)"
L["err_amount_invalid"]   = "Invalid amount."
L["lbl_bundle_contents"]  = "Bundle Contents:"
L["confirm_clear_free_resources"] = "Clear the list of free resources? (bundles are not affected)"
L["confirm_delete_resource_line"] = "Delete this resource line?"
L["popup_split_title"]    = "Split a Resource"
L["lbl_split_qty"]        = "Quantity to Split"
L["err_split_qty_invalid"]= "Invalid quantity. Must be between 1 and (quantity - 1)."
L["hint_split_resource"]  = "Split into two lines"
L["err_split_failed"]     = "Unable to perform split."
L["confirm_delete_history_line_permanent"] = "Permanently delete this history line?"
L["hint_no_bundle_for_raid"] = "No bundle has been linked to this raid."
L["hint_select_resources_bundle"] = "Select resources to create a bundle (fixed content)."
L["prompt_external_player_name"] = "Name of external player to include in the roster"
L["realm_external"]       = "External"
L["lbl_free_resources"]   = "Free Resources:"
L["confirm_question"]     = "Confirm?"
L["confirm_make_free_session"] = "Make this session free for all participants?"
L["confirm_cancel_free_session"] = "Cancel free session and restore initial state?"
L["lbl_total_amount_gold_alt"] = "Total Amount (g):"
L["lbl_purge_confirm_all"] = "Purge DB + reset UI then reload?"
L["lbl_purge_confirm_lots"] = "Delete depleted bundles and their items?"
L["lbl_purge_confirm_all_lots"] = "Delete ALL bundles and ALL items?"
L["lbl_purge_lots_confirm"] = "Purge completed: %d bundle(s), %d item(s) deleted."
L["lbl_purge_all_lots_confirm"] = "Purge completed: %d bundle(s), %d item(s) deleted."
L["lbl_no_res_selected"]  = "No resource selected"
L["tooltip_remove_history1"] = "Delete this history line"
L["tooltip_remove_history2"] = "• Delete without adjusting balances"
L["tooltip_remove_history3"] = "• If REFUNDED: no debit will be re-credited."
L["tooltip_remove_history4"] = "• If CLOSED: no refund will be made."


-- ============================================== --
-- ===   TOOLTIPS / MESSAGES / PREFIXES       === --
-- ============================================== --
L["badge_approved_list"]  = "Approved via list"
L["badge_refused_list"]   = "Refused via list"
L["warn_debit_n_players_each"] = "You will debit %d player(s) %s each."
L["prefix_add_gold_to"]   = "Add gold to "
L["prefix_remove_gold_from"] = "Remove gold from "
L["prefix_delete"]        = "Delete "
L["tooltip_send_back_active_roster"] = "Send this player back to Active Roster"
L["tooltip_view_raids_history"]      = "View raid history"
L["badge_exhausted"]      = "Exhausted"
L["suffix_remaining"]     = "remaining"
L["range_to"]             = "to"

-- ============================================== --
-- ===            COLORED STATUS              === --
-- ============================================== --
L["status_online"]        = "Online"
L["status_empty"]         = "-"
L["status_unknown"]       = "?"


-- ============================================== --
-- ===                OPTIONS                 === --
-- ============================================== --
L["opt_yes"]              = "Yes"
L["opt_no"]               = "No"
L["opt_alliance"]         = "Alliance"
L["opt_horde"]            = "Horde"
L["opt_neutral"]          = "Neutral"
L["opt_auto"]             = "Automatic"
L["opt_script_errors"]    = "Show Lua errors"
L["yes"]                  = "Yes"
L["no"]                   = "No"

-- ============================================== --
-- ===     NOTIFS / MINIMAP / INDICATORS      === --
-- ============================================== --
L["tooltip_minimap_left"]        = "Left click: Open/close window"
L["tooltip_minimap_drag"]        = "Drag: move icon around minimap"
L["btn_ok"]                      = "OK"
L["popup_tx_request_message"]    = "|cffffd200Requester:|r %s\n|cffffd200Operation:|r %s %s\n\nApprove?"
L["popup_deducted_amount_fmt"]   = "|cffffd200Amount deducted:|r %s"
L["popup_remaining_balance_fmt"] = "|cffffd200Remaining balance:|r %s"
L["warn_negative_balance"]      = "Warning: your balance is negative. Please settle your balance."
L["lbl_status_present_colored"]  = "|cff40ff40Present|r"
L["lbl_status_deleted_colored"]  = "|cffff7070Deleted|r"
L["lbl_db_version_prefix"]       = "DB v"
L["lbl_id_prefix"]               = "ID "
L["lbl_db_data"]                 = "Shared DB"
L["lbl_db_ui"]                   = "Personnal DB"
L["lbl_db_datas"]                = "History DB"
L["lbl_db_backup"]               = "Backup DB"
L["lbl_db_previous"]             = "Previous DB"


-- ============================================== --
-- ===         CALENDAR INVITATIONS           === --
-- ============================================== --
L["pending_invites_title"]       = "Pending invitations"
L["pending_invites_message_fmt"] = "You have %d unanswered calendar invitation(s).\nPlease respond.\nThis window will reappear at login while pending invitations remain."
L["btn_open_calendar"]           = "Open calendar"
L["col_when"]                    = "When"
L["col_event"]                   = "Event"


-- ============================================== --
-- ===         WEEKDAYS (min)                 === --
-- ============================================== --
L["weekday_mon"] = "Monday"
L["weekday_tue"] = "Tuesday"
L["weekday_wed"] = "Wednesday"
L["weekday_thu"] = "Thursday"
L["weekday_fri"] = "Friday"
L["weekday_sat"] = "Saturday"
L["weekday_sun"] = "Sunday"


-- ============================================== --
-- ===      OPTIONS : UI NOTIFICATIONS        === --
-- ============================================== --
L["options_notifications_title"] = "Popup display"
L["opt_popup_calendar_invite"]   = "Calendar invite notification"
L["opt_popup_raid_participation"]= "Raid participation notification"


-- ============================================== --
-- ===           BiS TAB (Trinkets)           === --
-- ============================================== --
L["tab_bis"]         = "BiS Trinkets"
L["col_tier"]        = "Tier"
L["col_owned"]       = "Owned"
L["lbl_class"]       = "Class"
L["lbl_spec"]        = "Specialization"
L["lbl_bis_filters"] = "Filters"
L["msg_no_data"]     = "No data"
L["footer_source_wowhead"] = "Source: wowhead.com"
L["bis_intro"] = "This tab lists BiS trinkets by class and specialization.\nRanks S to F indicate priority (S being best). Use dropdowns to change class and specialization."
L["col_useful_for"]        = "Useful for"
L["btn_useful_for"]        = "Useful for..."
L["popup_useful_for"]      = "Other classes that list this item in their Tier-List"
L["col_rank"]              = "Rank"
L["col_class"]             = "Class"
L["col_spec"]              = "Specialization"
L["msg_no_usage_for_item"] = "No class/spec references this item in the BiS tables."

-- ============================================== --
-- ===    CATEGORIES (side navigation)        === --
-- ============================================== --
L["cat_guild"]    = "Guild"
L["cat_raids"]    = "Raids"
L["cat_tools"]    = "Tools"
L["cat_tracker"]  = "Tracker"
L["cat_info"]     = "Helpers"
L["cat_settings"] = "Options"
L["cat_debug"]    = "Debug"

-- ====== Upgrade tracks (Helpers) ======
L["tab_upgrade_tracks"]       = "Upgrade tracks (ilvl)"
L["upgrade_header_itemlevel"] = "ITEM LEVELS"
L["upgrade_header_crests"]    = "REQUIRED CRESTS"
L["upgrade_track_adventurer"] = "ADVENTURER"
L["upgrade_track_veteran"]    = "VETERAN"
L["upgrade_track_champion"]   = "CHAMPION"
L["upgrade_track_hero"]       = "HERO"
L["upgrade_track_myth"]       = "MYTH"

-- ====== Crests ======
L["crest_valor"]   = "Valor"
L["crest_worn"]    = "Worn"
L["crest_carved"]  = "Carved"
L["crest_runic"]   = "Runic"
L["crest_golden"]  = "Golden"

-- ====== Upgrade steps ======
L["upgrade_step_adventurer"] = "Adventurer %d/8"
L["upgrade_step_veteran"]    = "Veteran %d/8"
L["upgrade_step_champion"]   = "Champion %d/8"
L["upgrade_step_hero"]       = "Hero %d/6"
L["upgrade_step_myth"]       = "Myth %d/6"


-- ====== Dungeons (Helpers) ======
L["tab_dungeons_loot"]             = "Dungeons (ilvl & vault)"
L["dungeons_header_activity"]      = "— — —"
L["dungeons_header_dungeon_loot"]  = "DUNGEON LOOT"
L["dungeons_header_vault"]         = "VAULT"
L["dungeons_header_crests"]        = "CRESTS"
L["dng_row_normal"]                = "Normal dungeons"
L["dng_row_timewalking"]           = "Timewalking"
L["dng_row_heroic"]                = "Heroic dungeons"
L["dng_row_m0"]                    = "Mythic 0"
L["dng_row_key_fmt"]               = "Key level %d"
L["dungeon_no_tag"]                = "no item mention"
L["max_short"]                     = "max"

-- Intro text
L["dng_note_intro"]   = "Season 3 of The War Within adjusts the item level of all dungeons:"
L["dng_note_week1"]   = "Week 1: Mythic 0 dungeons drop ilvl 681 (Champion 1/8)."
L["dng_note_week2"]   = "Week 2: Tazavesh in Mythic 0 drops ilvl 694 (Hero 1/6)."
L["dng_note_vault"]   = "The Great Vault offers up to 3 choices depending on the highest dungeon level completed (Heroic, Mythic, Mythic+ key, or Timewalking)."

-- Keystone scaling paragraph
L["dng_note_keystone_scaling"] =
"Item levels for Mythic+ dungeons scale up to level 10 keys, " ..
"with 2 gear pieces per dungeon (at level 10) and 1 additional piece every 5 levels. " ..
"In addition, the weekly Great Vault offers up to 3 loot options depending on completing 1, 4, and 8 " ..
"maximum-level dungeons in Heroic, Mythic, Mythic+ key, or Timewalking."


-- ====== Delves (Helpers) ======
L["tab_delves"]            = "Delves (rewards)"
L["delves_header_level"]   = "LEVEL"
L["delves_header_chest"]   = "ABUNDANT CHEST"
L["delves_header_map"]     = "TREASURE MAP"
L["delves_header_vault"]   = "VAULT"
L["delves_level_prefix"]   = "Level %s"
L["delves_cell_fmt"]       = "%d: %s (%d max)"

-- Intro text above
L["delves_intro_title"]    = "Rewards & functioning"
L["delves_intro_b1"]       = "Chests have a chance to contain a random gear piece with ilvl 655 (linked to battalion)."
L["delves_intro_b2"]       = "Delves quartermaster offers starter gear with ilvl 668 (Veteran) in exchange for Fragments."
L["delves_intro_b3"]       = "You can find 1 treasure map per week per character at 20% of the season journey progression."


-- ====== Raids (Helpers) ======
L["tab_raid_ilvls"]          = "Raids (iLvl per difficulty)"
L["raid_header_difficulty"]  = "DIFFICULTY"
L["difficulty_lfr"]          = "LFR"
L["difficulty_normal"]       = "NORMAL"
L["difficulty_heroic"]       = "HEROIC"
L["difficulty_mythic"]       = "MYTHIC"

-- Table rows
L["raid_row_group1"]         = "Plexus, Rou'ethar, Naazindhri"
L["raid_row_group2"]         = "Araz, Hunters and Fractillus"
L["raid_row_group3"]         = "Nexus-King and Dimensius"

-- Footer
L["raid_footer_ilvl_max"]    = "MAX ITEM LEVEL"

-- Bank/equilibrium footer (Roster)
L["lbl_bank_balance"] = "Bank balance"
L["lbl_equilibrium"]  = "Equilibrium"

-- Guild bank help/hints
L["no_data"] = "No data"
L["hint_open_gbank_to_update"] = "Open the guild bank to update this data"
L["tab_raid_loot"]           = "Manaforge Omega"
L["raid_intro_b1"]           = "The final raid Manaforge Omega contains several gear pieces from ilvl 671 to 723:"
L["raid_intro_b2"]           = "- Timewalking raids offer ilvl 681 (Champion 1) when active."
L["raid_intro_b3"]           = "- The raid contains up to 3 ilvl tiers with 1 upgrade track increase every 3 bosses."
L["raid_intro_b4"]           = "- Unlike Liberation of Terremine, the upgrade track starts at 2/8 (instead of 1) on early bosses."


-- ====== Crests (tab & headers) ======
L["tab_crests"]              = "Crests (sources)"
L["crests_header_crest"]     = "CRESTS"
L["crests_header_chasms"]    = "DELVES"
L["crests_header_dungeons"]  = "DUNGEONS"
L["crests_header_raids"]     = "RAIDS"
L["crests_header_outdoor"]   = "OUTDOOR"

-- Labels & formats
L["crest_range"]             = "%s (%d to %d)"
L["label_level"]             = "Level %d"
L["label_crests_n"]          = "%d crests"
L["label_per_boss"]          = "%d crests per boss"
L["label_per_cache"]         = "%d crests per cache"
L["label_except_last_boss"]  = "(except last boss)"
L["label_na"]                = "N/A"

-- Source names
L["gouffre_classic"]         = "Classic delve"
L["gouffre_abundant"]        = "Abundant delve"
L["archaeologist_loot"]      = "Archaeologist loot"
L["heroic"]                  = "Heroic"
L["normal"]                  = "Normal"
L["lfr"]                     = "Raid Finder"
L["mythic"]                  = "Mythic"
L["mythic0"]                 = "Mythic 0"
L["mplus_key"]               = "Mythic+ key"
L["weekly_event"]            = "Weekly event"
L["treasures_quests"]        = "Treasures/Quests"


-- ====== Group tracker (Helpers) ======
L["tab_group_tracker"]        = "Tracker"
L["group_tracker_title"]      = "Tracker"
L["group_tracker_toggle"]     = "Show tracking window"
L["group_tracker_hint"]       = "Tip: To open the tracking window directly, type this command in chat |cffaaaaaa/glog track|r"
L["btn_reset_counters"]       = "Reset counters"

L["group_tracker_cooldown_heal"]  = "Heal potion CD (s)"
L["group_tracker_cooldown_util"]  = "Other potions CD (s)"
L["group_tracker_cooldown_stone"] = "Healthstone CD (s)"

L["col_heal_potion"]   = "Heal"
L["col_other_potions"] = "Prepot"
L["col_healthstone"]   = "Stone"
L["col_cddef"]   = "Def"
L["col_dispel"]   = "Dispel"
L["col_taunt"]    = "Taunt"
L["col_move"]     = "Move"
L["col_kick"]     = "Kick"
L["col_cc"]       = "CC"
L["col_special"]  = "Util."
L["status_ready"]      = "Ready"
L["history_title"]     = "History: %s"
L["col_time"]          = "Time"
L["col_category"]      = "Category"
L["col_spell"]         = "Spell / Item"
L["history_ooc"]       = "Out of combat"
L["history_combat"]    = "Combat"
L["confirm_clear_history"] = "Clear encounter history?"
L["btn_reset_data"]    = "Clear encounter history"

L["match_healthstone"] = "healthstone"
L["match_potion"]      = "potion"
L["match_heal"]        = "heal"
L["match_mana"]        = "mana"

L["group_tracker_opacity_label"] = "Background Transparency"
L["group_tracker_opacity_tip"]   = "Set the tracking window background transparency."
L["group_tracker_record_label"]  = "Enable tracking"
L["group_tracker_record_tip"]    = "Enable tracking"
L["group_tracker_title_opacity_label"] = "Header Text transparency"
L["group_tracker_title_opacity_tip"]   = "Adjust header text opacity without affecting backgrounds or borders."
L["group_tracker_text_opacity_label"] = "Text transparency"
L["group_tracker_btn_opacity_label"] = "Button transparency"
L["group_tracker_btn_opacity_tip"]   = "Adjust button opacity (Close, Prev, Next, Clear) without affecting text or background."
L["group_tracker_history"]                = "History"
L["group_tracker_history_empty"]          = "Empty history"
L["group_tracker_popup_title_btn_hide"]   = "Hide title text (popup)"
L["group_tracker_popup_title_btn_show"]   = "Show title text (popup)"
L["group_tracker_popup_title_btn_tip"]    = "Toggle display of the popup history title text."
L["group_tracker_row_height_label"]       = "Row height."
L["group_tracker_row_height_tip"]         = "Adjust row height"
L["group_tracker_lock_label"] = "Lock tracker (disable clicksbloque clics/moves)"
L["group_tracker_lock_tip"]   = "Block all interections on tracker as long as checkbox is checked."


L["tab_debug_db"] = "Database"

L["col_key"]     = "Key"
L["col_preview"] = "Preview"

L["btn_open"]    = "Open"
L["btn_edit"]    = "Edit"
L["btn_delete"]  = "Delete"
L["btn_root"]    = "Root"
L["btn_up"]      = "Up"
L["btn_down"]         = "Down"
L["tooltip_move_up"]   = "Move this column up"
L["tooltip_move_down"] = "Move this column down"
L["btn_add_field"]  = "Add entry"

L["popup_edit_value"] = "Edit value"
L["lbl_edit_path"]    = "Path: "
L["lbl_lua_hint"]     = "Enter a Lua literal: 123, true, \"text\", { a = 1 }"
L["lbl_delete_confirm"] = "Delete this item?"
L["lbl_saved"]          = "Saved"

L["tab_custom_tracker"] = "Custom tracking"
L["custom_col_label"] = "Label"
L["custom_col_mappings"] = "Rules"
L["custom_col_active"] = "Active"
L["status_enabled"] = "Active"
L["status_disabled"] = "Inactive"
L["custom_add_column"] = "Add column"
L["custom_edit_column"] = "Edit column"
L["custom_spells_ids"] = "Spell IDs (comma-separated)"
L["custom_items_ids"]  = "Item IDs (comma-separated)"
L["custom_keywords"]   = "Keywords (comma-separated)"
L["custom_enabled"]    = "Enabled"
L["custom_confirm_delete"] = "Delete column '%s'?"
L["lbl_spells"]    = "Spells"
L["lbl_items"]     = "Items"
L["lbl_keywords"]  = "Keys"
L["err_label_required"] = "Label required"
L["custom_spells_list"] = "Tracked spells"
L["custom_items_list"] = "Tracked items"
L["custom_keywords_list"] = "Keywords"
L["placeholder_spell"] = "Spell ID"
L["placeholder_item"] = "Item ID"
L["placeholder_keyword"] = "Keyword"
L["btn_add"] = "Add"
L["custom_select_type"] = "Element type"
L["type_spells"] = "Spells"
L["type_items"] = "Items"
L["type_keywords"] = "Keywords"
L["tab_loot_tracker"] = "Loot log"
L["tab_loot_tracker_settings"] = "Loot record settings"
L["col_where"] = "Location"
L["col_who"] = "Looted by"
L["col_ilvl"]            = "iLvl"
L["col_instance"]        = "Instance"
L["col_difficulty"]      = "Difficulty"

L["format_date"] = "%Y-%m-%d"
L["format_heure"] = "%H:%M"
L["col_group"]            = "Group"
L["col_roll"]             = "Roll"
L["tip_show_group"]       = "Show group members"
L["popup_group_title"]    = "Group members"
L["tab_debug_events"] = "Event log"
L["btn_pause"]        = "Pause"
L["btn_resume"]       = "Resume"
L["lbl_min_quality"]    = "Minimum rarity"
L["lbl_min_req_level"]  = "Minimum level"
L["lbl_equippable_only"]= "Equippable only"
L["lbl_min_item_level"] = "Minimum ilvl"
L["lbl_instance_only"]  = "Only in instance"
L["opt_ui_scale_long"] = "Interface scale"
L["opt_ui_scale"] = "Scale"

-- === Debug: Errors ===
L["tab_debug_errors"] = "Lua Errors"
L["col_message"]      = "Message"
L["col_done"]         = "Handled"
L["lbl_error"]        = "Error"
L["lbl_stacktrace"]   = "Stack trace"
L["btn_copy"]         = "Copy"
L["lbl_yes"]          = "Yes"
L["lbl_no"]           = "No"
-- Toasts
L["toast_error_title"] = "New Lua Error"
L["instance_outdoor"] = "Outdoor"

-- ============================================== --
-- ===              BACKUP/RESTORE            === --
-- ============================================== --
L["btn_create_backup"]    = "Create Backup"
L["btn_restore_backup"]   = "Restore Backup"
L["tooltip_create_backup"] = "Create a complete backup of the database"
L["tooltip_restore_backup"] = "Restore database from the last backup"
L["err_no_main_db"]      = "No main database found"
L["err_no_backup"]       = "No backup found"
L["err_invalid_backup"]  = "Invalid backup"
L["msg_backup_created"]  = "Backup created successfully (%d elements)"
L["msg_backup_restored"] = "Database restored from backup dated %s"
L["msg_backup_deleted"]  = "Backup deleted"
L["unknown_date"]        = "Unknown date"
L["confirm_create_backup"] = "Create a database backup?"
L["confirm_restore_backup"] = "Restore database from backup?\n\nThis will replace all current data.\nThe current database will be saved as 'previous'."
L["lbl_backup_info"]     = "Backup info"
L["lbl_backup_date"]     = "Date: %s"
L["lbl_backup_size"]     = "Size: %d elements"
L["lbl_no_backup_available"] = "No backup available"


-- ============================================== --
-- ===           HARDCODED STRINGS            === --
-- ============================================== --
L["col_string"]          = "String"
L["col_spell_name"]      = "Spell Name"
L["col_item_name"]       = "Item Name"
L["spell_id_format"]     = "Spell #%d"
L["item_id_format"]      = "Item #%d"
L["btn_remove"]          = "Remove"
L["lbl_notification"]    = "Notification"
L["unknown_dungeon"]     = "Unknown dungeon"
L["dungeon_id_format"]   = "Dungeon #%d"
L["group_members"]       = "Group members"
L["col_hash"]            = "#"
L["btn_delete_short"]    = "X"
L["value_dash"]          = "-"
L["lbl_instance_only"]   = "Instance/Delve only"
L["lbl_equippable_only"] = "Equippable only"
L["btn_expand"]          = "+"
L["btn_collapse"]        = "-"
L["value_empty"]         = "—"