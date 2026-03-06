local cfg = cfg

-- Optional oxmysql support (used only if cfg.logging = true)
local MySQL = {}

function MySQL.ready()
	return GetResourceState('oxmysql') == 'started' and exports and exports.oxmysql ~= nil
end

function MySQL.query(q, p, cb)
	if not MySQL.ready() then
		if cb then cb(nil) end
		return
	end
	return exports.oxmysql:query(q, p or {}, cb)
end

function MySQL.insert(q, p, cb)
	if not MySQL.ready() then
		if cb then cb(nil) end
		return
	end
	return exports.oxmysql:insert(q, p or {}, cb)
end

function MySQL.execute(q, p, cb)
	if not MySQL.ready() then
		if cb then cb(nil) end
		return
	end
	local ok = pcall(function()
		exports.oxmysql:execute(q, p or {}, cb)
	end)
	if not ok then
		-- Fallback for older oxmysql export sets
		return exports.oxmysql:query(q, p or {}, cb)
	end
end


--	ShowLidar, repeater event to nearest player to show lidar to.
RegisterServerEvent('prolaser4:SendDisplayData')
AddEventHandler('prolaser4:SendDisplayData', function(target, data)
	TriggerClientEvent('prolaser4:ReturnDisplayData', target, data)
end)

--	Database timeout event from client->server for server console log.
RegisterServerEvent('prolaser4:DatabaseTimeout')
AddEventHandler('prolaser4:DatabaseTimeout', function()
	print(string.format('^8[ERROR]: ^3Database timed out for %s after 5 seconds. Lidar records tablet unavailable.\n\t\t1) Ensure your database is online.\n\t\t2) restart oxmysql.\n\t\t3) restart ProLaser4.^7', GetPlayerName(source)))
end)

function DebugPrint(text)
	if cfg.serverDebugging then
		print(text)
	end
end

--[[--------------- ADVANCED LOGGING --------------]]
if cfg.logging then
	local isInsertActive = false
	LOGGED_EVENTS = { }
	TEMP_LOGGED_EVENTS = { }
	
	---------------- QUERIES ----------------
	local insertQueryPrefix = [[
		INSERT INTO prolaser4 
			(timestamp, speed, distance, targetX, targetY, player, street, selfTestTimestamp) 
		VALUES 
	]]
	local insertRow = '(STR_TO_DATE(?, "%m/%d/%Y %H:%i:%s"), ?, ?, ?, ?, ?, ?, STR_TO_DATE(?, "%m/%d/%Y %H:%i:%s"))'
	local selectQueryRaw = [[
			SELECT 
				rid,
				DATE_FORMAT(timestamp, "%c/%d/%y %H:%i") AS timestamp, 
				speed, 
				distance as 'range',
				targetX, 
				targetY, 
				player, 
				street, 
				DATE_FORMAT(selfTestTimestamp, "%m/%d/%Y %H:%i") AS selfTestTimestamp 
			FROM prolaser4 
			ORDER BY timestamp
			LIMIT 
	]]
	local selectQuery = string.format("%s %s", selectQueryRaw, cfg.loggingSelectLimit)
	local countQuery = 'SELECT COUNT(*) FROM prolaser4'
	local cleanupQuery = 'DELETE FROM prolaser4 WHERE timestamp < DATE_SUB(NOW(), INTERVAL ? DAY);'
	-----------------------------------------
	-- Debugging Command
	RegisterCommand('lidarsqlupdate', function(source, args)
		-- check if from server console
		if source == 0 then
			DebugPrint('^3[INFO]: Manually inserting records to SQL.^7')
			if MySQL.ready() then InsertRecordsToSQL() end
		else
			DebugPrint(string.format('^3[INFO]: Attempted to manually insert records but got source %s.^7', source))
			TriggerClientEvent('chat:addMessage', source, { args = { '^1Error', 'This command can only be executed from the console.' } })
		end
	end)
	
	-----------------------------------------
	-- Main thread, every restart remove old records if needed, insert records every X minutes as defined by cfg.loggingInsertInterval.
	CreateThread(function()
		local insertWait = cfg.loggingInsertInterval * 60000
		while cfg.logging and not MySQL.ready() do
			Wait(2000)
		end
		if not cfg.logging then return end
		if cfg.loggingCleanUpInterval ~= -1 then
			CleanUpRecordsFromSQL()
		end
		while cfg.logging do
			InsertRecordsToSQL()
			Wait(insertWait)
		end
	end)

	---------------- SETTER / INSERT ----------------
	--	Shared event handler colate all lidar data from all players for SQL submission.
	RegisterServerEvent('prolaser4:SendLogData')
	AddEventHandler('prolaser4:SendLogData', function(logData)
		local playerName = GetPlayerName(source)
		if not isInsertActive then
    		for i, entry in ipairs(logData) do
    			entry.player = playerName
    			table.insert(LOGGED_EVENTS, entry)
    		end
        else
			-- since the insertion is active, inserting now may result in lost data, store temporarily.
            for i, entry in ipairs(logData) do
    			entry.player = playerName
    			table.insert(TEMP_LOGGED_EVENTS, entry)
            end
	    end
	end)

	--	Inserts records to SQL table
	function InsertRecordsToSQL()
		if not MySQL.ready() then return end
		if not isInsertActive then
			if #LOGGED_EVENTS > 0 then
				DebugPrint(string.format('^3[INFO]: Started inserting %s records.^7', #LOGGED_EVENTS))
				isInsertActive = true

				-- Snapshot current queue so new events can keep accumulating
				local toInsert = LOGGED_EVENTS
				LOGGED_EVENTS = {}

				-- Batch insert to reduce DB load
				local batchSize = 250
				for i = 1, #toInsert, batchSize do
					local placeholders = {}
					local params = {}
					local last = math.min(i + batchSize - 1, #toInsert)
					for j = i, last do
						local entry = toInsert[j]
						placeholders[#placeholders+1] = insertRow
						params[#params+1] = entry.time
						params[#params+1] = entry.speed
						params[#params+1] = entry.range
						params[#params+1] = entry.targetX
						params[#params+1] = entry.targetY
						params[#params+1] = entry.player
						params[#params+1] = entry.street
						params[#params+1] = entry.selfTestTimestamp
					end
					local query = insertQueryPrefix .. table.concat(placeholders, ',')
					MySQL.execute(query, params, function(_) end)
				end

				isInsertActive = false

				-- Move temp queue back in for next run
				for _, entry in ipairs(TEMP_LOGGED_EVENTS) do
					table.insert(LOGGED_EVENTS, entry)
				end
				TEMP_LOGGED_EVENTS = {}
				DebugPrint('^3[INFO]: Finished inserting records.^7')
			end
		end
	end
	
	---------------- GETTER / SELECT ----------------
	--	C->S request all record data
	RegisterNetEvent('prolaser4:GetLogData')
	AddEventHandler('prolaser4:GetLogData', function()
		SelectRecordsFromSQL(source)
	end)

	-- Get all record data and return to client
	function SelectRecordsFromSQL(source)
		if not MySQL.ready() then
			TriggerClientEvent('prolaser4:ReturnLogData', source, {})
			return
		end
		DebugPrint(string.format('^3[INFO]: Getting records for %s.^7', GetPlayerName(source)))
		MySQL.query(selectQuery, {}, function(result)
			DebugPrint(string.format('^3[INFO]: Returned %s from select query.^7', #result))
			if result then
				TriggerClientEvent('prolaser4:ReturnLogData', source, result)
			end
		end)
	end
	
	------------------ AUTO CLEANUP -----------------
	--	Remove old records after X days old.
	function CleanUpRecordsFromSQL()
		if not MySQL.ready() then return end
		DebugPrint('^3[INFO]: Removing old records.^7');
		MySQL.query(cleanupQuery, {cfg.loggingCleanUpInterval}, function(returnData)
			DebugPrint(string.format('^3[INFO]: Removed %s records (older than %s days)^7', returnData.affectedRows, cfg.loggingCleanUpInterval));
		end)
	end
	
	------------------ RECORD COUNT -----------------
	function GetRecordCount()
		if not MySQL.ready() then
			return '^8NO CONNECTION^7'
		end
		local recordCount = '^8FAILED TO RETRIEVE        ^7'
		MySQL.query(countQuery, {}, function(returnData)
			if returnData and returnData[1] and returnData[1]['COUNT(*)'] then
				recordCount = returnData[1]['COUNT(*)']
			end
		end)
		Wait(500)
		return recordCount
	end
end

--[[------------ STARTUP / VERSION CHECKING -----------]]
CreateThread( function()
	local currentVersion = semver(GetResourceMetadata(GetCurrentResourceName(), 'version', 0))
	local repoVersion = semver('0.0.0')
	local recordCount = 0
	
-- Get prolaser4 version from github
	PerformHttpRequest('https://raw.githubusercontent.com/TrevorBarns/ProLaser4/main/version', function(err, responseText, headers)
		if responseText ~= nil and responseText ~= '' then
			repoVersion = semver(responseText:gsub('\n', ''))
		end
	end)
	
	if cfg.logging then
		if not MySQL.ready() then
			print('^3[WARNING]: logging enabled, but oxmysql not found. Did you uncomment the oxmysql\n\t\t  lines in fxmanifest.lua?\n\n\t\t  Remember, changes to fxmanifest are only loaded after running `refresh`, then `restart`.^7')
			recordCount = '^8NO CONNECTION^7'
		else
			recordCount = GetRecordCount()
		end
	end
	
	Wait(1000)
	print('\n\t^7 _______________________________________________________')
    print('\t|^8     ____             __                         __ __ ^7|')
    print('\t|^8    / __ \\_________  / /   ____  ________  _____/ // / ^7|')
    print('\t|^8   / /_/ / ___/ __ \\/ /   / __ `/ ___/ _ \\/ ___/ // /_ ^7|')
    print('\t|^8  / ____/ /  / /_/ / /___/ /_/ (__  )  __/ /  /__  __/ ^7|')
    print('\t|^8 /_/   /_/   \\____/_____/\\__,_/____/\\___/_/     /_/    ^7|')
	print('\t^7|_______________________________________________________|')
	print(('\t|\t           INSTALLED: %-26s|'):format(currentVersion))
	print(('\t|\t              LATEST: %-26s|'):format(repoVersion))
	if cfg.logging then
		if type(recordCount) == 'number' then
			print(('\t|\t        RECORD COUNT: %-26s|'):format(recordCount))
		else
			print(('\t|\t        RECORD COUNT: %-30s|'):format(recordCount))
		end
	end
	if currentVersion < repoVersion then
		print('\t^7|_______________________________________________________|')
		print('\t|\t         ^8STABLE UPDATE AVAILABLE                ^7|')
		print('\t|^8                      DOWNLOAD AT:                     ^7|')
		print('\t|^5       github.com/TrevorBarns/ProLaser4/releases       ^7|')
   end
	print('\t^7|_______________________________________________________|')
	print('\t^7|    Updates, Support, Feedback: ^5discord.gg/PXQ4T8wB9   ^7|')
	print('\t^7|_______________________________________________________|\n\n')
end)
