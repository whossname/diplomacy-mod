-- Builds an isolated mock of the subset of the Spring/Recoil engine API that
-- LuaRules/Gadgets/api_diplomacy.lua relies on, loads a fresh copy of the
-- gadget into that sandbox, and returns helpers for driving it from tests.
--
-- Each call to createMockEnv() loads an independent copy of the gadget chunk
-- so tests never leak state into one another.

local function createMockEnv(gadgetPath, opts)
    opts = opts or {}
    local GAIA = 255
    local teams = opts.teams or { 1, 2, 3, 4 }

    local env = {}
    env.calls = {
        echo = {},
        killTeam = {},
        setAlly = {},
        transferUnit = {},
        messagesToPlayer = {},
        messagesToTeam = {},
    }
    env.allyState = {}
    env.unitDefByUnit = {}
    env.unitsByTeam = {}
    env.playerTeam = {}
    env.nextUnitID = 1
    for _, t in ipairs(teams) do
        env.unitsByTeam[t] = {}
        env.playerTeam[t] = t -- one player per team, playerID == teamID for simplicity
    end

    -- Minimal UnitDefs table: def 1 is a regular unit, def 2 is a commander.
    local UnitDefs = {
        [1] = { customParams = {} },
        [2] = { customParams = { commander = 1 } },
    }

    local function allyKey(a, b)
        return a .. ">" .. b -- directional, like the real teamHandler
    end

    local Spring = {}

    function Spring.GetGaiaTeamID()
        return GAIA
    end

    function Spring.GetTeamList()
        return teams
    end

    function Spring.GetAIInfo() return nil, nil end

    function Spring.GetTeamInfo(teamID)
        -- Returns allyTeamID as the 6th value, matching the real API shape.
        -- One allyteam per team by default (typical FFA setup).
        return teamID, nil, false, nil, nil, teamID
    end

    function Spring.SetAlly(allyA, allyB, isAllied)
        env.allyState[allyKey(allyA, allyB)] = isAllied
        table.insert(env.calls.setAlly, { allyA, allyB, isAllied })
    end

    function Spring.SetUnitLosMask(unitID, allyTeam, bits)
        env.losMask[unitID .. ">" .. allyTeam] = bits ~= 0 and bits or nil
    end
    function Spring.SetUnitLosState() end
    function Spring.GetUnitPosition() return nil end
    function Spring.GetModOptions() return {} end

    function Spring.KillTeam(teamID)
        table.insert(env.calls.killTeam, teamID)
    end

    function Spring.SendMessageToPlayer(teamID, msg)
        table.insert(env.calls.messagesToPlayer, { teamID, msg })
    end

    function Spring.SendMessageToTeam(teamID, msg)
        table.insert(env.calls.messagesToTeam, { teamID, msg })
    end

    function Spring.Echo(msg)
        table.insert(env.calls.echo, msg)
    end

    function Spring.GetPlayerInfo(playerID)
        local teamID = env.playerTeam[playerID]
        return "Player" .. tostring(playerID), true, false, teamID
    end

    function Spring.GetTeamUnits(teamID)
        local list = {}
        for uID in pairs(env.unitsByTeam[teamID] or {}) do
            table.insert(list, uID)
        end
        return list
    end

    function Spring.GetUnitDefID(unitID)
        return env.unitDefByUnit[unitID]
    end

    function Spring.TransferUnit(unitID, newTeam, given)
        local oldTeam
        for t, units in pairs(env.unitsByTeam) do
            if units[unitID] then
                oldTeam = t
                break
            end
        end
        if oldTeam then
            env.unitsByTeam[oldTeam][unitID] = nil
        end
        env.unitsByTeam[newTeam] = env.unitsByTeam[newTeam] or {}
        env.unitsByTeam[newTeam][unitID] = true
        table.insert(env.calls.transferUnit, { unitID = unitID, oldTeam = oldTeam, newTeam = newTeam })

        -- The real engine fires the synced UnitGiven call-in for every gadget
        -- as a direct result of a unit transfer; replicate that here so
        -- MakeVassal()'s automatic commander seizure behaves like a real match.
        if env.gadget and env.gadget.UnitGiven then
            local unitDefID = env.unitDefByUnit[unitID]
            env.gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
        end
    end

    local gadgetHandler = {}
    function gadgetHandler.IsSyncedCode()
        return true
    end

    local gadget = {}

    -- BAR/Spring loads each gadget file as its own chunk with `gadget` and the
    -- engine API pre-populated as globals (not Lua's real _G). Replicate that
    -- via a sandboxed environment table so state never leaks between tests.
    local chunkEnv = setmetatable({
        gadget = gadget,
        gadgetHandler = gadgetHandler,
        Spring = Spring,
        UnitDefs = UnitDefs,
    }, { __index = _G })

    local chunk = assert(loadfile(gadgetPath, "t", chunkEnv))
    chunk()

    env.gadget = gadget
    env.Spring = Spring
    env.losMask = {}
    env.teams = teams
    env.GAIA = GAIA

    function env.isAllied(a, b)
        return env.allyState[allyKey(a, b)] == true and env.allyState[allyKey(b, a)] == true
    end

    function env.spawnCommander(teamID)
        local uID = env.nextUnitID
        env.nextUnitID = env.nextUnitID + 1
        env.unitDefByUnit[uID] = 2 -- commander def
        env.unitsByTeam[teamID] = env.unitsByTeam[teamID] or {}
        env.unitsByTeam[teamID][uID] = true
        gadget:UnitCreated(uID, 2, teamID, nil)
        return uID
    end

    function env.killUnit(unitID, teamID)
        local unitDefID = env.unitDefByUnit[unitID]
        env.unitsByTeam[teamID][unitID] = nil
        gadget:UnitDestroyed(unitID, unitDefID, teamID, nil, nil, nil)
    end

    function env.giftUnit(unitID, newTeam)
        Spring.TransferUnit(unitID, newTeam, true)
    end

    function env.chat(playerID, msg)
        return gadget:RecvChat(playerID, msg, msg)
    end

    return env
end

return createMockEnv
