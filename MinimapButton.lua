-- Enemy Tracker: round minimap button (left-click: dashboard, right-click: settings,
-- drag: move around the minimap edge; angle saved).
local _, ET = ...
local L = ET.L

local button

local function updatePosition()
    local angle = math.rad(ET.db.minimap.angle or 220)
    local radius = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    ET.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    updatePosition()
end

local function create()
    button = CreateFrame("Button", "EnemyTrackerMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then ET:OpenOptions() else ET:ToggleDashboard() end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Enemy Tracker")
        GameTooltip:AddLine(string.format(L.COUNTER, ET:NearbyCount()), 1, 0.3, 0.3)
        GameTooltip:AddLine(L.MINIMAP_TIP_LEFT, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TIP_RIGHT, 1, 1, 1)
        GameTooltip:AddLine(L.MINIMAP_TIP_DRAG, 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updatePosition()
    button:SetShown(ET.db.settings.showMinimap)
end

ET:On("LOGIN", create)
ET:On("SETTINGS_CHANGED", function(what)
    if button and what == "showMinimap" then button:SetShown(ET.db.settings.showMinimap) end
end)
