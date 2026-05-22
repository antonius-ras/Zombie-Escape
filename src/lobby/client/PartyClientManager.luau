local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartyClientManager = {}

local REQUEST_RF_NAME = "PartyRequestRF"
local PARTY_EVENT_RE_NAME = "PartyEventRE"

local initialized = false
local requestRF: RemoteFunction
local partyEventRE: RemoteEvent

local inviteListeners: { (any) -> () } = {}
local partyUpdateListeners: { (any) -> () } = {}
local inviteDeclinedListeners: { (any) -> () } = {}

local function emit(listeners, payload)
	for _, listener in ipairs(listeners) do
		task.spawn(listener, payload)
	end
end

local function request(action: string, payload: {[string]: any}?)
	local ok, response = pcall(function()
		return requestRF:InvokeServer(action, payload or {})
	end)
	if not ok then
		return { ok = false, message = "request_failed" }
	end
	return response
end

local function onPartyEvent(eventType: string, payload: any)
	if eventType == "InviteReceived" then
		emit(inviteListeners, payload)
		return
	end
	if eventType == "PartyUpdated" then
		emit(partyUpdateListeners, payload)
		return
	end
	if eventType == "InviteDeclined" then
		emit(inviteDeclinedListeners, payload)
	end
end

local onlineFriendsUpdateListeners: { (any) -> () } = {}
local refreshRunning = false
local FRIEND_REFRESH_INTERVAL = 45 -- แก้ไข: เพิ่มเวลาหน่วงเพื่อลดภาระเซิร์ฟเวอร์ (Scalability)

local function startOnlineFriendsRefreshLoop()
	if refreshRunning then return end
	refreshRunning = true
	
	task.spawn(function()
		while refreshRunning do
			local friends = PartyClientManager.GetOnlineFriends()
			emit(onlineFriendsUpdateListeners, friends)
			task.wait(FRIEND_REFRESH_INTERVAL)
		end
	end)
end

function PartyClientManager.Init()
	if initialized then
		return
	end

	local remotesFolder = (ReplicatedStorage :: any)
		:WaitForChild("shared")
		:WaitForChild("Remotes")

	requestRF = remotesFolder:WaitForChild(REQUEST_RF_NAME)
	partyEventRE = remotesFolder:WaitForChild(PARTY_EVENT_RE_NAME)
	partyEventRE.OnClientEvent:Connect(onPartyEvent)

	initialized = true
	
	-- เริ่มต้นลูปอัปเดตเพื่อนออนไลน์อัตโนมัติ
	startOnlineFriendsRefreshLoop()
end

function PartyClientManager.OnOnlineFriendsUpdated(listener: (any) -> ())
	table.insert(onlineFriendsUpdateListeners, listener)
end

function PartyClientManager.GetOnlineFriends()
	if not initialized then
		PartyClientManager.Init()
	end

	local response = request("GetOnlineFriends")
	if response and response.ok then
		return response.data or {}
	end
	return {}
end

function PartyClientManager.GetPartySnapshot()
	if not initialized then
		PartyClientManager.Init()
	end

	local response = request("GetParty")
	if response and response.ok then
		return response.data
	end
	return nil
end

function PartyClientManager.SendInvite(toUserId: number): (boolean, string?)
	if not initialized then
		PartyClientManager.Init()
	end

	local response = request("SendInvite", { toUserId = toUserId })
	if response and response.ok then
		return true, nil
	end
	return false, response and response.message or "send_invite_failed"
end

function PartyClientManager.RespondInvite(inviteId: string, accept: boolean): (boolean, string?, any)
	if not initialized then
		PartyClientManager.Init()
	end

	local response = request("RespondInvite", {
		inviteId = inviteId,
		accept = accept,
	})

	if response and response.ok then
		return true, nil, response.data
	end

	return false, response and response.message or "respond_invite_failed", nil
end

function PartyClientManager.LeaveParty(): (boolean, string?, any)
	if not initialized then
		PartyClientManager.Init()
	end

	local response = request("LeaveParty")
	if response and response.ok then
		return true, nil, response.data
	end

	return false, response and response.message or "leave_party_failed", nil
end

function PartyClientManager.KickMember(targetUserId: number): (boolean, string?, any)
	if not initialized then
		PartyClientManager.Init()
	end

	local response = request("KickMember", { targetUserId = targetUserId })
	if response and response.ok then
		return true, nil, response.data
	end

	return false, response and response.message or "kick_member_failed", nil
end

function PartyClientManager.DisbandParty(): (boolean, string?, any)
	if not initialized then
		PartyClientManager.Init()
	end

	local response = request("DisbandParty")
	if response and response.ok then
		return true, nil, response.data
	end

	return false, response and response.message or "disband_party_failed", nil
end

function PartyClientManager.OnInviteReceived(listener: (any) -> ())
	table.insert(inviteListeners, listener)
end

function PartyClientManager.OnPartyUpdated(listener: (any) -> ())
	table.insert(partyUpdateListeners, listener)
end

function PartyClientManager.OnInviteDeclined(listener: (any) -> ())
	table.insert(inviteDeclinedListeners, listener)
end

function PartyClientManager.GetLocalUserId(): number
	return Players.LocalPlayer.UserId
end

return PartyClientManager
