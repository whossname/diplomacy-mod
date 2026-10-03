function gadget:GetInfo()
    return {
        name      = "Diplomacy FSM",
        desc      = "Implements Partnership and Fealty alliances",
        author    = "BAR Modder",
        date      = "2026",
        license   = "GNU GPL, v2 or later",
        layer     = 0,
        enabled   = true
    }
end

-- Everything runs on the server (Synced Code)
if not gadgetHandler:IsSyncedCode() then
    return false
end

local teamStates = {}
local teamCommanders = {}
local pendingProposals = {} -- Tracks /partner or /fealty requests

local STATE_INDEP = "Independent"
local STATE_PARTNER = "Partnership"
local STATE_KING = "King"
local STATE_VASSAL = "Vassal"
local STATE_ELIM = "Eliminated"

-- "Name (Team N)"; the "(Team N)" suffix is parsed by the UI widget, so keep it.
local function TeamName(teamID)
    local _, leader, _, isAI = Spring.GetTeamInfo(teamID)
    local name
    if isAI then
        local _, aiName = Spring.GetAIInfo(teamID)
        name = aiName
    elseif leader and leader >= 0 then
        name = Spring.GetPlayerInfo(leader)
    end
    return (name and name ~= "" and name or "Unknown") .. " (Team " .. teamID .. ")"
end

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------
local function IsCommander(unitDefID)
    local ud = UnitDefs[unitDefID]
    return ud and (ud.customParams.iscommander ~= nil or ud.customParams.commander ~= nil)
end

local function EliminateTeam(teamID)
    if teamStates[teamID].state == STATE_ELIM then return end
    teamStates[teamID].state = STATE_ELIM
    Spring.KillTeam(teamID)
    Spring.SendMessageToPlayer(teamID, "You have been Eliminated!")
    Spring.Echo(TeamName(teamID) .. " has been eliminated from the game.")
end

local function GetAllyTeam(teamID)
    local _, _, _, _, _, allyTeamID = Spring.GetTeamInfo(teamID)
    return allyTeamID
end

local function SetAlliance(teamA, teamB, isAllied)
    -- dynamically makes two teams friendly or hostile to each other
    Spring.SetAlly(GetAllyTeam(teamA), GetAllyTeam(teamB), isAllied)
end

--------------------------------------------------------------------------------
-- State Machine Logic
--------------------------------------------------------------------------------
local function HandleLastCommanderLost(teamID)
    local data = teamStates[teamID]
    
    if data.state == STATE_INDEP then
        EliminateTeam(teamID)
        
    elseif data.state == STATE_PARTNER then
        local partnerID = data.partner
        
        -- The survivor becomes the King, the fallen becomes a Vassal
        data.state = STATE_VASSAL
        data.partner = nil
        data.king = partnerID
        
        teamStates[partnerID].state = STATE_KING
        teamStates[partnerID].partner = nil
        table.insert(teamStates[partnerID].vassals, teamID)
        
        Spring.Echo("Partnership collapsed! " .. TeamName(partnerID) .. " is now King, and " .. TeamName(teamID) .. " is their Vassal.")
        
    elseif data.state == STATE_KING then
        Spring.Echo("The King " .. TeamName(teamID) .. " has fallen! The Kingdom crumbles.")
        local vassalsToKill = {}
        for _, v in ipairs(data.vassals) do
            table.insert(vassalsToKill, v)
        end
        
        EliminateTeam(teamID)
        -- Eliminate all attached vassals
        for _, v in ipairs(vassalsToKill) do
            EliminateTeam(v)
        end
    end
end

local function HandleCommanderObtained(teamID)
    local data = teamStates[teamID]
    
    if data.state == STATE_VASSAL then
        local oldKing = data.king
        data.state = STATE_INDEP
        data.king = nil
        
        -- Remove from King's vassal list
        if oldKing and teamStates[oldKing] then
            local kingData = teamStates[oldKing]
            for i, v in ipairs(kingData.vassals) do
                if v == teamID then
                    table.remove(kingData.vassals, i)
                    break
                end
            end

            -- A King with no remaining vassals has no one left to rule over
            if kingData.state == STATE_KING and #kingData.vassals == 0 then
                kingData.state = STATE_INDEP
                Spring.Echo(TeamName(oldKing) .. " has lost their last Vassal and is now Independent!")
            end
        end
        Spring.Echo(TeamName(teamID) .. " has obtained a Commander and is now Independent!")
    end
end

-- A King who gifts away their last Commander to one of their own Vassals
-- doesn't lose the game: the relationship simply reverses. The gifted
-- Vassal becomes the new King (inheriting the other Vassals), and the old
-- King becomes their Vassal.
local function ReverseKingVassalRoles(oldKingID, newKingID)
    local oldData = teamStates[oldKingID]
    local newData = teamStates[newKingID]

    -- Remove the newKing from the oldKing's vassal list
    for i, v in ipairs(oldData.vassals) do
        if v == newKingID then
            table.remove(oldData.vassals, i)
            break
        end
    end

    -- The new King inherits all remaining Vassals
    newData.vassals = oldData.vassals
    for _, v in ipairs(newData.vassals) do
        teamStates[v].king = newKingID
    end
    oldData.vassals = {}

    newData.state = STATE_KING
    newData.king = nil

    oldData.state = STATE_VASSAL
    oldData.king = newKingID
    table.insert(newData.vassals, oldKingID)

    Spring.Echo(TeamName(oldKingID) .. " gifted their last Commander to their Vassal, " .. TeamName(newKingID) ..
        "! The roles have reversed: " .. TeamName(newKingID) .. " is now King.")
end

local function MakeVassal(kingID, vassalID)
    -- 1. Setup the state changes
    teamStates[vassalID].state = STATE_VASSAL
    teamStates[vassalID].king = kingID
    
    -- Any existing partnership for vassal is broken by swearing fealty
    if teamStates[vassalID].partner then
        local p = teamStates[vassalID].partner
        teamStates[p].state = STATE_KING
        teamStates[p].partner = nil
    end
    
    teamStates[kingID].state = STATE_KING
    table.insert(teamStates[kingID].vassals, vassalID)
    SetAlliance(kingID, vassalID, true)
    
    -- 2. Automatically transfer all commanders to the King
    local vassalUnits = Spring.GetTeamUnits(vassalID)
    local transferredCount = 0
    
    for _, uID in ipairs(vassalUnits) do
        local uDefID = Spring.GetUnitDefID(uID)
        if IsCommander(uDefID) then
            Spring.TransferUnit(uID, kingID, true)
            transferredCount = transferredCount + 1
        end
    end
    
    Spring.Echo(TeamName(kingID) .. " accepted " .. TeamName(vassalID) .. " as a Vassal and seized " .. transferredCount .. " Commander(s)!")
end

--------------------------------------------------------------------------------
-- Call-ins: Tracking Commanders
--------------------------------------------------------------------------------
function gadget:Initialize()
    local teams = Spring.GetTeamList()
    for _, t in ipairs(teams) do
        -- Skip the GAIA team (usually team 255 or max teams)
        if t ~= Spring.GetGaiaTeamID() then
            teamStates[t] = { state = STATE_INDEP, partner = nil, king = nil, vassals = {} }
            teamCommanders[t] = 0
            pendingProposals[t] = {}
        end
    end
end

-- Publish each team's diplomatic state so the UI widget can read it
local publishedKeys = {}
local function PublishState()
    local pub = {public = true}
    for t, d in pairs(teamStates) do
        local vassals = table.concat(d.vassals, ",")
        local key = table.concat({d.state, d.partner or -1, d.king or -1, vassals, teamCommanders[t] or 0}, "|")
        if publishedKeys[t] ~= key then
            publishedKeys[t] = key
            Spring.SetTeamRulesParam(t, "dipState", d.state, pub)
            Spring.SetTeamRulesParam(t, "dipPartner", d.partner or -1, pub)
            Spring.SetTeamRulesParam(t, "dipKing", d.king or -1, pub)
            Spring.SetTeamRulesParam(t, "dipVassals", vassals, pub)
            Spring.SetTeamRulesParam(t, "dipCmdrs", teamCommanders[t] or 0, pub)
        end
    end
end

function gadget:GameFrame(n)
    if n == 1 then Spring.Echo("[Diplomacy] ready") end
    if n % 5 == 0 then PublishState() end
end

function gadget:UnitCreated(unitID, unitDefID, teamID, builderID)
    if IsCommander(unitDefID) and teamID ~= Spring.GetGaiaTeamID() then
        teamCommanders[teamID] = (teamCommanders[teamID] or 0) + 1
        if teamCommanders[teamID] == 1 then
            HandleCommanderObtained(teamID)
        end
    end
end

function gadget:UnitDestroyed(unitID, unitDefID, teamID, attackerID, attackerDefID, attackerTeamID)
    if IsCommander(unitDefID) and teamID ~= Spring.GetGaiaTeamID() then
        teamCommanders[teamID] = math.max(0, (teamCommanders[teamID] or 1) - 1)
        if teamCommanders[teamID] == 0 then
            HandleLastCommanderLost(teamID)
        end
    end
end

function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    if IsCommander(unitDefID) then
        local rolesReversed = false

        if oldTeam ~= Spring.GetGaiaTeamID() then
            teamCommanders[oldTeam] = math.max(0, (teamCommanders[oldTeam] or 1) - 1)
            if teamCommanders[oldTeam] == 0 then
                local oldData = teamStates[oldTeam]
                -- Special case: a King gifting their last Commander to one of
                -- their own Vassals reverses the relationship instead of
                -- eliminating the whole kingdom.
                if oldData and oldData.state == STATE_KING then
                    for _, v in ipairs(oldData.vassals) do
                        if v == newTeam then
                            rolesReversed = true
                            break
                        end
                    end
                end

                if rolesReversed then
                    ReverseKingVassalRoles(oldTeam, newTeam)
                else
                    HandleLastCommanderLost(oldTeam)
                end
            end
        end
        if newTeam ~= Spring.GetGaiaTeamID() then
            teamCommanders[newTeam] = (teamCommanders[newTeam] or 0) + 1
            if teamCommanders[newTeam] == 1 and not rolesReversed then
                HandleCommanderObtained(newTeam)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Call-ins: Chat Commands for Diplomacy
--------------------------------------------------------------------------------
local function HandleCommand(playerID, teamID, msg)
    if teamStates[teamID] == nil then return false end

    local words = {}
    for word in msg:gmatch("%S+") do table.insert(words, word) end
    
    if words[1] == "/diplomacy" then
        local action = words[2]
        local targetTeam = tonumber(words[3])
        
        if action == "info" then
            local d = teamStates[teamID]
            Spring.SendMessageToPlayer(playerID, TeamName(teamID) .. " | State: " .. d.state .. " | Commanders: " .. teamCommanders[teamID]
                .. " | Partner: " .. (d.partner or -1) .. " | King: " .. (d.king or -1) .. " | Vassals: " .. table.concat(d.vassals, ","))
            return true
        end

        -- Prevent actions if Eliminated or a Vassal (Vassals have no diplomatic rights)
        if teamStates[teamID].state == STATE_ELIM or teamStates[teamID].state == STATE_VASSAL then
            Spring.SendMessageToPlayer(playerID, "You do not have diplomatic rights.")
            return true
        end

        if action == "dissolve" then
            if teamStates[teamID].state == STATE_PARTNER then
                local partner = teamStates[teamID].partner
                teamStates[teamID].state = STATE_INDEP
                teamStates[teamID].partner = nil
                teamStates[partner].state = STATE_INDEP
                teamStates[partner].partner = nil
                SetAlliance(teamID, partner, false)
                Spring.Echo(TeamName(teamID) .. " dissolved the partnership with " .. TeamName(partner))
            end
            
        elseif action == "partner" and targetTeam then
            if teamStates[teamID].state ~= STATE_INDEP and teamStates[teamID].state ~= STATE_PARTNER then return true end
            
            if pendingProposals[targetTeam]["partner"] == teamID then
                -- Target already proposed to us, finalize it
                if teamStates[teamID].state == STATE_PARTNER then
                    -- Dissolve old partnership first
                    local old = teamStates[teamID].partner
                    teamStates[old].state = STATE_INDEP
                    teamStates[old].partner = nil
                    SetAlliance(teamID, old, false)
                end
                
                teamStates[teamID].state = STATE_PARTNER
                teamStates[teamID].partner = targetTeam
                teamStates[targetTeam].state = STATE_PARTNER
                teamStates[targetTeam].partner = teamID
                SetAlliance(teamID, targetTeam, true)
                pendingProposals[targetTeam]["partner"] = nil
                Spring.Echo(TeamName(teamID) .. " and " .. TeamName(targetTeam) .. " have formed a Partnership!")
            else
                pendingProposals[teamID]["partner"] = targetTeam
                -- Send private messages instead of a global echo
                Spring.SendMessageToTeam(teamID, "You secretly proposed a Partnership to " .. TeamName(targetTeam))
                Spring.SendMessageToTeam(targetTeam, TeamName(teamID) .. " secretly proposed a Partnership to you! Click 'Partner' to accept.")
            end

        elseif action == "fealty" and targetTeam then
            pendingProposals[teamID]["fealty"] = targetTeam
            Spring.SendMessageToTeam(teamID, "You secretly offered to swear fealty to " .. TeamName(targetTeam))
            Spring.SendMessageToTeam(targetTeam, TeamName(teamID) .. " offers to swear fealty to you! Click 'Accept' to vassalize them.")

        elseif action == "demand" and targetTeam then
            pendingProposals[teamID]["demand"] = targetTeam
            Spring.SendMessageToTeam(teamID, "You secretly demanded that " .. TeamName(targetTeam) .. " swear fealty to you.")
            Spring.SendMessageToTeam(targetTeam, TeamName(teamID) .. " demands you swear fealty to them! Click 'Accept' to submit and become their Vassal.")

        elseif action == "accept" and targetTeam then
            if pendingProposals[targetTeam]["fealty"] == teamID then
                -- Target offered to be my vassal. I (teamID) am the King. Target is the Vassal.
                MakeVassal(teamID, targetTeam)
                pendingProposals[targetTeam]["fealty"] = nil

            elseif pendingProposals[targetTeam]["demand"] == teamID then
                -- Target demanded I be their vassal. I (teamID) am the Vassal. Target is the King.
                MakeVassal(targetTeam, teamID)
                pendingProposals[targetTeam]["demand"] = nil
            end
        end
        return true -- Hide command from global chat
    end
    return false
end

function gadget:RecvChat(playerID, msg, text)
    local _, _, spectator, teamID = Spring.GetPlayerInfo(playerID)
    if spectator then return false end
    return HandleCommand(playerID, teamID, msg)
end

-- Widgets forward "/diplomacy ..." commands here, since plain chat never reaches gadgets.
-- Test hook (cheats only): "/diplomacy as <teamID> <action> ..." acts as another team, e.g. an AI.
function gadget:RecvLuaMsg(msg, playerID)
    if msg:sub(1, 10) ~= "/diplomacy" then return end
    local asTeam, rest = msg:match("^/diplomacy%s+as%s+(%d+)%s+(.*)$")
    if asTeam then
        if not Spring.IsCheatingEnabled() then
            Spring.SendMessageToPlayer(playerID, "'/diplomacy as' needs cheats (/cheat 1)")
            return true
        end
        return HandleCommand(playerID, tonumber(asTeam), "/diplomacy " .. rest)
    end
    return gadget:RecvChat(playerID, msg, msg)
end
