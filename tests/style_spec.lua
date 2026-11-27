-- Flat style kit shared by every window (Style.lua).
local H = require("harness")
local mock = H.mock
local eq, ok, no = H.eq, H.ok, H.no

return {
    { "an input shows its placeholder only while empty", function()
        local ET, env = H.boot()
        local e = ET.UI.EditBox(env.UIParent, 100, nil, "Search")
        eq(e.placeholder:GetText(), "Search")
        ok(e.placeholder:IsShown())
        e:SetText("Ivan")
        no(e.placeholder:IsShown(), "typed text hides it")
        e:SetText("")
        ok(e.placeholder:IsShown())
    end },

    { "buttons keep the normal button behaviour", function()
        local ET, env = H.boot()
        local clicked = 0
        local b = ET.UI.Button(env.UIParent, "Add", 80, "ETStyleTestButton", "primary")
        b:SetScript("OnClick", function() clicked = clicked + 1 end)
        mock.click(b)
        eq(clicked, 1)
        eq(b:GetText(), "Add")
        b:SetEnabled(false)
        no(b:IsEnabled())
        b:RunScript("OnEnter") -- hover on a disabled button must not error
        H.noErrors(env)
    end },

    { "palette colours render as chat colour codes", function()
        local ET = H.boot()
        eq(ET.UI.Color("muted", "-"), ET.UI.Hex("muted") .. "-|r")
        ok(ET.UI.Hex("accent"):match("^|cff%x%x%x%x%x%x$"))
    end },

}
