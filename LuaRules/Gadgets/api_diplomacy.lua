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
    Spring.Echo("Team " .. teamID .. " has been eliminated from the game.")
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
        
        Spring.Echo("Partnership collapsed! Team " .. partnerID .. " is now King, and Team " .. teamID .. " is their Vassal.")
        
    elseif data.state == STATE_KING then
        Spring.Echo("The King (Team " .. teamID .. ") has fallen! The Kingdom crumbles.")
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
            for i, v in ipairs(teamStates[oldKing].vassals) do
                if v == teamID then
                    table.remove(teamStates[oldKing].vassals, i)
                    break
                end
            end
        end
        Spring.Echo("Team " .. teamID .. " has obtained a Commander and is now Independent!")
    end
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
    
    Spring.Echo("Team " .. kingID .. " accepted Team " .. vassalID .. " as a Vassal and seized " .. transferredCount .. " Commander(s)!")
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
        if oldTeam ~= Spring.GetGaiaTeamID() then
            teamCommanders[oldTeam] = math.max(0, (teamCommanders[oldTeam] or 1) - 1)
            if teamCommanders[oldTeam] == 0 then
                HandleLastCommanderLost(oldTeam)
            end
        end
        if newTeam ~= Spring.GetGaiaTeamID() then
            teamCommanders[newTeam] = (teamCommanders[newTeam] or 0) + 1
            if teamCommanders[newTeam] == 1 then
                HandleCommanderObtained(newTeam)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Call-ins: Chat Commands for Diplomacy
--------------------------------------------------------------------------------
function gadget:RecvChat(playerID, msg, text)
    local name, active, spectator, teamID = Spring.GetPlayerInfo(playerID)
    if spectator or teamStates[teamID] == nil then return false end
    
    local words = {}
    for word in msg:gmatch("%S+") do table.insert(words, word) end
    
    if words[1] == "/diplomacy" then
        local action = words[2]
        local targetTeam = tonumber(words[3])
        
        -- Prevent actions if Eliminated or a Vassal (Vassals have no diplomatic rights)
        if teamStates[teamID].state == STATE_ELIM or teamStates[teamID].state == STATE_VASSAL then
            Spring.SendMessageToPlayer(playerID, "You do not have diplomatic rights.")
            return true
        end

        if action == "info" then
            Spring.SendMessageToPlayer(playerID, "Your State: " .. teamStates[teamID].state .. " | Commanders: " .. teamCommanders[teamID])
            
        elseif action == "dissolve" then
            if teamStates[teamID].state == STATE_PARTNER then
                local partner = teamStates[teamID].partner
                teamStates[teamID].state = STATE_INDEP
                teamStates[teamID].partner = nil
                teamStates[partner].state = STATE_INDEP
                teamStates[partner].partner = nil
                SetAlliance(teamID, partner, false)
                Spring.Echo("Team " .. teamID .. " dissolved the partnership with Team " .. partner)
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
                Spring.Echo("Team " .. teamID .. " and Team " .. targetTeam .. " have formed a Partnership!")
            else
                pendingProposals[teamID]["partner"] = targetTeam
                -- Send private messages instead of a global echo
                Spring.SendMessageToTeam(teamID, "You secretly proposed a Partnership to Team " .. targetTeam)
                Spring.SendMessageToTeam(targetTeam, "Team " .. teamID .. " secretly proposed a Partnership to you! Click 'Partner' to accept.")
            end

        elseif action == "fealty" and targetTeam then
            pendingProposals[teamID]["fealty"] = targetTeam
            Spring.SendMessageToTeam(teamID, "You secretly offered to swear fealty to Team " .. targetTeam)
            Spring.SendMessageToTeam(targetTeam, "Team " .. teamID .. " offers to swear fealty to you! Click 'Accept' to vassalize them.")

        elseif action == "demand" and targetTeam then
            pendingProposals[teamID]["demand"] = targetTeam
            Spring.SendMessageToTeam(teamID, "You secretly demanded that Team " .. targetTeam .. " swear fealty to you.")
            Spring.SendMessageToTeam(targetTeam, "Team " .. teamID .. " demands you swear fealty to them! Click 'Accept' to submit and become their Vassal.")

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
