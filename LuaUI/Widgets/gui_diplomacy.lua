function widget:GetInfo()
    return {
        name      = "Diplomacy UI V2",
        desc      = "Menu-driven interface for Diplomacy FSM",
        author    = "BAR Modder",
        date      = "2026",
        license   = "GNU GPL, v2",
        layer     = 0,
        enabled   = true
    }
end

--------------------------------------------------------------------------------
-- State & Configuration
--------------------------------------------------------------------------------
local uiState = "MAIN"          -- "MAIN" or "SELECT"
local pendingAction = nil       -- "partner", "fealty", or "demand"
local incomingProposals = {}    -- Stores proposals parsed from chat

local panelX, panelY = 0, 650  
local panelW = 320
local rowH = 30

local myTeamID = Spring.GetMyTeamID()
local otherTeams = {}

-- We rebuild hitboxes every frame based on the active screen
local clickables = {}
local bgRect = {x=0, y=0, w=0, h=0}

--------------------------------------------------------------------------------
-- Initialization & Chat Listener
--------------------------------------------------------------------------------
local COLORS = {
    King        = {0.8, 0.6, 0.0},
    Vassal      = {0.85, 0.15, 0.15},
    Partnership = {0.2, 0.8, 0.2},
    Independent = {0.25, 0.5, 1.0},
}

local function ColorCode(c)
    return string.char(255, math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end
local WHITE = string.char(255, 255, 255, 255)

local function Colored(text, state)
    return ColorCode(COLORS[state]) .. text .. WHITE
end

local function TeamLabel(tID)
    local _, leader, _, isAI = Spring.GetTeamInfo(tID)
    local name
    if isAI then
        -- Match the name shown by the player list / enemies panel
        name = Spring.GetGameRulesParam("ainame_" .. tID)
        if not name or name == "" then
            local _, aiName = Spring.GetAIInfo(tID)
            name = aiName
        end
        if name and name ~= "" then name = name .. " (AI)" end
    elseif leader and leader >= 0 then
        name = Spring.GetPlayerInfo(leader)
    end
    return (name and name ~= "" and name) or ("Team " .. tID)
end

-- Fallback state parsed from "/diplomacy info" replies, used when the gadget
-- hasn't published team rules params (e.g. widget reloaded mid-game)
local info = {}
local infoTimer, infoTries = 0, 0

local function DipParam(tID, rulesKey, infoKey)
    local v = Spring.GetTeamRulesParam(tID, rulesKey)
    if v == nil and tID == myTeamID then v = info[infoKey] end
    return v
end

local function GetDipState(tID)
    return DipParam(tID, "dipState", "state") or "Independent"
end

function widget:Update(dt)
    if Spring.GetTeamRulesParam(myTeamID, "dipState") ~= nil or infoTries >= 5 then return end
    infoTimer = infoTimer - dt
    if infoTimer <= 0 then
        infoTimer = 2
        infoTries = infoTries + 1
        Spring.SendLuaRulesMsg("/diplomacy info")
    end
end

local function IsTeamAlive(tID)
    local _, _, isDead = Spring.GetTeamInfo(tID)
    return not isDead and GetDipState(tID) ~= "Eliminated"
end

-- Teams that can be diplomatically targeted: alive and not a vassal
local function BuildTargets()
    local list = {}
    for _, tID in ipairs(otherTeams) do
        if IsTeamAlive(tID) and GetDipState(tID) ~= "Vassal" then
            list[#list + 1] = tID
        end
    end
    return list
end

local function StatusText()
    local state = GetDipState(myTeamID)
    if state == "Vassal" then
        local king = DipParam(myTeamID, "dipKing", "king") or -1
        return Colored("Vassal", "Vassal") .. " to " .. (king >= 0 and TeamLabel(king) or "?")
    end
    local cmdrs = (DipParam(myTeamID, "dipCmdrs", "cmdrs") or 0) .. " Cmdrs, "
    if state == "King" then
        local names = {}
        for id in string.gmatch(DipParam(myTeamID, "dipVassals", "vassals") or "", "%d+") do
            names[#names + 1] = TeamLabel(tonumber(id))
        end
        return cmdrs .. Colored("King", "King") .. " of " .. table.concat(names, ", ")
    elseif state == "Partnership" then
        local p = DipParam(myTeamID, "dipPartner", "partner") or -1
        return cmdrs .. Colored("Partner", "Partnership") .. " with " .. (p >= 0 and TeamLabel(p) or "?")
    end
    return cmdrs .. Colored("Independent", "Independent")
end

function widget:TextCommand(command)
    local name, args = command:match("^(%S+)%s*(.*)$")
    -- Test hook: "/diplo seen <team>" counts that team's units the local client can see (unsynced GetTeamUnits respects LOS)
    local seenTeam = name == "diplo" and args:match("^seen%s+(%d+)")
    if seenTeam then
        local t = tonumber(seenTeam)
        local seen, drawn = Spring.GetTeamUnits(t) or {}, 0
        for _, uID in ipairs(seen) do
            if Spring.IsUnitVisible(uID, nil, true) or Spring.IsUnitIcon(uID) then drawn = drawn + 1 end
        end
        local st = seen[1] and Spring.GetUnitLosState(seen[1], Spring.GetMyAllyTeamID(), true)
        Spring.Echo("[Diplomacy] client sees " .. #seen .. " units of team " .. t .. ", drawable=" .. drawn .. ", firstLosState=" .. tostring(st) .. ", fullview=" .. tostring(select(2, Spring.GetSpectatingState())))
        return true
    end

    -- Test hook: "/diplo shareunit <team> <unitdefname>" shares one of my units of that type via the engine
    local shTeam, shDef = args:match("^shareunit%s+(%d+)%s+(%S+)")
    if name == "diplo" and shTeam then
        local picked = {}
        for _, uID in ipairs(Spring.GetTeamUnits(myTeamID)) do
            if UnitDefs[Spring.GetUnitDefID(uID)].name == shDef then picked[1] = uID; break end
        end
        Spring.SelectUnitArray(picked)
        Spring.ShareResources(tonumber(shTeam), "units")
        Spring.Echo("[Diplomacy] shared " .. #picked .. " " .. shDef .. " with team " .. shTeam)
        return true
    end

    -- Test hook: "/diplo sharecmdr <team>" shares one of my Commanders via the engine, like the player list's share button
    local shareTeam = name == "diplo" and args:match("^sharecmdr%s+(%d+)")
    if shareTeam then
        local cmdrs = {}
        for _, uID in ipairs(Spring.GetTeamUnits(myTeamID)) do
            local ud = UnitDefs[Spring.GetUnitDefID(uID)]
            if ud and (ud.customParams.iscommander or ud.customParams.commander) then cmdrs[1] = uID; break end
        end
        Spring.SelectUnitArray(cmdrs)
        Spring.ShareResources(tonumber(shareTeam), "units")
        Spring.Echo("[Diplomacy] shared " .. #cmdrs .. " commander with team " .. shareTeam)
        return true
    end
    if name == "diplomacy" or name == "diplo" then
        Spring.SendLuaRulesMsg("/diplomacy " .. args)
        return true
    end
end

function widget:Initialize()
    local teams = Spring.GetTeamList()
    for _, tID in ipairs(teams) do
        if tID ~= myTeamID and tID ~= Spring.GetGaiaTeamID() then
            table.insert(otherTeams, tID)
        end
    end
end

function widget:AddConsoleLine(msg, priority)
    local st, cm, pa, ki, va = string.match(msg, "State: (%a+) | Commanders: (%d+) | Partner: (%-?%d+) | King: (%-?%d+) | Vassals: ([%d,]*)")
    if st then
        info = {state = st, cmdrs = tonumber(cm), partner = tonumber(pa), king = tonumber(ki), vassals = va}
        return
    end
    if string.find(msg, "You do not have diplomatic rights", 1, true) then
        info.state = "Vassal"
        return
    end

    -- Listen to the private messages sent by the server to detect proposals
    local tID = string.match(msg, "%(Team (%d+)%) secretly proposed a Partnership")
    if tID then incomingProposals[tonumber(tID)] = "Partnership"; return end

    tID = string.match(msg, "%(Team (%d+)%) offers to swear fealty")
    if tID then incomingProposals[tonumber(tID)] = "Fealty Offer"; return end

    tID = string.match(msg, "%(Team (%d+)%) demands you swear fealty")
    if tID then incomingProposals[tonumber(tID)] = "Fealty Demand"; return end
end

--------------------------------------------------------------------------------
-- Drawing (Immediate Mode UI)
--------------------------------------------------------------------------------
local function AddButton(id, label, x, y, w, h, color, data)
    table.insert(clickables, {id=id, x=x, y=y, w=w, h=h, data=data})
    gl.Color(color[1], color[2], color[3], color[4] or 0.8)
    gl.Rect(x, y, x + w, y + h)
    gl.Color(1, 1, 1, 1)
    gl.Text(label, x + 10, y + (h/2) - 4, 12, "o")
end

function widget:DrawScreen()
    if Spring.GetSpectatingState() then return end
    clickables = {} -- Reset buttons every frame

    -- 1. Calculate dynamic background height
    local state = GetDipState(myTeamID)
    local showPartner = state == "Partnership" or state == "Independent"
    local showFealty = showPartner
    local showDemand = state ~= "Vassal"
    local showDissolve = state == "Partnership"
    local buttonCount = (showPartner and 1 or 0) + (showFealty and 1 or 0) + (showDemand and 1 or 0) + (showDissolve and 1 or 0)
    local targets = BuildTargets()
    if state == "Vassal" then incomingProposals = {} end

    local totalH = 40 
    if uiState == "MAIN" then
        totalH = totalH + (buttonCount * rowH) + 5
        local propCount = 0
        for k, v in pairs(incomingProposals) do propCount = propCount + 1 end
        if propCount > 0 then
            totalH = totalH + 30 + (propCount * rowH)
        end
    elseif uiState == "SELECT" then
        totalH = totalH + (#targets * rowH) + rowH + 10
    end

    bgRect = {x = panelX, y = panelY - totalH, w = panelW, h = totalH}

    -- 2. Draw Background
    gl.Color(0.1, 0.15, 0.15, 0.9)
    gl.Rect(bgRect.x, bgRect.y, bgRect.x + bgRect.w, bgRect.y + bgRect.h)

    -- 3. Draw Title
    gl.Color(1, 1, 1, 1)
    if uiState == "MAIN" then
        gl.Text(StatusText(), panelX + 10, panelY - 20, 14, "o")
    else
        gl.Text("Select Target Team", panelX + 10, panelY - 20, 14, "o")
    end

    local currentY = panelY - 50

    -- 4. Draw Specific Screen
    if uiState == "MAIN" then
        if showPartner then
            AddButton("menu_partner", "Propose Partnership", panelX + 10, currentY, panelW - 20, 22, COLORS.Partnership)
            currentY = currentY - rowH
        end
        if showFealty then
            AddButton("menu_fealty", "Offer Fealty", panelX + 10, currentY, panelW - 20, 22, COLORS.Vassal)
            currentY = currentY - rowH
        end
        if showDemand then
            AddButton("menu_demand", "Demand Fealty", panelX + 10, currentY, panelW - 20, 22, COLORS.King)
            currentY = currentY - rowH
        end
        if showDissolve then
            AddButton("dissolve", "Dissolve Alliance", panelX + 10, currentY, panelW - 20, 22, COLORS.Independent)
            currentY = currentY - rowH
        end

        -- Incoming Proposals (Only drawn if they exist)
        local hasProps = false
        for k, v in pairs(incomingProposals) do hasProps = true; break end

        if hasProps then
            currentY = currentY - 10
            gl.Color(1, 0.8, 0, 1)
            gl.Text("Pending Proposals:", panelX + 10, currentY, 12, "o")
            currentY = currentY - 25

            for tID, pType in pairs(incomingProposals) do
                gl.Color(1, 1, 1, 1)
                gl.Text(TeamLabel(tID) .. " (" .. pType .. ")", panelX + 10, currentY + 5, 11, "o")
                AddButton("accept", "Accept", panelX + 180, currentY, 60, 22, {0.2, 0.8, 0.2}, tID)
                AddButton("decline", "Decline", panelX + 250, currentY, 60, 22, {0.8, 0.2, 0.2}, tID)
                currentY = currentY - rowH
            end
        end

    elseif uiState == "SELECT" then
        -- List all eligible teams
        for _, tID in ipairs(targets) do
            local r, g, b = Spring.GetTeamColor(tID)
            AddButton("select_team", TeamLabel(tID), panelX + 10, currentY, panelW - 20, 22, {r, g, b, 0.7}, tID)
            currentY = currentY - rowH
        end

        currentY = currentY - 10
        AddButton("back", "<- Back", panelX + 10, currentY, panelW - 20, 22, {0.4, 0.4, 0.4})
    end
end

--------------------------------------------------------------------------------
-- Input Handling
--------------------------------------------------------------------------------
local function IsInside(mx, my, rectX, rectY, rectW, rectH)
    return mx >= rectX and mx <= rectX + rectW and my >= rectY and my <= rectY + rectH
end

function widget:MousePress(mx, my, button)
    if button ~= 1 then return false end
    if Spring.GetSpectatingState() then return false end

    -- Check if the click hit any active buttons
    for _, btn in ipairs(clickables) do
        if IsInside(mx, my, btn.x, btn.y, btn.w, btn.h) then
            
            if btn.id == "dissolve" then
                Spring.SendLuaRulesMsg("/diplomacy dissolve")
            elseif btn.id == "menu_partner" then
                uiState = "SELECT"; pendingAction = "partner"
            elseif btn.id == "menu_fealty" then
                uiState = "SELECT"; pendingAction = "fealty"
            elseif btn.id == "menu_demand" then
                uiState = "SELECT"; pendingAction = "demand"
            elseif btn.id == "back" then
                uiState = "MAIN"; pendingAction = nil
            elseif btn.id == "select_team" then
                Spring.SendLuaRulesMsg("/diplomacy " .. pendingAction .. " " .. btn.data)
                uiState = "MAIN"; pendingAction = nil
            elseif btn.id == "accept" then
                Spring.SendLuaRulesMsg("/diplomacy accept " .. btn.data)
                incomingProposals[btn.data] = nil -- Clear from UI
            elseif btn.id == "decline" then
                Spring.SendLuaRulesMsg("/diplomacy decline " .. btn.data)
                incomingProposals[btn.data] = nil -- Clear from UI
            end
            
            return true -- Consume the click
        end
    end

    -- Block clicks from falling through the background panel to the game map
    if IsInside(mx, my, bgRect.x, bgRect.y, bgRect.w, bgRect.h) then 
        return true
    end

    return false
end
