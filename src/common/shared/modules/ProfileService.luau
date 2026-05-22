-- Lightweight ProfileService-compatible wrapper used by DataManager.
-- Provides a subset of the API used in this project.

local DataStoreService = game:GetService("DataStoreService")

local ProfileService = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, item in pairs(value) do
		copy[key] = deepCopy(item)
	end

	return copy
end

local function reconcileTable(target, template)
	for key, templateValue in pairs(template) do
		if target[key] == nil then
			target[key] = deepCopy(templateValue)
		elseif type(templateValue) == "table" and type(target[key]) == "table" then
			reconcileTable(target[key], templateValue)
		end
	end
end

function ProfileService.GetProfileStore(storeName: string, profileTemplate: table)
	local dataStore = DataStoreService:GetDataStore(storeName)

	local profileStore = {}

	function profileStore:LoadProfileAsync(profileKey: string)
		local success, loadedData = pcall(function()
			return dataStore:GetAsync(profileKey)
		end)

		local profileData
		if success and type(loadedData) == "table" then
			profileData = loadedData
		else
			profileData = deepCopy(profileTemplate)
		end

		local releaseListeners = {}
		local released = false

		local profile = {
			Data = profileData,
		}

		function profile.AddUserId(_self, _userId: number)
			-- no-op for lightweight wrapper
		end

		function profile.Reconcile(_profile)
			reconcileTable(_profile.Data, profileTemplate)
		end

		function profile.ListenToRelease(_self, listener)
			table.insert(releaseListeners, listener)
			local disconnected = false

			return {
				Disconnect = function()
					if disconnected then
						return
					end
					disconnected = true
					for index, registeredListener in ipairs(releaseListeners) do
						if registeredListener == listener then
							table.remove(releaseListeners, index)
							break
						end
					end
				end,
			}
		end

		function profile.Release(_profile)
			if released then
				return
			end
			released = true

			local savePayload = deepCopy(_profile.Data)
			pcall(function()
				dataStore:SetAsync(profileKey, savePayload)
			end)

			for _, listener in ipairs(releaseListeners) do
				task.spawn(listener)
			end
		end

		return profile
	end

	return profileStore
end

return ProfileService
