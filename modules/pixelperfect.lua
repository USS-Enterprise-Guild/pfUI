pfUI:RegisterModule("pixelperfect", "vanilla:tbc", function ()
  -- pre-calculated min values
  local statics = {
    [1] = nil, -- auto-calculate
    [4] = 1.4222222222222,
    [5] = 1.1377777777778,
    [6] = 0.94814814814815,
    [7] = 0.81269841269841,
    [8] = 0.71111111111111,  -- 1080p
    [9] = 0.53333333333333,  -- 1440p
    [10] = 0.35555555555556, -- 4K
  }

  -- pixel perfect
  local function pixelperfect()
    local conf = tonumber(C.global.pixelperfect)
    if conf < 1 then
      -- restore gamesettings (conf == 0, Off)
      local scale = GetCVar("uiScale")
      local use = GetCVar("useUiScale")

      if use == "1" then
        UIParent:SetScale(tonumber(scale))
      else
        UIParent:SetScale(.9)
      end
    elseif conf == 1 then
      -- auto-calculate: 768 / screen height
      local scale = 768 / GetScreenHeight()
      SetCVar("uiScale", scale)
      SetCVar("useUiScale", 1)
      UIParent:SetScale(scale)
    else
      -- use static value
      local scale = statics[conf] or 1

      SetCVar("uiScale", scale)
      SetCVar("useUiScale", 1)

      UIParent:SetScale(scale)
    end
  end

  -- pixelperfect: native UIScale listener
  if tonumber(C.global.pixelperfect) > 0 then
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", pixelperfect)
    pixelperfect()
  end

  pfUI.pixelperfect = {
    UpdateConfig = pixelperfect
  }
end)
