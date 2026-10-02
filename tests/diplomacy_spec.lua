-- Unit tests for LuaRules/Gadgets/api_diplomacy.lua
--
-- Run with: lua tests/run_tests.lua   (see tests/README.md)

local scriptDir = _G.TEST_DIR or (arg and arg[0] and arg[0]:match("(.*/)")) or "./"

local framework = dofile(scriptDir .. "test_framework.lua")
local createMockEnv = dofile(scriptDir .. "mock_env.lua")

local GADGET_PATH = scriptDir .. "../LuaRules/Gadgets/api_diplomacy.lua"

local describe, it, expect = framework.describe, framework.it, framework.expectValue

-- Builds a fresh mock environment with Initialize() already called, so every
-- test starts from a clean slate of Independent teams.
local function newGame(teams)
    local env = createMockEnv(GADGET_PATH, { teams = teams })
    env.gadget:Initialize()
    return env
end

-- Drives the two-sided chat handshake used by /diplomacy partner.
local function formPartnership(env, teamA, teamB)
    env.chat(teamA, "/diplomacy partner " .. teamB)
    env.chat(teamB, "/diplomacy partner " .. teamA)
end

-- Drives the two-sided chat handshake used by /diplomacy fealty + accept.
local function swearFealty(env, vassalTeam, kingTeam)
    env.chat(vassalTeam, "/diplomacy fealty " .. kingTeam)
    env.chat(kingTeam, "/diplomacy accept " .. vassalTeam)
end

describe("Independent teams", function()
    it("are eliminated when their last Commander dies", function()
        local env = newGame({ 1, 2 })
        local cmd = env.spawnCommander(1)
        env.killUnit(cmd, 1)

        expect(env.calls.killTeam).toEqual({ 1 })
    end)
end)

describe("Partnership", function()
    it("allies both teams immediately", function()
        local env = newGame({ 1, 2 })
        formPartnership(env, 1, 2)

        expect(env.isAllied(1, 2)).toBe(true)
    end)

    it("collapses into a King/Vassal pair when one partner loses their last Commander", function()
        local env = newGame({ 1, 2 })
        local cmd1 = env.spawnCommander(1)
        formPartnership(env, 1, 2)

        env.killUnit(cmd1, 1)

        -- Neither team is eliminated; the partnership becomes a fealty bond instead.
        expect(env.calls.killTeam).toEqual({})

        -- Team 2 (the survivor/new King) should still be able to eliminate the
        -- whole "kingdom" (itself + Team 1) if it later loses its own last Commander.
        local cmd2 = env.spawnCommander(2)
        env.killUnit(cmd2, 2)
        expect(env.calls.killTeam).toEqual({ 2, 1 })
    end)
end)

describe("Fealty", function()
    it("transfers the Vassal's Commanders to the King", function()
        local env = newGame({ 1, 2 })
        local cmd = env.spawnCommander(2) -- vassal-to-be has a commander
        swearFealty(env, 2, 1) -- team 2 swears fealty to team 1

        expect(env.isAllied(1, 2)).toBe(true)
        expect(env.calls.transferUnit[1].unitID).toBe(cmd)
        expect(env.calls.transferUnit[1].newTeam).toBe(1)
    end)

    it("regaining a Commander restores Independence and leaves the King's vassal list", function()
        local env = newGame({ 1, 2, 3 })
        swearFealty(env, 2, 1)
        swearFealty(env, 3, 1) -- King 1 now has two vassals: 2 and 3

        env.spawnCommander(2) -- team 2 obtains a commander and should become Independent again

        -- Team 1 still has vassal 3, so it should still behave like a King:
        -- losing its last commander should take vassal 3 down with it, but NOT team 2.
        local kingCmd = env.spawnCommander(1)
        env.killUnit(kingCmd, 1)
        expect(env.calls.killTeam).toEqual({ 1, 3 })
    end)
end)

describe("Bug fix: King losing their last Vassal", function()
    it("becomes Independent again instead of staying stuck as King", function()
        local env = newGame({ 1, 2, 3 })
        swearFealty(env, 2, 1) -- team 1 is King with a single vassal, team 2

        -- Team 2 (the only vassal) regains a commander and leaves -- team 1
        -- should fall back to Independent, which (unlike King) is allowed to
        -- form a brand-new Partnership.
        env.spawnCommander(2)

        formPartnership(env, 1, 3)

        expect(env.isAllied(1, 3)).toBe(true)
    end)
end)

describe("Bug fix: King gifting their last Commander to their own Vassal", function()
    it("reverses the relationship instead of eliminating the kingdom", function()
        local env = newGame({ 1, 2, 3 })
        local kingCmd = env.spawnCommander(1) -- King (team 1) has exactly one Commander
        swearFealty(env, 2, 1) -- team 2 becomes a vassal of team 1
        swearFealty(env, 3, 1) -- team 3 also becomes a vassal of team 1

        env.giftUnit(kingCmd, 2) -- King gifts their last Commander to vassal team 2

        -- Nobody should have been eliminated by the gift itself.
        expect(env.calls.killTeam).toEqual({})

        -- Team 2 should now be King (inheriting team 3 as a vassal) and team 1
        -- should now be team 2's vassal. Prove this by killing the gifted
        -- commander (team 2's only one): it should bring down team 2's whole
        -- new "kingdom" -- itself, plus team 3 and team 1.
        env.killUnit(kingCmd, 2)
        expect(env.calls.killTeam).toEqual({ 2, 3, 1 })
    end)
end)

return framework.run()
