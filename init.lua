-- Mission_TOBHighPriest
-- Version 1.0
-- TODO: Change to handle using RGMercs as well as CWTN
-- DONE: Check to make sure entire group has zoned in
-- TODO: Make sure LEM is loaded and the correct LEM is active.  Also place ta link to the LEM in the setup
-- TODO: Allow script restart if it errors out by knowing what phase is going
-- TODO: 
-- TODO: 
-- TODO: 
---------------------------
local mq = require('mq')
local lip = require('lib.LIP')
local logger = require('utils.logger')

-- #region Variables
logger.set_log_level(4) -- 4 = Info level, use 5 for debug, and 6 for trace
local command = 0
local Ready = false
local my_class = mq.TLO.Me.Class.ShortName()
local my_name = mq.TLO.Me.CleanName()
local zone_name = mq.TLO.Zone.ShortName()
local request_zone = 'aureatecovert'
local request_npc = 'Lokta'
local request_phrase = 'priest'
local zonein_phrase = 'ready'
local quest_zone = 'gildedspire_missiontwo'
local task_name = 'High Priest'
local groupSize = 0

local delay_before_zoning = 27000  -- 27s
local config_path = ''
local groupRunning = 0
local hold_groupRunning = 0
local task = mq.TLO.Task(task_name)

local settings = {
    general = {
        GroupMessage = "dannet", -- or "bc"
        Automation = "CWTN", -- or "RGmercs"
        OpenChest = false,
    }
}
-- #endregion

-- #region Functions
local function file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then io.close(f) return true else return false end
end

local function load_settings()
    local config_dir = mq.configDir:gsub('\\', '/') .. '/'
    local config_file = string.format('mission_tobhighpriest_%s.ini', mq.TLO.Me.CleanName())
    config_path = config_dir .. config_file
    if (file_exists(config_path) == false) then
        lip.save(config_path, settings)
	else
        settings = lip.load(config_path)

        -- Version updates
        local is_dirty = false
        if (settings.general.GroupMessage == nil) then
            settings.general.GroupMessage = 'dannet'
            is_dirty = true
        end
        if (settings.general.Automation == nil) then
            settings.general.Automation = 'CWTN'
            is_dirty = true
        end
        if (settings.general.OpenChest == nil) then
            settings.general.OpenChest = false
            is_dirty = true
        end
        if (is_dirty) then lip.save(config_path, settings) end
	end
end

local function WaitForNav()
	logger.debug('Starting WaitForNav()...')
	while mq.TLO.Navigation.Active() == false do
		mq.delay(10)
	end
	while mq.TLO.Navigation.Active() == true do
		mq.delay(10)
	end
	logger.debug('Exiting WaitForNav()...')
end

local function checkGroup()
	local myID = mq.TLO.Me.ID
	local groupLeaderID = mq.TLO.Group.Leader.ID
	groupSize = mq.TLO.Group() + 1
	if mq.TLO.SpawnCount('group radius 40')() < groupSize then
		groupRunning = 1
	else
		groupRunning = 0
	end
	if groupRunning ~= hold_groupRunning then 
		logger.debug('checkGroup - groupRunning = %s', groupRunning )
		hold_groupRunning = groupRunning
	end
end

local function MoveToSpawn(spawn, distance)
    if (distance == nil) then distance = 5 end

    if (spawn == nil or spawn.ID() == nil) then return end
    if (spawn.Distance() < distance) then return true end

    mq.cmdf('/squelch /nav id %d npc |dist=%s log=off', spawn.ID(), distance)
    mq.delay(10)
    WaitForNav()
    mq.delay(500)
    return true
end

local function MoveTo(spawn_name, distance)
    local spawn = mq.TLO.Spawn('npc '..spawn_name)
    return MoveToSpawn(spawn, distance)
end

local function MoveToId(spawn_id, distance)
    local spawn = mq.TLO.Spawn('npc id '..spawn_id)
    return MoveToSpawn(spawn, distance)
end

local function MoveToAndTarget(spawn)
    if MoveTo(spawn, 15) == false then return false end
    mq.cmdf('/squelch /mqtarget %s', spawn)
    mq.delay(250)
    return true
end

local function MoveToAndAct(spawn, cmd)
    if MoveToAndTarget(spawn) == false then return false end
    mq.cmd(cmd)
    return true
end

local function MoveToAndSay(spawn,say) return MoveToAndAct(spawn, string.format('/say %s', say)) end

local function query(peer, query, timeout)
    mq.cmdf('/dquery %s -q "%s"', peer, query)
    mq.delay(timeout)
    local value = mq.TLO.DanNet(peer).Q(query)()
    return value
end

local function tell(delay,gm,aa) 
    local z = mq.cmdf('/timed %s /dex %s /multiline ; /stopcast; /timed 1 /alt act %s', delay, mq.TLO.Group.Member(gm).Name(), aa)
    return z
end

local function classShortName(x)
    local y = mq.TLO.Group.Member(x).Class.ShortName()
    return y
end

local function all_double_invis()
    
    local dbl_invis_status = false
    local grpsize = mq.TLO.Group.Members()

    for gm = 0,grpsize do
        local name = mq.TLO.Group.Member(gm).Name()
        local result1 = query(name, 'Me.Invis[1]', 100) 
        local result2 = query(name, 'Me.Invis[2]', 100)
        local both_result = false
        
        if result1 == 'TRUE' and result2 == 'TRUE' then
            both_result = true
            --print(string.format("\ay%s \at%s \ag%s", name, "DBL Invis: ", both_result))
        else
            --print('gm'..gm)
            break
        end

        if gm == grpsize then
            dbl_invis_status = true
        end
    end
    return dbl_invis_status
end

local function the_invis_thing()
    --if i am bard or group has bard, do the bard invis thing
    if mq.TLO.Spawn('Group Bard').ID()>0 then
        local bard = mq.TLO.Spawn('Group Bard').Name()
            if bard == mq.TLO.Me.Name() then
                -- I am a bard, cast 'Selos Sonata' then 'Shaun's Sonorous Clouding'
                mq.cmd('/mutliline ; /stopsong; /timed 1 /alt act 3704; /timed 3 /alt act 231') 
            else
                -- Telling the bard to cast 'Selos Sonata' then 'Shaun's Sonorous Clouding'
                mq.cmdf('/dex %s /multiline ; /stopsong; /timed 1 /alt act 3704; /timed 3 /alt act 231', bard)
            end
            
            logger.info('\ag-->\atINVer: \ay%s\at IVUer: \ay%s\ag<--', bard, bard)
    else
        --without a bard, find who can invis and who can IVU
        local inver = 0
        local ivuer = 0
        local grpsize = mq.TLO.Group.Members()
        
            --check classes that can INVIS only
        for i=0,grpsize do
            if string.find("RNG DRU SHM", classShortName(i)) ~= nil then
                inver = i
                break
            end
        end

        --check classes that can IVU only
        for i=0,grpsize do
            if string.find("CLR NEC PAL SHD", classShortName(i)) ~= nil then
                ivuer = i
                break
            end
        end
        
        --check classes that can do BOTH
        if inver == 0 then
            for i=0,grpsize do
                if string.find("ENC MAG WIZ", classShortName(i)) ~= nil then
                    inver = i
                    break

                end    
            end
        end

        if ivuer == 0 then
            for i=grpsize,0,-1 do
                if string.find("ENC MAG WIZ", classShortName(i)) ~= nil then
                    ivuer = i
                    if i == inver then
                        logger.info('\arUnable to Double Invis')
                        mq.exit()  
                    end
                break
                end
            end
        end 

        --catch anyone else in group
        if string.find("WAR MNK ROG BER", classShortName(inver)) ~= nil or string.find("WAR MNK ROG BER", classShortName(ivuer)) ~= nil then
            logger.info('\arUnable to Double Invis')
            mq.exit()
        end

        logger.info('\ag-->\atINVer: \ay%s\at IVUer: \ay%s\ag<--', mq.TLO.Group.Member(inver).Name(), mq.TLO.Group.Member(ivuer).Name())
        
        --if i am group leader and can INVIS, then do the INVIS thing
        if classShortName(inver) == 'SHM' and inver == 0 then
                mq.cmd('/multiline ; /stopcast; /timed 3 /alt act 630')
            elseif string.find("ENC MAG WIZ", classShortName(inver)) ~= nil then
                mq.cmd('/multiline ; /stopcast; /timed 1 /alt act 1210')
            elseif string.find("RNG DRU", classShortName(inver)) ~= nil then
                mq.cmd('/multiline ; /stopcast; /timed 1 /alt act 518')
        end

        --if i have an INVISER in the group, then 'tell them' do the INVIS thing
        if classShortName(inver) == 'SHM' and inver ~= 0 then
                tell(4,inver,630)
            elseif string.find("ENC MAG WIZ", classShortName(inver)) ~= nil then
                tell(0,inver,1210)
            elseif string.find("RNG DRU", classShortName(inver)) ~= nil then
                tell(5,inver,518)
        end
        
        --if i am group leader and can IVU, then do the IVU thing
        if string.find("CLR NEC PAL SHD", classShortName(ivuer)) ~= nil and ivuer == 0 then
                mq.cmd('/multiline ; /stopcast; /timed 1 /alt activate 1212')
            else
                mq.cmd('/multiline ; /stopcast; /timed 1 /alt activate 280')
        end
        
        --if i have an IVUER in the group, then 'tell them' do the IVU thing
        if string.find("CLR NEC PAL SHD", classShortName(ivuer)) ~= nil and ivuer ~= 0 then
                tell(2,ivuer,1212)    
            else
                tell(2,ivuer,280)
        end
    end
    mq.delay(8000)
end

local function DBLinvis()
    while not all_double_invis() do
        the_invis_thing()
         mq.delay(5000)
    end
end

local function checkGroupStats()
	Ready = false
	local groupSize = mq.TLO.Group()
    local firstMsg = true

    while Ready ~= true do
        Ready = true
        for i = groupSize, 0, -1 do
            if mq.TLO.Group.Member(i).PctHPs() < 99 then Ready = false end
            if mq.TLO.Group.Member(i).PctEndurance() < 99 then Ready = false end
            if mq.TLO.Group.Member(i).PctMana() ~= 0 and mq.TLO.Group.Member(i).PctMana() < 99 then Ready = false end
        end

       	if Ready == false then 
            -- Only show the message the first time it runs through this routine
            if firstMsg then 
                logger.info('Group not fully ready.  Sitting to regen...')
                firstMsg = false
            end
            mq.cmd('/noparse /dgga /if (${Me.Standing}) /sit')
            mq.delay(5000)
    	end
    end
end

local function StopAttack()
	mq.cmd('/squelch /attack off') 
	mq.cmd('/squelch /cwtna CheckPriorityTarget off nosave')
	mq.cmdf('/squelch /%s CheckPriorityTarget off nosave', my_class )
	mq.cmdf('/squelch /%s Mode manual nosave', my_class )
	logger.debug('StopAttack branch...')
	if mq.TLO.Target.CleanName() ~= my_name then mq.cmdf('/mqtarget %s', my_name) end
end

local function ZoneIn(npcName, zoneInPhrase, quest_zone)
    local GroupSize = mq.TLO.Group.Members()

    for g = 1, GroupSize, 1 do
        local Member = mq.TLO.Group.Member(g).Name()
        logger.info('\ay-->%s<--\apShould Be Zoning In Now', Member)
        mq.cmdf('/dex %s /mqtarget %s', Member, npcName)
        mq.delay(2000) -- Add a random delay ?
        mq.cmdf('/dex %s /say %s', Member, zoneInPhrase)
    end

    -- This is to make us the last to zone in
    while mq.TLO.Group.AnyoneMissing() == false do
        mq.delay(2000)
    end
    if mq.TLO.Target.CleanName() ~= npcName then
        mq.cmdf('/mqtarget %s', npcName)
        mq.delay(5000)
        mq.cmdf('/say %s', zoneInPhrase)
    else
        mq.delay(5000)
        mq.cmdf('/say %s', zoneInPhrase)
    end
    local counter = 0
    while mq.TLO.Zone.ShortName() ~= quest_zone do 
        counter = counter + 1
        if counter >= 10 then 
            logger.info('Not able to zone into the %s. Look at the issue and fix it please.', quest_zone)
            os.exit()
        end
        mq.delay(5000)
    end
    zone_name = mq.TLO.Zone.ShortName()
end

--- Gets the name of a group member, even if they are out of zone
---@param index integer
---@return string|nil
local function getGroupMemberName(index)
    local member = mq.TLO.Group.Member(index)
    if not member() then return nil end
    local name = member.Name()
    if name and name:len() > 0 then
        return name
    end
    return nil
end

--- Returns a table of group members not in the zone
---@return string[]
local function getGroupMembersNotInZone()
    local missing = {}
    for i = 1, mq.TLO.Me.GroupSize() do
        local name = getGroupMemberName(i)
        if name and not mq.TLO.Spawn("pc = " .. name)() then
            table.insert(missing, name)
        end
    end
    return missing
end

--- Wait until all group members are in zone, or timeout
---@param timeoutSec number
---@return boolean
local function waitForGroupToZone(timeoutSec)
    local start = os.time()
    while os.difftime(os.time(), start) < timeoutSec do
        local notInZone = getGroupMembersNotInZone()
        if #notInZone == 0 then
            logger.info("All group members are in zone.")
            return true
        end
        logger.info("Still waiting on: " .. table.concat(notInZone, ", "))
        mq.delay(5000)
    end
    logger.info("Timeout waiting for group members to zone.")
    return false
end


local function Task()
    if (task() == nil) then
        if (mq.TLO.Zone.ShortName() ~= request_zone) then
            logger.info('Not In %s to request task.  Move group to that zone and restart.', request_zone)
            os.exit()
        end

        MoveToAndSay(request_npc, request_phrase)

        for index=1, 5 do
            mq.delay(1000)
            mq.doevents()

            task = mq.TLO.Task(task_name)
            if (task() ~= nil) then break end

            if (index >= 5) then
                logger.info('Unable to get quest. Exiting.')
                os.exit()
            end
            logger.info('...waiting for quest.')
        end

        if (task() == nil) then
            logger.info('Unable to get quest. Exiting.')
            os.exit()
        end

        logger.info('\at Got quest.')
        mq.cmd('/timed 50 /dgga /squelch /windowstate TaskWnd close')
    end

    if (task() == nil) then
        logger.info('Problem requesting or getting task.  Exiting.')
        os.exit()
    end
end

local function WaitForTask()
    local time_since_request = 21600000 - task.Timer()
    local time_to_wait = delay_before_zoning - time_since_request
    logger.debug('TimeSinceReq: \ag%d\ao  TimeToWait: \ag%d\ao', time_since_request, time_to_wait)
    if (time_to_wait > 0) then
        logger.info('\at Waiting for instance generation \aw(\ay%.f second(s)\aw)', time_to_wait / 1000)
        mq.delay(time_to_wait)
    end  
end

local function DoPrep()
    mq.delay(2000)
    mq.cmd('/cwtn mode 2')
    mq.cmdf('/%s mode 0', my_class)
    mq.cmdf('/%s mode 7', my_class)
    mq.cmdf('/%s pause off', my_class)
    mq.cmdf('/%s checkprioritytarget off nosave', my_class)
    mq.cmdf('/%s resetcamp', my_class)
    mq.cmd('/dgga /makemevis')
    mq.cmd('/cwtna burnalways on nosave')

    mq.cmd('/cwtna CheckPriorityTarget off nosave')
    mq.cmd('/cwtna UseAOE Off nosave')
    mq.cmd('/cwtna BYOS Off nosave')
    mq.cmd('/cwtna BurnAllNamed off nosave')
    mq.cmd('/cwtna burnalways off nosave')
    mq.cmd('/cwtna userez on nosave')
    mq.cmd('/cwtna userezcall on nosave')
    mq.cmd('/cwtna pause off')
    mq.cmdf('/%s mode manual', my_class)
    mq.cmd('/dgza /makemevisible')
    mq.cmd('/dgga /plugin autoloot unload')
    mq.cmd('/dgga /lootly off')
    mq.cmd('/dgga /makemevisible')
    mq.cmd('/dgga /lua run lem')
    mq.cmd('/dgga /timed 10 /lem show')
    mq.cmd('/dgga /timed 10 /lem event \'The_Priest_Cure_Lua\' on')
end

local function ClearStartingSetup()
    mq.delay(2000)
    mq.cmd('/cwtn mode chase nosave')
    mq.cmdf('/%s mode sictank nosave', my_class)
    mq.cmdf('/%s pause off', my_class)
    mq.cmdf('/%s checkprioritytarget on nosave', my_class)
end


local function action_openChest()
    mq.cmd('/squelch /nav spawn _chest | log=off')
    while mq.TLO.Nav.Active() do mq.delay(5) end
    mq.cmd('/mqtarget _chest')
    mq.delay(250)
    mq.cmd('/open')
end

-- #endregion

load_settings()

if (settings.general.GroupMessage == 'dannet') then
   logger.info('\aw Group Chat: \ayDanNet\aw.')
elseif (settings.general.GroupMessage == 'bc') then
   logger.info('\aw Group Chat: \ayBC\aw.')
else
   logger.info("Unknown or invalid group command.  Must be either 'dannet' or 'bc'. Ending script. \ar%s", settings.general.GroupMessage)
   return
end

logger.info('\aw Open Chest: \ay%s', settings.general.OpenChest)

if my_class ~= 'WAR' and my_class ~= 'SHD' and my_class ~= 'PAL' then 
	logger.info('You must run the script on a tank class...')
	os.exit()
end
mq.cmdf('/%s pause on', my_class)

if zone_name == request_zone then 
	if mq.TLO.Spawn(request_npc).Distance() > 40 then 
        logger.info('You are in %s, but too far away from %s to start the mission!  We will attempt to double-invis and run to the mission npc', request_zone, request_npc)
        DBLinvis()
        MoveToAndSay(request_npc, request_phrase)
    end
	Task()
    WaitForTask()    
    
    ZoneIn(request_npc, zonein_phrase, quest_zone)
    mq.delay(5000)
    waitForGroupToZone(60)
end

zone_name = mq.TLO.Zone.ShortName()

if zone_name ~= quest_zone then 
	logger.info('You are not in the mission...')
	os.exit()
end

-- Check group mana / endurance / hp
checkGroupStats()

mq.cmdf('/%s mode 0', my_class)

mq.cmd('/dgga /nav locyxz 382 -45 1467.59 log=off')

WaitForNav()

logger.info('Doing some setup.')
DoPrep()

logger.info('Starting the event in 10 seconds!')
mq.delay(10000)

mq.cmd('/nav locyxz 355 -3 1467.59 log=off')
WaitForNav()

mq.cmd('/mqtarget npc High Priest Yaran')
mq.delay(300)
mq.cmd('/keypress hail')

while mq.TLO.SpawnCount('Animated Statue')() < 1 do
	mq.delay(100)
end

while mq.TLO.SpawnCount('Animated Statue')() > 0 do
	mq.delay(100)
	if mq.TLO.Me.XTarget(1).CleanName() == mq.TLO.Spawn('Animated Statue').CleanName() and not mq.TLO.Me.Combat() then
		mq.cmd('/xtar 1')
		mq.delay(300)
        mq.cmd('/squelch /face')
		mq.cmd('/attack on')
        if mq.TLO.Target() and mq.TLO.Target.Distance() > 25 then mq.cmd('/squelch /nav target distance=15 log=off') end
	end
end

mq.cmd('/squelch /nav spawn High Priest Yaran | log=off')
WaitForNav()

mq.cmd('/squelch /mqtarget npc High Priest Yaran')
mq.delay(300)
mq.cmd('/squelch /face')
mq.cmd('/attack on')

while mq.TLO.SpawnCount('High Priest Yaran xtarhater')() < 1 do
	mq.delay(100)
end

-- Event Setup
local event_zoned = function(line)
    -- zoned so quit
    command = 1
end
local event_failed = function(line)
    -- failed so quit
    command = 1
end

mq.event('Zoned','LOADING, PLEASE WAIT...#*#',event_zoned)
mq.event('Failed','#*#summons overwhelming enemies and your mission fails.#*#',event_failed)

mq.delay(1000)

local function StopAttack()
	mq.cmd('/attack off') 
	mq.cmd('/cwtna CheckPriorityTarget off nosave')
	mq.cmdf('/%s CheckPriorityTarget off nosave', my_class )
	mq.cmdf('/%s Mode manual nosave', my_class )
	logger.debug('StopAttack branch...')
	if mq.TLO.Target.CleanName() ~= my_name then mq.cmdf('/mqtarget %s', my_name) end
end

logger.debug('Starting Loop...')
while true do
	mq.doevents()
	checkGroup()

	if command == 1 then break end

	if mq.TLO.SpawnCount('_chest')() == 1 then
		logger.info('I see the chest! You won!')
		break
	end

	if mq.TLO.SpawnCount('penance npc')() > 0 then 
		logger.debug('penance branch...')
		if mq.TLO.SpawnCount('penance npc radius 60')() > 0 then 
			logger.debug('penance Attack branch...')
			if mq.TLO.Target.CleanName() ~= mq.TLO.Spawn('penance').CleanName() then mq.cmd('/mqtarget npc penance') end
			mq.delay(100)
            mq.cmd('/squelch /face')
			mq.cmd('/attack on')
		else
			StopAttack()
		end
	elseif mq.TLO.SpawnCount('purification npc')() > 0 then 
		logger.debug('purification branch...')
		if mq.TLO.SpawnCount('purification npc radius 60')() > 0 then 
			logger.debug('purification Attack branch...')
			if mq.TLO.Target.CleanName() ~= mq.TLO.Spawn('purification').CleanName() then mq.cmd('/mqtarget purification npc') end
			mq.delay(100)
			mq.cmd('/attack on')
		else
			StopAttack()
		end		
	elseif mq.TLO.SpawnCount('Rector npc')() > 0 then 
		logger.debug('Rector branch...')
		if mq.TLO.SpawnCount('Rector npc radius 120')() > 0 then 
			logger.debug('Rector Attack branch...')
			if mq.TLO.Target.CleanName() ~= mq.TLO.Spawn('Rector').CleanName() then mq.cmd('/mqtarget Rector npc') end
			mq.delay(100)
			mq.cmd('/attack on')
		else
			StopAttack()
		end
	elseif mq.TLO.SpawnCount('acolyte npc')() > 0 then
		logger.debug('Acolyte branch...')
		if mq.TLO.SpawnCount('acolyte npc radius 60')() > 0 then
			logger.debug('Acolyte attack branch...')
			if mq.TLO.Target.CleanName() ~= mq.TLO.Spawn('acolyte').CleanName() then mq.cmd('/mqtarget acolyte npc') end
			mq.delay(100)
			mq.cmd('/attack on')
		else
			StopAttack()
		end
	else
		checkGroup()
		if groupRunning == 1 then 
			StopAttack()
		elseif groupRunning == 0 then 
			logger.debug('Priest attack branch...')
			if mq.TLO.Target.CleanName() ~= mq.TLO.Spawn('yaran').CleanName() then
				mq.cmd('/mqtarget yaran npc') 
				Hold_NamedHP = mq.TLO.Spawn('yaran').PctHPs()
			end
			mq.cmdf('/%s Mode sictank nosave', my_class )
			mq.delay(100)
			mq.cmd('/attack on')
		elseif groupRunning == 0 and mq.TLO.Spawn('yaran').PctHPs() <= Hold_NamedHP - 7 then 
			-- Delay for 15 seconds before attacking named again?
		end
	end

	mq.delay(100)
end

if (settings.general.OpenChest == true) then action_openChest() end
ClearStartingSetup()
mq.unevent('Zoned')
mq.unevent('Failed')
logger.info('...Ended')