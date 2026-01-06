--- @type Mq
local mq = require('mq')
local lip = require('lib.LIP')
local logger = require('utils.logger')

local delay_before_zoning = 27000  -- 27s
local config_path = ''
local my_name = mq.TLO.Me.CleanName()


local function file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then io.close(f) return true else return false end
end

local function load_settings()
    local config_dir = mq.configDir:gsub('\\', '/') .. '/'
    local config_file = string.format('mission_tobhazuri_%s.ini', mq.TLO.Me.CleanName())
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
		if (settings.general.BestForLast == nil) then
            settings.general.BestForLast = true
            is_dirty = true
        end
		if (settings.general.OpenChest == nil) then
            settings.general.OpenChest = false
            is_dirty = true
        end
        if (settings.general.Automation == nil) then
            settings.general.Automation = 'CWTN'
            is_dirty = true
        end
        if (is_dirty) then lip.save(config_path, settings) end
    end
 end

local function MoveToSpawn(spawn, distance)
    if (distance == nil) then distance = 15 end

    if (spawn == nil or spawn.ID() == nil) then return false end
    if (spawn.Distance() < distance) then return true end

    mq.cmdf('/squelch /nav id %d npc |dist=%s log=off', spawn.ID(), distance)
    mq.delay(10)
    while mq.TLO.Nav.Active() do mq.delay(10) end
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
    if MoveTo(spawn) == false then return false end
    while mq.TLO.Target.CleanName() ~= mq.TLO.Spawn(spawn).CleanName() do 
        mq.cmdf('/eqtarget %s npc', spawn) 
        mq.delay(10)
    end
    mq.delay(250)
    return true
end

local function MoveToAndAct(spawn,cmd)
    if MoveToAndTarget(spawn) == false then return false end
    mq.cmd(cmd)
    return true
end

local function MoveToAndAttack(spawn)
    if MoveTo(spawn) == false then return false end
    while mq.TLO.Target.CleanName() ~= mq.TLO.Spawn(spawn).CleanName() do 
        mq.cmdf('/eqtarget %s npc', spawn) 
        mq.delay(10)
    end
    mq.delay(250)
    if mq.TLO.Target.CleanName() == mq.TLO.Spawn(spawn).CleanName() and mq.TLO.Me.Combat() == false then 
        mq.cmd('/attack on') 
    end
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
            logger.debug(string.format("\ay%s \at%s \ag%s", name, "DBL Invis: ", both_result))
        else
            logger.debug('gm'..gm)
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
                    mq.cmd('/mutliline ; /stopsong; /timed 1 /alt act 3704; /timed 3 /alt act 231') 
                else
                    mq.cmdf('/dex %s /multiline ; /stopsong; /timed 1 /alt act 3704; /timed 3 /alt act 231', bard)
            end
            logger.info('\ag-->\atINVer: \ay',bard, '\at IVUer: \ay', bard,'\ag<--')
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

        print('\ag-->\atINVer: \ay',mq.TLO.Group.Member(inver).Name(), '\at IVUer: \ay', mq.TLO.Group.Member(ivuer).Name(),'\ag<--')
        
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

local function checkGroupStats()
	Ready = true
	local groupSize = mq.TLO.Group()
   
    for i = groupSize, 0, -1 do
		-- if DEBUG and ( mq.TLO.Group.Member(i).PctHPs() < 99 or  mq.TLO.Group.Member(i).PctEndurance() < 99 or (mq.TLO.Group.Member(i).PctMana() ~= 0 and  mq.TLO.Group.Member(i).PctMana() < 99)) then 
		-- 	printf('%s : %s : %s : %s', mq.TLO.Group.Member(i).CleanName(), mq.TLO.Group.Member(i).PctHPs(), mq.TLO.Group.Member(i).PctEndurance(), mq.TLO.Group.Member(i).PctMana() )
		-- end
		if mq.TLO.Group.Member(i).PctHPs() < 99 then Ready = false end
		if mq.TLO.Group.Member(i).PctEndurance() < 99 then Ready = false end
		if mq.TLO.Group.Member(i).PctMana() ~= 0 and mq.TLO.Group.Member(i).PctMana() < 99 then Ready = false end
    end
	-- mq.delay(5000)
end

local function StopAttack()
	mq.cmd('/attack off') 
	mq.cmd('/cwtna CheckPriorityTarget off nosave')
	mq.cmdf('/%s CheckPriorityTarget off nosave', my_class )
	mq.cmdf('/%s Mode manual nosave', my_class )
	logger.debug('StopAttack branch...')
	if mq.TLO.Target.CleanName() ~= my_name then mq.cmdf('/eqtarget %s', my_name) end
end

local function ZoneIn(npcName, zoneInPhrase, quest_zone)
    local GroupSize = mq.TLO.Group.Members()

    for g = 1, GroupSize, 1 do
        local Member = mq.TLO.Group.Member(g).Name()
        logger.info('\ay-->%s<--\apShould Be Zoning In Now', Member)
        mq.cmdf('/dex %s /eqtarget %s', Member, npcName)
        mq.delay(2000) -- Add a random delay ?
        mq.cmdf('/dex %s /say %s', Member, zoneInPhrase)
    end

    -- This is to make us the last to zone in
    while mq.TLO.Group.AnyoneMissing() == false do
        mq.delay(2000)
    end
    if mq.TLO.Target.CleanName() ~= npcName then
        mq.cmdf('/eqtarget %s', npcName)
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
        mq.cmd('/dgga /squelch /timed 50 /windowstate TaskWnd close')
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

-- local function MoveToPool()
--     mq.cmd('/dgga /nav spawn pool')
--     mq.cmd('/dgga /nav spawn puddle')
-- end

local function DoPrep()
    mq.cmd('/cwtn mode chase nosave')
    mq.cmdf('/%s mode sictank nosave', my_class)
    mq.cmdf('/%s pause off', my_class)
    mq.cmdf('/%s checkprioritytarget off nosave', my_class)
    mq.cmdf('/%s resetcamp', my_class)
    mq.cmd('/dgga /makemevis')
    mq.cmd('/cwtna burnalways on nosave')
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
    mq.cmd('/eqtarget _chest')
    mq.delay(250)
    mq.cmd('/open')
end
