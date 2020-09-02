local initialised = false
local playerServerId = GetPlayerServerId(PlayerId())
local unmutedPlayers = {}
local gridTargets = {}
local radioTargets = {}
local callTargets = {}
local speakerTargets = {}
local nearbySpeakerTargets = {}
local playerChunk = nil
local voiceTarget = 2

-- Functions
function SetVoiceData(key, value, target)
	TriggerServerEvent("mumble:SetVoiceData", key, value, target)
end

function PlayMicClick(channel, value)
	if channel <= mumbleConfig.radioClickMaxChannel then
		if mumbleConfig.micClicks then
			if (value and mumbleConfig.micClickOn) or (not value and mumbleConfig.micClickOff) then
				SendNUIMessage({ sound = (value and "audio_on" or "audio_off"), volume = mumbleConfig.micClickVolume })
			end
		end
	end
end

function SetGridTargets(pos, reset) -- Used to set the players voice targets depending on where they are in the map
	local currentChunk = GetCurrentChunk(pos)
	local nearbyChunks = GetNearbyChunks(pos)
	local nearbyChunksStr = "None"
	local targets = {}
	local playerData = voiceData[playerServerId]

	if not playerData then
		playerData  = {
			mode = 2,
			radio = 0,
			radioActive = false,
			call = 0,
			callSpeaker = false,
		}
	end

	for i = 1, #nearbyChunks do
		if nearbyChunks[i] ~= currentChunk then
			targets[nearbyChunks[i]] = true

			if gridTargets[nearbyChunks[i]] then
				gridTargets[nearbyChunks[i]] = nil
			end

			if nearbyChunksStr ~= "None" then
				nearbyChunksStr = nearbyChunksStr .. ", " .. nearbyChunks[i]
			else
				nearbyChunksStr = nearbyChunks[i]
			end
		end
	end

	local newGridTargets = false

	for channel, exists in pairs(gridTargets) do
		if exists then
			newGridTargets = true
			break
		end
	end

	if reset then
		MumbleClearVoiceTarget(voiceTarget) -- Reset voice target
		MumbleSetVoiceTarget(voiceTarget)
		NetworkSetTalkerProximity(mumbleConfig.voiceModes[playerData.mode][1] + 0.0) -- Set voice proximity
	end

	if playerChunk ~= currentChunk or newGridTargets or reset then -- Only reset target channels if the current chunk or any nearby chunks have changed
		MumbleClearVoiceTargetChannels(voiceTarget)

		MumbleAddVoiceTargetChannel(voiceTarget, currentChunk)

		for channel, _ in pairs(targets) do
			MumbleAddVoiceTargetChannel(voiceTarget, channel)
		end

		NetworkSetVoiceChannel(currentChunk)

		playerChunk = currentChunk
		gridTargets = targets

		DebugMsg("Current Chunk: " .. currentChunk .. ", Nearby Chunks: " .. nearbyChunksStr)

		if reset then
			SetPlayerTargets(callTargets, speakerTargets, playerData.radioActive and radioTargets or nil)
		end
	end
end

function SetPlayerTargets(...)	
	local targets = { ... }
	local targetList = ""
	local addedTargets = {}
	
	MumbleClearVoiceTargetPlayers(voiceTarget)

	for i = 1, #targets do
		for id, _ in pairs(targets[i]) do
			if not addedTargets[id] then
				MumbleAddVoiceTargetPlayerByServerId(voiceTarget, id)

				if targetList == "" then
					targetList = targetList .. id
				else
					targetList = targetList .. ", " .. id
				end

				addedTargets[id] = true
			end
		end
	end

	if targetList ~= "" then
		DebugMsg("Sending voice to Player " .. targetList)
	else
		DebugMsg("Sending voice to Nobody")
	end
end

function TogglePlayerVoice(serverId, value)
	DebugMsg((value and "Unmuting" or "Muting") .. " Player " .. serverId)
	if value then
		if not unmutedPlayers[serverId] then
			unmutedPlayers[serverId] = true
			MumbleSetVolumeOverrideByServerId(serverId, 1.0)
		end
	else
		if unmutedPlayers[serverId] then
			unmutedPlayers[serverId] = nil
			MumbleSetVolumeOverrideByServerId(serverId, -1.0)			
		end		
	end
end

function SetRadioChannel(channel)
	local channel = tonumber(channel)

	if channel ~= nil then
		SetVoiceData("radio", channel)

		if radioData[channel] then -- Check if anyone is talking and unmute if so
			for id, _ in pairs(radioData[channel]) do
				if id ~= playerServerId then					
					if not unmutedPlayers[id] then
						local playerData = voiceData[id]

						if playerData ~= nil then
							if playerData.radioActive then
								TogglePlayerVoice(id, true)
							end
						end
					end
				end
			end
		end
	end
end

function SetCallChannel(channel)
	local channel = tonumber(channel)

	if channel ~= nil then
		SetVoiceData("call", channel)

		if callData[channel] then -- Unmute current call participants
			for id, _ in pairs(callData[channel]) do
				if id ~= playerServerId then
					if not unmutedPlayers[id] then
						TogglePlayerVoice(id, true)
					end
				end
			end
		end
	end
end

function CheckVoiceSetting(varName, msg)
	local setting = GetConvarInt(varName, -1)

	if setting == 0 then
		SendNUIMessage({ warningId = varName, warningMsg = msg })

		Citizen.CreateThread(function()
			local varName = varName
			while GetConvarInt(varName, -1) == 0 do
				Citizen.Wait(1000)
			end

			SendNUIMessage({ warningId = varName })
		end)
	end

	DebugMsg("Checking setting: " .. varName .. " = " .. setting)

	return setting == 1
end

function CompareChannels(playerData, type, channel)
	local match = false

	if playerData[type] ~= nil then
		if playerData[type] == channel then
			match = true
		end
	end

	return match
end

-- Events
AddEventHandler("onClientResourceStart", function(resName) -- Initialises the script, sets up voice range, voice targets and request sync with server
	if GetCurrentResourceName() ~= resName then
		return
	end

	DebugMsg("Initialising")

	Citizen.Wait(2500)

	if mumbleConfig.useExternalServer then
		MumbleSetServerAddress(mumbleConfig.externalAddress, mumbleConfig.externalPort)
	end

	CheckVoiceSetting("profile_voiceEnable", "Voice chat disabled")
	CheckVoiceSetting("profile_voiceTalkEnabled", "Microphone disabled")

	if not MumbleIsConnected() then
		SendNUIMessage({ warningId = "mumble_is_connected", warningMsg = "Not connected to mumble" })

		while not MumbleIsConnected() do
			Citizen.Wait(250)
		end

		SendNUIMessage({ warningId = "mumble_is_connected" })
	end

	voiceData[playerServerId] = {
		mode = 2,
		radio = 0,
		radioActive = false,
		call = 0,
		callSpeaker = false,
		speakerTargets = {},
	}

	SetGridTargets(GetEntityCoords(PlayerPedId()), true) -- Add voice targets

	TriggerServerEvent("mumble:Initialise")

	SendNUIMessage({ speakerOption = mumbleConfig.callSpeakerEnabled })

	TriggerEvent("mumble:Initialised")

	initialised = true
end)

RegisterNetEvent("mumble:SetVoiceData") -- Used to sync players data each time something changes
AddEventHandler("mumble:SetVoiceData", function(player, key, value)
	if not voiceData[player] then
		voiceData[player] = {
			mode = 2,
			radio = 0,
			radioActive = false,
			call = 0,
			callSpeaker = false,
			speakerTargets = {},
		}
	end

	local radioChannel = voiceData[player]["radio"]
	local callChannel = voiceData[player]["call"]
	local radioActive = voiceData[player]["radioActive"]
	local playerData = voiceData[playerServerId]

	if not playerData then
		playerData = {
			mode = 2,
			radio = 0,
			radioActive = false,
			call = 0,
			callSpeaker = false,
			speakerTargets = {},
		}
	end

	if key == "radio" and radioChannel ~= value then -- Check if channel has changed
		if radioChannel > 0 then -- Check if player was in a radio channel
			if radioData[radioChannel] then  -- Remove player from radio channel
				if radioData[radioChannel][player] then
					DebugMsg("Player " .. player .. " was removed from radio channel " .. radioChannel)
					radioData[radioChannel][player] = nil

					if CompareChannels(playerData, "radio", radioChannel) then
						if playerServerId ~= player then
							if unmutedPlayers[player] then
								if playerData.call > 0 then -- Check if the client is in a call
									if not CompareChannels(voiceData[player], "call", playerData.call) then -- Check if the client is in a call with the unmuted player
										TogglePlayerVoice(player, false)
									end
								else
									TogglePlayerVoice(player, false) -- mute player on radio channel leave
								end
							end

							if radioTargets[player] then
								radioTargets[player] = nil
							end
						elseif playerServerId == player then
							for id, _ in pairs(radioData[radioChannel]) do -- Mute players that aren't supposed to be unmuted
								if id ~= playerServerId then
									if unmutedPlayers[id] then -- Check if a player isn't muted
										if playerData.call > 0 then -- Check if the client is in a call
											if not CompareChannels(voiceData[id], "call", playerData.call) then -- Check if the client is in a call with the unmuted player
												TogglePlayerVoice(id, false)
											end
										else
											if unmutedPlayers[id] then
												TogglePlayerVoice(id, false)
											end
										end
									end
								end
							end
							
							radioTargets = {} -- Remove all radio targets as client has left the radio channel

							if playerData.radioActive then
								SetPlayerTargets(callTargets, speakerTargets) -- Reset active targets if for some reason if the client was talking on the radio when the client left
							end
						end
					end
				end
			end
		end

		if value > 0 then
			if not radioData[value] then -- Create channel if it does not exist
				DebugMsg("Player " .. player .. " is creating channel: " .. value)
				radioData[value] = {}
			end
			
			DebugMsg("Player " .. player .. " was added to channel: " .. value)
			radioData[value][player] = true -- Add player to channel

			if CompareChannels(playerData, "radio", value) then
				if playerServerId ~= player then
					if not radioTargets[player] then
						radioTargets[player] = true							
						
						if playerData.radioActive then
							SetPlayerTargets(callTargets, speakerTargets, radioTargets)
						end
					end
				end
			end

			if playerServerId == player then
				for id, _ in pairs(radioData[value]) do -- Add radio targets of existing players in channel
					if id ~= playerServerId then
						if not radioTargets[id] then
							radioTargets[id] = true
						end
					end
				end
			end
		end
	elseif key == "call" and callChannel ~= value then
		if callChannel > 0 then -- Check if player was in a call channel
			if callData[callChannel] then  -- Remove player from call channel
				if callData[callChannel][player] then
					DebugMsg("Player " .. player .. " was removed from call channel " .. callChannel)
					callData[callChannel][player] = nil

					if CompareChannels(playerData, "call", callChannel) then
						if playerServerId ~= player then
							if unmutedPlayers[player] then
								if playerData.radio > 0 then -- Check if the client is in a call
									if not CompareChannels(voiceData[player], "radio", playerData.radio) then -- Check if the client is in a call with the unmuted player
										TogglePlayerVoice(player, false)
									end
								else
									TogglePlayerVoice(player, false) -- mute player on radio channel leave
								end
							end

							if callTargets[player] then
								callTargets[player] = nil
								SetPlayerTargets(callTargets, speakerTargets, playerData.radioActive and radioTargets or nil)
							end
						elseif playerServerId == player then
							for id, _ in pairs(callData[callChannel]) do -- Mute players that aren't supposed to be unmuted
								if id ~= playerServerId then
									if unmutedPlayers[id] then -- Check if a player isn't muted
										if playerData.radio > 0 then -- Check if the client is in a radio channel
											if not CompareChannels(voiceData[id], "radio", playerData.radio) then -- Check if the client isn't in the radio channel with the unmuted player
												TogglePlayerVoice(id, false)
											else -- Client is in the same radio channel with unmuted player
												if voiceData[id] ~= nil then
													if not voiceData[id].radioActive then -- Check if the unmuted player isn't talking
														TogglePlayerVoice(id, false)
													end
												end
											end
										else
											if unmutedPlayers[id] then
												TogglePlayerVoice(id, false)
											end
										end
									end
								end
							end
							
							callTargets = {} -- Remove all call targets as client has left the call

							SetPlayerTargets(callTargets, speakerTargets, playerData.radioActive and radioTargets or nil) -- Reset player targets
						end
					end
				end
			end
		end

		if value > 0 then
			if not callData[value] then -- Create call if it does not exist
				DebugMsg("Player " .. player .. " is creating call: " .. value)
				callData[value] = {}
			end
			
			DebugMsg("Player " .. player .. " was added to call: " .. value)
			callData[value][player] = true -- Add player to call

			if CompareChannels(playerData, "call", value) then
				if playerServerId ~= player then
					TogglePlayerVoice(player, value)

					if not callTargets[player] then
						callTargets[player] = true
						SetPlayerTargets(callTargets, speakerTargets, playerData.radioActive and radioTargets or nil)
					end
				end
			end
			
			if playerServerId == player then
				for id, _ in pairs(callData[value]) do
					if id ~= playerServerId then
						if not unmutedPlayers[id] then
							TogglePlayerVoice(id, true)
						end

						if not callTargets[id] then
							callTargets[id] = true
							SetPlayerTargets(callTargets, speakerTargets, playerData.radioActive and radioTargets or nil)
						end
					end
				end
			end
		end
	elseif key == "radioActive" and radioActive ~= value then
		DebugMsg("Player " .. player .. " radio talking state was changed from: " .. tostring(radioActive):upper() .. " to: " .. tostring(value):upper())
		if radioChannel > 0 then
			if CompareChannels(playerData, "radio", radioChannel) then -- Check if player is in the same radio channel as you
				if playerServerId ~= player then
					TogglePlayerVoice(player, value) -- unmute/mute player
					PlayMicClick(radioChannel, value) -- play on/off clicks
				end
			end
		end
	elseif key == "speakerTargets" then
		local speakerTargetsRemoved = false
		local speakerTargetsAdded = {}

		for id, _ in pairs(value) do
			if voiceData[player] ~= nil then
				if voiceData[player][key] ~= nil then
					if voiceData[player][key][id] then
						voiceData[player][key][id] = nil
					else
						if playerServerId == id then -- Check if the client is gonna hear a nearby call
							TogglePlayerVoice(player, true) -- Unmute
						end

						if playerServerId == player then -- Check if the client is a paricipant in the phone call whose voice is heard through the speaker
							if not speakerTargets[id] then -- Send voice to player
								speakerTargets[id] = true
								speakerTargetsAdded[#speakerTargetsAdded + 1] = id
							end
						end
					end
				end
			end
		end

		if voiceData[player] ~= nil then
			if voiceData[player][key] ~= nil then
				for id, _ in pairs(voiceData[player][key]) do
					if playerServerId == id then -- Check if the client has been removed from a nearby call
						TogglePlayerVoice(player, false) -- Mute
					end

					if playerServerId == player then -- Check if the client is a paricipant in the phone call whose voice is heard through the speaker
						if speakerTargets[id] then -- Stop sending voice to player
							speakerTargets[id] = nil
							speakerTargetsRemoved = true
						end
					end	
				end
			end
		end

		if speakerTargetsRemoved or #speakerTargetsAdded > 0 then
			SetPlayerTargets(callTargets, speakerTargets, playerData.radioActive and radioTargets or nil)
		end
	elseif key == "callSpeaker" and not value then
		if voiceData[player] ~= nil then
			if voiceData[player].call ~= nil then
				if voiceData[player].call > 0  then
					if callData[voiceData[player].call] ~= nil then -- Check if the call exists
						for id, _ in pairs(callData[voiceData[player].call]) do -- Loop through each call participant
							if voiceData[id] ~= nil then
								if voiceData[id].speakerTargets ~= nil then
									local speakerTargetsRemoved = false

									for targetId, _ in pairs(voiceData[id].speakerTargets) do -- Loop through each call participants speaker targets
										if playerServerId == targetId then -- Check if the client was a target and mute the call
											TogglePlayerVoice(id, false) -- Mute
										end

										if playerServerId == id then -- Check if the client is a paricipant in the phone call whose voice is heard through the speaker
											if speakerTargets[targetId] then -- Stop sending voice to player
												speakerTargets[targetId] = nil
												speakerTargetsRemoved = true
											end
										end	
									end

									if speakerTargetsRemoved then
										SetPlayerTargets(callTargets, speakerTargets, playerData.radioActive and radioTargets or nil)
									end
								end
							end
						end
					end
				end
			end 
		end
	end

	voiceData[player][key] = value

	DebugMsg("Player " .. player .. " changed " .. key .. " to: " .. tostring(value))
end)

RegisterNetEvent("mumble:SyncVoiceData") -- Used to sync players data on initialising
AddEventHandler("mumble:SyncVoiceData", function(voice, radio, call)
	voiceData = voice
	radioData = radio
	callData = call
end)

RegisterNetEvent("mumble:RemoveVoiceData") -- Used to remove redundant data when a player disconnects
AddEventHandler("mumble:RemoveVoiceData", function(player)
	if voiceData[player] then
		local radioChannel = voiceData[player]["radio"] or 0
		local callChannel = voiceData[player]["call"] or 0

		if radioChannel > 0 then -- Check if player was in a radio channel
			if radioData[radioChannel] then  -- Remove player from radio channel
				if radioData[radioChannel][player] then
					DebugMsg("Player " .. player .. " was removed from radio channel " .. radioChannel)
					radioData[radioChannel][player] = nil
				end
			end
		end

		if callChannel > 0 then -- Check if player was in a call channel
			if callData[callChannel] then  -- Remove player from call channel
				if callData[callChannel][player] then
					DebugMsg("Player " .. player .. " was removed from call channel " .. callChannel)
					callData[callChannel][player] = nil
				end
			end
		end

		if radioTargets[player] or callTargets[player] or speakerTargets[player] then
			local playerData = voiceData[playerServerId]

			if not playerData then
				playerData = {
					mode = 2,
					radio = 0,
					radioActive = false,
					call = 0,
					callSpeaker = false,
					speakerTargets = {},
				}
			end

			radioTargets[player] = nil
			callTargets[player] = nil
			speakerTargets[player] = nil

			SetPlayerTargets(callTargets, speakerTargets, playerData.radioActive and radioTargets or nil)
		end

		voiceData[player] = nil
	end
end)

-- Simulate PTT when radio is active
Citizen.CreateThread(function()
	while true do
		Citizen.Wait(0)

		if initialised then
			local playerData = voiceData[playerServerId]

			if not playerData then
				playerData = {
					mode = 2,
					radio = 0,
					radioActive = false,
					call = 0,
					callSpeaker = false,
					speakerTargets = {},
				}
			end

			if playerData.radioActive then -- Force PTT enabled
				SetControlNormal(0, 249, 1.0)
				SetControlNormal(1, 249, 1.0)
				SetControlNormal(2, 249, 1.0)
			end

			if IsControlJustPressed(0, mumbleConfig.controls.proximity.key) then
				if mumbleConfig.controls.speaker.key ~= mumbleConfig.controls.proximity.key or ((not mumbleConfig.controls.speaker.secondary == nil) and IsControlPressed(0, mumbleConfig.controls.speaker.secondary) or true) then
					local voiceMode = playerData.mode
				
					local newMode = voiceMode + 1
				
					if newMode > #mumbleConfig.voiceModes then
						voiceMode = 1
					else
						voiceMode = newMode
					end
					
					NetworkSetTalkerProximity(mumbleConfig.voiceModes[voiceMode][1] + 0.0)

					SetVoiceData("mode", voiceMode)
					playerData.mode = voiceMode
				end
			end

			if mumbleConfig.radioEnabled then
				if not mumbleConfig.controls.radio.pressed then
					if IsControlJustPressed(0, mumbleConfig.controls.radio.key) then
						if playerRadio > 0 then
							SetVoiceData("radioActive", true)
							playerData.radioActive = true
							SetPlayerTargets(callTargets, speakerTargets, radioTargets) -- Send voice to everyone in the radio and call
							PlayMicClick(playerRadio, true)
							mumbleConfig.controls.radio.pressed = true

							Citizen.CreateThread(function()
								while IsControlPressed(0, mumbleConfig.controls.radio.key) do
									Citizen.Wait(0)
								end

								SetVoiceData("radioActive", false)
								SetPlayerTargets(callTargets, speakerTargets) -- Stop sending voice to everyone in the radio
								PlayMicClick(playerRadio, false)
								playerData.radioActive = false
								mumbleConfig.controls.radio.pressed = false
							end)
						end
					end
				end
			else
				if playerData.radioActive then
					SetVoiceData("radioActive", false)
					playerData.radioActive = false
				end
			end

			if mumbleConfig.callSpeakerEnabled then
				if ((not mumbleConfig.controls.speaker.secondary == nil) and IsControlPressed(0, mumbleConfig.controls.speaker.secondary) or true) then
					if IsControlJustPressed(0, mumbleConfig.controls.speaker.key) then
						if playerCall > 0 then
							SetVoiceData("callSpeaker", not playerData.callSpeaker)
							playerData.callSpeaker = not playerData.callSpeaker
						end
					end
				end
			end
		end
	end
end)

-- UI
Citizen.CreateThread(function()
	while true do
		if initialised then
			local playerId = PlayerId()
			local playerData = voiceData[playerServerId]
			local playerTalking = NetworkIsPlayerTalking(playerId)
			local playerMode = 2
			local playerRadio = 0
			local playerRadioActive = false
			local playerCall = 0
			local playerCallSpeaker = false

			if playerData ~= nil then
				playerMode = playerData.mode or 2
				playerRadio = playerData.radio or 0
				playerRadioActive = playerData.radioActive or false
				playerCall = playerData.call or 0
				playerCallSpeaker = playerData.callSpeaker or false
			end

			-- Update UI
			SendNUIMessage({
				talking = playerTalking,
				mode = mumbleConfig.voiceModes[playerMode][2],
				radio = mumbleConfig.radioChannelNames[playerRadio] ~= nil and mumbleConfig.radioChannelNames[playerRadio] or playerRadio,
				radioActive = playerRadioActive,
				call = mumbleConfig.callChannelNames[playerCall] ~= nil and mumbleConfig.callChannelNames[playerCall] or playerCall,
				speaker = playerCallSpeaker,
			})

			Citizen.Wait(200)
		else
			Citizen.Wait(0)
		end
	end
end)

-- Manage Grid Target Channels
Citizen.CreateThread(function()
	local resetTargets = false
	while true do
		if initialised then
			if not MumbleIsConnected() then
				SendNUIMessage({ warningId = "mumble_is_connected", warningMsg = "Not connected to mumble" })

				while not MumbleIsConnected() do
					Citizen.Wait(250)
				end

				SendNUIMessage({ warningId = "mumble_is_connected" })

				resetTargets = true
			elseif resetTargets then
				resetTargets = false
			end

			local playerPed = PlayerPedId()
			local playerCoords = GetEntityCoords(playerPed)
			
			SetGridTargets(playerCoords, resetTargets)

			Citizen.Wait(2500)
		else
			Citizen.Wait(0)
		end
	end
end)

-- Manage hearing nearby players on call
Citizen.CreateThread(function()
	while true do
		if initialised then
			if mumbleConfig.callSpeakerEnabled then
				local playerData = voiceData[playerServerId]

				if not playerData then
					playerData  = {
						mode = 2,
						radio = 0,
						radioActive = false,
						call = 0,
						callSpeaker = false,
					}
				end
				
				if playerData.call > 0 then -- Check if player is in call
					if playerData.callSpeaker then -- Check if they have loud speaker on
						local playerId = PlayerId()
						local playerPed = PlayerPedId()
						local playerPos = GetEntityCoords(playerPed)
						local playerList = GetActivePlayers()
						local nearbyPlayers = {}
						local nearbyPlayerAdded = false
						local nearbyPlayerRemoved = false

						for i = 1, #playerList do -- Get a list of all players within loud speaker range
							local remotePlayerId = playerList[i]
							if playerId ~= remotePlayerId then
								local remotePlayerServerId = GetPlayerServerId(remotePlayerId)
								local remotePlayerPed = GetPlayerPed(remotePlayerId)
								local remotePlayerPos = GetEntityCoords(remotePlayerPed)
								local distance = #(playerPos - remotePlayerPos)
								
								if distance <= mumbleConfig.speakerRange then
									local remotePlayerData = voiceData[remotePlayerServerId]

									if remotePlayerData ~= nil then
										if remotePlayerData.call ~= nil then
											if remotePlayerData.call ~= playerData.call then
												nearbyPlayers[remotePlayerServerId] = true
												
												if nearbySpeakerTargets[remotePlayerServerId] then
													nearbySpeakerTargets[remotePlayerServerId] = nil
												else
													nearbyPlayerAdded = true
												end
											end
										end
									end
								end
							end
						end
						
						for id, exists in pairs(nearbySpeakerTargets) do
							if exists then
								nearbyPlayerRemoved = true
							end
						end

						if nearbyPlayerAdded or nearbyPlayerRemoved then -- Check that we don't send an empty list
							if callData[playerData.call] ~= nil then -- Check if the call still exists
								for id, _ in pairs(callData[playerData.call]) do -- Send a copy of the nearby players to each participant in the call
									if playerServerId ~= id then
										SetVoiceData("speakerTargets", nearbyPlayers, id)
									end
								end
							end
						end

						nearbySpeakerTargets = nearbyPlayers
					end
				end
			end

			Citizen.Wait(1000)
		else
			Citizen.Wait(0)
		end
	end
end)

-- Exports
exports("SetRadioChannel", SetRadioChannel)
exports("addPlayerToRadio", SetRadioChannel)
exports("removePlayerFromRadio", function()
	SetRadioChannel(0)
end)

exports("SetCallChannel", SetCallChannel)
exports("addPlayerToCall", SetCallChannel)
exports("removePlayerFromCall", function()
	SetCallChannel(0)
end)