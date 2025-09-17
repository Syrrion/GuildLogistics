## Guide interne : GuildLogistics

Ce document synthétise le fonctionnement de l’addon Guild Logistics pour faciliter toute intervention future (correctifs, évolutions, localisation, QA). Il peut servir de base à un fichier PROJECT\_INSTRUCTIONS.md.

---

## 1. Aperçu global

Addon World of Warcraft orienté gestion de guilde : suivi roster, finances (dépenses/recettes), suivi raids, distribution de butin, outils Mythic+, journal d’erreurs et modules de debug.

L’espace global est structuré autour du namespace \_G\[...] = ... passé par WoW : local ADDON, ns = ....

* **ns.GLOG** : cœur applicatif (logique métier, communications, état global).
* **ns.Util** : utilitaires génériques (normalisation noms, dates, helpers math).
* **ns.UI** : primitives et composants UI (fenêtre principale, widgets, listviews).
* **ns.Tr** : fonction de traduction, alimentée par Locales.

Les SavedVariables sont listées dans GuildLogistics.toc. Les données persistent sous **GuildLogisticsShared.guilds**, segmentées par guilde et mode (normal/standalone).

---

## 2. Structure des dossiers

### /Core

**Core/Core/** : socle applicatif

* **Addon.lua** : lecture métadonnées TOC, helpers version, gestion notifications versions.
* **DatabaseManager.lua** : initialise/migre les SavedVariables, gère buckets par guilde.
* **Helper.lua** : utilitaires exposés (Clamp, safenum, gestion fenêtre, icône).
* **Time.lua, Timers.lua** : helpers temporels/throttle.
* **Permissions.lua, HistoryManager.lua, BackupManager.lua, Legacy.lua** : rôles, historique, sauvegardes, compatibilité versions antérieures.

**Core/Player/** : gestion du roster et des profils

* **Manager.lua** : lien mains/alts, soldes, toasts de crédit/débit.
* **Alias.lua, Name.lua, Status.lua, Class.lua, MythicProgress.lua, MainAlt.lua** : enrichissement des données personnages.

**Core/Guild/** et **Core/Group/** : abstractions guilde/groupe (roster live, raid/party watchers).

**Core/Game/** : helpers métiers (spells, affixes, calendrier).

**Core/Comm/** : couche réseau

* **Serialization.lua, Transport.lua, DataSync.lua, NetworkDiscovery.lua, MessageHandlers.lua, Requests.lua, Comm.lua, etc.**
* Utilise LibDeflate/LibStub pour compression/interop.

**Core/Tracker/** et **Core/LootTracker/** : suivi d’instances/groupe, loot tracking, parser des messages, API UI associée.

**Core/Economy/** : dépenses, lots, hooks pour transactions.

**Core/Debug/** : early error handler, journal d’erreurs, transport de rapports, logging, handlers debug.

### /Data

Données statiques : Players.lua, Tracker.lua, Upgrades.lua, BiS\_Trinkets.lua.

### /UI

* **UI.lua** : constantes globales UI, formatage gold, couleurs.
* **UI\_Core.lua** : scheduler, gestion headers, scrollbars, colonnes listview.
* **UI\_**\* : composants (Buttons, Dropdown, Slider, Scrollbar, Toast, ListView, Popup, TokenList).
* **UI\_Skin.lua, UI\_Pixel.lua, UI\_Fonts.lua, UI\_Scale.lua** : thèmes et adaptation résolutions.
* **Layout.lua, UI\_Cell.lua, UI\_Badge.lua, UI\_Float.lua, UI\_PlainWindow\.lua** : helpers d’agencement.

**UI/UI.lua** instancie la fenêtre principale (dimensions 1360x680 par défaut).

### /Tabs

Chaque fichier = un onglet logique (Guild, Roster, RaidHistory, Resources, Requests, BiS, Settings, Debug...).

### /Locales

* **locales-enUS.lua** et **locales-frFR.lua** : tables L\["key"] = value. ns.Tr cherche ns.L.
* Toute nouvelle chaîne doit être ajoutée dans les deux fichiers.

### /Ressources

* **Media/** : icônes multi-résolutions.
* **Fonts/** : polices (vixar.ttf).
* **Libs embarquées** : LibStub, LibDeflate.

### Fichiers racine

* **GuildLogistics.toc** : ordre de chargement critique.
* **cliff.toml** : configuration changelog/outillage.

---

## 3. Flux d’initialisation

* WoW charge les fichiers selon **GuildLogistics.toc**.
* **Addon.lua** s’exécute en premier : métadonnées, caches versions, init GuildLogisticsShared.
* **DatabaseManager.lua** migre les anciennes sauvegardes.
* Modules Core attachent leurs fonctions à ns.GLOG / ns.Util.
* **Comm.lua** vérifie les sous-modules critiques et expose API InitComm, StartNetworkSync.
* **UI\_PlainWindow + UI.lua + UI\_Core.lua** construisent la fenêtre.
* Les évènements WoW alimentent la base et rafraîchissent l’UI.

---

## 4. Base de données & persistance

Structure pivot : **GuildLogisticsShared.guilds\[<bucket>]**

* players, history, expenses, lots, meta, requests, account (mains, altToMain), errors.
* **DatabaseManager** fournit \_InitSchema, GLOG.GetActiveGuildBucketKey().
* **GLOG.EnsureDB()** accessible dans Data/Players.lua et Core/Player/Manager.lua.
* Migrations gérées lors du chargement.
* Mode standalone : **standalone\_<guildKey>**.

---

## 5. Communications & synchronisation

* **Serialization.lua** : encodeKV/decode.
* **Transport.lua** : gère canaux (GUILD, OFFICER, compression LibDeflate).
* **DataSync.lua, NetworkDiscovery.lua, Broadcasting.lua, MessageHandlers.lua, Requests.lua** orchestrent synchro et discovery.
* **DebugLogging.lua** propose GLOG.pushLog.

Processus pour ajouter un message réseau :

1. Définir format dans MessageHandlers.lua.
2. Sérialiser via encodeKV + Transport.Send.
3. Documenter le message dans Tabs/Debug\_Packets.lua.

---

## 6. Gestion joueurs / guilde

* **Manager.lua** : gestion identifiants stables, soldes, toasts.
* **Alias.lua, MainAlt.lua, Status.lua, MythicProgress.lua, Class.lua** : mapping, suivi progress, classes.
* **Core/Guild/Core.lua** : interactions roster.
* **Core/Group/** : watchers groupe/raid.

---

## 7. Trackers & Loot

* **Core/Tracker/** : suivi sessions groupe.
* **Core/LootTracker/** : enregistrement butins.
* Relié aux onglets **Tracker\_Loots.lua** et **Tracker\_Custom.lua**.

---

## 8. Économie & ressources

* **Expenses.lua** : enregistrement dépenses.
* **Lots.lua** : gestion lots.
* Consommés par **Tabs/Resources.lua** et **Tabs/Requests.lua**.

---

## 9. Interface utilisateur

* Chaque tab définit **ns.UI.RegisterTab**.
* UI gère colonnes, scroll, filtrage.
* **UI\_PlainWindow + UI\_Skin** pour skin global.
* **UI.Toast, UI.Popup** : notifications/confirmations.
* **UI\_Scale** : adaptation multi-résolutions.
* Onglets debug reliés à Core/Debug et Core/Comm.

---

## 10. Localisation & contenus statiques

* Ajouter chaînes dans **locales-enUS.lua**, répliquer dans **locales-frFR.lua**.
* Si traduction manquante : laisser anglais commenté.
* Maintenir ordre par sections.
* Données statiques dans **/Data** (BiS, upgrades).

---

## 11. Debug & journalisation

* Early errors : interceptés par **EarlyErrorHandler.lua**.
* Rapports via **ErrorHandler.lua** et **ErrorComm.lua**.
* Journal d’erreurs : **ErrorJournal.lua**.
* Logging : **GLOG.pushLog**.
* Analyse locale possible via ErrorComm.

---

## 12. Conventions & bonnes pratiques

* Toujours commencer fichiers par `local ADDON, ns = ...`.
* Ne pas polluer \_G sauf helpers prévus.
* Ajouter fonctions sur **GLOG** plutôt que globals.
* Utiliser **Debounce/Throttle** pour limiter surcharges.
* Respecter timers/ticks existants.
* Pour UI : utiliser **UI.NextFrame** plutôt que **C\_Timer.After**.
* Colonnes ListView : définir id, label, largeur, flex.
* Nouvel onglet : déclarer dans settings.
* Modif schema DB : passer par DatabaseManager.

---

## 13. Tests & QA

* Pas de tests automatisés.
* QA manuelle :

  * Vérifier chargement sans erreurs.
  * Tester workflow principal.
  * Contrôler onglets Debug.
* Pour bug : journal Debug\_Errors.

---

## 14. Processus type pour une évolution

1. Identifier la zone (UI/Core/Data).
2. Mettre à jour Core (API, DB, migrations).
3. Mettre à jour UI (composants, locales).
4. Synchronisation réseau si besoin.
5. Localisation (FR/EN).
6. QA manuelle.

---

## 15. Points d’attention

* **Performances** : éviter OnUpdate lourds.
* **Limitations WoW** : éviter "script ran too long".
* **Compatibilité** : fallback si API non dispo.
* **Sécurité données** : backup avant suppression.
* **Network** : respecter compression LibDeflate.
* **UI** : test multi-échelles, combat lockdown.

---

## 16. Ressources complémentairesLors du déploie

* Logos/assets : **Ressources/Media**.
* Fonts : **Ressources/Fonts**.
* Libs : **Ressources/Libs**.
* Config release : **cliff.toml**.

---

Ces instructions doivent être tenues à jour après chaque refactor majeur. Pour améliorer ce guide, documenter les flux additionnels (captures UI, mapping onglets).
