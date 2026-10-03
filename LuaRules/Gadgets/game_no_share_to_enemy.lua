local gadget = gadget ---@type Gadget

function gadget:GetInfo()
    return {
        name    = "game_no_share_to_enemy",
        desc    = "Diplomacy Mod override of BAR's gadget: units and resources can be given to any team",
        author  = "BAR Modder",
        date    = "2026",
        license = "GNU GPL, v2 or later",
        layer   = 0,
        enabled = true,
    }
end

if not gadgetHandler:IsSyncedCode() then
    return
end

-- Anyone can give resources to anyone.
function gadget:AllowResourceTransfer(oldTeam, newTeam, type, amount)
    return true
end

-- BAR's version refuses unit transfers between non-allied teams; here anyone can give units to anyone.
function gadget:AllowUnitTransfer(unitID, unitDefID, oldTeam, newTeam, capture)
    return true
end
