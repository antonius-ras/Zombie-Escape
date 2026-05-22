local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QueueConfig = require((ReplicatedStorage :: any).shared:WaitForChild("QueueConfig"))

local QueueManager = {}

local requestEvent: RemoteEvent
local statusEvent: RemoteEvent

local initialized = false
local queueToken = 0
local isQueueing = false
local awaitingTeleport = false
local isPartyQueueing = false
local isPartyTeleporting = false
local partyQueueSecondsLeft = 0
local partyQueueListeners: { (string, number?, string?) -> () } = {}

local pendingFailureCallback: ((string?) -> ())?

local function emitPartyStatus(status: string, secondsLeft: number?, message: string?)
	for _, listener in ipairs(partyQueueListeners) do
		task.spawn(listener, status, secondsLeft, message)
	end
end

local function onStatusEvent(status: string, value: any?)
	if status == "failed" then
		awaitingTeleport = false
		if pendingFailureCallback then
			pendingFailureCallback(if type(value) == "string" then value else nil)
		end
		return
	end

	if status == "party_queue_started" then
		isPartyQueueing = true
		isPartyTeleporting = false
		partyQueueSecondsLeft = if type(value) == "number" then value else 0
		emitPartyStatus("started", partyQueueSecondsLeft, nil)
		return
	end

	if status == "party_queue_tick" then
		isPartyQueueing = true
		partyQueueSecondsLeft = if type(value) == "number" then value else 0
		emitPartyStatus("tick", partyQueueSecondsLeft, nil)
		return
	end

	if status == "party_queue_teleporting" then
		isPartyQueueing = false
		isPartyTeleporting = true
		partyQueueSecondsLeft = 0
		emitPartyStatus("teleporting", nil, nil)
		return
	end

	if status == "party_queue_cancelled" then
		isPartyQueueing = false
		isPartyTeleporting = false
		partyQueueSecondsLeft = 0
		emitPartyStatus("cancelled", nil, if type(value) == "string" then value else nil)
		return
	end

	if status == "party_queue_failed" then
		isPartyQueueing = false
		isPartyTeleporting = false
		partyQueueSecondsLeft = 0
		emitPartyStatus("failed", nil, if type(value) == "string" then value else nil)
	end
end

function QueueManager.Init()
	if initialized then
		return
	end

	local remotesFolder = (ReplicatedStorage :: any)
		:WaitForChild("shared")
		:WaitForChild("Remotes")

	requestEvent = remotesFolder:WaitForChild("QueueTeleportRequest")
	statusEvent = remotesFolder:WaitForChild("QueueTeleportStatus")
	statusEvent.OnClientEvent:Connect(onStatusEvent)

	initialized = true
end

function QueueManager.StartSoloQueue(options: {
	seconds: number?,
	onTick: ((number) -> ())?,
	onDispatch: (() -> ())?,
	onTeleportFailed: ((string?) -> ())?,
}): boolean
	if not initialized then
		QueueManager.Init()
	end

	if isQueueing or awaitingTeleport then
		return false
	end

	local secondsLeft = options.seconds or QueueConfig.SoloCountdownSeconds
	local onTick = options.onTick
	local onDispatch = options.onDispatch
	pendingFailureCallback = options.onTeleportFailed

	queueToken += 1
	local token = queueToken
	isQueueing = true

	if onTick then
		onTick(secondsLeft)
	end

	task.spawn(function()
		local remaining = secondsLeft
		while remaining > 0 do
			task.wait(1)
			if token ~= queueToken or not isQueueing then
				return
			end
			remaining -= 1
			if onTick then
				onTick(remaining)
			end
		end

		if token ~= queueToken or not isQueueing then
			return
		end

		isQueueing = false
		awaitingTeleport = true

		if onDispatch then
			onDispatch()
		end

		requestEvent:FireServer("solo")
	end)

	return true
end

function QueueManager.CancelSoloQueue(): boolean
	if not isQueueing then
		return false
	end

	queueToken += 1
	isQueueing = false
	return true
end

function QueueManager.StartPartyQueue(): boolean
	if not initialized then
		QueueManager.Init()
	end

	if isQueueing or awaitingTeleport or isPartyQueueing or isPartyTeleporting then
		return false
	end

	requestEvent:FireServer("party_start")
	return true
end

function QueueManager.CancelPartyQueue(): boolean
	if not initialized then
		QueueManager.Init()
	end

	if not isPartyQueueing and not isPartyTeleporting then
		return false
	end

	requestEvent:FireServer("party_cancel")
	return true
end

function QueueManager.OnPartyQueueStatus(listener: (string, number?, string?) -> ())
	table.insert(partyQueueListeners, listener)
end

function QueueManager.GetPartyQueueState(): (boolean, boolean, number)
	return isPartyQueueing, isPartyTeleporting, partyQueueSecondsLeft
end

function QueueManager.IsBusy(): boolean
	return isQueueing or awaitingTeleport or isPartyQueueing or isPartyTeleporting
end

function QueueManager.GetQueueLabel(secondsLeft: number): string
	return string.format("%s (%ds)", QueueConfig.CancelQueueLabel, secondsLeft)
end

function QueueManager.GetTeleportingLabel(): string
	return QueueConfig.TeleportingLabel
end

function QueueManager.GetDefaultPlayLabel(): string
	return QueueConfig.DefaultPlayLabel
end

return QueueManager
