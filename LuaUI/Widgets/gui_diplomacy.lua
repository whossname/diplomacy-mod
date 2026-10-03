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

local panelX, panelY = 0, 400  
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
local function TeamLabel(tID)
    local _, leader, _, isAI = Spring.GetTeamInfo(tID)
    local name
    if isAI then
        local _, aiName = Spring.GetAIInfo(tID)
        name = aiName
    elseif leader and leader >= 0 then
        name = Spring.GetPlayerInfo(leader)
    end
    return (name and name ~= "" and name) or ("Team " .. tID)
end

function widget:TextCommand(command)
    local name, args = command:match("^(%S+)%s*(.*)$")
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
    local totalH = 40 
    if uiState == "MAIN" then
        totalH = totalH + (5 * rowH) + 15
        local propCount = 0
        for k, v in pairs(incomingProposals) do propCount = propCount + 1 end
        if propCount > 0 then
            totalH = totalH + 30 + (propCount * rowH)
        end
    elseif uiState == "SELECT" then
        totalH = totalH + (#otherTeams * rowH) + rowH + 10
    end

    bgRect = {x = panelX, y = panelY - totalH, w = panelW, h = totalH}

    -- 2. Draw Background
    gl.Color(0.1, 0.15, 0.15, 0.9)
    gl.Rect(bgRect.x, bgRect.y, bgRect.x + bgRect.w, bgRect.y + bgRect.h)

    -- 3. Draw Title
    gl.Color(1, 1, 1, 1)
    if uiState == "MAIN" then
        gl.Text("Diplomacy Menu", panelX + 10, panelY - 20, 14, "o")
    else
        gl.Text("Select Target Team", panelX + 10, panelY - 20, 14, "o")
    end

    local currentY = panelY - 50

    -- 4. Draw Specific Screen
    if uiState == "MAIN" then
        -- Top Buttons
        AddButton("info", "My Status Info", panelX + 10, currentY, panelW/2 - 15, 22, {0.2, 0.6, 1})
        AddButton("dissolve", "Dissolve Alliance", panelX + panelW/2 + 5, currentY, panelW/2 - 15, 22, {0.8, 0.2, 0.2})
        currentY = currentY - (rowH + 10)

        -- Action Buttons
        AddButton("menu_partner", "Propose Partnership", panelX + 10, currentY, panelW - 20, 22, {0.2, 0.8, 0.2})
        currentY = currentY - rowH
        AddButton("menu_fealty", "Offer Fealty (Become Vassal)", panelX + 10, currentY, panelW - 20, 22, {0.8, 0.5, 0.1})
        currentY = currentY - rowH
        AddButton("menu_demand", "Demand Fealty (Become King)", panelX + 10, currentY, panelW - 20, 22, {0.8, 0.2, 0.6})
        currentY = currentY - rowH

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
        for _, tID in ipairs(otherTeams) do
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
            
            if btn.id == "info" then
                Spring.SendLuaRulesMsg("/diplomacy info")
            elseif btn.id == "dissolve" then
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
