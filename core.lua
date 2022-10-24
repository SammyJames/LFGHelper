--- LFGHelper - prunes locked activities from the LFG window
-- @author: Sammy James
-- @copyright: MIT

local ADDON_NAME  = ...
local ADDON_TITLE = select(2, GetAddOnInfo(ADDON_NAME))
local C_LFGList   = C_LFGList

local LFGHelper = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0",
	"AceHook-3.0")
LFGHelper.m_Lockouts = {}

local function StringHash(text)
	local counter = 1
	local len = string.len(text)
	for i = 1, len, 3 do
		counter = math.fmod(counter * 8161, 4294967279) + -- 2^32 - 17: Prime!
			(string.byte(text, i) * 16776193) +
			((string.byte(text, i + 1) or (len - i + 256)) * 8372226) +
			((string.byte(text, i + 2) or (len - i + 256)) * 3932164)
	end
	return math.fmod(counter, 4294967291) -- 2^32 - 5: Prime (and different from the prime in the loop)
end

local function MakeKey(name, max_players, heroic)
	return StringHash(name .. max_players .. tostring(heroic))
end

function LFGHelper:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
	self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnUpdateInstanceInfo")
	self:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE", "OnLfgAvailable")
	self:ScheduleRepeatingTimer("UpdateLockoutData", 60)

	self:RawHook("LFGListingActivityView_UpdateActivities", true)

	self:UpdateLockoutData()
	self:BuildLookupTable()
end

function LFGHelper:OnDisable()
	self:CancelAllTimers()
end

function LFGHelper:OnEnteringWorld(_, ...)
	self:UpdateLockoutData()
end

function LFGHelper:OnUpdateInstanceInfo(_, ...)
	self:UpdateLockoutData()
end

function LFGHelper:OnLfgAvailable(_)
	self:BuildLookupTable()
end

function LFGHelper:UpdateLockoutData()
	self.m_Lockouts = {}

	local num_saved = GetNumSavedInstances()

	for i = 1, num_saved do
		local name, id, _, _, _, _, _, is_raid, max_players, _, _, _, _ = GetSavedInstanceInfo(i)
		-- treat any saved instance that isn't a raid as a heroic dungeon for now
		local key = MakeKey(name, max_players, not is_raid)
		self.m_Lockouts[key] = id
	end
end

function LFGHelper:BuildLookupTable()
	self.m_LookupTable        = {}
	self.m_ReverseLookupTable = {}

	local activity_handler = function(self, activity_id, heroic)
		local info = C_LFGList.GetActivityInfoTable(activity_id);
		local name = info.shortName ~= "" and info.shortName or info.fullName;

		local key                       = MakeKey(name, info.maxNumPlayers, heroic)
		self.m_LookupTable[activity_id] = key
		self.m_ReverseLookupTable[key]  = activity_id
	end

	local categories = C_LFGList.GetAvailableCategories()
	for _, category_id in ipairs(categories) do
		do
			local activities = C_LFGList.GetAvailableActivities(category_id, 0);

			if #activities > 0 then
				for _, activity_id in ipairs(activities) do
					activity_handler(self, activity_id, false)
				end
			end
		end


		local activity_groups = C_LFGList.GetAvailableActivityGroups(category_id);

		for _, group_id in ipairs(activity_groups) do
			local activities = C_LFGList.GetAvailableActivities(category_id, group_id);

			if #activities > 0 then
				local name, order_index = C_LFGList.GetActivityGroupInfo(group_id);
				for _, activity_id in ipairs(activities) do
					activity_handler(self, activity_id, order_index == 2)
				end
			end
		end
	end
end

function LFGHelper:LFGListingActivityView_UpdateActivities(widget, category_id)
	self.hooks.LFGListingActivityView_UpdateActivities(widget, category_id)

	local to_remove = {}
	local dp        = widget.ScrollBox:GetDataProvider()
	dp:ForEach(function(node)
		local data = node:GetData()

		if data.buttonType == 2 then
			local key = self.m_LookupTable[data.activityID]
			if self.m_Lockouts[key] then
				table.insert(to_remove, node)
			end
		end
	end)

	local node_remove = function(parent, child)
		for index, node2 in ipairs(parent.nodes) do
			if node2 == child then
				local removed = table.remove(parent.nodes, index);
				parent:Invalidate();
				return removed;
			end
		end
	end

	local dp_remove = function(dp, node)
		local index, node2 = dp:FindIndex(node);
		if node2 then
			local parent = node2.parent;
			assert(parent ~= nil);
			if parent then
				node_remove(parent, node)
			end
		end
	end

	for _, v in pairs(to_remove) do
		dp_remove(dp, v)
	end

	dp:Invalidate()
	widget.ScrollBox:FullUpdate(true)
end
