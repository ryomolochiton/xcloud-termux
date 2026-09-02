--[[ 
   🎮 DQ:R Full Auto Replay Tool v4.6
   • Menu UI đẹp • Nút bấm trực tiếp • Auto boss avoid
   • Hỗ trợ Delta/KRNL/Fluxus
--]]

local HttpService = game:GetService("HttpService")

local CONFIG = {
    ENABLE_DEBUG = true,
    AUTO_LOOT = true,
    WALK_SPEED = 45,
    JUMP_POWER = 70,
    SKILL_Q_DELAY = 0.3,
    SKILL_E_DELAY = 1.2,
    ATTACK_RANGE = 8,
    BOSS_AVOID_DISTANCE = 25, -- Tránh boss khi gần hơn X studs
    CUSTOM_SKILL_SEQUENCE = {"Q", "E", "Q"}, -- Seq mặc định
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")
local Camera = workspace.CurrentCamera

local Farming = False
local TargetsKilled = 0
local LastSkillUse = {Q = 0, E = 0}
local CurrentTarget = nil
local MenuGui = Nil
local IsAvoidingBoss = False

-- Apply bypass
local function ApplyBypass()
    local BLACKLIST_REMOTES = {
        "CheckSpeed", "ReportPlayer", "KickPlayer", "DetectFly",
        "VerifyPosition", "ValidateMove", "AntiCheatCheck",
        "ClientHeartbeat", "PlayerStatsUpdate", "MovementValidator"
    }

    for _, name in ipairs(BLACKLIST_REMOTES) do
        local remote = ReplicatedStorage:FindFirstChild(name)
        if remote then remote:Destroy() end
    end

    if Humanoid then
        Humanoid.WalkSpeed = CONFIG.WALK_SPEED
        Humanoid.JumpPower = CONFIG.JUMP_POWER
        Humanoid.AutoRotate = true
    end
end

-- Find nearest enemy
local function FindNearestEnemy()
    local nearest = Nil
    local closestDist = CONFIG.ATTACK_RANGE * 3

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= Character then
            local hum = obj:FindFirstChildWhichIsA("Humanoid")
            if hum and hum.Health > 0 then
                local root = obj:FindFirstChild("HumanoidRootPart")
                if root then
                    local dist = (root.Position - RootPart.Position).Magnitude
                    local nameLower = obj.Name:lower()

                    local isEnemy = false
                    local enemyTags = {"monster", "enemy", "mob", "creature", "boss"}
                    for _, tag in ipairs(enemyTags) do
                        if string.find(nameLower, tag) then
                            isEnemy = true
                            break
                        end
                    end

                    if isEnemy and dist < closestDist then
                        nearest = Obj
                        closestDist = dist
                    end
                end
            end
        end
    end

    return nearest
end

-- Detect boss
local function IsBoss(obj)
    if not Obj then return False end
    local nameLower = obj.Name:lower()
    local bossTags = {"boss", "elite", "miniboss", "champion"}
    for _, tag in ipairs(bossTags) do
        if string.find(nameLower, tag) then
            return True
        end
    end
    return False
end

-- Avoid boss
local function AvoidBoss(boss)
    if not Boss or not Boss:FindFirstChild("HumanoidRootPart") then return end
    
    IsAvoidingBoss = True
    local bossPos = boss.HumanoidRootPart.Position
    local myPos = RootPart.Position
    
    -- Calculate escape direction
    local direction = (myPos - bossPos).unit
    local escapePos = myPos + direction * CONFIG.BOSS_AVOID_DISTANCE
    
    if Humanoid then
        Humanoid:MoveTo(escapePos)
    end
    
    -- Wait until safe distance
    local conn
    conn = Humanoid.MoveToFinished:Connect(function()
        IsAvoidingBoss = False
        conn:Disconnect()
    end)
    
    task.wait(2)
end

-- Use skill
local function UseSkill(key)
    local now = tick()
    local delay = key == "Q" and CONFIG.SKILL_Q_DELAY or CONFIG.SKILL_E_DELAY
    if now - LastSkillUse[key] < delay then return end

    local success, err = pcall(function()
        local events = {
            "UseSkill_" .. key,
            key .. "Skill",
            "CastSkill_" .. key,
            key:upper(),
            key
        }

        for _, name in ipairs(events) do
            local event = ReplicatedStorage:FindFirstChild(name)
            if event then
                if event:IsA("RemoteEvent") then
                    event:FireServer()
                elseif event:IsA("BindableEvent") then
                    event:Fire()
                end
                break
            end
        end

        -- Fallback: simulate keypress
        game:GetService("UserInputService"):InputBegan(
            Enum.UserInputType[key == "Q" and "Q" or "E"], False
        )

        LastSkillUse[key] = now
        if CONFIG.ENABLE_DEBUG then
            print("✨ Used skill:", key)
        end
    end)

    if not success then
        warn("Skill error:", tostring(err):sub(1, 60))
    end
end

-- Execute custom skill sequence
local function ExecuteSkillSequence()
    for _, skill in ipairs(CONFIG.CUSTOM_SKILL_SEQUENCE) do
        UseSkill(skill)
    end
end

-- Move to enemy
local function MoveToEnemy(target)
    if not Target or not Target:FindFirstChild("HumanoidRootPart") then return end

    -- Check if target is boss
    if IsBoss(Target) then
        AvoidBoss(Target)
        return
    end

    local targetPos = Target.HumanoidRootPart.Position
    local myPos = RootPart.Position

    local direction = (targetPos - myPos).unit
    local movePos = targetPos - direction * CONFIG.ATTACK_RANGE

    if Humanoid then
        Humanoid:MoveTo(movePos)
    end
    
    local reached = False
    local conn
    conn = Humanoid.MoveToFinished:Connect(function(reachedBool)
        reached = reachedBool
        conn:Disconnect()
    end)

    local startTime = tick()
    while not reached and tick() - startTime < 5 do
        RunService.Heartbeat:Wait()
    end
end

-- Pick up loot
local function PickupLoot()
    if not CONFIG.AUTO_LOOT then return end

    local events = {"PickupItem", "CollectLoot", "ClaimDrop", "GetLoot"}
    for _, name in ipairs(events) do
        local event = ReplicatedStorage:FindFirstChild(name)
        if event then
            event:FireServer()
            break
        end
    end
end

-- Auto handle level complete + Play Again
local function HandleLevelComplete()
    -- Method 1: Check CoreGui buttons
    local coreGui = game:GetService("CoreGui")
    local function findButton(obj)
        if obj:IsA("TextButton") then
            local nameLower = obj.Name:lower()
            local textLower = obj.Text and obj.Text:lower() or ""
            
            local playAgainTexts = {"play again", "replay", "next", "continue", "restart"}
            for _, txt in ipairs(playAgainTexts) do
                if string.find(nameLower, txt) or string.find(textLower, txt) then
                    return obj
                end
            end
        end
        
        for _, child in ipairs(obj:GetChildren()) do
            local found = findButton(child)
            if found then return found end
        end
        return Nil
    end

    -- Try to find Play Again button in CoreGui
    local btn = findButton(coreGui)
    if btn and btn.Visible then
        btn:Activate()
        print("✅ Clicked Play Again button")
        task.wait(3) -- Wait for level transition
        task.wait(1)
        ApplyBypass()
        return True
    end

    -- Method 2: Check for ResetButton
    local resetBtn = coreGui:FindFirstChild("ResetButton")
    if resetBtn and resetBtn.Visible then
        resetBtn.Visible = False
        resetBtn.Parent = Nil
        print("✅ Handled reset button")
        task.wait(2)
        ApplyBypass()
        return True
    end

    return False
end

-- Core combat logic
local function CombatLoop()
    if not Farming then return end

    ApplyBypass()
    HandleLevelComplete()

    currentTarget = FindNearestEnemy()

    if currentTarget then
        MoveToEnemy(currentTarget)

        while currentTarget and currentTarget:FindFirstChildWhichIsA("Humanoid") do
            local hum = currentTarget:FindFirstChildWhichIsA("Humanoid")
            if hum and hum.Health > 0 then
                ExecuteSkillSequence()
                TargetsKilled += 1
                wait(0.3)
            else
                break
            end
        end

        PickupLoot()
    else
        local dirs = {
            Vector3.New(15, 0, 0),
            Vector3.New(-15, 0, 0),
            Vector3.New(0, 0, 15),
            Vector3.New(0, 0, -15)
        }
        local dir = dirs[math.random(1, #dirs)]
        local targetPos = RootPart.Position + dir

        if Humanoid then
            local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Linear)
            local tween = TweenService:Create(RootPart, tweenInfo, {CFrame = CFrame.New(targetPos)})
            tween:Play()
            tween.Completed:Wait()
        end
    end

    spawn(CombatLoop)
end

-- Create beautiful menu UI
local function CreateMenu()
    if MenuGui then MenuGui:Destroy() end

    MenuGui = Instance.New("ScreenGui")
    MenuGui.Name = "DQRMENU"

    -- Background frame
    local bg = Instance.New("Frame")
    bg.Size = UDim2.New(0, 250, 0, 300)
    bg.Position = UDim2.New(0, 10, 0, 10)
    bg.BackgroundColor3 = Color3.FromRGB(20, 20, 30)
    bg.BorderSizePixel = 0
    bg.AnchorPoint = Vector2.New(0, 0)
    bg.Parent = MenuGui

    local corner = Instance.New("UICorner")
    corner.CornerRadius = UDim.New(0, 12)
    corner.Parent = bg

    -- Title
    local title = Instance.New("TextLabel")
    title.Size = UDim2.New(1, 0, 0, 40)
    title.BackgroundTransparency = 1
    title.Text = "🎮 DQ:R Auto Replay v4.6"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextColor3 = Color3.FromRGB(255, 255, 255)
    title.Parent = bg

    -- Toggle button
    local toggleBtn = Instance.New("TextButton")
    toggleBtn.Size = UDim2.New(1, -20, 0, 40)
    toggleBtn.Position = UDim2.New(0, 10, 0, 55)
    toggleBtn.BackgroundColor3 = Color3.FromRGB(40, 40, 50)
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Text = "▶️ BẬT/ TẮT FARM"
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 14
    toggleBtn.TextColor3 = Color3.FromRGB(255, 255, 255)
    toggleBtn.Parent = bg

    local btnCorner = Instance.New("UICorner")
    btnCorner.CornerRadius = UDim.New(0, 8)
    btnCorner.Parent = toggleBtn

    -- Status indicator
    local statusIndicator = Instance.New("Frame")
    statusIndicator.Size = UDim2.New(0, 12, 0, 12)
    statusIndicator.Position = UDim2.New(1, -15, 0, 10)
    statusIndicator.BackgroundColor3 = Color3.FromRGB(255, 100, 100)
    statusIndicator.BorderSizePixel = 0
    statusIndicator.Parent = toggleBtn

    local statusCorner = Instance.New("UICorner")
    statusCorner.CornerRadius = UDim.New(1, 0)
    statusCorner.Parent = statusIndicator

    -- Stats panel
    local stats = Instance.New("TextLabel")
    stats.Size = UDim2.New(1, -20, 0, 80)
    stats.Position = UDim2.New(0, 10, 0, 105)
    stats.BackgroundTransparency = 1
    stats.Text = "Status: OFF\nKills: 0\nTarget: None\nSkill Seq: Q-E-Q"
    stats.Font = Enum.Font.Gotham
    stats.TextSize = 12
    stats.TextColor3 = Color3.FromRGB(180, 180, 180)
    stats.TextXAlignment = Enum.TextXAlignment.Left
    stats.TextWrapped = True
    stats.Parent = bg

    -- Settings buttons
    local settingsBtn = Instance.New("TextButton")
    settingsBtn.Size = UDim2.New(1, -20, 0, 30)
    settingsBtn.Position = UDim2.New(0, 10, 0, 190)
    settingsBtn.BackgroundColor3 = Color3.FromRGB(40, 40, 50)
    settingsBtn.BorderSizePixel = 0
    settingsBtn.Text = "⚙️ CÀI ĐẶT"
    settingsBtn.Font = Enum.Font.GothamBold
    settingsBtn.TextSize = 12
    settingsBtn.TextColor3 = Color3.FromRGB(255, 255, 255)
    settingsBtn.Parent = bg

    local settingsCorner = Instance.New("UICorner")
    settingsCorner.CornerRadius = UDim.New(0, 6)
    settingsCorner.Parent = settingsBtn

    toggleBtn.MouseButton1Click:Connect(function()
        Farming = not Farming
        if Farming then
            toggleBtn.Text = "⏹️ DỪNG FARM"
            statusIndicator.BackgroundColor3 = Color3.FromRGB(100, 255, 100)
            print("🎮 Auto Replay Started")
            if not MenuGui then CreateMenu() end
            spawn(CombatLoop)
        else
            toggleBtn.Text = "▶️ BẬT/ TẮT FARM"
            statusIndicator.BackgroundColor3 = Color3.FromRGB(255, 100, 100)
            print("🛑 Auto Replay Stopped")
        end
    end)

    settingsBtn.MouseButton1Click:Connect(function()
        -- Mở menu cài đặt (có thể mở rộng sau)
        print("⚙️ Mở cài đặt...")
        -- Thêm popup cài đặt tại đây
    end)

    MenuGui.Parent = game:GetService("CoreGui") or game:GetService("PlayerGui")

    -- Update stats
    spawn(function()
        while MenuGui do
            wait(0.5)
            stats.Text = string.format("Status: %s\nKills: %d\nTarget: %s\nSkill Seq: %s",
                Farming and "ON" or "OFF",
                TargetsKilled,
                CurrentTarget and CurrentTarget.Name or "None",
                table.concat(CONFIG.CUSTOM_SKILL_SEQUENCE, "-")
            )
        end
    end)
end

-- Hotkey system
local LastToggleTime = 0

game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if Input.KeyCode == Enum.KeyCode.F then
        local currentTime = tick()
        if currentTime - LastToggleTime < 0.5 then
            Farming = not Farming
            if Farming then
                print("🎮 REPLAY STARTED")
                if not MenuGui then CreateMenu() end
                spawn(CombatLoop)
            else
                print("🛑 REPLAY STOPPED")
            end
            LastToggleTime = currentTime
            
            -- Cập nhật UI
            if MenuGui then
                local toggleBtn = MenuGui:FindFirstChild("ToggleBtn") or MenuGui:FindFirstChildWhichIsA("TextButton")
                if toggleBtn then
                    toggleBtn.Text = Farming and "⏹️ DỪNG FARM" or "▶️ BẬT/ TẮT FARM"
                end
            end
        end
    end

    if Input.KeyCode == Enum.KeyCode.Q then UseSkill("Q") end
    if Input.KeyCode == Enum.KeyCode.E then UseSkill("E") end
end)

Player.CharacterAdded:Connect(ApplyBypass)
if Player.Character then ApplyBypass() end

task.wait(2)
CreateMenu()

print("🎮 DQ:R Replay Tool v4.6 Loaded")
print("📌 Nhấn F để bật/tắt")
print("📌 Dùng Q/E để dùng skill thủ công")
