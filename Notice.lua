getgenv().Commands = {
    ["Hide"] = "/e hide",
    ["UnHide"] = "/e unhide"
}

game:GetService("Players").LocalPlayer.Chatted:Connect(function(message)
    local msg = message:lower()

    if msg == getgenv().Commands["Hide"]:lower() then
        game:GetService("Players").LocalPlayer.PlayerGui.ZxL_SidePanel.ZxL_menu.Visible = false
    elseif msg == getgenv().Commands["UnHide"]:lower() then
        game:GetService("Players").LocalPlayer.PlayerGui.ZxL_SidePanel.ZxL_menu.Visible = true
    end
end)

game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed then
        if input.KeyCode == Enum.KeyCode.F4 then
            game:GetService("Players").LocalPlayer.PlayerGui.ZxL_SidePanel.ZxL_menu.Visible = false
        end
    end
end)