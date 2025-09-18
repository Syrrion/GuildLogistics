local ADDON, ns = ...
if GetLocale and GetLocale() ~= "frFR" then return end

ns.L = ns.L or {}
local L = ns.L

-- ============================================== --
-- ===           LOCALISATION (frFR)           === --
-- ============================================== --


-- ============================================== --
-- ===                 ONGLETS                 === --
-- ============================================== --
L["tab_roster"]           = "Roster"
L["tab_start_raid"]       = "Démarrer un raid"
L["tab_history"]          = "Historique des sorties"
L["tab_resources"]        = "Ressources"
L["tab_requests"]         = "Transactions en attente"
L["tab_debug"]            = "Diffusion des données"
L["tab_settings"]         = "Options"
L["tab_guild_members"]    = "Membres de la guilde"
L["tab_mythic_plus"]      = "Rotation Mythique+"
L["tab_consumables"]      = "Consommables (Potions & Flacons)"


-- ============================================== --
-- ===     TITRES / APPLICATION / SYNCHRO      === --
-- ============================================== --
L["msg_no_guild"]         = "Vous n'appartenez à aucune guilde sur ce personnage"
L["app_title"]            = "Guild Logistics"
L["main_title_guild"]     = "Guilde"
L["sync_data"]            = "Synchronisation en cours"

-- ============================================== --
-- ===            ROTATION MYTHIQUE+           === --
-- ============================================== --
L["mythicplus_title"]     = "Rotation des Affixes Mythique+"
L["mythicplus_current"]   = "Actuelle"
L["mythicplus_next"]      = "Suivante"
L["mythicplus_previous"]  = "Précédente"
L["mythicplus_week"]      = "Semaine %d (%s%d)"
L["mythicplus_affix"]     = "Affixe %d"
L["btn_reload"]           = "Reload"

-- ➕ Obsolescence version
L["popup_outdated_title"] = "Version obsolète"
L["msg_outdated_line1"]   = "Votre version de "..L["app_title"].." (%s) est obsolète."
L["msg_outdated_line2"]   = "Une version plus récente est disponible : %s."
L["msg_outdated_hint"]    = "Merci de mettre à jour l’addon pour assurer la compatibilité."
L["msg_outdated_from"]    = "Signalé par : %s"


-- ============================================== --
-- ===          COLONNES / LIBELLÉS            === --
-- ============================================== --
L["col_time"]             = "Heure"
L["col_dir"]              = "Sens"
L["col_status"]           = "Statut"
L["col_type"]             = "Type"
L["col_version_short"]    = "Addon"
L["col_size"]             = "Taille"
L["col_channel"]          = "Canal"
L["col_sender"]           = "Émetteur"
L["col_frag"]             = "Frag"
L["col_date"]             = "Date"
L["col_player"]           = "Joueur"
L["tab_mythic_progress"]  = "Progression Mythique"
L["col_operation"]        = "Opération"
L["col_actions"]          = "Actions"
L["col_name"]             = "Nom"
L["col_balance"]          = "Solde"
L["col_invidual"]         = "Individuel"
L["col_after"]            = "Après"
L["col_remaining"]        = "Restant"
L["col_amount"]           = "Montant"
L["col_unit_amount"]      = "Montant/objet"
L["col_qty_short"]        = "Qté"
L["col_item"]             = "Objet"
L["col_source"]           = "Source"
L["col_bundle"]           = "Lot"
L["col_content"]          = "Contenu"
L["col_uses"]             = "Utilisations"
L["col_total_value"]      = "Valeur totale"
L["col_level_short"]      = "Niv"
L["col_ilvl"]             = "iLvl (Max)\rdu main"
L["col_attendance"]       = "Localisation"
L["col_participants"]     = "Participants"
L["col_value"]            = "Valeur"
L["col_price"]            = "Prix"
L["col_total"]            = "Total"
L["col_last_seen"]        = "Dernière connexion"
L["col_rerolls"]          = "Rerolls"
L["col_mplus_score"]      = "Côte M+\rdu main"
L["col_mplus_key"]        = "Clé Mythique + du main"
L["col_mplus_overall"]    = "Global"
L["col_state"]            = "État"
L["col_request"]          = "Demande"
L["col_version"]          = "Version Addon"
L["lbl_of_main"]          = "du main"


-- ============================================== --
-- ===           BOUTONS / ACTIONS             === --
-- ============================================== --
L["btn_view"]             = "Voir"
L["btn_purge_all"]        = "Purge totale"
L["btn_purge_bundles_exhausted"] = "Purge Lots & objets épuisés"
L["btn_purge_resources"]  = "Purger Ressources"
L["btn_force_version_gm"] = "Forcer ma version (GM)"
L["btn_approve"]          = "Approuver"
L["btn_refuse"]           = "Refuser"
L["btn_make_free"]        = "Rendre gratuit"
L["btn_cancel_free"]      = "Annuler la gratuité"
L["btn_back"]             = "< Retour"
L["btn_add_to_roster"]    = "Ajouter au Roster"
L["btn_remove_from_roster"] = "Retirer du Roster"
L["btn_add_player"]       = "Ajouter un joueur"
L["btn_clear_all_free"]   = "Tout vider (libres)"
L["btn_clear"]            = "Vider le log"
L["btn_close"]            = "Fermer"
L["btn_delete_short"]     = "X"
L["btn_enable_debug"]     = "Activer le débug"
L["btn_create_bundle"]    = "Créer un lot"
L["btn_deposit_gold"]     = "Dépôt"
L["btn_withdraw_gold"]    = "Retrait"
L["btn_stop_recording"]   = "Stopper l'enregistrement"
L["btn_start_recording_expenses"] = "Démarrer l'enregistrement des dépenses"
L["add_guild_member"]     = "Gestion du roster"
L["guild_members"]        = "Membres de la guilde"
L["btn_purge_full"]       = "Purge totale"
L["btn_purge_free_items_lots"] = "Purge Lots & objets épuisés"
L["btn_purge_all_items_lots"]  = "Purger tous les Lots & objets"
L["btn_notify_players"]   = "Notifier les joueurs"
L["btn_confirm"]          = "Valider"
L["btn_cancel"]           = "Annuler"
L["btn_create"]           = "Créer"
L["btn_split"]            = "Scinder"
L["btn_show_hidden_reserve"] = "Afficher joueurs masqués"
L["btn_purge_debug"]      = "Purger Débug" -- (déduplication : on conserve la 2ᵉ occurrence)


-- ============================================== --
-- ===               ALIAS / UI               === --
-- ============================================== --
L["col_alias"]            = "Alias"
L["btn_set_alias"]        = "Alias…"
L["popup_set_alias_title"]= "Définir un alias"
L["lbl_alias"]            = "Alias :"

-- Bouton Ping et toast
L["tip_ping"]                    = "Pinger ce joueur"
L["tip_disabled_ping_cd_fmt"]    = "En recharge : %ds restantes"
L["toast_ping_title"]            = "Ping"
L["toast_ping_text_fmt"]         = "Vous avez été ping par %s"
-- Avec message personnalisé
L["toast_ping_text_with_msg_fmt"] = "Vous avez été ping par %s :\n|cffffd200%s|r"
-- Invite de saisie pour Ping
L["popup_ping_title"]   = "Ping"
L["lbl_ping_message"]   = "Message (optionnel)"
L["ph_ping_message"]    = "Ex : besoin d’un coup de main ?"


-- ============================================== --
-- ===      LISTES / BADGES / LIBELLÉS        === --
-- ============================================== --
L["lbl_bundles"]          = "Lots"
L["lbl_in_roster"]        = "Dans le roster"
L["lbl_in_reserve"]       = "En réserve"
L["lbl_guild_members"]    = "Membres de la guilde"
L["lbl_usable_bundles"]   = "Lots utilisables"
L["lbl_used_bundles"]     = "Lots utilisés"
L["lbl_item_reserve"]     = "Réserve d'objets"
L["lbl_usable_bundles_raids"] = "Lots utilisables pour les raids"
L["lbl_participating_players"] = "Joueurs participants"
L["lbl_reserved_players"] = "Joueurs en réserve"
L["lbl_bundle"]           = "Lot"
L["lbl_no_data"]          = "Aucune donnée..."
L["opt_ui_theme"]         = "Thème de l'interface"
L["opt_open_on_login"]    = "Ouvrir automatiquement à l'ouverture du jeu"
L["lbl_active_roster"]    = "Roster actif"
L["lbl_message"]          = "Message"
L["lbl_message_received"] = "Message reçu"
L["lbl_message_sent"]     = "Message envoyé"
L["lbl_shop"]             = "Boutique"
L["lbl_ah"]               = "HdV"
L["lbl_incoming_packets"] = "Liste des paquets entrants"
L["lbl_outgoing_packets"]= "Liste des paquets sortants"
L["lbl_pending_queue"]  = "Liste des paquets en file d'attente"
L["lbl_diffusing_snapshot"] = "Diffuse immédiatement un snapshot complet"
L["lbl_diffusing_snapshot_confirm"] = "Diffuser et FORCER la version du GM ?"
L["lbl_status_sent"]      = "ENVOI"
L["lbl_status_waiting"]   = "En attente"
L["lbl_status_inprogress"]= "En cours"
L["lbl_status_transmitted"]= "Transmis"
L["lbl_status_discovering"]= "Découverte…"
L["lbl_status_elected"]   = "Élu : "
L["lbl_status_assembling"]= "Assemblage"
L["lbl_empty_payload"]    = "(payload vide)"
L["lbl_empty_raw"]        = "(brut indisponible)"
L["lbl_raw"]              = "RAW"
L["lbl_uses"]             = " utilisations"
L["lbl_use"]              = " utilisation"
L["lbl_lot"]              = "Lot "
L["lbl_left_short"]       = "rest."
L["lbl_refunded"]         = "Remboursé"
L["lbl_closed"]           = "Clôturé"
L["lbl_used_charges"]     = "Charges utilisées"
L["lbl_bundle_gold_only"] = "Or"
L["lbl_recent_online"]    = "Connectés < 1 mois (perso le + récent)"
L["lbl_old_online"]       = "Dernière connexion ≥ 1 mois"
L["lbl_no_player_found"]  = "Aucun joueur trouvé"
L["lbl_out_of_guild"]     = "Joueurs hors guilde"
L["confirm_delete"]       = "Supprimer ce joueur ?"
L["lbl_scan_roster_progress"] = "Scan du roster en cours..."
L["lbl_from_roster_question"] = "Du roster ?"
L["lbl_total_balance"]    = "Total soldes"
L["lbl_total_resources"]   = "Total ressources"
L["lbl_total_both"]       = "Solde restant"
L["lbl_status_recieved"]  = "Reçu" 
L["lbl_guild_members"] = "Membres de la guilde"
L["lbl_sep_online"]  = "Connectés"
L["lbl_sep_offline"] = "Déconnectés"


-- ============================================== --
-- ===           POPUPS / PROMPTS             === --
-- ============================================== --
L["popup_info_title"]     = "Information"
L["popup_confirm_title"]  = "Confirmation"
L["popup_input_title"]    = "Saisie"
L["popup_tx_request"]     = "Demande de transaction"
L["popup_raid_ok"]        = "Participation au raid validée !"
L["msg_good_raid"]        = "Bon raid !"
L["lbl_total_amount_gold"] = "Montant global (po) :"
L["btn_confirm_participants"] = "Valider les participants"
L["lbl_bundle_name"]      = "Nom du lot :"
L["lbl_num_uses"]         = "Nombre d'utilisations"
L["lbl_amount_gold"]      = "Montant (po)"
L["err_amount_invalid"]   = "Montant invalide."
L["lbl_bundle_contents"]  = "Contenu du lot : "
L["confirm_clear_free_resources"] = "Vider la liste des ressources libres ? (les lots ne sont pas affectés)"
L["confirm_delete_resource_line"] = "Supprimer cette ligne de ressource ?"
L["popup_split_title"]    = "Séparer une ressource"
L["lbl_split_qty"]        = "Quantité à séparer"
L["err_split_qty_invalid"]= "Quantité invalide. Elle doit être comprise entre 1 et (quantité - 1)."
L["hint_split_resource"]  = "Séparer en deux lignes"
L["err_split_failed"]     = "Impossible d'effectuer la séparation."
L["confirm_delete_history_line_permanent"] = "Supprimer définitivement cette ligne d’historique ?"
L["hint_no_bundle_for_raid"] = "Aucun lot n’a été associé à ce raid."
L["hint_select_resources_bundle"] = "Sélectionnez des ressources pour créer un lot (contenu figé)."
L["prompt_external_player_name"] = "Nom du joueur externe à inclure dans le roster"
L["realm_external"]       = "Externe"
L["lbl_free_resources"]   = "Ressources libres :"
L["confirm_question"]     = "Confirmer ?"
L["confirm_make_free_session"] = "Rendre cette session gratuite pour tous les participants ?"
L["confirm_cancel_free_session"] = "Annuler la gratuité et revenir à l’état initial ?"
L["lbl_total_amount_gold_alt"] = "Montant total (po) :"
L["lbl_purge_confirm_all"] = "Purger la DB + réinitialiser l’UI puis recharger ?"
L["lbl_purge_confirm_lots"] = "Supprimer les lots épuisés et leurs objets associés ?"
L["lbl_purge_confirm_all_lots"] = "Supprimer TOUS les lots et TOUS les objets ?"
L["lbl_purge_lots_confirm"] = "Purge effectuée : %d lot(s), %d objet(s) supprimés."
L["lbl_purge_all_lots_confirm"] = "Purge effectuée : %d lot(s), %d objet(s) supprimés."
L["lbl_no_res_selected"]  = "Aucune ressource sélectionnée"
L["tooltip_remove_history1"] = "Supprimer cette ligne d’historique"
L["tooltip_remove_history2"] = "• Suppression sans ajuster les soldes"
L["tooltip_remove_history3"] = "• Si REMBOURSÉE : aucun débit ne sera recrédité."
L["tooltip_remove_history4"] = "• Si CLÔTURÉE : aucun remboursement ne sera effectué."


-- ============================================== --
-- ===   TOOLTIPS / MESSAGES / PRÉFIXES       === --
-- ============================================== --
L["badge_approved_list"]  = "Approuvé via la liste"
L["badge_refused_list"]   = "Refusé via la liste"
L["warn_debit_n_players_each"] = "Vous allez débiter %d joueur(s) de %s chacun."
L["prefix_add_gold_to"]   = "Ajouter de l’or à "
L["prefix_remove_gold_from"] = "Retirer de l’or à "
L["prefix_delete"]        = "Supprimer "
L["tooltip_send_back_active_roster"] = "Renvoyer ce joueur dans le Roster actif"
L["tooltip_view_raids_history"]      = "Voir l’historique des raids"
L["badge_exhausted"]      = "Épuisé"
L["suffix_remaining"]     = "restantes"
L["range_to"] = "à"

-- ============================================== --
-- ===            STATUTS COLORÉS             === --
-- ============================================== --
L["status_online"]        = "En ligne"
L["status_empty"]         = "-"
L["status_unknown"]       = "?"


-- ============================================== --
-- ===                OPTIONS                 === --
-- ============================================== --
L["opt_yes"]              = "Oui"
L["opt_no"]               = "Non"
L["opt_alliance"]         = "Alliance"
L["opt_horde"]            = "Horde"
L["opt_neutral"]          = "Neutre"
L["opt_auto"]             = "Automatique"
L["opt_script_errors"]   = "Afficher les erreurs Lua"
L["yes"]                 = "Oui"
L["no"]                  = "Non"

-- ============================================== --
-- ===     NOTIFS / MINIMAP / INDICATEURS     === --
-- ============================================== --
L["tooltip_minimap_left"]        = "Clic gauche : Ouvrir / fermer la fenêtre"
L["tooltip_minimap_drag"]        = "Glisser : déplacer l’icône autour de la minimap"
L["btn_ok"]                      = "OK"
L["popup_tx_request_message"]    = "|cffffd200Demandeur:|r %s\n|cffffd200Opération:|r %s %s"
L["popup_deducted_amount_fmt"]   = "|cffffd200Montant déduit :|r %s"
L["popup_remaining_balance_fmt"] = "|cffffd200Solde restant :|r %s"
L["tx_reason_gbank_deposit"]     = "|cffaaaaaaOrigine :|r Dépôt Banque de guilde"
L["tx_reason_gbank_withdraw"]    = "|cffaaaaaaOrigine :|r Retrait Banque de guilde"

-- Notifications Banque de guilde
L["toast_gbank_deposit_title"]    = "Dépôt transmis"
L["toast_gbank_withdraw_title"]   = "Retrait transmis"
L["toast_gbank_deposit_text_fmt"] = "Votre dépôt de %s a été transmis pour traitement de votre solde."
L["toast_gbank_withdraw_text_fmt"] = "Votre retrait de %s a été transmis pour traitement de votre solde."
L["tx_reason_manual_request"]    = "|cffaaaaaaOrigine :|r Demande manuelle"
L["warn_negative_balance"]      = "Attention, votre solde est négatif, merci de régulariser la situation."
L["lbl_status_present_colored"]  = "|cff40ff40Présent|r"
L["lbl_status_deleted_colored"]  = "|cffff7070Supprimé|r"
L["lbl_db_version_prefix"]       = "DB v"
L["lbl_id_prefix"]               = "ID "
L["lbl_db_data"]                 = "BDD partagée"
L["lbl_db_ui"]                   = "BDD personelle"
L["lbl_db_datas"]                = "BDD historique"
L["lbl_db_backup"]               = "BDD sauvegarde"
L["lbl_db_previous"]             = "BDD précédente"

-- Reload prompt & editor rights
L["btn_later"]                  = "Plus tard"
L["btn_reload_ui"]              = "Recharger l'interface"
L["msg_reload_needed"]          = "Des changements de droits ont été appliqués."
L["msg_editor_promo"]           = "Vous avez été promu éditeur dans "..L["app_title"] ..". Certaines options nécessitent un rechargement."
L["msg_editor_demo"]            = "Vous avez été dégradé dans "..L["app_title"] ..". L'interface doit être rechargée pour refléter les changements."

-- ============================================== --
-- ===         INVITATIONS CALENDRIER         === --
-- ============================================== --
L["pending_invites_title"]       = "Invitations en attente"
L["pending_invites_message_fmt"] = "Vous avez %d invitation(s) dans le calendrier sans réponse.\nMerci d'y répondre.\nCette fenêtre réapparaîtra à chaque connexion tant qu'il restera des invitations en attente."
L["btn_open_calendar"]           = "Ouvrir le calendrier"
L["col_when"]                    = "Quand"
L["col_event"]                   = "Événement"


-- ============================================== --
-- ===         JOURS DE LA SEMAINE (min)      === --
-- ============================================== --
L["weekday_mon"] = "lundi"
L["weekday_tue"] = "mardi"
L["weekday_wed"] = "mercredi"
L["weekday_thu"] = "jeudi"
L["weekday_fri"] = "vendredi"
L["weekday_sat"] = "samedi"
L["weekday_sun"] = "dimanche"


-- ============================================== --
-- ===      OPTIONS : NOTIFICATIONS UI        === --
-- ============================================== --
L["options_notifications_title"] = "Affichage des popups"
L["opt_popup_calendar_invite"]   = "Notification d'invitation dans le calendrier"
L["opt_popup_raid_participation"]= "Notification de participation à un raid"
L["opt_popup_gchat_mention"]      = "Notification de ping & mentions dans le chat de guilde"
L["opt_popup_trinket_ranking"]    = "Afficher la popup de classement du bijou au loot"


-- ============================================== --
-- ===           Onglet BiS (Trinkets)        === --
-- ============================================== --
L["tab_bis"]         = "Bijoux BiS (Wowhead)"
L["col_tier"]        = "Rang"
L["col_owned"]       = "Possédé"
L["lbl_class"]       = "Classe"
L["lbl_spec"]        = "Spécialisation"
L["lbl_bis_filters"] = "Filtres"
L["msg_no_data"]     = "Aucune donnée"
L["footer_source_wowhead"] = "Source : wowhead.com"
L["bis_intro"] = "Cet onglet liste les bijoux (trinkets) BiS par classe et spécialisation.\nLes rangs S à F indiquent la priorité (S étant le meilleur). Utilisez les listes déroulantes pour changer la classe et la spécialisation."
L["simc_intro"] = "Cet onglet affiche le classement des bijoux simulés par classe/spécialisation et nombre de cibles. Utilisez les filtres pour changer la classe, la spé, le nombre de cibles et le niveau d'objet. Source : bloodmallet.com"
L["col_useful_for"]        = "Utile pour"
L["btn_useful_for"]        = "Utile pour..."
L["popup_useful_for"]      = "Autres classes ayant cet objet dans sa Tier-List"
L["col_rank"]              = "Rang"
L["col_class"]             = "Classe"
L["col_spec"]              = "Spécialisation"
L["msg_no_usage_for_item"] = "Aucune classe/spécialisation ne référence cet objet dans les tableaux BiS."
L["loot_rank_disclaimer"] = "Classement indicatif. À adapter selon la composition actuelle du raid et les butins déjà obtenus."

-- ============================================== --
-- ===    CATEGORIES (navigation latérale)       ===
-- ============================================== --
L["cat_guild"]    = "Guilde"
L["cat_raids"]    = "Raids"
L["cat_tools"]    = "Outils"
L["cat_tracker"]  = "Tracker"
L["cat_info"]     = "Helpers"
L["cat_settings"] = "Options"
L["cat_debug"]    = "Débug"

-- ====== Paliers d’amélioration (Helpers) ======
L["tab_upgrade_tracks"]       = "Paliers d’amélioration"
L["upgrade_header_itemlevel"] = "NIVEAUX D’OBJET"
L["upgrade_header_crests"]    = "ÉCUS REQUIS"
L["upgrade_track_adventurer"] = "AVENTURIER"
L["upgrade_track_veteran"]    = "VÉTÉRAN"
L["upgrade_track_champion"]   = "CHAMPION"
L["upgrade_track_hero"]       = "HÉROS"
L["upgrade_track_myth"]       = "MYTHE"

-- ====== Écus ======
L["crest_valor"]   = "Vaillance"
L["crest_worn"]    = "Abîmé"
L["crest_carved"]  = "Gravé"
L["crest_runic"]   = "Runique"
L["crest_golden"]  = "Doré"

-- ====== Étapes d’amélioration ======
L["upgrade_step_adventurer"] = "Aventurier %d/8"
L["upgrade_step_veteran"]    = "Vétéran %d/8"
L["upgrade_step_champion"]   = "Champion %d/8"
L["upgrade_step_hero"]       = "Héros %d/6"
L["upgrade_step_myth"]       = "Mythe %d/6"


-- ====== Donjons (Helpers) ======
L["tab_dungeons_loot"]             = "Paliers Donjons"
L["dungeons_header_activity"]      = "— — —"
L["dungeons_header_dungeon_loot"]  = "BUTIN DE DONJON"
L["dungeons_header_vault"]         = "CHAMBRE-FORTE"
L["dungeons_header_crests"]        = "ÉCUS"
L["dng_row_normal"]                = "Donjons normaux"
L["dng_row_timewalking"]           = "Marcheurs du temps"
L["dng_row_heroic"]                = "Donjons héroïques"
L["dng_row_m0"]                    = "Mythique 0"
L["dng_row_key_fmt"]               = "Clé de niveau %d"
L["dungeon_no_tag"]                = "aucune mention d'objet"
L["max_short"]                     = "max"

-- Texte d’intro (FR)
L["dng_note_intro"]   = "La saison 3 de The War Within adapte le niveau d'objet de tous les donjons :"
L["dng_note_week1"]   = "Semaine 1 : les donjons Mythique 0 donnent du butin 681 (Champion 1/8)."
L["dng_note_week2"]   = "Semaine 2 : Tazavesh en Mythique 0 donne du butin 694 (Héros 1/6)."
L["dng_note_vault"]   = "La grande chambre-forte propose jusqu’à 3 choix selon le niveau le plus élevé de donjons terminés (Héroïque, Mythique, clé Mythique ou Marcheurs du temps)."

-- Paragraphe explicatif (FR)
L["dng_note_keystone_scaling"] =
"Le niveau d'objet pour les donjons de clé mythique est échelonné jusqu'au niveau 10 maximum en fonction du niveau de la clé, " ..
"avec 2 pièces d'équipement par donjon (au niveau 10) et 1 pièce supplémentaire par tranche de 5 niveaux. " ..
"De plus, la grande chambre-forte hebdomadaire propose jusqu'à 3 options de butin au terme de la semaine en fonction de 1, 4 et 8 " ..
"donjons de niveau maximum terminés en mode héroïque, mythique, clé mythique ou Marcheurs du temps."


-- ====== Gouffres (Helpers) ======
L["tab_delves"]            = "Paliers Gouffres"
L["delves_header_level"]   = "NIVEAU"
L["delves_header_chest"]   = "COFFRE ABONDANT"
L["delves_header_map"]     = "CARTE AUX TRÉSORS"
L["delves_header_vault"]   = "CHAMBRE FORTE"
L["delves_level_prefix"]   = "Niveau %s"
L["delves_cell_fmt"]       = "%d : %s (%d max)"

-- Texte au-dessus
L["delves_intro_title"]    = "Récompenses & fonctionnement"
L["delves_intro_b1"]       = "Les coffres ont une chance de proposer une pièce d’équipement aléatoire avec 655 niveaux d’objet (lié au bataillon)."
L["delves_intro_b2"]       = "L’intendant des Gouffres propose de l’équipement de départ avec 668 niveaux d’objet (Vétéran) contre les Sous-pièces."
L["delves_intro_b3"]       = "Il est possible de trouver 1 seule carte aux trésors par semaine par personnage à 20% de la progression du périple de saison."


-- ====== Raids (Helpers) ======
L["tab_raid_ilvls"]          = "Paliers Raids"
L["raid_header_difficulty"]  = "DIFFICULTÉ"
L["difficulty_lfr"]          = "LFR"
L["difficulty_normal"]       = "NORMAL"
L["difficulty_heroic"]       = "HÉROÏQUE"
L["difficulty_mythic"]       = "MYTHIQUE"

-- lignes du tableau
L["raid_row_group1"]         = "Plexus, Rou'ethar, Naazindhri"
L["raid_row_group2"]         = "Araz, Chasseurs et Fractillus"
L["raid_row_group3"]         = "Roi-nexus et Dimensius"

-- pied récapitulatif
L["raid_footer_ilvl_max"]    = "NIVEAU D'OBJET MAX"

-- Pied de page banque/équilibre (Roster)
L["lbl_bank_balance"] = "Solde Banque"
L["lbl_equilibrium"]  = "Équilibre"

-- Aide / infos banque guilde
L["no_data"] = "Aucune données"
L["hint_open_gbank_to_update"] = "Ouvrir la banque de guilde pour mettre à jour cette donnée"
L["tab_raid_loot"]           = "Manaforge Oméga"
L["raid_intro_b1"]           = "Le raid final de la Manaforge Omega contient plusieurs pièces d’équipement de 671 à 723 niveaux d’objet :"
L["raid_intro_b2"]           = "- Les raids des marcheurs du temps proposent 681 niveaux d’objet (Champion 1) lorsque l’événement est actif."
L["raid_intro_b3"]           = "- Le raid contient jusqu’à 3 paliers de niveau d’objet avec une augmentation de 1 voie d’amélioration tous les 3 boss."
L["raid_intro_b4"]           = "- Contrairement à la Libération de Terremine, la voie d’amélioration commence à 2/8 (au lieu de 1) sur les boss du début."


-- ====== Crests (onglet & entêtes) ======
L["tab_crests"]              = "Écus (Sources)"
L["crests_header_crest"]     = "ÉCUS"
L["crests_header_chasms"]    = "GOUFFRES"
L["crests_header_dungeons"]  = "DONJONS"
L["crests_header_raids"]     = "RAIDS"
L["crests_header_outdoor"]   = "EXTÉRIEUR"

-- ====== Libellés & formats ======
L["crest_range"]             = "%s (%d à %d)"
L["label_level"]             = "Niveau %d"
L["label_crests_n"]          = "%d écus"
L["label_per_boss"]          = "%d écus par boss"
L["label_per_cache"]         = "%d écus par cache"
L["label_except_last_boss"]  = "(hors boss final)"
L["label_na"]                = "N/A"

-- ====== Noms de sources ======
L["gouffre_classic"]         = "Gouffre classique"
L["gouffre_abundant"]        = "Gouffre abondant"
L["archaeologist_loot"]      = "Butin de l'archéologue"
L["heroic"]                  = "Héroïque"
L["normal"]                  = "Normal"
L["lfr"]                     = "Outils raids"
L["mythic"]                  = "Mythique"
L["mythic0"]                 = "Mythique 0"
L["mplus_key"]               = "Clé mythique"
L["weekly_event"]            = "Événement hebdomadaire"
L["treasures_quests"]        = "Trésors/Quêtes"


-- ====== Suivi de groupe (Helpers) ======
L["tab_group_tracker"]        = "Tracker"
L["group_tracker_title"]      = "Tracker"
L["group_tracker_toggle"]     = "Afficher la fenêtre de suivi"
L["group_tracker_hint"]       = "Astuce : Pour ouvrir directement la fenêtre de suivi, saisissez cette commande dans le chat |cffaaaaaa/glog track|r"
L["btn_reset_counters"]       = "Réinitialiser les compteurs"

L["group_tracker_cooldown_heal"]  = "CD Potion de soins (s)"
L["group_tracker_cooldown_util"]  = "CD Autres potions (s)"
L["group_tracker_cooldown_stone"] = "CD Pierre de soins (s)"

L["col_heal_potion"]   = "Soin"
L["col_other_potions"] = "Prépot"
L["col_healthstone"]   = "Pierre"
L["col_cddef"]   = "Def"
L["col_dispel"]   = "Dispel"
L["col_taunt"]    = "Taunt"
L["col_move"]     = "Move"
L["col_kick"]     = "Kick"
L["col_cc"]       = "CC"
L["col_special"]  = "Util."

L["status_ready"]      = "Prêt"
L["history_title"]   = "Historique : %s"
L["col_time"]        = "Heure"
L["col_category"]    = "Catégorie"
L["col_spell"]       = "Sort / Objet"
L["history_ooc"]     = "Hors combat"
L["history_combat"]  = "Combat"
L["confirm_clear_history"] = "Vider l'historique des rencontres ?"
L["btn_reset_data"] = "Vider l'historique des rencontres"

L["match_healthstone"] = "pierre de soins"
L["match_potion"]      = "potion"
L["match_heal"]        = "soin"
L["match_mana"]        = "mana"

L["group_tracker_opacity_label"] = "Transparence du fond"
L["group_tracker_opacity_tip"]   = "Définit la transparence du fond de la fenêtre de suivi."
L["group_tracker_record_label"]  = "Activer le suivi"
L["group_tracker_record_tip"]    = "Activer le suivi"
L["group_tracker_title_text_opacity_label"] = "Transparence du texte de l'entête"
L["group_tracker_title_text_opacity_tip"]   = "Contrôle l'opacité du texte de l'entête sans affecter les fonds ni les bordures."
L["group_tracker_text_opacity_label"] = "Transparence du texte"
L["group_tracker_text_opacity_tip"]   = "Contrôle l'opacité du texte sans affecter les fonds ni les bordures."
L["group_tracker_btn_opacity_label"] = "Transparence des boutons"
L["group_tracker_btn_opacity_tip"]   = "Contrôle l'opacité des boutons (Fermer, Précédent, Suivant, Vider) sans affecter le texte ni le fond."
L["group_tracker_history"]                = "Historique"
L["group_tracker_history_empty"]          = "Historique vide"
L["group_tracker_popup_title_btn_hide"]   = "Masquer le texte du titre (popup)"
L["group_tracker_popup_title_btn_show"]   = "Afficher le texte du titre (popup)"
L["group_tracker_popup_title_btn_tip"]    = "Bascule l'affichage du texte du titre de la popup d'historique."
L["group_tracker_row_height_label"]    = "Hauteur des lignes."
L["group_tracker_row_height_tip"]    = "Ajuste la hauteur des lignes"
L["group_tracker_lock_label"] = "Verrouiller le tracker (bloque clics/déplacement)"
L["group_tracker_lock_tip"]   = "Empêche tout clic/drag/scroll sur la fenêtre flottante tant que cette option est cochée."

L["tab_debug_db"] = "Base de données"

L["col_key"]     = "Clé"
L["col_preview"] = "Aperçu"

L["btn_open"]    = "Ouvrir"
L["btn_edit"]    = "Éditer"
L["btn_delete"]  = "Supprimer"
L["btn_root"]    = "Racine"
L["btn_up"]      = "Remonter"
L["btn_down"]         = "Descendre"
L["tooltip_move_up"]   = "Monter cette colonne"
L["tooltip_move_down"] = "Descendre cette colonne"

L["btn_add_field"]      = "Nouvelle entrée"

L["popup_edit_value"] = "Éditer la valeur"
L["lbl_edit_path"]    = "Chemin : "
L["lbl_lua_hint"]     = "Entrez un littéral Lua : 123, true, \"text\", { a = 1 }"
L["lbl_delete_confirm"] = "Supprimer cet élément ?"
L["lbl_saved"]          = "Enregistré"

L["tab_custom_tracker"] = "Suivi personnalisé"
L["custom_col_label"] = "Libellé"
L["custom_col_mappings"] = "Règles"
L["custom_col_active"] = "Actif"
L["status_enabled"] = "Actif"
L["status_disabled"] = "Inactif"
L["custom_add_column"] = "Ajouter une colonne"
L["custom_edit_column"] = "Éditer la colonne"
L["custom_spells_ids"] = "IDs de sorts (séparés par des virgules)"
L["custom_items_ids"]  = "IDs d'objets (séparés par des virgules)"
L["custom_keywords"]   = "Mots-clés (séparés par des virgules)"
L["custom_enabled"]    = "Activer"
L["custom_confirm_delete"] = "Supprimer la colonne '%s' ?"
L["lbl_spells"]    = "Sorts"
L["lbl_items"]     = "Objets"
L["lbl_keywords"]  = "Clés"
L["err_label_required"] = "Libellé requis"
L["custom_spells_list"] = "Sorts suivis"
L["custom_items_list"] = "Objets suivis"
L["custom_keywords_list"] = "Mots-clés"
L["placeholder_spell"] = "ID de sort"
L["placeholder_item"] = "ID d'objet"
L["placeholder_keyword"] = "Mot-clé"
L["btn_add"] = "Ajouter"
L["custom_select_type"] = "Type d’éléments"
L["type_spells"] = "Sorts"
L["type_items"] = "Objets"
L["type_keywords"] = "Mots-clés"

L["tab_loot_tracker"] = "Log des butins"
L["tab_loot_tracker_settings"] = "Paramètres d'enregistrement de l'historique"

L["col_who"] = "Ramassé par"
L["col_where"] = "Lieu"
L["col_ilvl"]            = "iLvl"
L["col_instance"]        = "Instance"
L["col_difficulty"]      = "Difficulté"
L["format_date"] = "%d/%m/%Y"
L["format_heure"] = "%H:%M"
L["col_group"]            = "Groupe"
L["col_roll"]             = "Roll"
L["tip_show_group"]       = "Voir les membres du groupe"
L["popup_group_title"]    = "Membres du groupe"
L["tab_debug_events"] = "Historique des évènements"
L["btn_pause"]        = "Pause"
L["btn_resume"]       = "Reprendre"
L["lbl_min_quality"]    = "Rareté minimale"
L["lbl_min_req_level"]  = "Niveau minimal"
L["lbl_equippable_only"]= "Équippable uniquement"
L["lbl_min_item_level"] = "Ilvl minimum"
L["lbl_instance_only"]  = "Seulement en instance"
L["opt_ui_scale_long"] = "Echelle de l'interface"
L["opt_ui_scale"] = "Echelle"

-- === Débug : Erreurs ===
L["tab_debug_errors"] = "Erreurs Lua"
L["col_message"]      = "Message"
L["col_done"]         = "Traité"
L["lbl_error"]        = "Erreur"
L["lbl_stacktrace"]   = "Pile d'appel"
L["btn_copy"]         = "Copier"
L["lbl_yes"]          = "Oui"
L["lbl_no"]           = "Non"
L["toast_error_title"] = "Nouvelle erreur Lua"

-- Notifications personnelles de crédit/débit
L["toast_credit_title"]      = "Crédit reçu"
L["toast_debit_title"]       = "Débit appliqué"
L["toast_credit_text_fmt"]   = "Vous avez été crédité de %s.\nNouveau solde : %s."
L["toast_debit_text_fmt"]    = "Vous avez été débité de %s.\nNouveau solde : %s."
L["instance_outdoor"] = "Extérieur"

-- Mention dans le chat de guilde
L["toast_gmention_title"]      = "Mention dans le chat de guilde"
L["toast_gmention_text_fmt"]   = "Vous avez été mentionné par %s : %s"

-- ============================================== --
-- ===              BACKUP/RESTORE            === --
-- ============================================== --
L["btn_create_backup"]    = "Créer un backup"
L["btn_restore_backup"]   = "Restaurer le backup"
L["tooltip_create_backup"] = "Créer une sauvegarde complète de la base de données"
L["tooltip_restore_backup"] = "Restaurer la base de données depuis le dernier backup"
L["err_no_main_db"]      = "Aucune base de données principale trouvée"
L["err_no_backup"]       = "Aucun backup trouvé"
L["err_invalid_backup"]  = "Backup invalide"
L["msg_backup_created"]  = "Backup créé avec succès (%d éléments)"
L["msg_backup_restored"] = "Base de données restaurée depuis le backup du %s"
L["msg_backup_deleted"]  = "Backup supprimé"
L["unknown_date"]        = "Date inconnue"
L["confirm_create_backup"] = "Créer un backup de la base de données ?"
L["confirm_restore_backup"] = "Restaurer la base de données depuis le backup ?\n\nCela remplacera toutes les données actuelles.\nLa base actuelle sera sauvegardée comme 'previous'."
L["lbl_backup_info"]     = "Info backup"
L["lbl_backup_date"]     = "Date : %s"
L["lbl_backup_size"]     = "Taille : %d éléments"
L["lbl_no_backup_available"] = "Aucun backup disponible"


-- ============================================== --
-- ===           CHAÎNES EN DUR               === --
-- ============================================== --
L["col_string"]          = "Chaîne"
L["col_spell_name"]      = "Nom du sort"
L["col_item_name"]       = "Nom de l'objet"
L["spell_id_format"]     = "Sort #%d"
L["item_id_format"]      = "Objet #%d"
L["btn_remove"]          = "Supprimer"
L["lbl_notification"]    = "Notification"
L["unknown_dungeon"]     = "Donjon inconnu"
L["dungeon_id_format"]   = "Donjon #%d"
L["group_members"]       = "Membres du groupe"
L["col_hash"]            = "#"
L["btn_delete_short"]    = "X"
L["value_dash"]          = "-"
L["lbl_instance_only"]   = "Seulement en instance/gouffre"
L["lbl_equippable_only"]   = "Équippable seulement"
L["btn_expand"]          = "+"
L["btn_collapse"]        = "-"
L["value_empty"]         = "—"
-- Indice pied de toast
L["toast_hint_click_close"] = "Cliquer pour fermer la notification"
-- === Sélection de mode (dual-mode) ===
L["mode_settings_header"]    = "Mode d'utilisation"
L["mode_guild"]              = "Version de guilde"
L["mode_standalone"]         = "Version standalone"
L["mode_firstrun_title"]     = "Choisir le mode d'utilisation"
L["mode_firstrun_body"]      = "\nVeuillez choisir le mode à utiliser sur ce personnage pour "..L["app_title"].." : \n\n|cffffd200Version de guilde|r\n Synchronisation des données avec votre guilde entre les possesseurs de l'addon mais nécéssite le rôle de GM pour configurer l'addon et initier le partage.\n\n|cffffd200Version standalone|r\n Aucune synchronisation avec les autres joueurs mais toutes les fonctions sont utilisables sans droits GM.\n\n\n\nVous pourrez changer de mode plus tard dans les options pour basculer d'un mode a l'autre - les deux modes pouvant fonctionner indépendamment sans perte de données."
-- Main/Alt (nouveaux libellés)
L["tab_main_alt"] = "Main/Alt"
L["lbl_player"] = "Joueur"
L["lbl_note"] = "Note"
L["lbl_guild_note"] = "Note de guilde"
L["lbl_actions"] = "Actions"
L["lbl_mains"] = "Mains"
L["lbl_associated_alts"] = "Alts"
L["lbl_associated_alts2"] = "Alts (selectionner un main)"
L["lbl_available_pool"] = "Joueurs non attribués"
L["lbl_suggested"] = "Suggéré"
L["lbl_main_prefix"] = "Main: "
L["tip_set_main"] = "Confirmer en main"
L["tip_assign_alt"] = "Associer en alt au main sélectionné"
L["tip_remove_main"] = "Supprimer le main (les persos restent dans le pool)"
L["tip_unassign_alt"] = "Dissocier l'alt (retour au pool)"
-- Info-bulles éditeur
L["tip_grant_editor"]  = "Accorder droits d'édition"
L["tip_revoke_editor"] = "Retirer droits d'édition"
-- Raison de désactivation (tooltips)
L["tip_disabled_offline_group"] = "Désactivé : aucun personnage de ce joueur n'est en ligne"
-- Contexte statut éditeur
L["tip_editor_status_promoted"] = "Editeur"
L["tip_editor_status_demoted"]  = "Non-éditeur"
-- Fusion de solde (popup)
L["msg_merge_balance_title"] = "Fusionner le solde ?"
L["msg_merge_balance_body"]  = "Transférer %s de %s vers %s et mettre %s à 0 ?"
-- Suppression d'un main avec solde (popup)
L["msg_remove_main_balance_title"] = "Supprimer le main avec solde ?"
L["msg_remove_main_balance_body"]  = "Ce main dispose actuellement d'un solde de %s.\nLa suppression du main remettra ce solde à 0 et supprimera également son appartenance au Roster s’il en fait partie.\n\nContinuer ?"

-- Helpers Trinkets
L["tab_trinkets"]        = "Bijoux BiS (SimCraft)"
L["lbl_targets"]         = "Cibles"
L["lbl_target_single"]   = "1 cible"
L["lbl_target_plural"]   = "%d cibles"
L["lbl_ilvl"]            = "Niveau d'objet"
L["lbl_ilvl_value"]      = "ilvl %d"
L["lbl_trinket"]         = "Bijou"
L["lbl_score"]           = "Score"
L["lbl_diff"]            = "Écart"
L["lbl_source"]          = "Source"
L["label_legendary"]     = "Légendaire"
L["footer_source_bloodmallet"] = "Source : https://bloodmallet.com/"

-- Popup de classement de butin
L["loot_rank_title"] = "Classement de l'objet"
L["col_score"] = "Score"
