local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG, U = ns.GLOG, ns.Util

-- Wrappers de compatibilité pour anciens appels GLOG.* (UID/Roster)
GLOG.GetOrAssignUID   = GLOG.GetOrAssignUID    or U.GetOrAssignUID
GLOG.GetNameByUID     = GLOG.GetNameByUID      or U.GetNameByUID
GLOG.MapUID           = GLOG.MapUID            or U.MapUID
GLOG.UnmapUID         = GLOG.UnmapUID          or U.UnmapUID
GLOG.EnsureRosterLocal= GLOG.EnsureRosterLocal or U.EnsureRosterLocal
GLOG.FindUIDByName    = GLOG.FindUIDByName     or U.FindUIDByName
GLOG.GetUID           = GLOG.GetUID            or U.FindUIDByName
