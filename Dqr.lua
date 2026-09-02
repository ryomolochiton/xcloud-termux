--[[ 
   🔄 Dungeon Quest Reborn - Auto Replay v4.3
   • Tự động respawn + trở lại vị trí cũ
   • Auto combat với Q/E skills
   • Không cần map detection
   • Hỗ trợ Delta/KRNL/Fluxus
--]]

local CONFIG = {
    ENABLE_DEBUG = true,
    AUTO_LOOT = true,
    WALK_SPEED = 45,
    JUMP_POWER = 70,
    SKILL_KEYS = {"Q", "E"},
    SKILL_DELAYS = {Q = 0.3, E = 1.2},
    ATTACK_RANGE = 8,
    MOVE_SPEED = 20,
    RESPAWN_WAIT = 3,
}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Variables
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")
local Camera = workspace.CurrentCamera

local Farming = false
local CurrentTarget = nil
local TargetsKilled = 0
local LastSkillUse = {Q = 0, E = 0}
local MenuGui = nil
local LastSafePosition = nil  -- Lưu vị trí an toàn trước khi chết

-- Apply bypass
local function ApplyBypass()
    local REMOTES_TO_BLOCK = {
        "CheckSpeed", "ReportPlayer", "KickPlayer", "DetectFly",
        "VerifyPosition", "ValidateMove", "AntiCheatCheck",
        "ClientHeartbeat", "PlayerStatsUpdate", "MovementValidator",
        "SpeedHackDetector", "AimAssistCheck", "CheckFly", "ValidateJump"
    }

    for _, name in ipairs(REMOTES_TO_BLOCK) do
        local remote = ReplicatedStorage:FindFirstChild(name)
        if remote then remote:Destroy() end
    end

    Humanoid.WalkSpeed = CONFIG.WALK_SPEED
    Humanoid.JumpPower = CONFIG.JUMP_POWER
    Humanoid.AutoRotate = true
end

-- Handle respawn
local function HandleRespawn()
    print("💀 Player died — waiting for respawn...")
    
    -- Đợi character mới
    local newChar = Player.CharacterAdded:Wait()
    task.wait(0.5)
    
    Character = newChar
    Humanoid = Character:WaitForChild("Humanoid")
    RootPart = Character:WaitForChild("HumanoidRootPart")
    
    ApplyBypass()
    
    -- Auto click respawn button nếu có
    local respawnBtn = game:GetService("CoreGui"):FindFirstChild("Respawn") 
        or game:GetService("CoreGui"):FindFirstChild("Retry")
    
    if respawnBtn then
        if CONFIG.ENABLE_DEBUG then
            print("🔁 Clicking respawn button...")
        end
        respawnBtn:Fire()
    end
    
    task.wait(CONFIG.RESPAWN_WAIT)
    
    -- Trở lại vị trí cũ
    if LastSafePosition then
        if CONFIG.ENABLE_DEBUG then
            print("🏠 Returning to last position...")
        end
        Humanoid:MoveTo(LastSafePosition)
        task.wait(3)
    end
end

-- Find enemies around player
local function FindNearestEnemy()
    local nearest = nil
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
                        nearest = obj
                        closestDist = dist
                    end
                end
            end
        end
    end

    return nearest
end

-- Use skill
local function UseSkill(key)
    local now = tick()
    local delay = CONFIG.SKILL_DELAYS[key] or 0.3

    if now - LastSkillUse[key] < delay then return end

    local success, err = pcall(function()
        local eventName = nil
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
                eventName = name
                if event:IsA("RemoteEvent") then
                    event:FireServer()
                elseif event:IsA("BindableEvent") then
                    event:Fire()
                end
                break
            end
        end

        -- Fallback: simulate keypress
        if not eventName then
            game:GetService("UserInputService"):InputBegan(
                Enum.UserInputType[key == "Q" and "Q" or "E"], false
            )
        end

        LastSkillUse[key] = now
        if CONFIG.ENABLE_DEBUG then
            print("✨ Used skill:", key)
        end
    end)

    if not success then
        warn("Skill error:", tostring(err):sub(1, 60))
    end
end

-- Move to enemy
local function MoveToEnemy(target)
    if not target or not target:FindFirstChild("HumanoidRootPart") then return end

    local targetPos = target.HumanoidRootPart.Position
    local myPos = RootPart.Position

    local direction = (targetPos - myPos).unit
    local movePos = targetPos - direction * CONFIG.ATTACK_RANGE

    Humanoid:MoveTo(movePos)
    
    local reached = false
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
            if CONFIG.ENABLE_DEBUG then
                print("🎁 Picked up loot via", name)
            end
            break
        end
    end
end

-- Core combat logic
local function CombatLoop()
    if not Farming then return end

    -- Lưu vị trí hiện tại làm điểm an toàn
    LastSafePosition = RootPart.Position

    ApplyBypass()

    -- Tìm enemy gần nhất
    CurrentTarget = FindNearestEnemy()

    if CurrentTarget then
        if CONFIG.ENABLE_DEBUG then
            print("🎯 Found target:", CurrentTarget.Name)
        end

        -- Di chuyển đến enemy
        MoveToEnemy(CurrentTarget)

        -- Tấn công bằng skill
        while CurrentTarget and CurrentTarget:FindFirstChildWhichIsA("Humanoid") do
            local hum = CurrentTarget:FindFirstChildWhichIsA("Humanoid")
            if hum and hum.Health > 0 then
                -- Dùng cả 2 skill
                UseSkill("Q")
                wait(0.1)
                UseSkill("E")
                
                TargetsKilled += 1
                wait(0.3)
                
                -- Cập nhật vị trí an toàn
                LastSafePosition = RootPart.Position
            else
                break
            end
        end

        -- Pickup loot sau khi giết
        PickupLoot()
    else
        -- Không có enemy — quay đầu tìm
        if CONFIG.ENABLE_DEBUG then
            print("🔍 No enemies found — scanning area...")
        end

        -- Di chuyển ngẫu nhiên để tìm enemy
        local dirs = {
            Vector3.new(CONFIG.MOVE_SPEED, 0, 0),
            Vector3.new(-CONFIG.MOVE_SPEED, 0, 0),
            Vector3.new(0, 0, CONFIG.MOVE_SPEED),
            Vector3.new(0, 0, -CONFIG.MOVE_SPEED)
        }
        local dir = dirs[math.random(1, #dirs)]
        local targetPos = RootPart.Position + dir

        local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear)
        local tween = TweenService:Create(RootPart, tweenInfo, {CFrame = CFrame.new(targetPos)})
        tween:Play()
        tween.Completed:Wait()
    end

    -- Tiếp tục vòng lặp
    spawn(CombatLoop)
end

-- Create minimal UI
local function CreateMenu()
    if MenuGui then MenuGui:Destroy() end

    MenuGui = Instance.new("ScreenGui")
    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(0, 220, 0, 120)
    bg.Position = UDim2.new(0, 10, 0, 10)
    bg.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    bg.BorderSizePixel = 0
    bg.Parent = MenuGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = bg

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 25)
    title.BackgroundTransparency = 1
    title.Text = "🔁 AUTO REPLAY v4.3"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Parent = bg

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -10, 0, 20)
    status.Position = UDim2.new(0, 5, 0, 35)
    status.BackgroundTransparency = 1
    status.Text = "Status: ❌ OFF"
    status.Font = Enum.Font.Gotham
    status.TextSize = 13
    status.TextColor3 = Color3.fromRGB(255, 100, 100)
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = bg

    local stats = Instance.new("TextLabel")
    stats.Size = UDim2.new(1, -10, 0, 60)
    stats.Position = UDim2.new(0, 5, 0, 60)
    stats.BackgroundTransparency = 1
    stats.Text = "Kills: 0\nTarget: None\nPosition: Saved"
    stats.Font = Enum.Font.Gotham
    stats.TextSize = 12
    stats.TextColor3 = Color3.fromRGB(180, 180, 180)
    stats.TextXAlignment = Enum.TextXAlignment.Left
    stats.Parent = bg

    MenuGui.Parent = game:GetService("CoreGui") or game:GetService("PlayerGui")

    -- Update stats
    spawn(function()
        while MenuGui do
            wait(0.5)
            stats.Text = string.format("Kills: %d\nTarget: %s\nPosition: %s",
                TargetsKilled,
                CurrentTarget and CurrentTarget.Name or "None",
                LastSafePosition and "Saved" or "None"
            )
        end
    end)
end

-- Hotkey system
local LastToggleTime = 0

game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.F then
        local currentTime = tick()
        if currentTime - LastToggleTime < 0.5 then
            Farming = not Farming
            if Farming then
                print("🔁 REPLAY MODE STARTED")
                if not MenuGui then CreateMenu() end
                spawn(CombatLoop)
            else
                print("🛑 REPLAY MODE STOPPED")
            end
            LastToggleTime = currentTime
        end
    end

    -- Manual skill keys
    if input.KeyCode == Enum.KeyCode.Q then UseSkill("Q") end
    if input.KeyCode == Enum.KeyCode.E then UseSkill("E") end
end)

-- Handle respawn automatically
Player.CharacterRemoving:Connect(function()
    spawn(HandleRespawn)
end)

-- Initialize
Player.CharacterAdded:Connect(ApplyBypass)
if Player.Character then ApplyBypass() end

task.wait(2)
CreateMenu()

print("🔁 Auto Replay Tool v4.3 Loaded")
print("📌 Nhấn F để bật/tắt replay mode")
print("📌 Dùng Q/E để dùng skill thủ công")
local MenuGui = nil
local CurrentZoneName = nil

-- Map sequence (đầy đủ tên map DQR)
local MAP_SEQUENCE = {
    { name = "Newbie Forest", keywords = {"newbie", "forest", "start"} },
    { name = "Goblin Cave", keywords = {"goblin", "cave", "tunnel"} },
    { name = "Ancient Ruins", keywords = {"ancient", "ruin", "temple"} },
    { name = "Frozen Peaks", keywords = {"frozen", "ice", "peak", "snow"} },
    { name = "Lava Caves", keywords = {"lava", "volcano", "fire"} },
    { name = "Sky Temple", keywords = {"sky", "temple", "cloud"} },
    { name = "Underworld", keywords = {"underworld", "cave", "deep"} },
    { name = "Crystal Depths", keywords = {"crystal", "depth"} },
    { name = "Dragon Lair", keywords = {"dragon", "lair", "boss"} }
}

-- Auto detect current map/zone
local function DetectCurrentMap()
    local zoneNames = {}
    local possibleZones = {
        Workspace:FindFirstChild("Zone"),
        Workspace:FindFirstChild("Map"),
        Workspace:FindFirstChild("Level"),
        Workspace:FindFirstChild("Area"),
    }

    -- Scan tất cả đối tượng trong workspace để tìm zone name
    for _, obj in ipairs(Workspace:GetChildren()) do
        local nameLower = obj.Name:lower()
        table.insert(zoneNames, nameLower)
    end

    -- Fuzzy match với từng map trong danh sách
    for i, map in ipairs(MAP_SEQUENCE) do
        for _, keyword in ipairs(map.keywords) do
            for _, zoneName in ipairs(zoneNames) do
                if string.find(zoneName, keyword) or string.find(keyword, zoneName) then
                    return i, map.name
                end
            end
        end
    end

    -- Nếu không tìm thấy map, quay về map đầu tiên
    return 1, MAP_SEQUENCE[1].name
end

-- Apply anti-cheat bypass
local function ApplyBypass()
    local REMOTES_TO_BLOCK = {
        "CheckSpeed", "ReportPlayer", "KickPlayer", "DetectFly",
        "VerifyPosition", "ValidateMove", "AntiCheatCheck",
        "ClientHeartbeat", "PlayerStatsUpdate", "MovementValidator",
        "SpeedHackDetector", "AimAssistCheck", "CheckFly", "ValidateJump"
    }

    for _, name in ipairs(REMOTES_TO_BLOCK) do
        local remote = ReplicatedStorage:FindFirstChild(name)
        if remote then remote:Destroy() end
    end

    Humanoid.WalkSpeed = CONFIG.WALK_SPEED
    Humanoid.JumpPower = CONFIG.JUMP_POWER
    Humanoid.AutoRotate = true
    if CONFIG.ENABLE_DEBUG then
        print("🛡️ Bypass applied - walking speed:", CONFIG.WALK_SPEED)
    end
end

-- Find nearest enemy
local function FindNearestEnemy()
    local nearest = nil
    local closestDist = CONFIG.ATTACK_RANGE

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= Character then
            local hum = obj:FindFirstChildWhichIsA("Humanoid")
            if hum and hum.Health > 0 then
                local root = obj:FindFirstChild("HumanoidRootPart")
                if root then
                    local dist = (root.Position - RootPart.Position).Magnitude
                    local nameLower = obj.Name:lower()

                    local isEnemy = false
                    local enemies = {"monster", "enemy", "mob", "creature", "boss", "enemy_", "monster_", "npc"}
                    for _, e in ipairs(enemies) do
                        if string.find(nameLower, e) then
                            isEnemy = true
                            break
                        end
                    end

                    if isEnemy and dist < closestDist then
                        nearest = obj
                        closestDist = dist
                    end
                end
            end
        end
    end

    return nearest
end

-- Use skill
local function UseSkill(skillName, delayCheck)
    local now = tick()
    if now - delayCheck < 0.1 then return false end

    local success, err = pcall(function()
        local skillEvent = nil
        local events = {
            "UseSkill_" .. skillName,
            skillName .. "Skill",
            "CastSkill_" .. skillName,
            skillName:upper(),
            skillName
        }

        for _, eventName in ipairs(events) do
            skillEvent = ReplicatedStorage:FindFirstChild(eventName)
            if skillEvent then
                if skillEvent:IsA("RemoteEvent") then
                    skillEvent:FireServer()
                elseif skillEvent:IsA("BindableEvent") then
                    skillEvent:Fire()
                end
                if CONFIG.ENABLE_DEBUG then
                    print("✨ Used skill:", skillName, "via", eventName)
                end
                return true
            end
        end
    end)

    if not success then
        warn("Skill error:", err)
    end
    return success
end

-- Auto skills
local function AutoSkills()
    if tick() - LastSkillQ >= CONFIG.SKILL_Q_DELAY then
        UseSkill("Q", LastSkillQ)
        LastSkillQ = tick()
    end

    if tick() - LastSkillE >= CONFIG.SKILL_E_DELAY then
        UseSkill("E", LastSkillE)
        LastSkillE = tick()
    end
end

-- Attack target
local function AttackTarget(target)
    if not target then return false end

    local targetPos = target.HumanoidRootPart.Position
    Camera.CFrame = CFrame.new(RootPart.Position, targetPos)

    local attackRemote = ReplicatedStorage:FindFirstChild("Attack") or
                         ReplicatedStorage:FindFirstChild("PlayerAttack")

    if attackRemote then
        attackRemote:FireServer(target)
    else
        local mouse = Player:GetMouse()
        mouse.Button1Down:Fire()
        wait(0.05)
        mouse.Button1Up:Fire()
    end

    AutoSkills()
    return true
end

-- Loot pickup
local function PickupLoot()
    if not CONFIG.AUTO_LOOT then return end

    local pickupEvents = {
        "PickupItem", "CollectLoot", "ClaimDrop", "GetLoot"
    }

    for _, name in ipairs(pickupEvents) do
        local event = ReplicatedStorage:FindFirstChild(name)
        if event then
            event:FireServer()
            if CONFIG.ENABLE_DEBUG then
                print("🎁 Picked up items via", name)
            end
            break
        end
    end
end

-- Go to next map (improved portal detection)
local function GoToNextMap()
    if CurrentMapIndex >= #MAP_SEQUENCE then
        print("🏁 Hoàn thành tất cả map!")
        Farming = false
        return false
    end

    CurrentMapIndex += 1
    local nextMap = MAP_SEQUENCE[CurrentMapIndex]
    print("🗺️ Chuyển sang map:", nextMap.name)

    -- Find portals/exists dynamically
    local portals = {}
    for _, obj in ipairs(Workspace:GetChildren()) do
        local nameLower = obj.Name:lower()
        local validPortalNames = {"exitportal", "portal", "mapchanger", "dungeonexit", "nextmap", "teleport", "transfer"}
        for _, validName in ipairs(validPortalNames) do
            if string.find(nameLower, validName) then
                table.insert(portals, obj)
                break
            end
        end
    end

    -- Sort by distance
    table.sort(portals, function(a, b)
        local aPos = a.Position or (a.PrimaryPart and a.PrimaryPart.Position)
        local bPos = b.Position or (b.PrimaryPart and b.PrimaryPart.Position)
        if not aPos or not bPos then return false end
        return (aPos - RootPart.Position).Magnitude < (bPos - RootPart.Position).Magnitude
    end)

    -- Try to reach closest portal
    for _, portal in ipairs(portals) do
        local pos = portal.Position or (portal.PrimaryPart and portal.PrimaryPart.Position)
        if pos then
            Humanoid:MoveTo(pos + Vector3.new(0, 3, 0))
            local reached = false
            Humanoid.MoveToFinished:Connect(function(reachedBool)
                reached = reachedBool
            end)

            local startTime = tick()
            while not reached and tick() - startTime < 15 do
                RunService.Heartbeat:Wait()
            end

            if reached then
                -- Touch/interact with portal
                if portal:IsA("BasePart") then
                    RootPart.CFrame = CFrame.new(portal.Position)
                else
                    -- Model - try to find primary part
                    if portal.PrimaryPart then
                        RootPart.CFrame = CFrame.new(portal.PrimaryPart.Position)
                    end
                end
                wait(3)
                return true
            end
        end
    end

    return false
end

-- Farm logic
local function FarmLogic()
    if not Farming then return end

    ApplyBypass()

    -- Auto detect current map
    local mapIndex, mapName = DetectCurrentMap()
    if mapIndex ~= CurrentMapIndex then
        CurrentMapIndex = mapIndex
        CurrentZoneName = mapName
        print("🗺️ Detected current map:", mapName)
    end

    CurrentTarget = FindNearestEnemy()

    if CurrentTarget then
        if CONFIG.ENABLE_DEBUG and TargetsKilled % 10 == 0 then
            print("🎯 Killing:", CurrentTarget.Name, "Total kills:", TargetsKilled)
        end

        while CurrentTarget and CurrentTarget:FindFirstChildWhichIsA("Humanoid") do
            local hum = CurrentTarget:FindFirstChildWhichIsA("Humanoid")
            if hum and hum.Health > 0 then
                AttackTarget(CurrentTarget)
                TargetsKilled += 1
                wait(0.3)
            else
                break
            end
        end

        PickupLoot()
    else
        if CONFIG.SAFE_MODE then
            wait(1)
        else
            -- Roam to find enemies
            local dirs = {Vector3.new(20,0,0), Vector3.new(-20,0,0), Vector3.new(0,0,20), Vector3.new(0,0,-20)}
            local dir = dirs[math.random(1, #dirs)]
            local targetPos = RootPart.Position + dir

            local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Linear)
            local tween = TweenService:Create(RootPart, tweenInfo, {CFrame = CFrame.new(targetPos)})
            tween:Play()
            tween.Completed:Wait()
            wait(0.5)
        end

        -- If no enemies found for a while, go to next map
        if not FindNearestEnemy() then
            wait(2)
            if not FindNearestEnemy() then
                GoToNextMap()
            end
        end
    end

    spawn(FarmLogic)
end

-- Create menu UI
local function CreateMenu()
    if MenuGui then MenuGui:Destroy() end

    MenuGui = Instance.new("ScreenGui")
    MenuGui.Name = "FarmMenu"

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(0, 250, 0, 270)
    bg.Position = UDim2.new(0, 15, 0, 15)
    bg.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    bg.BorderSizePixel = 0
    bg.Parent = MenuGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = bg

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 35)
    title.BackgroundTransparency = 1
    title.Text = "🗺️ AUTO FARM v4.1"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Parent = bg

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 20)
    status.Position = UDim2.new(0, 10, 0, 45)
    status.BackgroundTransparency = 1
    status.Text = "Status: ❌ OFF"
    status.Font = Enum.Font.Gotham
    status.TextSize = 14
    status.TextColor3 = Color3.fromRGB(255, 100, 100)
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = bg

    local stats = Instance.new("TextLabel")
    stats.Size = UDim2.new(1, -20, 0, 80)
    stats.Position = UDim2.new(0, 10, 0, 70)
    stats.BackgroundTransparency = 1
    stats.Text = "Map: Detecting...\nKills: 0\nTarget: None"
    stats.Font = Enum.Font.Gotham
    stats.TextSize = 12
    stats.TextColor3 = Color3.fromRGB(180, 180, 180)
    stats.TextXAlignment = Enum.TextXAlignment.Left
    stats.TextWrapped = true
    stats.Parent = bg

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 40)
    btn.Position = UDim2.new(0, 10, 0, 160)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    btn.BorderSizePixel = 0
    btn.Text = "▶️ BẮT ĐẦU FARM"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Parent = bg

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = btn

    btn.MouseButton1Click:Connect(function()
        Farming = not Farming
        if Farming then
            status.Text = "Status: ✅ ON"
            status.TextColor3 = Color3.fromRGB(100, 255, 100)
            btn.Text = "⏹️ DỪNG FARM"
            CurrentMapIndex = 1
            TargetsKilled = 0
            print("🗺️ Starting farm...")
            spawn(FarmLogic)
        else
            status.Text = "Status: ❌ OFF"
            status.TextColor3 = Color3.fromRGB(255, 100, 100)
            btn.Text = "▶️ BẮT ĐẦU FARM"
            print("🛑 Stopped farm")
        end
    end)

    spawn(function()
        while MenuGui do
            wait(1)
            stats.Text = string.format(
                "Map: %s\nKills: %d\nTarget: %s",
                CurrentZoneName or "Detecting...",
                TargetsKilled,
                CurrentTarget and CurrentTarget.Name or "None"
            )
        end
    end)

    MenuGui.Parent = game:GetService("CoreGui") or game:GetService("PlayerGui")
end

-- Hotkey system
local LastToggleTime = 0

game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.F then
        local currentTime = tick()
        if currentTime - LastToggleTime < 0.5 then
            Farming = not Farming
            if Farming then
                print("🗺️ AUTO FARM ACTIVATED via hotkey")
                CurrentMapIndex = 1
                TargetsKilled = 0
                if not MenuGui then CreateMenu() end
                spawn(FarmLogic)
            else
                print("🛑 AUTO FARM DEACTIVATED via hotkey")
            end
            if MenuGui then
                local btn = MenuGui.FarmMenu:FindFirstChild("TextButton")
                if btn then
                    btn.Text = Farming and "⏹️ DỪNG FARM" or "▶️ BẮT ĐẦU FARM"
                end
            end
        end
        LastToggleTime = currentTime
    end

    if input.KeyCode == Enum.KeyCode.Q then
        UseSkill("Q", 0)
    end
    if input.KeyCode == Enum.KeyCode.E then
        UseSkill("E", 0)
    end
end)

-- Initialization
Player.CharacterAdded:Connect(ApplyBypass)
if Player.Character then ApplyBypass() end

task.wait(2)
CreateMenu()

print("🗺️ Dungeon Quest Reborn Auto Farm v4.1 Loaded")
print("📌 Nhấn 'F' 2 lần nhanh để bật/tắt")
print("📌 Dùng Q/E để kích hoạt skill thủ công")
-- States
local Farming = false
local CurrentTarget = nil
local TargetsKilled = 0
local CurrentMapIndex = 1
local LastSkillQ = 0
local LastSkillE = 0
local MenuGui = nil

-- Map sequence
local MAP_SEQUENCE = {
    { name = "Newbie Forest", area = 1 },
    { name = "Goblin Cave", area = 2 },
    { name = "Ancient Ruins", area = 3 },
    { name = "Frozen Peaks", area = 4 },
    { name = "Lava Caves", area = 5 },
    { name = "Sky Temple", area = 6 },
    { name = "Underworld", area = 7 },
    { name = "Crystal Depths", area = 8 },
    { name = "Dragon Lair", area = 9 }
}
-- └──────────────────────────────────────────────────────┘

-- ┌─────────────────────[ ANTICHEAT BYPASS ]─────────────────────┐
local function ApplyBypass()
    local REMOTES_TO_BLOCK = {
        "CheckSpeed", "ReportPlayer", "KickPlayer", "DetectFly",
        "VerifyPosition", "ValidateMove", "AntiCheatCheck",
        "ClientHeartbeat", "PlayerStatsUpdate", "MovementValidator",
        "SpeedHackDetector", "AimAssistCheck", "CheckFly", "ValidateJump"
    }

    for _, name in ipairs(REMOTES_TO_BLOCK) do
        local remote = ReplicatedStorage:FindFirstChild(name)
        if remote then remote:Destroy() end
    end

    -- Patch humanoid properties
    Humanoid.WalkSpeed = CONFIG.WALK_SPEED
    Humanoid.JumpPower = CONFIG.JUMP_POWER
    Humanoid.AutoRotate = true
    
    if CONFIG.ENABLE_DEBUG then
        print("🛡️ Bypass applied - walking speed:", CONFIG.WALK_SPEED)
    end
end
-- └──────────────────────────────────────────────────────────────┘

-- ┌─────────────────────[ TARGET DETECTION ]─────────────────────┐
local function FindNearestEnemy()
    local nearest = nil
    local closestDist = CONFIG.ATTACK_RANGE

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= Character then
            local hum = obj:FindFirstChildWhichIsA("Humanoid")
            if hum and hum.Health > 0 then
                local root = obj:FindFirstChild("HumanoidRootPart")
                if root then
                    local dist = (root.Position - RootPart.Position).Magnitude
                    local nameLower = obj.Name:lower()

                    -- Check if it's an enemy
                    local isEnemy = false
                    local enemies = {"monster", "enemy", "mob", "creature", "boss", "enemy_", "monster_"}
                    for _, e in ipairs(enemies) do
                        if string.find(nameLower, e) then
                            isEnemy = true
                            break
                        end
                    end

                    if isEnemy and dist < closestDist then
                        nearest = obj
                        closestDist = dist
                    end
                end
            end
        end
    end

    return nearest
end

local function AimAtTarget(target)
    if not target or not target:FindFirstChild("HumanoidRootPart") then return end
    local targetPos = target.HumanoidRootPart.Position
    Camera.CFrame = CFrame.new(RootPart.Position, targetPos)
end
-- └──────────────────────────────────────────────────────────────┘

-- ┌─────────────────────[ SKILL SYSTEM ]─────────────────────┐
local function UseSkill(skillName, delayCheck)
    local now = tick()
    if now - delayCheck < 0.1 then return false end -- Anti-spam
    
    local success, err = pcall(function()
        local skillEvent = nil
        -- Try multiple possible skill event names
        local events = {
            "UseSkill_" .. skillName,
            skillName .. "Skill",
            "CastSkill_" .. skillName,
            skillName:upper(),
            skillName
        }
        
        for _, eventName in ipairs(events) do
            skillEvent = ReplicatedStorage:FindFirstChild(eventName)
            if skillEvent then
                if skillEvent:IsA("RemoteEvent") then
                    skillEvent:FireServer()
                elseif skillEvent:IsA("BindableEvent") then
                    skillEvent:Fire()
                end
                if CONFIG.ENABLE_DEBUG then
                    print("✨ Used skill:", skillName, "via", eventName)
                end
                return true
            end
        end
        
        -- Fallback: simulate key press
        if skillName == "Q" then
            game:GetService("ReplicatedStorage"):FindFirstChild("SkillQ"):FireServer()
        elseif skillName == "E" then
            game:GetService("ReplicatedStorage"):FindFirstChild("SkillE"):FireServer()
        end
    end)

    if not success then
        warn("Skill error:", err)
    end
    return success
end

local function AutoSkills()
    -- Auto Q (short cooldown)
    if tick() - LastSkillQ >= CONFIG.SKILL_Q_DELAY then
        UseSkill("Q", LastSkillQ)
        LastSkillQ = tick()
    end

    -- Auto E (long cooldown)
    if tick() - LastSkillE >= CONFIG.SKILL_E_DELAY then
        UseSkill("E", LastSkillE)
        LastSkillE = tick()
    end
end
-- └──────────────────────────────────────────────────────────────┘

-- ┌─────────────────────[ ATTACK SYSTEM ]─────────────────────┐
local function AttackTarget(target)
    if not target then return false end

    AimAtTarget(target)
    
    -- Send attack command
    local attackRemote = ReplicatedStorage:FindFirstChild("Attack") or
                         ReplicatedStorage:FindFirstChild("PlayerAttack")
    
    if attackRemote then
        attackRemote:FireServer(target)
    else
        -- Simulate mouse click
        local mouse = Player:GetMouse()
        mouse.Button1Down:Fire()
        wait(0.05)
        mouse.Button1Up:Fire()
    end

    -- Use auto skills during combat
    AutoSkills()
    
    return true
end

local function PickupLoot()
    if not CONFIG.AUTO_LOOT then return end
    
    local pickupEvents = {
        "PickupItem", "CollectLoot", "ClaimDrop", "GetLoot"
    }
    
    for _, name in ipairs(pickupEvents) do
        local event = ReplicatedStorage:FindFirstChild(name)
        if event then
            event:FireServer()
            if CONFIG.ENABLE_DEBUG then
                print("🎁 Picked up items via", name)
            end
            break
        end
    end
end
-- └──────────────────────────────────────────────────────────────┘

-- ┌─────────────────────[ MAP NAVIGATION ]─────────────────────┐
local function GoToNextMap()
    if CurrentMapIndex >= #MAP_SEQUENCE then
        print("🏁 Hoàn thành tất cả map!")
        Farming = false
        return false
    end

    CurrentMapIndex += 1
    local nextMap = MAP_SEQUENCE[CurrentMapIndex]
    print("🗺️ Chuyển sang map:", nextMap.name)

    -- Tìm portal
    local portals = {
        workspace:FindFirstChild("ExitPortal"),
        workspace:FindFirstChild("MapChanger"),
        workspace:FindFirstChild("Portal"),
        workspace:FindFirstChild("DungeonExit")
    }

    for _, portal in ipairs(portals) do
        if portal and (portal:IsA("SpatialBasePart") or portal:IsA("Model")) then
            local pos = portal.Position or (portal.PrimaryPart and portal.PrimaryPart.Position)
            if pos then
                -- Move to portal
                Humanoid:MoveTo(pos + Vector3.new(0, 3, 0))
                
                -- Wait for arrival
                local reached = false
                Humanoid.MoveToFinished:Connect(function(reachedBool)
                    reached = reachedBool
                end)
                
                -- Timeout after 10 seconds
                local startTime = tick()
                while not reached and tick() - startTime < 10 do
                    RunService.Heartbeat:Wait()
                end

                if reached then
                    -- Interact with portal
                    if portal:FindFirstChild("Touch") then
                        portal.Touch:Fire(RootPart)
                    else
                        RootPart.CFrame = CFrame.new(pos)
                    end
                    wait(3)
                    return true
                end
            end
        end
    end

    return false
end

local function FarmLogic()
    if not Farming then return end

    ApplyBypass()

    -- Find enemy
    CurrentTarget = FindNearestEnemy()

    if CurrentTarget then
        if CONFIG.ENABLE_DEBUG and TargetsKilled % 10 == 0 then
            print("🎯 Killing:", CurrentTarget.Name, "Total kills:", TargetsKilled)
        end

        -- Attack loop
        while CurrentTarget and CurrentTarget:FindFirstChildWhichIsA("Humanoid") do
            local hum = CurrentTarget:FindFirstChildWhichIsA("Humanoid")
            if hum and hum.Health > 0 then
                AttackTarget(CurrentTarget)
                TargetsKilled += 1
                wait(0.3)
            else
                break
            end
        end

        -- Pickup loot
        PickupLoot()
    else
        -- No enemies nearby
        if CONFIG.SAFE_MODE then
            wait(1)
        else
            -- Roam to find enemies
            local dirs = {Vector3.new(20,0,0), Vector3.new(-20,0,0), Vector3.new(0,0,20), Vector3.new(0,0,-20)}
            local dir = dirs[math.random(1, #dirs)]
            local targetPos = RootPart.Position + dir
            
            local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Linear)
            local tween = TweenService:Create(RootPart, tweenInfo, {CFrame = CFrame.new(targetPos)})
            tween:Play()
            tween.Completed:Wait()
            wait(0.5)
        end

        -- If no enemies found for a while, go to next map
        if not FindNearestEnemy() then
            wait(2)
            if not FindNearestEnemy() then
                GoToNextMap()
            end
        end
    end

    -- Continue farming
    spawn(FarmLogic)
end
-- └──────────────────────────────────────────────────────────────┘

-- ┌─────────────────────[ MENU SYSTEM ]─────────────────────┐
local function CreateMenu()
    -- Cleanup old menu
    if MenuGui then MenuGui:Destroy() end

    MenuGui = Instance.new("ScreenGui")
    MenuGui.Name = "FarmMenu"

    -- Background
    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(0, 250, 0, 250)
    bg.Position = UDim2.new(0, 15, 0, 15)
    bg.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    bg.BorderSizePixel = 0
    bg.AnchorPoint = Vector2.new(0, 0)
    bg.Parent = MenuGui

    -- Corner rounding
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = bg

    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 35)
    title.BackgroundTransparency = 1
    title.Text = "🗺️ AUTO FARM v4.0"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Parent = bg

    -- Status indicator
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 20)
    status.Position = UDim2.new(0, 10, 0, 45)
    status.BackgroundTransparency = 1
    status.Text = "Status: ❌ OFF"
    status.Font = Enum.Font.Gotham
    status.TextSize = 14
    status.TextColor3 = Color3.fromRGB(255, 100, 100)
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = bg

    -- Stats
    local stats = Instance.new("TextLabel")
    stats.Size = UDim2.new(1, -20, 0, 60)
    stats.Position = UDim2.new(0, 10, 0, 70)
    stats.BackgroundTransparency = 1
    stats.Text = "Map: " .. (MAP_SEQUENCE[CurrentMapIndex] or {name=""}).name .. "\nKills: 0\nTarget: None"
    stats.Font = Enum.Font.Gotham
    stats.TextSize = 12
    stats.TextColor3 = Color3.fromRGB(180, 180, 180)
    stats.TextXAlignment = Enum.TextXAlignment.Left
    stats.TextWrapped = true
    stats.Parent = bg

    -- Toggle button
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 40)
    btn.Position = UDim2.new(0, 10, 0, 145)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    btn.BorderSizePixel = 0
    btn.Text = "▶️ BẮT ĐẦU FARM (Nhấn F để toggle)"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Parent = bg

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = btn

    btn.MouseButton1Click:Connect(function()
        Farming = not Farming
        if Farming then
            status.Text = "Status: ✅ ON"
            status.TextColor3 = Color3.fromRGB(100, 255, 100)
            btn.Text = "⏹️ DỪNG FARM"
            CurrentMapIndex = 1
            TargetsKilled = 0
            print("🗺️ Starting farm...")
            spawn(FarmLogic)
        else
            status.Text = "Status: ❌ OFF"
            status.TextColor3 = Color3.fromRGB(255, 100, 100)
            btn.Text = "▶️ BẮT ĐẦU FARM"
            print("🛑 Stopped farm")
        end
    end)

    -- Update stats periodically
    spawn(function()
        while MenuGui do
            wait(1)
            stats.Text = string.format(
                "Map: %s\nKills: %d\nTarget: %s",
                (MAP_SEQUENCE[CurrentMapIndex] or {name=""}).name,
                TargetsKilled,
                CurrentTarget and CurrentTarget.Name or "None"
            )
        end
    end)

    MenuGui.Parent = game:GetService("CoreGui") or game:GetService("PlayerGui")
end
-- └──────────────────────────────────────────────────────────────┘

-- ┌─────────────────────[ HOTKEY SYSTEM ]─────────────────────┐
local LastToggleTime = 0

game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.F then
        local currentTime = tick()
        if currentTime - LastToggleTime < 0.5 then
            Farming = not Farming
            if Farming then
                print("🗺️ AUTO FARM ACTIVATED via hotkey")
                CurrentMapIndex = 1
                TargetsKilled = 0
                if not MenuGui then CreateMenu() end
                spawn(FarmLogic)
            else
                print("🛑 AUTO FARM DEACTIVATED via hotkey")
            end
            -- Sync menu state
            if MenuGui then
                local btn = MenuGui.FarmMenu:FindFirstChild("TextButton")
                if btn then
                    btn.Text = Farming and "⏹️ DỪNG FARM" or "▶️ BẮT ĐẦU FARM"
                end
            end
        end
        LastToggleTime = currentTime
    end

    -- Manual skill trigger
    if input.KeyCode == Enum.KeyCode.Q then
        UseSkill("Q", 0)
    end
    if input.KeyCode == Enum.KeyCode.E then
        UseSkill("E", 0)
    end
end)
-- └──────────────────────────────────────────────────────────────┘

-- ┌─────────────────────[ INITIALIZATION ]─────────────────────┐
Player.CharacterAdded:Connect(ApplyBypass)
if Player.Character then ApplyBypass() end

-- Create menu on load
task.wait(2)
CreateMenu()

print("🗺️ Dungeon Quest Reborn Auto Farm v4.0 Loaded")
print("📌 Nhấn 'F' 2 lần nhanh để bật/tắt")
print("📌 Dùng Q/E để kích hoạt skill thủ công")
-- └─────────────────────────────────────────────────────────────┘
