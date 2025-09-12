# GuildLogistics AI Coding Instructions

## Project Overview

GuildLogistics is a sophisticated World of Warcraft addon for guild raid management, featuring guild economics, automated loot tracking, cross-player data synchronization, and comprehensive raid analytics. Built with Lua for WoW Retail (Interface 110200).

**⚡ Performance Priority**: Always optimize for memory and CPU efficiency. WoW addons share limited resources - every function call, event handler, and memory allocation matters. When modifying existing code, look for optimization opportunities even if the feature works.

## Architecture Patterns

### Module Loading System
Files load sequentially via `GuildLogistics.toc` - dependencies must come before dependents. Core modules in `Core/` are loaded first, followed by `UI/`, then `Tabs/`. Always add new files to `.toc` in dependency order.

IMPORTANT maintenance: Whenever you create, move, or rename modules/files, update BOTH the `GuildLogistics.toc` (in dependency order) and this `copilot-instructions.md` to keep the architecture map accurate.

### Namespace Pattern
All code uses shared namespace pattern:
```lua
local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG
```
- `ns.GLOG` = primary API namespace
- `ns.UI` = UI system namespace  
- `ns.Util` = utilities namespace
- `ns.Events` = centralized event hub

### Communication Architecture
Multi-layered network communication system:
- `Core/Comm/Transport.lua` - Low-level messaging via WoW addon channels
- `Core/Comm/Serialization.lua` - Data encoding/compression with LibDeflate
- `Core/Comm/MessageHandlers.lua` - Message routing and processing
- `Core/Comm/DataSync.lua` - Automatic data synchronization between guild members

### Database System
Character-based persistence with migration support:
- Primary DB: `GuildLogisticsDB_Char` (per-character data)
- UI Settings: `GuildLogisticsUI_Char` (per-character UI state)
- Migration version tracking in `db.meta.lastMigration`
- All database operations via `GLOG.EnsureDB()` in `Core/Core/DatabaseManager.lua`

### Event-Driven Architecture
Dual event systems:
1. **WoW Events**: `ns.Events.Register(event, owner, callback)` for WoW game events
2. **Internal Events**: `GLOG.On(event, callback)` / `GLOG.Emit(event, ...)` for addon-internal communication

Both systems use unified dispatcher in `Core/Core/Events.lua`.

### UI Component System
Tab-based interface with category sidebar:
- Register tabs: `UI.RegisterTab(label, buildFunc, refreshFunc, layoutFunc, opts)`
- Categories: `cat_guild`, `cat_raids`, `cat_tools`, `cat_tracker`, `cat_info`, `cat_settings`, `cat_debug`
- **MANDATORY**: Use `UI.CreateMainContainer(container, {footer = true/false})` in all Build functions
- Reusable components in `UI/UI_*.lua` (ListView, Popup, Dropdown, etc.)
- Consistent scaling system via `UI.Scale.ApplyAll()`

## Critical Development Patterns

### Performance-First Development
**ALWAYS** prioritize performance and resource efficiency. WoW addons run in a constrained environment:

**Memory Management**:
- Reuse objects instead of creating new ones in loops
- Use `wipe(table)` instead of `table = {}` for clearing large tables
- Call `collectgarbage()` after major operations via `/glog gc`
- Monitor memory with `/glog mem` during development

**Event Optimization**:
- Throttle high-frequency events (especially `GUILD_ROSTER_UPDATE`)
- Use `_ScheduleActiveTabRefresh()` instead of immediate UI updates
- Batch operations with `C_Timer.After(delay, callback)` for non-blocking execution
- Unregister events when not needed via `ns.Events.UnregisterOwner()`

**UI Performance**:
- Use `UI.ListView()` with efficient `updateRow` functions for large datasets
- Avoid creating frames in loops - use frame recycling patterns
- Implement lazy loading for tabs - only build UI when first shown
- Use `lv:SetData()` sparingly - cache and diff data when possible

**Data Processing**:
- Cache expensive calculations (guild roster, item info, etc.)
- Use lookup tables instead of linear searches
- Implement data pagination for large datasets
- Prefer `pairs()` over `ipairs()` for sparse arrays

**Communication Efficiency**:
- Compress data via LibDeflate before network transmission
- Use message batching to avoid spam
- Implement request throttling for data synchronization
- Cache remote data to minimize network requests

**Code Review Checklist**:
- Is this operation O(n²)? Can it be O(n) or O(log n)?
- Are we creating objects in tight loops?
- Could this UI update be throttled or batched?
- Is there an existing cached version of this data?
- Can this expensive operation be moved to background processing?

### Don't Reinvent the Wheel - Use Existing Components
**ALWAYS** check for existing functions before creating new ones. The codebase has extensive utility libraries:

**UI Components** - Never create manual frames when these exist:
- `UI.CreateMainContainer(container, {footer = true/false})` - **Mandatory** for all tab layouts
- `UI.ListView(panel, columns, opts)` - For all data tables
- `UI.Button(parent, text, opts)` - Standardized buttons with scaling
- `UI.Dropdown(parent, opts)` - Dropdown menus with consistent styling
- `UI.CreatePopup({title, width, height})` - Modal dialogs
- `UI.SectionHeader(parent, text, opts)` - Section separators

**Data Management** - Use centralized functions:
- `GLOG.EnsureDB()` - Database access (never access GuildLogisticsDB directly)
- `GLOG.GetOrAssignUID(playerName)` - Player ID management
- `GLOG.ResolveFullName(name, opts)` - Name validation/normalization
- `ns.Tr("key")` - Localization (never hardcode English strings)

**Common Utilities** - Check `ns.Util` and `GLOG` namespaces first:
- `UI.FormatThousands(number)` - Number formatting with separators
- `UI.MoneyText(amount)` - Gold formatting with icons
- `ns.Util.After(delay, callback)` - Delayed execution
- `GLOG.IsGM()` - Guild leader permissions check

### Function Registration Pattern
Most systems use registration patterns for extensibility:
```lua
-- Tab registration
UI.RegisterTab("My Tab", BuildFunc, RefreshFunc, LayoutFunc, {category = "cat_tools"})

-- Event handlers  
ns.Events.Register("GUILD_ROSTER_UPDATE", "my-module", function(...) end)

-- Message handlers
GLOG.RegisterMessageHandler("MY_MSG_TYPE", function(sender, data) end)
```

### Data Validation & UID System
Player data uses centralized UID system:
- `GLOG.GetOrAssignUID(playerName)` - Gets or creates unique ID
- `GLOG.MapUID(uid, playerName)` - Associates UID with name
- `GLOG.GetNameByUID(uid)` - Reverse lookup
- Always validate player names via `GLOG.ResolveFullName(name, opts)`

### Error Handling
Comprehensive error system:
- Early errors: `Core/Debug/EarlyErrorHandler.lua` (pre-ADDON_LOADED)
- Runtime errors: `Core/Debug/ErrorHandler.lua` with journaling
- Communication errors: `Core/Debug/ErrorComm.lua` for network issues
- Debug logging via `GLOG.pushLog(level, module, message, data)`

## Development Workflows

### Adding New Tabs
1. Create file in `Tabs/` following mandatory pattern:
   ```lua
   local function Build(container)
       -- ALWAYS use UI.CreateMainContainer for consistent layout
       panel, footer = UI.CreateMainContainer(container, { footer = true })
       -- OR for tabs without footer:
       -- panel = UI.CreateMainContainer(container, { footer = false })
       
       -- UI construction in panel
   end
   local function Refresh() -- Data refresh  
   local function Layout() -- Responsive layout (usually empty - CreateMainContainer handles sizing)
   UI.RegisterTab("Tab Name", Build, Refresh, Layout, {category = "cat_tools"})
   ```
2. Add to `GuildLogistics.toc` after existing tab files
3. Use `ns.RefreshAll()` to update all tabs

**Critical**: Always use `UI.CreateMainContainer()` - never create manual frames for tab content. This ensures consistent padding, footer handling, and responsive layout.

### Communication Messages
1. Define message type constant: `MSG_MY_ACTION = "MY_ACTION"`
2. Add handler: `GLOG.RegisterMessageHandler("MY_ACTION", function(sender, data) end)`
3. Send via: `GLOG._send("MY_ACTION", data, "GUILD")` or specific player
4. All messages auto-compressed and versioned

### Database Changes
1. Increment migration target in `DatabaseManager.lua`
2. Add migration logic preserving existing data
3. Test with `/glog bc` (bulk cleanup) command
4. Use `GLOG.EnsureDB()` before all database access

### Testing & Debugging
Built-in testing commands:
- `/glog mem` - Memory statistics
- `/glog gc` - Garbage collection 
- `/glog testlootroll` - Test loot roll system
- Debug tabs available when `GuildLogisticsUI.debugEnabled = true`
- Communication tests in `Core/Comm/CommunicationTest.lua`

## Critical Implementation Details

### Localization
Use translation function: `ns.Tr("key")` or `Tr("key")` in files with local reference. Keys defined in `Locales/locales-*.lua`.

### Game Integration
- Guild data via `C_GuildInfo.GuildRoster()` with caching in `GLOG.RefreshGuildCache()`
- Item links: WoW format `|cffffff|Hitem:id:...|h[Name]|h|r`
- Player status tracking (ilvl, mythic+ keys, location) via unified status system
- Calendar integration for raid scheduling

### Performance Considerations
- UI refresh throttling via `_ScheduleActiveTabRefresh()` - prevents excessive redraws
- Async operations with `C_Timer.After()` for non-blocking updates
- Memory management with periodic cleanup via `GLOG.Debug_BulkCleanup()`
- Event batching to prevent spam (especially GUILD_ROSTER_UPDATE)
- Data caching systems: `GLOG.RefreshGuildCache()` for guild data
- ListView recycling patterns - rows are reused, not recreated
- Lazy tab initialization - UI built only when first accessed
- Compressed network communication via LibDeflate reduces bandwidth
- Player UID system reduces memory footprint vs storing full names repeatedly

**Performance Commands**:
- `/glog mem` - Monitor memory usage during development
- `/glog gc` - Force garbage collection to test memory cleanup
- `/glog bc` - Bulk cleanup operation for testing data purging

### Version Compatibility
- Addon version in `Core/Core/Addon.lua` with semantic versioning
- Cross-version message compatibility via version headers
- Graceful degradation for missing features between versions

### Comment hygiene
- Do not leave comments about systems that no longer exist (e.g., removed migrations, deprecated fallbacks). When deprecating or removing a feature, also remove or update any related comments and docs to avoid confusion.


Always preserve existing APIs when modifying core systems. Use the comprehensive debug system for troubleshooting. The addon has extensive built-in diagnostics accessible via debug tabs and slash commands.

# Plan Architectural - GuildLogistics

## Vue d'ensemble du projet

**GuildLogistics** est un addon World of Warcraft pour la gestion de guildes et le suivi des activités de raids. Il s'agit d'un système modulaire complexe avec une architecture en couches pour gérer les données, la communication, l'interface utilisateur et les différentes fonctionnalités de suivi.

**Version actuelle :** 3.1.0  
**Interface WoW :** 110200 (Retail)  
**Auteur :** Ysendril-KirinTor

---

## Architecture générale

### Structure modulaire
Le projet suit un pattern d'architecture modulaire avec séparation des responsabilités :
- **Core/** : Modules fondamentaux (données, communication, événements)
- **UI/** : Interface utilisateur et composants visuels
- **Tabs/** : Onglets d'interface spécialisés
- **Data/** : Données statiques et configurations
- **Locales/** : Système de traduction
- **Ressources/** : Assets visuels et polices

### Chargement et dépendances
- Chargement séquentiel défini par `GuildLogistics.toc`
- Dépendance externe : `LibDeflate` pour la compression
- Système d'événements centralisé
- Initialisation différée et vérification des modules

---

## Détail des modules

### 📁 **Core/** - Modules fondamentaux

#### **Core/Core/**
- **`Core.lua`** : Coordinateur principal refactorisé, point d'entrée minimal
- **`Addon.lua`** : Métadonnées addon, gestion des versions, comparaisons de versions
- **`DatabaseManager.lua`** : Gestion base de données, migrations, initialisation
- **`Events.lua`** : Système d'événements centralisé (actuellement ouvert dans l'éditeur)
- **`Helper.lua`** : Utilitaires communs et helpers
- **`Time.lua`** / **`Timers.lua`** : Gestion du temps et des minuteurs
- **`Serialize.lua`** : Sérialisation/désérialisation des données
- **`Debug.lua`** : Système de debug et logging
- **`HistoryManager.lua`** : Gestion de l'historique des sessions
- **`BackupManager.lua`** : Sauvegardes et restauration
- **`LotsManager.lua`** : Gestion des lots de ressources
- **`PlayersManager.lua`** : Gestion des joueurs et soldes
- **`Tiers.lua`** : Système de tiers/difficultés
- **`Legacy.lua`** : Compatibilité rétro
- **`Diagnostic.lua`** : Diagnostics et instrumentation internes

#### **Core/Comm/** - Système de communication
- **`Comm.lua`** : Orchestrateur principal de communication
- **`Serialization.lua`** : Encodage/décodage des messages
- **`DebugLogging.lua`** : Logging spécialisé pour la communication
- **`Transport.lua`** : Couche transport (canaux de communication)
- **`DataSync.lua`** : Synchronisation des données entre joueurs
- **`NetworkDiscovery.lua`** : Découverte réseau des autres utilisateurs
- **`Broadcasting.lua`** : Diffusion de messages
- **`MessageHandlers.lua`** : Gestionnaires de messages entrants
- **`Requests.lua`** : Système de requêtes/réponses
- **`ModuleLoader.lua`** : Chargement dynamique de modules
- **`RefactoringValidator.lua`** : Validation post-refactoring

#### **Core/Debug/** - Système de debug
- **`EarlyErrorHandler.lua`** : Gestion d'erreurs précoces
- **`ErrorHandler.lua`** : Gestion générale des erreurs
- **`ErrorJournal.lua`** : Journal des erreurs
- **`ErrorComm.lua`** : Communication d'erreurs

#### **Core/Player/** - Gestion des joueurs
- **`Manager.lua`** : Gestionnaire principal des joueurs
- **`Alias.lua`** : Système d'alias de joueurs
- **`Class.lua`** : Gestion des classes de personnages
- **`Name.lua`** : Normalisation et gestion des noms
- **`Status.lua`** : États des joueurs
- **`MainAlt.lua`** : Lien main/alt et regroupement des personnages

#### **Core/Game/** - Intégration WoW
- **`Affixes.lua`** : Gestion des affixes Mythique+
- **`Calendar.lua`** : Intégration calendrier WoW
- **`Spell.lua`** : Gestion des sorts

#### **Core/Group/** - Gestion des groupes
- **`Party.lua`** : Gestion des groupes de 5
- **`Raid.lua`** : Gestion des raids

#### **Core/Guild/** - Gestion de guilde
- **`Core.lua`** : Fonctionnalités core de guilde

#### **Core/Economy/** - Système économique
- **`Expenses.lua`** : Gestion des dépenses
- **`Hooks.lua`** : Hooks économiques
- **`Lots.lua`** : Gestion des lots économiques

#### **Core/Tracker/** - Système de suivi
- **`GroupTracker.lua`** : Suivi de groupe principal
- **`GroupTrackerAPI.lua`** : API publique du tracker
- **`GroupTrackerState.lua`** : État du tracker
- **`GroupTrackerSession.lua`** : Sessions de tracking
- **`GroupTrackerConsumables.lua`** : Suivi des consommables
- **`GroupTrackerEvents.lua`** : Événements du tracker
- **`GroupTrackerUI.lua`** : Interface utilisateur du tracker

#### **Core/LootTracker/** - Suivi du loot
- **`LootTracker.lua`** : Orchestrateur principal du loot tracker
- **`LootTrackerAPI.lua`** : API publique
- **`LootTrackerState.lua`** : État du loot tracker
- **`LootTrackerInstance.lua`** : Gestion des instances
- **`LootTrackerRolls.lua`** : Gestion des jets de dés
- **`LootTrackerParser.lua`** : Parsing des événements de loot

---

### 📁 **UI/** - Interface utilisateur

#### Architecture UI
- **`UI.lua`** : Système UI principal, fenêtre principale, gestion des onglets
- **`UI_Core.lua`** : Composants UI de base
- **`Layout.lua`** : Gestion des layouts
- **`Pixel.lua`** : Gestion pixel-perfect

#### Composants spécialisés
- **`UI_Scale.lua`** : Gestion de l'échelle
- **`UI_Fonts.lua`** : Système de polices
- **`UI_Colors.lua`** : Palette de couleurs
- **`UI_Skin.lua`** : Thèmes et apparence

#### Widgets
- **`UI_ListView.lua`** : Listes scrollables
- **`UI_Popup.lua`** : Fenêtres popup
- **`UI_Buttons.lua`** : Boutons personnalisés
- **`UI_Dropdown.lua`** : Menus déroulants
- **`UI_Cell.lua`** : Cellules de tableau
- **`UI_Badge.lua`** : Badges et indicateurs
- **`UI_Float.lua`** : Éléments flottants
- **`UI_PlainWindow.lua`** : Fenêtres simples
- **`UI_Slider.lua`** : Barres de défilement
- **`UI_Scrollbar.lua`** : Barres de défilement avancées
- **`UI_TokenList.lua`** : Listes de tokens
- **`UI_Toast.lua`** : Notifications toast

---

### 📁 **Tabs/** - Onglets d'interface

#### Catégories d'onglets
Les onglets sont organisés en catégories avec sidebar :

**Guilde (`cat_guild`)**
- **`Guild.lua`** : Membres de guilde, zones, statuts en ligne

**Raids (`cat_raids`)**
- **`RaidStart.lua`** : Démarrage de raids (GM uniquement)
- **`RaidHistory.lua`** : Historique des raids
- **`Resources.lua`** : Gestion des ressources et enregistrement des dépenses

**Outils (`cat_tools`)**
- **`Helpers_MythicPlus.lua`** : Rotation des affixes Mythique+
- **`Helpers_Upgrades.lua`** : Paliers d'amélioration (ilvl)
- **`Helpers_Delves.lua`** : Récompenses des Delves
- **`Helpers_Dungeons.lua`** : Donjons et paliers
- **`Helpers_Raids.lua`** : Raids et iLvl par difficulté
- **`Helpers_Crests.lua`** : Sources d'écus
- **`Helpers_GroupTracker.lua`** : Suivi de groupe

**Tracker (`cat_tracker`)**
- **`Tracker_Custom.lua`** : Suivi personnalisé
- **`Tracker_Loots.lua`** : Suivi des loots équipables

**Info (`cat_info`)**
- **`Roster.lua`** : Roster principal (renommé "Info")
- **`RosterManage.lua`** : Ajout/gestion membres
- **`Roster_MainAlt.lua`** : Vue et gestion des liens main/alt
- **`BiS.lua`** : Best in Slot
- **`Requests.lua`** : Transactions en attente (GM uniquement si demandes)

**Paramètres (`cat_settings`)**
- **`Settings.lua`** : Configuration de l'addon

**Debug (`cat_debug`)** - Conditionnel
- **`Debug_Database.lua`** : Vue de la base de données
- **`Debug_Events.lua`** : Historique des événements
- **`Debug_Errors.lua`** : Journal des erreurs
- **`Debug_Packets.lua`** : Diffusion de données/paquets

---

### 📁 **Data/** - Données statiques

- **`Players.lua`** : Gestion des données joueurs, UID, mapping
- **`Tracker.lua`** : Données de configuration du tracker
- **`Upgrades.lua`** : Tables d'amélioration d'équipement
- **`BIS_Trinkets.lua`** : Base de données des trinkets Best in Slot

---

### 📁 **Locales/** - Traductions

- **`locales-enUS.lua`** : Anglais (base)
- **`locales-frFR.lua`** : Français
- Système de traduction avec fonction `ns.Tr()`

---

### 📁 **Ressources/** - Assets

- **`Fonts/`** : Polices personnalisées
- **`Media/`** : Icônes, logos, textures
- **`Libs/`** : Bibliothèques tierces intégrées (ex. LibDeflate)

---

## Fonctionnalités principales

### 1. **Gestion de guilde**
- Suivi des membres en temps réel
- Localisation des joueurs (zones)
- Gestion des rangs et statuts
- Système d'alias pour les alts

### 2. **Système économique**
- Gestion des soldes de joueurs
- Suivi des dépenses de raid
- Gestion des lots de ressources
- Système de remboursements

### 3. **Communication réseau**
- Synchronisation automatique entre joueurs
- Compression des données (LibDeflate)
- Système de découverte réseau
- Messages typés et versionning

### 4. **Suivi d'activités**
- **LootTracker** : Suivi automatique du loot
- **GroupTracker** : Suivi des activités de groupe
- Historique des sessions de raid
- Gestion des consommables

### 5. **Outils d'aide**
- Rotation des affixes Mythique+
- Paliers d'amélioration d'équipement
- Informations sur les raids et donjons
- Sources d'écus et récompenses

### 6. **Interface utilisateur avancée**
- Système d'onglets avec catégories sidebar
- Thèmes et scaling adaptatif
- Listes scrollables optimisées
- Badges et indicateurs de statut

---

## Patterns architecturaux

### 1. **Modularité**
- Séparation claire des responsabilités
- Chargement conditionnel des modules
- APIs internes définies

### 2. **Événements**
- Bus d'événements centralisé (`Events.lua`)
- Découplage entre modules
- Hooks sur les événements WoW

### 3. **Persistance**
- Données sauvegardées par personnage
- Système de backup/restore
- Migration de schémas de données

### 4. **Communication**
- Protocole de synchronisation robuste
- Gestion des versions d'addon
- Compression et fragmentation

### 5. **Interface utilisateur**
- Composants réutilisables
- Système de thèmes
- Layouts adaptatifs

---

## Points d'extension

### Pour futurs développements
1. **Nouveaux onglets** : Utiliser `UI.RegisterTab()` avec catégorie
2. **Modules de communication** : Étendre le système de handlers
3. **Trackers personnalisés** : Utiliser l'API GroupTracker
4. **Nouvelles données** : Étendre le système de synchronisation
5. **Thèmes** : Utiliser le système UI existant

### Hooks principaux
- `ns.Events.Register()` pour les événements
- `UI.RegisterTab()` pour les onglets
- `GLOG.HandleMessage()` pour la communication
- `ns.RefreshAll()` pour le rafraîchissement UI

---

## Configuration et personnalisation

### Variables sauvegardées
- **`GuildLogisticsDB`** : Base de données principale
- **`GuildLogisticsUI_Char`** : Paramètres UI par personnage
- **`GuildLogisticsDatas_Char`** : Données par personnage
- **`GuildLogisticsDB_Backup`** : Sauvegardes
- **`GuildLogisticsDB_Previous`** : Versions précédentes

### Système de debug
- Activation via interface Settings
- Onglets de debug conditionnels
- Logging multi-niveaux
- Journal d'erreurs

---

## Conclusion

GuildLogistics est un addon complexe et bien structuré qui implémente un système complet de gestion de guilde avec communication réseau, persistance de données, et interface utilisateur riche. L'architecture modulaire facilite la maintenance et l'extension, tandis que le système de communication permet une synchronisation automatique entre les membres de la guilde équipés de l'addon.
