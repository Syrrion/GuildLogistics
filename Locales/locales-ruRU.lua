local ADDON, ns = ...
if GetLocale and GetLocale() ~= "ruRU" then return end

ns.L = ns.L or {}
local L = ns.L
-- ============================================== --
-- ===           LOCALISATION (ruRU)           === --
-- ============================================== --
-- Russian (Russia) localisation
-- Translator(s): ZamestoTV
-- ============================================== --
-- ===                 TABS                   === --
-- ============================================== --
L["tab_roster"]           = "Состав"
L["tab_start_raid"]       = "Начать рейд"
L["tab_history"]          = "История рейдов"
L["tab_resources"]        = "Ресурсы"
L["tab_requests"]         = "Ожидающие транзакции"
L["tab_debug"]            = "Трансляция данных"
L["tab_settings"]         = "Настройки"
-- Main/Alt
L["tab_main_alt"] = "Основной/Альт"
L["lbl_player"] = "Игрок"
L["lbl_note"] = "Заметка"
L["lbl_guild_note"] = "Заметка гильдии"
L["lbl_actions"] = "Действия"
L["lbl_mains"] = "Основные"
L["lbl_associated_alts"] = " Альты"
L["lbl_associated_alts2"] = " Альты (выберите основной)"
L["lbl_available_pool"] = "Игроки без назначения"
L["lbl_suggested"] = "Предложено"
L["lbl_main_prefix"] = "Основной: "
L["tip_set_main"] = "Отметить как основной"
L["tip_assign_alt"] = "Назначить альтом к выбранному основному"
L["tip_remove_main"] = "Удалить основной (персонажи остаются в пуле)"
L["tip_unassign_alt"] = "Отвязать альта (вернуть в пул)"
-- Editor tooltips
L["tip_grant_editor"]  = "Предоставить права редактора"
L["tip_revoke_editor"] = "Отозвать права редактора"
-- Disabled reason (tooltips)
L["tip_disabled_offline_group"] = "Отключено: ни один из персонажей этого игрока не в сети"
-- Editor status context
L["tip_editor_status_promoted"] = "Редактор"
L["tip_editor_status_demoted"]  = "Не редактор"
-- Merge balance popup
L["msg_merge_balance_title"] = "Объединить баланс?"
L["msg_merge_balance_body"]  = "Перенести %s с %s на %s и установить %s в 0?"
-- Remove main confirmation (non-zero balance)
L["msg_remove_main_balance_title"] = "Удалить основной с балансом?"
L["msg_remove_main_balance_body"]  = "У этого основного текущий баланс %s.\nУдаление основного сбросит этот баланс на 0 и также очистит членство в составе, если оно есть.\n\nПродолжить?"
L["lbl_equippable_only"]   = "Только экипируемое"
L["tab_guild_members"]    = "Члены гильдии"
L["tab_mythic_plus"]      = "Ротация Эпох+"


-- ============================================== --
-- ===     TITLES / APPLICATION / SYNC         === --
-- ============================================== --
L["msg_no_guild"]         = "Вы не состоите в гильдии на этом персонаже"
L["app_title"]            = "Логистика гильдии"
L["main_title_guild"]     = "Гильдия"
L["sync_data"]            = "Синхронизация..."

-- ============================================== --
-- ===            MYTHIC+ ROTATION             === --
-- ============================================== --
L["mythicplus_title"]     = "Ротация аффиксов Эпох+"
L["mythicplus_current"]   = "Текущий"
L["mythicplus_next"]      = "Следующий"
L["mythicplus_previous"]  = "Предыдущий"
L["mythicplus_week"]      = "Неделя %d (%s%d)"
L["mythicplus_affix"]     = "Аффикс %d"
L["btn_reload"]           = "Перезагрузить"

-- ➕ Outdated version
L["popup_outdated_title"] = "Устаревшая версия"
L["msg_outdated_line1"]   = "Ваша версия "..L["app_title"].." (%s) устарела."
L["msg_outdated_line2"]   = "Доступна новая версия: %s."
L["msg_outdated_hint"]    = "Пожалуйста, обновите аддон для обеспечения совместимости."
L["msg_outdated_from"]    = "Сообщено: %s"


-- ============================================== --
-- ===          COLUMNS / LABELS              === --
-- ============================================== --
L["col_time"]             = "Время"
L["col_dir"]              = "Направление"
L["col_status"]           = "Статус"
L["col_type"]             = "Тип"
L["col_version_short"]    = "Аддон"
L["col_size"]             = "Размер"
L["col_channel"]          = "Канал"
L["col_sender"]           = "Отправитель"
L["col_frag"]             = "Фрагмент"
L["col_date"]             = "Дата"
L["col_player"]           = "Игрок"
L["tab_mythic_progress"]  = "Прогресс Эпох"
L["col_operation"]        = "Операция"
L["col_actions"]          = "Действия"
L["col_name"]             = "Имя"
L["col_balance"]          = "Баланс"
L["col_invidual"]         = "Индивидуальный"
L["col_after"]            = "После"
L["col_remaining"]        = "Остаток"
L["col_amount"]           = "Сумма"
L["col_unit_amount"]      = "Сумма/предмет"
L["col_qty_short"]        = "Кол-во"
L["col_item"]             = "Предмет"
L["col_source"]           = "Источник"
L["col_bundle"]           = "Набор"
L["col_content"]          = "Содержимое"
L["col_uses"]             = "Использования"
L["col_total_value"]      = "Общая стоимость"
L["col_level_short"]      = "Ур."
L["col_ilvl"]             = "iLvl (Макс)\rот основного"
L["col_attendance"]       = "Местоположение"
L["col_participants"]     = "Участники"
L["col_value"]            = "Стоимость"
L["col_price"]            = "Цена"
L["col_total"]            = "Итого"
L["col_last_seen"]        = "Последний вход"
L["col_rerolls"]          = "Перебросы"
L["col_mplus_score"]      = "Очки М+\rот основного"
L["col_mplus_key"]        = "Основной ключ Эпох+"
L["col_state"]            = "Состояние"
L["col_request"]          = "Запрос"
L["col_version"]          = "Версия аддона"
L["lbl_of_main"]          = "основного"


-- ============================================== --
-- ===           BUTTONS / ACTIONS            === --
-- ============================================== --
L["btn_view"]             = "Просмотр"
L["btn_purge_all"]        = "Полная очистка"
L["btn_purge_bundles_exhausted"] = "Очистить наборы и исчерпанные предметы"
L["btn_purge_resources"]  = "Очистить ресурсы"
L["btn_force_version_gm"] = "Принудительно использовать мою версию (ГМ)"
L["btn_approve"]          = "Одобрить"
L["btn_refuse"]           = "Отклонить"
L["btn_make_free"]        = "Сделать бесплатным"
L["btn_cancel_free"]      = "Отменить бесплатный"
L["btn_back"]             = "< Назад"
L["btn_add_to_roster"]    = "Добавить в состав"
L["btn_remove_from_roster"] = "Удалить из состава"
L["btn_add_player"]       = "Добавить игрока"
L["btn_clear_all_free"]   = "Очистить все (бесплатно)"
L["btn_close"]            = "Закрыть"
L["btn_delete_short"]     = "X"
L["btn_enable_debug"]     = "Включить отладку"
L["btn_create_bundle"]    = "Создать набор"
L["btn_deposit_gold"]     = "Внести"
L["btn_withdraw_gold"]    = "Снять"
L["btn_stop_recording"]   = "Остановить запись"
L["btn_start_recording_expenses"] = "Начать запись расходов"
L["add_guild_member"]     = "Управление составом"
L["guild_members"]        = "Члены гильдии"
L["btn_purge_full"]       = "Полная очистка"
L["btn_purge_free_items_lots"] = "Очистить наборы и исчерпанные предметы"
L["btn_purge_all_items_lots"]  = "Очистить все наборы и предметы"
L["btn_notify_players"]   = "Уведомить игроков"
L["btn_confirm"]          = "Подтвердить"
L["btn_cancel"]           = "Отменить"
L["btn_create"]           = "Создать"
L["btn_split"]            = "Разделить"
L["btn_show_hidden_reserve"] = "Показать скрытых игроков"
L["btn_purge_debug"]      = "Очистить отладку"


-- ============================================== --
-- ===               ALIAS / UI               === --
-- ============================================== --
L["col_alias"]            = "Псевдоним"
L["btn_set_alias"]        = "Псевдоним…"
L["popup_set_alias_title"]= "Установить псевдоним"
L["lbl_alias"]            = "Псевдоним:"

-- Ping button and toast
L["tip_ping"]                    = "Пингнуть этого игрока"
L["tip_disabled_ping_cd_fmt"]    = "На перезарядке: осталось %d сек."
L["toast_ping_title"]            = "Пинг"
L["toast_ping_text_fmt"]         = "Вас пингнул %s"
-- With custom message support
L["toast_ping_text_with_msg_fmt"] = "Вас пингнул %s:\n|cffffd200%s|r"
-- Ping prompt
L["popup_ping_title"]   = "Пинг"
L["lbl_ping_message"]   = "Сообщение (опционально)"
L["ph_ping_message"]    = "Например, нужна помощь?"


-- ============================================== --
-- ===      LISTS / BADGES / LABELS           === --
-- ============================================== --
L["lbl_bundles"]          = "Наборы"
L["lbl_in_roster"]        = "В составе"
L["lbl_in_reserve"]       = "В резерве"
L["lbl_guild_members"]    = "Члены гильдии"
L["lbl_usable_bundles"]   = "Доступные наборы"
L["lbl_used_bundles"]     = "Использованные наборы"
L["lbl_item_reserve"]     = "Резерв предметов"
L["lbl_usable_bundles_raids"] = "Доступные рейдовые наборы"
L["lbl_participating_players"] = "Участвующие игроки"
L["lbl_reserved_players"] = "Резервированные игроки"
L["lbl_bundle"]           = "Набор"
L["lbl_no_data"]          = "Нет данных..."
L["opt_ui_theme"]         = "Тема интерфейса"
L["opt_open_on_login"]    = "Открывать автоматически при входе"
L["lbl_active_roster"]    = "Активный состав"
L["lbl_message"]          = "Сообщение"
L["lbl_message_received"] = "Сообщение получено"
L["lbl_message_sent"]     = "Сообщение отправлено"
L["lbl_shop"]             = "Магазин"
L["lbl_ah"]               = "Аукцион"
L["lbl_incoming_packets"] = "Список входящих пакетов"
L["lbl_outgoing_packets"]= "Список исходящих пакетов"
L["lbl_pending_queue"]  = "Список ожидающих пакетов"
L["lbl_diffusing_snapshot"] = "Немедленно распространить полный снимок"
L["lbl_diffusing_snapshot_confirm"] = "Распространить и ПРИНУДИТЕЛЬНО использовать версию ГМ?"
L["lbl_status_sent"]      = "ОТПРАВЛЕНО"
L["lbl_status_waiting"]   = "Ожидание"
L["lbl_status_inprogress"]= "В процессе"
L["lbl_status_transmitted"]= "Передано"
L["lbl_status_discovering"]= "Обнаружение..."
L["lbl_status_elected"]   = "Выбрано: "
L["lbl_status_assembling"]= "Сборка"
L["lbl_empty_payload"]    = "(пустая нагрузка)"
L["lbl_empty_raw"]        = "(сырые данные недоступны)"
L["lbl_raw"]              = "СЫРЫЕ"
L["lbl_uses"]             = " использований"
L["lbl_use"]              = " использование"
L["lbl_lot"]              = "Набор "
L["lbl_left_short"]       = "ост."
L["lbl_refunded"]         = "Возвращено"
L["lbl_closed"]           = "Закрыто"
L["lbl_used_charges"]     = "Использовано зарядов"
L["lbl_bundle_gold_only"] = "Золото"
L["lbl_recent_online"]    = "В сети < 1 месяц (последний персонаж)"
L["lbl_old_online"]       = "Последний вход ≥ 1 месяц"
L["lbl_no_player_found"]  = "Игрок не найден"
L["lbl_out_of_guild"]     = "Игроки вне гильдии"
L["confirm_delete"]       = "Удалить этого игрока?"
L["lbl_scan_roster_progress"] = "Сканирование состава..."
L["lbl_from_roster_question"] = "Из состава?"
L["lbl_total_balance"]    = "Общий баланс"
L["lbl_total_resources"]  = "Всего ресурсов"
L["lbl_total_both"]       = "Остаток баланса"
L["lbl_status_recieved"]  = "Получено"
L["lbl_guild_members"]    = "Члены гильдии"
L["lbl_sep_online"]       = "В сети"
L["lbl_sep_offline"]      = "Не в сети"
L["btn_clear"]            = "Очистить лог"


-- ============================================== --
-- ===           POPUPS / PROMPTS             === --
-- ============================================== --
L["popup_info_title"]     = "Информация"
L["popup_confirm_title"]  = "Подтверждение"
L["popup_input_title"]    = "Ввод"
L["popup_tx_request"]     = "Запрос транзакции"
L["popup_raid_ok"]        = "Участие в рейде подтверждено!"
L["msg_good_raid"]        = "Удачного рейда!"
L["lbl_total_amount_gold"] = "Общая сумма (золото):"
L["btn_confirm_participants"] = "Подтвердить участников"
L["lbl_bundle_name"]      = "Название набора:"
L["lbl_num_uses"]         = "Количество использований"
L["lbl_amount_gold"]      = "Сумма (золото)"
L["err_amount_invalid"]   = "Недопустимая сумма."
L["lbl_bundle_contents"]  = "Содержимое набора:"
L["confirm_clear_free_resources"] = "Очистить список бесплатных ресурсов? (наборы не затрагиваются)"
L["confirm_delete_resource_line"] = "Удалить эту строку ресурса?"
L["popup_split_title"]    = "Разделить ресурс"
L["lbl_split_qty"]        = "Количество для разделения"
L["err_split_qty_invalid"]= "Недопустимое количество. Должно быть от 1 до (количество - 1)."
L["hint_split_resource"]  = "Разделить на две строки"
L["err_split_failed"]     = "Не удалось выполнить разделение."
L["confirm_delete_history_line_permanent"] = "Навсегда удалить эту строку истории?"
L["hint_no_bundle_for_raid"] = "Для этого рейда не привязан ни один набор."
L["hint_select_resources_bundle"] = "Выберите ресурсы для создания набора (фиксированное содержимое)."
L["prompt_external_player_name"] = "Имя внешнего игрока для включения в состав"
L["realm_external"]       = "Внешний"
L["lbl_free_resources"]   = "Бесплатные ресурсы:"
L["confirm_question"]     = "Подтвердить?"
L["confirm_make_free_session"] = "Сделать эту сессию бесплатной для всех участников?"
L["confirm_cancel_free_session"] = "Отменить бесплатную сессию и восстановить начальное состояние?"
L["lbl_total_amount_gold_alt"] = "Общая сумма (золото):"
L["lbl_purge_confirm_all"] = "Очистить БД + сбросить интерфейс и перезагрузить?"
L["lbl_purge_confirm_lots"] = "Удалить исчерпанные наборы и их предметы?"
L["lbl_purge_confirm_all_lots"] = "Удалить ВСЕ наборы и ВСЕ предметы?"
L["lbl_purge_lots_confirm"] = "Очистка завершена: удалено %d набор(ов), %d предмет(ов)."
L["lbl_purge_all_lots_confirm"] = "Очистка завершена: удалено %d набор(ов), %d предмет(ов)."
L["lbl_no_res_selected"]  = "Ресурс не выбран"
L["tooltip_remove_history1"] = "Удалить эту строку истории"
L["tooltip_remove_history2"] = "• Удалить без корректировки балансов"
L["tooltip_remove_history3"] = "• Если ВОЗВРАЩЕНО: дебет не будет возвращен."
L["tooltip_remove_history4"] = "• Если ЗАКРЫТО: возврат не будет произведен."


-- ============================================== --
-- ===   TOOLTIPS / MESSAGES / PREFIXES       === --
-- ============================================== --
L["badge_approved_list"]  = "Одобрено через список"
L["badge_refused_list"]   = "Отклонено через список"
L["warn_debit_n_players_each"] = "Вы снимете с %d игроков по %s с каждого."
L["prefix_add_gold_to"]   = "Добавить золото для "
L["prefix_remove_gold_from"] = "Снять золото с "
L["prefix_delete"]        = "Удалить "
L["tooltip_send_back_active_roster"] = "Отправить этого игрока обратно в активный состав"
L["tooltip_view_raids_history"]      = "Просмотреть историю рейдов"
L["badge_exhausted"]      = "Исчерпано"
L["suffix_remaining"]     = "осталось"
L["range_to"]             = "до"

-- ============================================== --
-- ===            COLORED STATUS              === --
-- ============================================== --
L["status_online"]        = "В сети"
L["status_empty"]         = "-"
L["status_unknown"]       = "?"


-- ============================================== --
-- ===                OPTIONS                 === --
-- ============================================== --
L["opt_yes"]              = "Да"
L["opt_no"]               = "Нет"
L["opt_alliance"]         = "Альянс"
L["opt_horde"]            = "Орда"
L["opt_neutral"]          = "Нейтральный"
L["opt_auto"]             = "Автоматически"
L["opt_script_errors"]    = "Показывать ошибки Lua"
L["yes"]                  = "Да"
L["no"]                   = "Нет"

-- ============================================== --
-- ===     NOTIFS / MINIMAP / INDICATORS      === --
-- ============================================== --
L["tooltip_minimap_left"]        = "ЛКМ: Открыть/закрыть окно"
L["tooltip_minimap_drag"]        = "Перетаскивание: переместить иконку вокруг миникарты"
L["btn_ok"]                      = "ОК"
L["popup_tx_request_message"]    = "|cffffd200Запросивший:|r %s\n|cffffd200Операция:|r %s %s"
L["popup_deducted_amount_fmt"]   = "|cffffd200Списанная сумма:|r %s"
L["popup_remaining_balance_fmt"] = "|cffffd200Остаток баланса:|r %s"
L["tx_reason_gbank_deposit"]     = "|cffaaaaaaИсточник:|r Вклад в банк гильдии"
L["tx_reason_gbank_withdraw"]    = "|cffaaaaaaИсточник:|r Снятие из банка гильдии"

-- Guild Bank notifications
L["toast_gbank_deposit_title"]     = "Вклад в очереди"
L["toast_gbank_withdraw_title"]    = "Снятие в очереди"
L["toast_gbank_deposit_text_fmt"]  = "Ваш вклад %s отправлен на обработку баланса."
L["toast_gbank_withdraw_text_fmt"] = "Ваше снятие %s отправлено на обработку баланса."
L["tx_reason_manual_request"]    = "|cffaaaaaaИсточник:|r Ручной запрос"
L["warn_negative_balance"]      = "Внимание: ваш баланс отрицательный. Пожалуйста, урегулируйте баланс."
L["lbl_status_present_colored"]  = "|cff40ff40Присутствует|r"
L["lbl_status_deleted_colored"]  = "|cffff7070Удалено|r"
L["lbl_db_version_prefix"]       = "БД v"
L["lbl_id_prefix"]               = "ID "
L["lbl_db_data"]                 = "Общая БД"
L["lbl_db_ui"]                   = "Личная БД"
L["lbl_db_datas"]                = "БД истории"
L["lbl_db_backup"]               = "Резервная БД"
L["lbl_db_previous"]             = "Предыдущая БД"

-- Reload prompt & editor rights
L["btn_later"]                  = "Позже"
L["btn_reload_ui"]              = "Перезагрузить интерфейс"
L["msg_reload_needed"]          = "Изменения прав применены."
L["msg_editor_promo"]           = "Вы были повышены до редактора в "..L["app_title"] ..". Некоторые настройки требуют перезагрузки."
L["msg_editor_demo"]            = "Вы были понижены в "..L["app_title"] ..". Для отображения изменений требуется перезагрузка интерфейса."


-- ============================================== --
-- ===         CALENDAR INVITATIONS           === --
-- ============================================== --
L["pending_invites_title"]       = "Ожидающие приглашения"
L["pending_invites_message_fmt"] = "У вас %d необработанных приглашений в календарь.\nПожалуйста, ответьте.\nЭто окно будет появляться при входе, пока есть ожидающие приглашения."
L["btn_open_calendar"]           = "Открыть календарь"
L["col_when"]                    = "Когда"
L["col_event"]                   = "Событие"


-- ============================================== --
-- ===         WEEKDAYS (min)                 === --
-- ============================================== --
L["weekday_mon"] = "Понедельник"
L["weekday_tue"] = "Вторник"
L["weekday_wed"] = "Среда"
L["weekday_thu"] = "Четверг"
L["weekday_fri"] = "Пятница"
L["weekday_sat"] = "Суббота"
L["weekday_sun"] = "Воскресенье"


-- ============================================== --
-- ===      OPTIONS : UI NOTIFICATIONS        === --
-- ============================================== --
L["options_notifications_title"] = "Отображение всплывающих окон"
L["opt_popup_calendar_invite"]   = "Уведомление о приглашении в календарь"
L["opt_popup_raid_participation"]= "Уведомление об участии в рейде"
L["opt_popup_gchat_mention"]      = "Упоминание в чате гильдии и уведомление о пинге"


-- ============================================== --
-- ===           BiS TAB (Trinkets)           === --
-- ============================================== --
L["tab_bis"]         = "БиС Аксессуары"
L["col_tier"]        = "Уровень"
L["col_owned"]       = "В наличии"
L["lbl_class"]       = "Класс"
L["lbl_spec"]        = "Специализация"
L["lbl_bis_filters"] = "Фильтры"
L["msg_no_data"]     = "Нет данных"
L["footer_source_wowhead"] = "Источник: wowhead.com"
L["bis_intro"] = "Эта вкладка показывает список БиС аксессуаров по классу и специализации.\nРанги от S до F указывают приоритет (S — лучший). Используйте выпадающие списки для смены класса и специализации."
L["col_useful_for"]        = "Полезно для"
L["btn_useful_for"]        = "Полезно для..."
L["popup_useful_for"]      = "Другие классы, которые включают этот предмет в свой список БиС"
L["col_rank"]              = "Ранг"
L["col_class"]             = "Класс"
L["col_spec"]              = "Специализация"
L["msg_no_usage_for_item"] = "Ни один класс/специализация не ссылается на этот предмет в таблицах БиС."

-- ============================================== --
-- ===    CATEGORIES (side navigation)        === --
-- ============================================== --
L["cat_guild"]    = "Гильдия"
L["cat_raids"]    = "Рейды"
L["cat_tools"]    = "Инструменты"
L["cat_tracker"]  = "Трекер"
L["cat_info"]     = "Помощники"
L["cat_settings"] = "Настройки"
L["cat_debug"]    = "Отладка"

-- ====== Upgrade tracks (Helpers) ======
L["tab_upgrade_tracks"]       = "Пути улучшений (iLvl)"
L["upgrade_header_itemlevel"] = "УРОВНИ ПРЕДМЕТОВ"
L["upgrade_header_crests"]    = "ТРЕБУЕМЫЕ ГЕРБЫ"
L["upgrade_track_adventurer"] = "ПРИКЛЮЧЕНЕЦ"
L["upgrade_track_veteran"]    = "ВЕТЕРАН"
L["upgrade_track_champion"]   = "ЗАЩИТНИК"
L["upgrade_track_hero"]       = "ГЕРОЙ"
L["upgrade_track_myth"]       = "ЛЕГЕНДА"

-- ====== Crests ======
L["crest_valor"]   = "Доблесть"
L["crest_worn"]    = "Изношенный"
L["crest_carved"]  = "Резной"
L["crest_runic"]   = "Рунический"
L["crest_golden"]  = "Золотой"

-- ====== Upgrade steps ======
L["upgrade_step_adventurer"] = "Приключенец %d/8"
L["upgrade_step_veteran"]    = "Ветеран %d/8"
L["upgrade_step_champion"]   = "Защитник %d/8"
L["upgrade_step_hero"]       = "Герой %d/6"
L["upgrade_step_myth"]       = "Легенда %d/6"


-- ====== Dungeons (Helpers) ======
L["tab_dungeons_loot"]             = "Подземелья (iLvl и хранилище)"
L["dungeons_header_activity"]      = "— — —"
L["dungeons_header_dungeon_loot"]  = "ЛУТ ПОДЗЕМЕЛИЙ"
L["dungeons_header_vault"]         = "ХРАНИЛИЩЕ"
L["dungeons_header_crests"]        = "ГЕРБЫ"
L["dng_row_normal"]                = "Обычные подземелья"
L["dng_row_timewalking"]           = "Путешествия во времени"
L["dng_row_heroic"]                = "Героические подземелья"
L["dng_row_m0"]                    = "Эпох 0"
L["dng_row_key_fmt"]               = "Уровень ключа %d"
L["dungeon_no_tag"]                = "без упоминания предмета"
L["max_short"]                     = "макс"

-- Intro text
L["dng_note_intro"]   = "Сезон 3 «The War Within» корректирует уровень предметов всех подземелий:"
L["dng_note_week1"]   = "Неделя 1: Подземелья Эпох 0 дают предметы iLvl 681 (Чемпион 1/8)."
L["dng_note_week2"]   = "Неделя 2: Тазавеш в Эпох 0 дает предметы iLvl 694 (Герой 1/6)."
L["dng_note_vault"]   = "Великое Хранилище предлагает до 3 вариантов лута в зависимости от самого высокого завершенного уровня подземелья (Героический, Эпохальный, Эпох+ или Путешествия во времени)."

-- Keystone scaling paragraph
L["dng_note_keystone_scaling"] =
"Уровни предметов для подземелий Эпох+ увеличиваются до ключей 10 уровня, " ..
"с 2 предметами за подземелье (на 10 уровне) и 1 дополнительным предметом каждые 5 уровней. " ..
"Кроме того, еженедельное Великое Хранилище предлагает до 3 вариантов лута в зависимости от завершения 1, 4 и 8 " ..
"максимальных уровней подземелий в Героическом, Эпохальный, Эпох+ или Путешествиях во времени."


-- ====== Delves (Helpers) ======
L["tab_delves"]            = "Вылазки (награды)"
L["delves_header_level"]   = "УРОВЕНЬ"
L["delves_header_chest"]   = "ОБИЛЬНЫЙ СУНДУК"
L["delves_header_map"]     = "КАРТА СОКРОВИЩ"
L["delves_header_vault"]   = "ХРАНИЛИЩЕ"
L["delves_level_prefix"]   = "Уровень %s"
L["delves_cell_fmt"]       = "%d: %s (%d макс)"

-- Intro text above
L["delves_intro_title"]    = "Награды и функционирование"
L["delves_intro_b1"]       = "Сундуки имеют шанс содержать случайный предмет экипировки с iLvl 655 (связанный с батальоном)."
L["delves_intro_b2"]       = "Квартирмейстер по вылазкам предлагает стартовую экипировку с iLvl 668 (Ветеран) в обмен на фрагменты."
L["delves_intro_b3"]       = "Вы можете найти 1 карту сокровищ в неделю на персонажа при 20% прогресса сезонного путешествия."


-- ====== Raids (Helpers) ======
L["tab_raid_ilvls"]          = "Рейды (iLvl по сложности)"
L["raid_header_difficulty"]  = "СЛОЖНОСТЬ"
L["difficulty_lfr"]          = "Поиск рейда"
L["difficulty_normal"]       = "ОБЫЧНЫЙ"
L["difficulty_heroic"]       = "ГЕРОИЧЕСКИЙ"
L["difficulty_mythic"]       = "ЭПОХАЛЬНЫЙ"

-- Table rows
L["raid_row_group1"]         = "Сплетенный страж, Ткан'итар, Наазиндри"
L["raid_row_group2"]         = "Араз, Охотники и Разломий"
L["raid_row_group3"]         = "Соправитель Салхадаар и Пространствус"

-- Footer
L["raid_footer_ilvl_max"]    = "МАКСИМАЛЬНЫЙ УРОВЕНЬ ПРЕДМЕТА"

-- Bank/equilibrium footer (Roster)
L["lbl_bank_balance"] = "Баланс банка"
L["lbl_equilibrium"]  = "Равновесие"

-- Guild bank help/hints
L["no_data"] = "Нет данных"
L["hint_open_gbank_to_update"] = "Откройте банк гильдии для обновления этих данных"
L["tab_raid_loot"]           = "Манагорн Омега"
L["raid_intro_b1"]           = "Финальный рейд Манагорн Омега содержит несколько предметов экипировки с iLvl от 671 до 723:"
L["raid_intro_b2"]           = "- Рейды Путешествий во времени дают iLvl 681 (Чемпион 1) при активности."
L["raid_intro_b3"]           = "- Рейд содержит до 3 уровней iLvl с увеличением пути улучшения каждые 3 босса."
L["raid_intro_b4"]           = "- В отличие от Освобождения Нижней Шахты, путь улучшения начинается с 2/8 (вместо 1) на ранних боссах."


-- ====== Crests (tab & headers) ======
L["tab_crests"]              = "Гербы (источники)"
L["crests_header_crest"]     = "ГЕРБЫ"
L["crests_header_chasms"]    = "ВЫЛАЗКИ"
L["crests_header_dungeons"]  = "ПОДЗЕМЕЛЬЯ"
L["crests_header_raids"]     = "РЕЙДЫ"
L["crests_header_outdoor"]   = "ОТКРЫТЫЙ МИР"

-- Labels & formats
L["crest_range"]             = "%s (%d до %d)"
L["label_level"]             = "Уровень %d"
L["label_crests_n"]          = "%d гербов"
L["label_per_boss"]          = "%d гербов за босса"
L["label_per_cache"]         = "%d гербов за тайник"
L["label_except_last_boss"]  = "(кроме последнего босса)"
L["label_na"]                = "Н/Д"

-- Source names
L["gouffre_classic"]         = "Классические вылазки"
L["gouffre_abundant"]        = "Многообещающие вылазки"
L["archaeologist_loot"]      = "Лут археолога"
L["heroic"]                  = "Героический"
L["normal"]                  = "Обычный"
L["lfr"]                     = "Поиск рейда"
L["mythic"]                  = "Эпохальный"
L["mythic0"]                 = "Эпох 0"
L["mplus_key"]               = "Эпох+"
L["weekly_event"]            = "Еженедельное событие"
L["treasures_quests"]        = "Сокровища/Квесты"


-- ====== Group tracker (Helpers) ======
L["tab_group_tracker"]        = "Трекер"
L["group_tracker_title"]      = "Трекер"
L["group_tracker_toggle"]     = "Показать окно отслеживания"
L["group_tracker_hint"]       = "Подсказка: Чтобы открыть окно отслеживания напрямую, введите эту команду в чат |cffaaaaaa/glog track|r"
L["btn_reset_counters"]       = "Сбросить счетчики"

L["group_tracker_cooldown_heal"]  = "Перезарядка зелья лечения (с)"
L["group_tracker_cooldown_util"]  = "Перезарядка других зелий (с)"
L["group_tracker_cooldown_stone"] = "Перезарядка камня здоровья (с)"

L["col_heal_potion"]   = "Лечение"
L["col_other_potions"] = "Предпот"
L["col_healthstone"]   = "Камень"
L["col_cddef"]   = "Защита"
L["col_dispel"]   = "Рассеивание"
L["col_taunt"]    = "Танковая"
L["col_move"]     = "Движение"
L["col_kick"]     = "Прерывание"
L["col_cc"]       = "Контроль"
L["col_special"]  = "Утил."
L["status_ready"]      = "Готово"
L["history_title"]     = "История: %s"
L["col_time"]          = "Время"
L["col_category"]      = "Категория"
L["col_spell"]         = "Заклинание / Предмет"
L["history_ooc"]       = "Вне боя"
L["history_combat"]    = "В бою"
L["confirm_clear_history"] = "Очистить историю сражений?"
L["btn_reset_data"]    = "Очистить историю сражений"

L["match_healthstone"] = "камень здоровья"
L["match_potion"]      = "зелье"
L["match_heal"]        = "лечение"
L["match_mana"]        = "мана"

L["group_tracker_opacity_label"] = "Прозрачность фона"
L["group_tracker_opacity_tip"]   = "Установить прозрачность фона окна отслеживания."
L["group_tracker_record_label"]  = "Включить отслеживание"
L["group_tracker_record_tip"]    = "Включить отслеживание"
L["group_tracker_title_opacity_label"] = "Прозрачность текста заголовка"
L["group_tracker_title_opacity_tip"]   = "Настроить прозрачность текста заголовка без влияния на фон или границы."
L["group_tracker_text_opacity_label"] = "Прозрачность текста"
L["group_tracker_btn_opacity_label"] = "Прозрачность кнопок"
L["group_tracker_btn_opacity_tip"]   = "Настроить прозрачность кнопок (Закрыть, Пред., След., Очистить) без влияния на текст или фон."
L["group_tracker_history"]                = "История"
L["group_tracker_history_empty"]          = "Пустая история"
L["group_tracker_popup_title_btn_hide"]   = "Скрыть текст заголовка (всплывающее окно)"
L["group_tracker_popup_title_btn_show"]   = "Показать текст заголовка (всплывающее окно)"
L["group_tracker_popup_title_btn_tip"]    = "Переключить отображение текста заголовка всплывающей истории."
L["group_tracker_row_height_label"]       = "Высота строки"
L["group_tracker_row_height_tip"]         = "Настроить высоту строки"
L["group_tracker_lock_label"] = "Заблокировать трекер (отключить клики/перемещения)"
L["group_tracker_lock_tip"]   = "Блокировать все взаимодействия с трекером, пока включен флажок."


L["tab_debug_db"] = "База данных"

L["col_key"]     = "Ключ"
L["col_preview"] = "Предпросмотр"

L["btn_open"]    = "Открыть"
L["btn_edit"]    = "Редактировать"
L["btn_delete"]  = "Удалить"
L["btn_root"]    = "Корень"
L["btn_up"]      = "Вверх"
L["btn_down"]         = "Вниз"
L["tooltip_move_up"]   = "Переместить эту колонку вверх"
L["tooltip_move_down"] = "Переместить эту колонку вниз"
L["btn_add_field"]  = "Добавить запись"

L["popup_edit_value"] = "Редактировать значение"
L["lbl_edit_path"]    = "Путь: "
L["lbl_lua_hint"]     = "Введите литерал Lua: 123, true, \"текст\", { a = 1 }"
L["lbl_delete_confirm"] = "Удалить этот элемент?"
L["lbl_saved"]          = "Сохранено"

L["tab_custom_tracker"] = "Пользовательское отслеживание"
L["custom_col_label"] = "Метка"
L["custom_col_mappings"] = "Правила"
L["custom_col_active"] = "Активно"
L["status_enabled"] = "Активно"
L["status_disabled"] = "Неактивно"
L["custom_add_column"] = "Добавить колонку"
L["custom_edit_column"] = "Редактировать колонку"
L["custom_spells_ids"] = "ID заклинаний (через запятую)"
L["custom_items_ids"]  = "ID предметов (через запятую)"
L["custom_keywords"]   = "Ключевые слова (через запятую)"
L["custom_enabled"]    = "Включено"
L["custom_confirm_delete"] = "Удалить колонку '%s'?"
L["lbl_spells"]    = "Заклинания"
L["lbl_items"]     = "Предметы"
L["lbl_keywords"]  = "Ключи"
L["err_label_required"] = "Требуется метка"
L["custom_spells_list"] = "Отслеживаемые заклинания"
L["custom_items_list"] = "Отслеживаемые предметы"
L["custom_keywords_list"] = "Ключевые слова"
L["placeholder_spell"] = "ID заклинания"
L["placeholder_item"] = "ID предмета"
L["placeholder_keyword"] = "Ключевое слово"
L["btn_add"] = "Добавить"
L["custom_select_type"] = "Тип элемента"
L["type_spells"] = "Заклинания"
L["type_items"] = "Предметы"
L["type_keywords"] = "Ключевые слова"
L["tab_loot_tracker"] = "Журнал лута"
L["tab_loot_tracker_settings"] = "Настройки записи лута"
L["col_where"] = "Местоположение"
L["col_who"] = "Кем добыто"
L["col_ilvl"]            = "iLvl"
L["col_instance"]        = "Подземелье"
L["col_difficulty"]      = "Сложность"

L["format_date"] = "%Y-%m-%d"
L["format_heure"] = "%H:%M"
L["col_group"]            = "Группа"
L["col_roll"]             = "Бросок"
L["tip_show_group"]       = "Показать членов группы"
L["popup_group_title"]    = "Члены группы"
L["tab_debug_events"] = "Журнал событий"
L["btn_pause"]        = "Пауза"
L["btn_resume"]       = "Возобновить"
L["lbl_min_quality"]    = "Минимальная редкость"
L["lbl_min_req_level"]  = "Минимальный уровень"
L["lbl_equippable_only"]= "Только экипируемое"
L["lbl_min_item_level"] = "Минимальный iLvl"
L["lbl_instance_only"]  = "Только в подземелье"
L["opt_ui_scale_long"] = "Масштаб интерфейса"
L["opt_ui_scale"] = "Масштаб"

-- === Debug: Errors ===
L["tab_debug_errors"] = "Ошибки Lua"
L["col_message"]      = "Сообщение"
L["col_done"]         = "Обработано"
L["lbl_error"]        = "Ошибка"
L["lbl_stacktrace"]   = "Трассировка стека"
L["btn_copy"]         = "Копировать"
L["lbl_yes"]          = "Да"
L["lbl_no"]           = "Нет"
-- Toasts
L["toast_error_title"] = "Новая ошибка Lua"

-- Personal credit/debit toasts
L["toast_credit_title"]      = "Золото зачислено"
L["toast_debit_title"]       = "Золото списано"
L["toast_credit_text_fmt"]   = "Вам зачислено %s.\nНовый баланс: %s."
L["toast_debit_text_fmt"]    = "С вас списано %s.\nНовый баланс: %s."
L["instance_outdoor"] = "Открытый мир"

-- Guild chat mention
L["toast_gmention_title"]      = "Упоминание в чате гильдии"
L["toast_gmention_text_fmt"]   = "Вас упомянул %s: %s"

-- ============================================== --
-- ===              BACKUP/RESTORE            === --
-- ============================================== --
L["btn_create_backup"]    = "Создать резервную копию"
L["btn_restore_backup"]   = "Восстановить резервную копию"
L["tooltip_create_backup"] = "Создать полную резервную копию базы данных"
L["tooltip_restore_backup"] = "Восстановить базу данных из последней резервной копии"
L["err_no_main_db"]      = "Основная база данных не найдена"
L["err_no_backup"]       = "Резервная копия не найдена"
L["err_invalid_backup"]  = "Недопустимая резервная копия"
L["msg_backup_created"]  = "Резервная копия успешно создана (%d элементов)"
L["msg_backup_restored"] = "База данных восстановлена из резервной копии от %s"
L["msg_backup_deleted"]  = "Резервная копия удалена"
L["unknown_date"]        = "Неизвестная дата"
L["confirm_create_backup"] = "Создать резервную копию базы данных?"
L["confirm_restore_backup"] = "Восстановить базу данных из резервной копии?\n\nЭто заменит все текущие данные.\nТекущая база данных будет сохранена как 'предыдущая'."
L["lbl_backup_info"]     = "Информация о резервной копии"
L["lbl_backup_date"]     = "Дата: %s"
L["lbl_backup_size"]     = "Размер: %d элементов"
L["lbl_no_backup_available"] = "Резервная копия недоступна"


-- ============================================== --
-- ===           HARDCODED STRINGS            === --
-- ============================================== --
L["col_string"]          = "Строка"
L["col_spell_name"]      = "Название заклинания"
L["col_item_name"]       = "Название предмета"
L["spell_id_format"]     = "Заклинание #%d"
L["item_id_format"]      = "Предмет #%d"
L["btn_remove"]          = "Удалить"
L["lbl_notification"]    = "Уведомление"
L["unknown_dungeon"]     = "Неизвестное подземелье"
L["dungeon_id_format"]   = "Подземелье #%d"
L["group_members"]       = "Члены группы"
L["col_hash"]            = "#"
L["btn_delete_short"]    = "X"
L["value_dash"]          = "-"
L["lbl_instance_only"]   = "Только подземелье/вылазка"
L["lbl_equippable_only"] = "Только экипируемое"
L["btn_expand"]          = "+"
L["btn_collapse"]        = "-"
L["value_empty"]         = "—"

-- Toast/footer hint
L["toast_hint_click_close"] = "Нажмите, чтобы закрыть уведомление"

-- === Mode selection (dual-mode) ===
L["mode_settings_header"]    = "Режим использования"
L["mode_guild"]              = "Гильдейская версия"
L["mode_standalone"]         = "Автономная версия"
L["mode_firstrun_title"]     = "Выберите режим использования"
L["mode_firstrun_body"]      = "\nПожалуйста, выберите режим использования для "..L["app_title"]..":\n\n|cffffd200Гильдейская версия|r\n Обменивается данными с другими пользователями аддона в вашей гильдии. Обычно ГМ или редактор настраивает и инициирует обмен.\n\n|cffffd200Автономная версия|r\n Без связи с другими игроками. Все функции остаются локальными и доступными без прав ГМ; ничего не транслируется.\n\nВы можете изменить это позже в настройках — оба режима могут работать независимо без потери данных."
