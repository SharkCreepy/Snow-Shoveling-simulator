-- ============================================
-- Snow Shoveling Simulator - COMPACT VERSION
-- Fixes: No TileSelector require, uses direct logic instead
-- JUMP & MOVEMENT FIX: Properly restores after shop close
-- VEHICLE SPEED v3: Proper MaxSpeed restore + separate MaxSpeed override slider
-- VEHICLE FLY (VFly): Fly while inside vehicle using BodyVelocity on vehicle model
-- ============================================

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Network = require(ReplicatedStorage.LoadModule)("Network")
local PlayerData = require(ReplicatedStorage.LoadModule)("PlayerData")
local Database = require(ReplicatedStorage.LoadModule)("Database")
local GetShopItemInfo = require(ReplicatedStorage.LoadModule)("GetShopItemInfo")
local GuiHandler = require(player.PlayerScripts.Modules.UI.GuiHandler)

-- NO TileSelector require — we replicate its logic directly

local targetPart = workspace:WaitForChild("Interactions"):WaitForChild("Frosty")
local backpackStorePart = workspace:WaitForChild("Interactions"):WaitForChild("OpenBackpackStore")

local toolsStorePart = nil
for _, child in ipairs(workspace.Interactions:GetChildren()) do
    if child.Name:lower():find("tool") or child.Name:lower():find("jim") then
        toolsStorePart = child
        break
    end
end

local backpackLabelPath = "ScreenGui.Hud.Stats.Snow.Progress.AmountLabel"

local function getHRP()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:FindFirstChildOfClass("Humanoid")
end

local function getBackpackNumbers()
    local success, label = pcall(function()
        local path = playerGui
        for _, name in ipairs(backpackLabelPath:split(".")) do
            path = path:WaitForChild(name, 1)
        end
        return path
    end)
    if not success or not label then return nil, nil end
    local text = label.Text
    
    text = text:gsub(",", "")
    
    local currentStr, maxStr = text:match("([%d%.%s]+)%s*/%s*([%d%.%s]+)")
    
    if currentStr and maxStr then
        currentStr = currentStr:gsub("%s", "")
        maxStr = maxStr:gsub("%s", "")
        
        local function parseNumber(str)
            str = str:upper()
            local num = str:gsub("[KM]", "")
            local val = tonumber(num) or 0
            if str:find("K") then
                val = val * 1000
            elseif str:find("M") then
                val = val * 1000000
            end
            return val
        end
        
        local current = parseNumber(currentStr)
        local max = parseNumber(maxStr)
        return current, max
    end
    
    local nums = {}
    for num in text:gmatch("[%d%.]+") do
        table.insert(nums, tonumber(num) or 0)
    end
    if #nums >= 2 then
        return nums[1], nums[2]
    end
    
    return nil, nil
end

local function buildInteractionData(part)
    local args = {}
    for attrName, attrValue in pairs(part.Args:GetAttributes()) do
        args[attrName] = attrValue
    end
    local instanceRef = part.Args:FindFirstChild("Instance")
    if instanceRef then args.Instance = instanceRef.Value end
    return {
        Position = part.Position,
        Range = part.Size.Y / 2,
        Name = part.Name,
        Text = part:GetAttribute("Text") or "Interact",
        InteractName = part:GetAttribute("InteractName") or "",
        Args = args
    }
end

-- ============================================
-- CRITICAL FIX: Restore movement after shop close
-- ============================================

local function forceRestoreMovement()
    local hrp = getHRP()
    local hum = getHumanoid()
    if hrp then 
        hrp.Anchored = false 
    end
    if hum then
        hum.WalkSpeed = 16
        hum.JumpHeight = 7.2
        hum.JumpPower = 50
        hum.Sit = false
        hum.PlatformStand = false
        hum.AutoRotate = true
    end
    
    -- Re-enable interactions
    pcall(function()
        player:SetAttribute("DisableInteractions", false)
    end)
    
    -- Re-enable backpack GUI
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
    end)
    
    -- Force camera back to custom if stuck
    pcall(function()
        workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
    end)
end

-- Repeatedly restore over time to beat the shop's Close() function
local function scheduleRestore()
    -- Immediate
    forceRestoreMovement()
    
    -- After shop Close() likely runs
    task.delay(0.3, forceRestoreMovement)
    task.delay(0.6, forceRestoreMovement)
    task.delay(1.0, forceRestoreMovement)
    task.delay(1.5, forceRestoreMovement)
end

local function teleportAndSellStay()
    local hrp = getHRP()
    if not hrp or not targetPart then return false end
    
    hrp.CFrame = targetPart.CFrame + Vector3.new(0, 5, 0)
    task.wait(0.15)
    
    local interactData = buildInteractionData(targetPart)
    interactData.Args.Range = interactData.Range
    
    local success = pcall(function()
        Network:FireServer("SellSnow", interactData.Name)
    end)
    
    -- Wait for sell animation/shop to process
    task.wait(0.5)
    
    -- CRITICAL: Schedule multiple restores to beat shop's Close()
    scheduleRestore()
    
    return success
end

-- ============================================
-- SHOP OPENING (for auto-buy)
-- ============================================

local function openShop(storePart)
    if not storePart then return false end
    local hrp = getHRP()
    if not hrp then return false end
    
    hrp.CFrame = storePart.CFrame + Vector3.new(0, 5, 0)
    task.wait(0.3)
    
    local data = buildInteractionData(storePart)
    data.Args.Range = data.Range
    local interactName = storePart:GetAttribute("InteractName") or storePart.Name
    data.InteractName = interactName
    
    pcall(function()
        local mod = player.PlayerScripts.Modules.InteractionHandler.Interactions:FindFirstChild(interactName)
        if mod then 
            require(mod)(player, data) 
        else 
            Network:FireServer(interactName, data.Name) 
        end
    end)
    
    task.wait(0.5)
    scheduleRestore()
    
    return true
end

local function openBackpackStore() return openShop(backpackStorePart) end
local function openToolsStore() return openShop(toolsStorePart) end

-- ============================================
-- AUTO BUY FUNCTIONS
-- ============================================

local function getOwnedBackpacks()
    local s,r = pcall(function() return PlayerData.Get("Backpacks") or {} end)
    return s and r or {}
end

local function getOwnedTools()
    local s,r = pcall(function() return PlayerData.Get("Tools") or {} end)
    return s and r or {}
end

local function getCurrentBackpack()
    local s,r = pcall(function() return PlayerData.Get("CurrentBackpack") end)
    return s and r or "Small"
end

local function getCurrentTools()
    local s,r = pcall(function() return PlayerData.Get("CurrentTools") or {} end)
    return s and r or {}
end

local function getCurrency(currencyType)
    local success, label = pcall(function()
        return playerGui:WaitForChild("ScreenGui"):WaitForChild("Hud"):WaitForChild("Stats"):WaitForChild("Money"):WaitForChild("AmountLabel")
    end)
    if success and label then
        local text = label.Text
        text = text:gsub(",", "")
        local num = text:gsub("[^%dKkMm]", "")
        if num and num ~= "" then
            local multiplier = 1
            if num:match("[Kk]") then
                multiplier = 1000
                num = num:gsub("[Kk]", "")
            elseif num:match("[Mm]") then
                multiplier = 1000000
                num = num:gsub("[Mm]", "")
            end
            local val = tonumber(num)
            if val then return val * multiplier end
        end
    end
    local s,r = pcall(function() return PlayerData.Get(currencyType or "Snow") or 0 end)
    return s and r or 0
end

local function isBackpackOwned(n) return table.find(getOwnedBackpacks(), n) ~= nil end
local function isToolOwned(n) return table.find(getOwnedTools(), n) ~= nil end

local function getShopItems(shopName)
    local items = {}
    local s, folder = pcall(function()
        return workspace.Regions.Winterville.Shops[shopName].ShopItems
    end)
    if not s then return items end
    for _, item in ipairs(folder:GetChildren()) do
        local info = item:FindFirstChild("Info")
        if info then
            local itemName = info:FindFirstChild("ItemName")
            local itemType = info:FindFirstChild("ItemType")
            local price = info:FindFirstChild("Price")
            if itemName and price then
                local shopInfo = nil
                pcall(function() shopInfo = GetShopItemInfo(item) end)
                table.insert(items, {
                    Instance = item,
                    Name = itemName.Value,
                    Type = itemType and itemType.Value or "Tool",
                    Price = tonumber(price.Value) or math.huge,
                    IsRobuxOnly = shopInfo and (shopInfo.GamePass or shopInfo.DevProduct) or false,
                    OffSale = shopInfo and shopInfo.OffSale or false,
                    Earnable = shopInfo and shopInfo.Earnable or false,
                })
            end
        end
    end
    table.sort(items, function(a,b) return a.Price < b.Price end)
    return items
end

local function getBackpackCapacity(name)
    local data = Database.Backpacks
    if data and data[name] then return data[name].Storage or 0 end
    return 0
end

local function getNextItemToBuy(shopName, itemType, ownedFn)
    local items = getShopItems(shopName)
    local money = getCurrency("Snow")
    for _, item in ipairs(items) do
        if item.Type == itemType and not ownedFn(item.Name) and not item.IsRobuxOnly and not item.OffSale and not item.Earnable and item.Price <= money then
            return item
        end
    end
    return nil
end

local function getNextBackpackToBuy() return getNextItemToBuy("WaynesPacks", "Backpack", isBackpackOwned) end
local function getNextShovelToBuy() return getNextItemToBuy("JimsTools", "Tool", isToolOwned) end

local function getCurrentCapacity() return getBackpackCapacity(getCurrentBackpack()) end

local function closeShop()
    GuiHandler.CloseGui("Shop")
end

local function buyItem(shopName, itemName, ownedFn, openFn, equipType)
    if ownedFn(itemName) then return false, "Owned" end
    if not openFn() then return false, "No shop" end
    task.wait(0.8)
    local s, folder = pcall(function() return workspace.Regions.Winterville.Shops[shopName].ShopItems end)
    if not s then 
        closeShop() 
        scheduleRestore()
        return false, "No folder" 
    end
    local targetItem = nil
    for _, item in ipairs(folder:GetChildren()) do
        local info = item:FindFirstChild("Info")
        if info then
            local n = info:FindFirstChild("ItemName")
            if n and n.Value == itemName then targetItem = item break end
        end
    end
    if not targetItem then 
        closeShop() 
        scheduleRestore()
        return false, "Not found" 
    end
    local shopInfo = nil
    pcall(function() shopInfo = GetShopItemInfo(targetItem) end)
    if shopInfo and (shopInfo.GamePass or shopInfo.DevProduct) then 
        closeShop() 
        scheduleRestore()
        return false, "Robux" 
    end
    local ok = pcall(function() Network:FireServer("BuyItem", targetItem) end)
    task.wait(0.5)
    if ok and equipType then
        pcall(function()
            if equipType == "Backpack" then
                Network:FireServer("EquipBackpack", itemName)
            elseif equipType == "Tool" then
                Network:FireServer("EquipTool", itemName)
            end
        end)
        task.wait(0.2)
    end
    closeShop()
    scheduleRestore()
    return ok
end

local function buyBackpack(n) return buyItem("WaynesPacks", n, isBackpackOwned, openBackpackStore, "Backpack") end
local function buyShovel(n) return buyItem("JimsTools", n, isToolOwned, openToolsStore, "Tool") end

-- ============================================
-- SHOVEL AURA - Replicates TileSelector logic directly
-- ============================================
local auraEnabled = false
local auraConnection = nil
local auraMultiplier = 3
local auraMaxTiles = 4
local auraCooldown = 0.005
local auraBatchSize = 1
local lastAuraTime = 0

-- Aura selection part (like TileSelector's SelectionPart)
local AuraPart = Instance.new("Part")
AuraPart.Name = "AuraPart"
AuraPart.Transparency = 1
AuraPart.Color = Color3.fromRGB(55, 235, 255)
AuraPart.Size = Vector3.new(10, 5, 5)
AuraPart.Shape = Enum.PartType.Cylinder
AuraPart.CanCollide = false
AuraPart.Anchored = true
AuraPart.Material = Enum.Material.SmoothPlastic
AuraPart.CastShadow = false
AuraPart.Parent = workspace
AuraPart.Touched:Connect(function() end)

-- Update AuraPart size based on current multiplier + max tiles
local function updateAuraSize()
    local baseMult = math.max(auraMultiplier, 1)
    local tileScale = math.max(auraMaxTiles, 1)
    local v6 = (5 * baseMult / 2) + (tileScale * 0.5)
    AuraPart.Size = Vector3.new(10, v6, v6)
end

-- Same as TileSelector.canShovelTile
local function canShovelTile(tile, snowTypes)
    if tile:GetAttribute("Height") == 0 then
        return false
    elseif snowTypes then
        local isSpecial = tile:GetAttribute("IsSpecial")
        if isSpecial then
            return table.find(snowTypes, tile:GetAttribute("OriginalType")) ~= nil
        else
            return table.find(snowTypes, tile:GetAttribute("Type")) ~= nil
        end
    else
        return true
    end
end

-- Same as TileSelector.getTiles
local function getAuraTiles(position, snowTypes)
    updateAuraSize()
    AuraPart.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, 1.5707963267948966)
    local touching = AuraPart:GetTouchingParts()
    local tiles = {}
    for _, part in ipairs(touching) do
        if CollectionService:HasTag(part, "Tile") and canShovelTile(part, snowTypes) then
            table.insert(tiles, part)
        end
    end
    return tiles
end

-- Same as TileSelector.getClosestTiles
local function getClosestTiles(tiles, maxCount)
    if not tiles or #tiles == 0 then return {} end
    local result = {}
    local playerPos = player:GetAttribute("Position") or Vector3.new()
    local temp = {unpack(tiles)}
    
    while #result < math.min(#temp, maxCount) do
        local closestDist = math.huge
        local closestTile = nil
        local closestIndex = 1
        
        for i, tile in ipairs(temp) do
            local dist = (playerPos - tile.Position).magnitude
            if dist < closestDist then
                closestDist = dist
                closestTile = tile
                closestIndex = i
            end
        end
        
        if closestTile then
            table.insert(result, closestTile)
            table.remove(temp, closestIndex)
        else
            break
        end
    end
    
    return result
end

-- Split tiles into small batches (each batch = one remote)
local function batchTiles(tiles, batchSize)
    local batches = {}
    for i = 1, #tiles, batchSize do
        local batch = {}
        for j = i, math.min(i + batchSize - 1, #tiles) do
            table.insert(batch, tiles[j])
        end
        table.insert(batches, batch)
    end
    return batches
end

local function getEquippedShovel()
    local char = player.Character
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool and tool.Name:lower():find("shovel") then return tool end
    return nil
end

local function auraShovel(tool, tiles)
    if not tool or #tiles == 0 then return end
    pcall(function()
        Network:FireServer("Shovel", tool, tiles)
    end)
end

local function startAura()
    if auraConnection then return end
    auraConnection = RunService.Heartbeat:Connect(function()
        if not auraEnabled then return end
        
        local now = tick()
        if now - lastAuraTime < auraCooldown then return end
        
        local tool = getEquippedShovel()
        if not tool then return end
        
        local hrp = getHRP()
        if not hrp then return end
        
        -- Get tiles in dynamic range, then pick closest N
        local allTiles = getAuraTiles(hrp.Position, nil)
        local closestTiles = getClosestTiles(allTiles, auraMaxTiles)
        
        if #closestTiles > 0 then
            -- If we have more tiles than batch size, fire multiple remotes rapidly
            if #closestTiles > auraBatchSize then
                local batches = batchTiles(closestTiles, auraBatchSize)
                for _, batch in ipairs(batches) do
                    auraShovel(tool, batch)
                    -- No task.wait() — fire all in same frame for max speed
                end
            else
                auraShovel(tool, closestTiles)
            end
            lastAuraTime = now
        end
    end)
end

local function stopAura()
    if auraConnection then
        auraConnection:Disconnect()
        auraConnection = nil
    end
end

-- ============================================
-- VEHICLE SPEED HACK v3 - PROPER RESTORE + MAXSPEED OVERRIDE
-- NOTE: You MUST exit and re-enter the vehicle after changing speed settings!
-- ============================================

local VehicleSpeed = {
    Enabled = false,
    Multiplier = 1,        -- Motor velocity multiplier (1 = normal, 10 = 10x)
    MaxSpeedOverride = 0,  -- 0 = use original, >0 = override MaxSpeed attribute
    Conn = nil,
    CurrentVehicle = nil,
    Motors = {},
    OriginalMaxSpeed = nil,
}

local function getPlayerVehicle()
    for _, vehicle in ipairs(workspace.Vehicles:GetChildren()) do
        local owner = vehicle:FindFirstChild("Owner")
        if owner and owner.Value == player then
            return vehicle
        end
    end
    return nil
end

local function getVehicleMotors(vehicle)
    local motors = {}
    if not vehicle then return motors end
    
    local motorsFolder = vehicle:FindFirstChild("Motors")
    if motorsFolder then
        for _, motor in ipairs(motorsFolder:GetChildren()) do
            if motor:IsA("HingeConstraint") then
                table.insert(motors, motor)
            end
        end
    end
    return motors
end

local function getVehicleSeat(vehicle)
    if not vehicle then return nil end
    return vehicle:FindFirstChildOfClass("VehicleSeat")
end

local function startVehicleSpeed()
    if VehicleSpeed.Conn then return end
    
    VehicleSpeed.Conn = RunService.Heartbeat:Connect(function()
        if not VehicleSpeed.Enabled then return end
        
        -- Find current vehicle
        local vehicle = getPlayerVehicle()
        if not vehicle then
            -- Player left vehicle - restore if we had one
            if VehicleSpeed.CurrentVehicle and VehicleSpeed.CurrentVehicle.Parent then
                pcall(function()
                    if VehicleSpeed.OriginalMaxSpeed then
                        VehicleSpeed.CurrentVehicle:SetAttribute("MaxSpeed", VehicleSpeed.OriginalMaxSpeed)
                    end
                end)
            end
            VehicleSpeed.CurrentVehicle = nil
            VehicleSpeed.Motors = {}
            VehicleSpeed.OriginalMaxSpeed = nil
            return
        end
        
        -- New vehicle detected
        if vehicle ~= VehicleSpeed.CurrentVehicle then
            VehicleSpeed.CurrentVehicle = vehicle
            VehicleSpeed.Motors = getVehicleMotors(vehicle)
            -- Store original MaxSpeed
            VehicleSpeed.OriginalMaxSpeed = vehicle:GetAttribute("MaxSpeed") or 30
        end
        
        -- Apply MaxSpeed override if set (>0)
        if VehicleSpeed.MaxSpeedOverride > 0 then
            pcall(function()
                vehicle:SetAttribute("MaxSpeed", VehicleSpeed.MaxSpeedOverride)
            end)
        end
        
        -- DIRECT MOTOR OVERRIDE: Boost AngularVelocity in real-time
        local seat = getVehicleSeat(vehicle)
        if seat then
            local throttle = seat.Throttle
            if math.abs(throttle) > 0.01 then
                for _, motor in ipairs(VehicleSpeed.Motors) do
                    local currentVel = motor.AngularVelocity
                    if currentVel ~= 0 then
                        -- Apply multiplier (1 = no change, 10 = 10x)
                        motor.AngularVelocity = currentVel * VehicleSpeed.Multiplier
                    end
                end
            end
        end
    end)
end

local function stopVehicleSpeed()
    if VehicleSpeed.Conn then
        VehicleSpeed.Conn:Disconnect()
        VehicleSpeed.Conn = nil
    end
    
    -- Restore original MaxSpeed on current vehicle
    if VehicleSpeed.CurrentVehicle and VehicleSpeed.CurrentVehicle.Parent then
        pcall(function()
            if VehicleSpeed.OriginalMaxSpeed then
                VehicleSpeed.CurrentVehicle:SetAttribute("MaxSpeed", VehicleSpeed.OriginalMaxSpeed)
            end
        end)
    end
    
    VehicleSpeed.CurrentVehicle = nil
    VehicleSpeed.Motors = {}
    VehicleSpeed.OriginalMaxSpeed = nil
end

local function toggleVehicleSpeed(enabled)
    VehicleSpeed.Enabled = enabled
    
    if enabled then
        startVehicleSpeed()
        Library:Notify("Vehicle Speed Enabled! Re-enter vehicle to apply changes.", 3)
    else
        stopVehicleSpeed()
        Library:Notify("Vehicle Speed Disabled - Restored original MaxSpeed", 2)
    end
end

-- ============================================
-- VEHICLE FLY (VFly) v5 - NEW VERSION
-- Fixed thumbstick forward/back direction
-- Supports both Vehicle and Player Character fly
-- ============================================

local VFly = {
    Enabled = false,
    Connection = nil,
    BodyVelocity = nil,
    BodyGyro = nil,
    Speed = 50,
    ForwardBack = 0,
    LeftRight = 0,
    UpDown = 0,
    Mode = "player",
}

local function getPlayerVehicleModel()
    for _, vehicle in ipairs(workspace.Vehicles:GetChildren()) do
        local owner = vehicle:FindFirstChild("Owner")
        if owner and owner.Value == player then
            return vehicle
        end
    end
    return nil
end

local function getCharacterHumanoid()
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function getVehicleSeatModel(vehicle)
    if not vehicle then return nil end
    return vehicle:FindFirstChildOfClass("VehicleSeat")
end

-- PC Controls
local function bindVFlyPCControls()
    ContextActionService:BindAction("VFlyForward", function(_, inputState)
        if inputState == Enum.UserInputState.Begin then
            VFly.ForwardBack = -1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.W) then
                VFly.ForwardBack = 0
            else
                VFly.ForwardBack = 1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.S, Enum.KeyCode.Down)

    ContextActionService:BindAction("VFlyBack", function(_, inputState)
        if inputState == Enum.UserInputState.Begin then
            VFly.ForwardBack = 1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.S) then
                VFly.ForwardBack = 0
            else
                VFly.ForwardBack = -1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.W, Enum.KeyCode.Up)

    ContextActionService:BindAction("VFlyLeft", function(_, inputState)
        if inputState == Enum.UserInputState.Begin then
            VFly.LeftRight = -1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.D) then
                VFly.LeftRight = 0
            else
                VFly.LeftRight = 1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.A, Enum.KeyCode.Left)

    ContextActionService:BindAction("VFlyRight", function(_, inputState)
        if inputState == Enum.UserInputState.Begin then
            VFly.LeftRight = 1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.A) then
                VFly.LeftRight = 0
            else
                VFly.LeftRight = -1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.D, Enum.KeyCode.Right)

    ContextActionService:BindAction("VFlyUp", function(_, inputState)
        if inputState == Enum.UserInputState.Begin then
            VFly.UpDown = 1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                VFly.UpDown = 0
            else
                VFly.UpDown = 1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.Space)

    ContextActionService:BindAction("VFlyDown", function(_, inputState)
        if inputState == Enum.UserInputState.Begin then
            VFly.UpDown = -1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                VFly.UpDown = 0
            else
                VFly.UpDown = 1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
end

local function unbindVFlyPCControls()
    ContextActionService:UnbindAction("VFlyForward")
    ContextActionService:UnbindAction("VFlyBack")
    ContextActionService:UnbindAction("VFlyLeft")
    ContextActionService:UnbindAction("VFlyRight")
    ContextActionService:UnbindAction("VFlyUp")
    ContextActionService:UnbindAction("VFlyDown")
    VFly.ForwardBack = 0
    VFly.LeftRight = 0
    VFly.UpDown = 0
end

-- Mobile up/down buttons
local mobileUpBtn, mobileDownBtn

local function createVFlyMobileButtons()
    if mobileUpBtn then return end
    
    mobileUpBtn = Instance.new("TextButton")
    mobileUpBtn.Size = UDim2.new(0, 70, 0, 70)
    mobileUpBtn.Position = UDim2.new(0, 20, 1, -160)
    mobileUpBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
    mobileUpBtn.Text = "UP"
    mobileUpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    mobileUpBtn.TextScaled = true
    mobileUpBtn.Font = Enum.Font.GothamBold
    mobileUpBtn.Parent = playerGui
    
    local upCorner = Instance.new("UICorner")
    upCorner.CornerRadius = UDim.new(1, 0)
    upCorner.Parent = mobileUpBtn
    
    mobileUpBtn.InputBegan:Connect(function()
        VFly.UpDown = 1
    end)
    mobileUpBtn.InputEnded:Connect(function()
        VFly.UpDown = 0
    end)
    
    mobileDownBtn = Instance.new("TextButton")
    mobileDownBtn.Size = UDim2.new(0, 70, 0, 70)
    mobileDownBtn.Position = UDim2.new(0, 20, 1, -80)
    mobileDownBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    mobileDownBtn.Text = "DOWN"
    mobileDownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    mobileDownBtn.TextScaled = true
    mobileDownBtn.Font = Enum.Font.GothamBold
    mobileDownBtn.Parent = playerGui
    
    local downCorner = Instance.new("UICorner")
    downCorner.CornerRadius = UDim.new(1, 0)
    downCorner.Parent = mobileDownBtn
    
    mobileDownBtn.InputBegan:Connect(function()
        VFly.UpDown = -1
    end)
    mobileDownBtn.InputEnded:Connect(function()
        VFly.UpDown = 0
    end)
end

local function destroyVFlyMobileButtons()
    if mobileUpBtn then mobileUpBtn:Destroy(); mobileUpBtn = nil end
    if mobileDownBtn then mobileDownBtn:Destroy(); mobileDownBtn = nil end
end

-- Get the part to fly (vehicle PrimaryPart or player HumanoidRootPart)
local function getVFlyTarget()
    local vehicle = getPlayerVehicleModel()
    if vehicle then
        local primaryPart = vehicle.PrimaryPart
        if primaryPart then
            VFly.Mode = "vehicle"
            return primaryPart
        end
    end
    
    local char = player.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            VFly.Mode = "player"
            return hrp
        end
    end
    
    return nil
end

-- Main fly loop
local function startVFly()
    local targetPart = getVFlyTarget()
    if not targetPart then
        Library:Notify("Status: No vehicle or character!", 3)
        VFly.Enabled = false
        return
    end

    VFly.BodyGyro = Instance.new("BodyGyro")
    VFly.BodyGyro.Name = "VFly_Gyro"
    VFly.BodyGyro.P = 9e4
    VFly.BodyGyro.D = 500
    VFly.BodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    VFly.BodyGyro.CFrame = targetPart.CFrame
    VFly.BodyGyro.Parent = targetPart

    VFly.BodyVelocity = Instance.new("BodyVelocity")
    VFly.BodyVelocity.Name = "VFly_Velocity"
    VFly.BodyVelocity.Velocity = Vector3.zero
    VFly.BodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    VFly.BodyVelocity.P = 12500
    VFly.BodyVelocity.Parent = targetPart

    bindVFlyPCControls()
    if UserInputService.TouchEnabled then
        createVFlyMobileButtons()
    end

    VFly.Connection = RunService.RenderStepped:Connect(function()
        local currentTarget = getVFlyTarget()
        if not currentTarget then
            stopVFly()
            return
        end
        
        if currentTarget ~= targetPart then
            if VFly.BodyGyro then VFly.BodyGyro:Destroy() end
            if VFly.BodyVelocity then VFly.BodyVelocity:Destroy() end
            
            targetPart = currentTarget
            
            VFly.BodyGyro = Instance.new("BodyGyro")
            VFly.BodyGyro.Name = "VFly_Gyro"
            VFly.BodyGyro.P = 9e4
            VFly.BodyGyro.D = 500
            VFly.BodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            VFly.BodyGyro.CFrame = targetPart.CFrame
            VFly.BodyGyro.Parent = targetPart

            VFly.BodyVelocity = Instance.new("BodyVelocity")
            VFly.BodyVelocity.Name = "VFly_Velocity"
            VFly.BodyVelocity.Velocity = Vector3.zero
            VFly.BodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            VFly.BodyVelocity.P = 12500
            VFly.BodyVelocity.Parent = targetPart
        end

        local camera = Workspace.CurrentCamera
        local flySpeed = VFly.Speed

        local camCF = camera.CFrame
        local camLook = camCF.LookVector
        local camRight = camCF.RightVector
        local camUp = Vector3.new(0, 1, 0)

        local fb = VFly.ForwardBack
        local lr = VFly.LeftRight
        local ud = VFly.UpDown

        if VFly.Mode == "vehicle" then
            local vehicle = getPlayerVehicleModel()
            local seat = getVehicleSeatModel(vehicle)
            if seat then
                local throttle = seat.Throttle
                local steer = seat.Steer
                
                if math.abs(throttle) > 0.05 or math.abs(steer) > 0.05 then
                    fb = throttle
                    
                    local vehLook = targetPart.CFrame.LookVector
                    local camFlatLook = Vector3.new(camLook.X, 0, camLook.Z).Unit
                    local vehFlatLook = Vector3.new(vehLook.X, 0, vehLook.Z).Unit
                    local camVehDot = camFlatLook:Dot(vehFlatLook)
                    
                    if camVehDot < 0 then
                        lr = -steer
                    else
                        lr = steer
                    end
                end
            end
        else
            local hum = getCharacterHumanoid()
            if hum then
                local moveDir = hum.MoveDirection
                if moveDir.Magnitude > 0.1 then
                    local flatLook = Vector3.new(camLook.X, 0, camLook.Z).Unit
                    local flatRight = Vector3.new(camRight.X, 0, camRight.Z).Unit
                    if flatLook.Magnitude > 0.1 and flatRight.Magnitude > 0.1 then
                        fb = moveDir:Dot(flatLook)
                        lr = moveDir:Dot(flatRight)
                    end
                end
            end
        end

        local velocity = Vector3.zero

        if math.abs(fb) > 0.1 then
            velocity = velocity + (camLook * fb * flySpeed)
        end

        if math.abs(lr) > 0.1 then
            velocity = velocity + (camRight * lr * flySpeed)
        end

        if math.abs(ud) > 0.1 then
            velocity = velocity + (camUp * ud * flySpeed)
        end

        if velocity.Magnitude < 0.1 then
            velocity = Vector3.new(0, 0.1, 0)
        end

        VFly.BodyVelocity.Velocity = velocity
        VFly.BodyGyro.CFrame = CFrame.new(targetPart.Position, targetPart.Position + camLook)
    end)

    Library:Notify("VFly Enabled! Flying (" .. VFly.Mode .. ") - WASD + Space/Shift", 3)
end

function stopVFly()
    if VFly.Connection then
        VFly.Connection:Disconnect()
        VFly.Connection = nil
    end
    if VFly.BodyGyro then
        VFly.BodyGyro:Destroy()
        VFly.BodyGyro = nil
    end
    if VFly.BodyVelocity then
        VFly.BodyVelocity:Destroy()
        VFly.BodyVelocity = nil
    end

    unbindVFlyPCControls()
    destroyVFlyMobileButtons()

    Library:Notify("VFly Disabled!", 2)
end

local function toggleVFly()
    VFly.Enabled = not VFly.Enabled
    if VFly.Enabled then
        startVFly()
    else
        stopVFly()
    end
end

RunService.Heartbeat:Connect(function()
    if VFly.Enabled then
        local target = getVFlyTarget()
        if not target then
            stopVFly()
            VFly.Enabled = false
        end
    end
end)

-- ============================================
-- QFLY - FROM GHOST HUNTER ESP
-- ============================================

local QFly = {
    Enabled = false,
    Connection = nil,
    BodyGyro = nil,
    BodyVelocity = nil,
    FlyKey = Enum.KeyCode.Q,
    ForwardBack = 0,
    LeftRight = 0,
    UpDown = 0,
    Speed = 50,
}

local function BindFlyControls()
    ContextActionService:BindAction("FlyForward", function(actionName, inputState, inputObj)
        if inputState == Enum.UserInputState.Begin then
            QFly.ForwardBack = -1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.W) then
                QFly.ForwardBack = 0
            else
                QFly.ForwardBack = 1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.S, Enum.KeyCode.Down)

    ContextActionService:BindAction("FlyBack", function(actionName, inputState, inputObj)
        if inputState == Enum.UserInputState.Begin then
            QFly.ForwardBack = 1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.S) then
                QFly.ForwardBack = 0
            else
                QFly.ForwardBack = -1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.W, Enum.KeyCode.Up)

    ContextActionService:BindAction("FlyLeft", function(actionName, inputState, inputObj)
        if inputState == Enum.UserInputState.Begin then
            QFly.LeftRight = -1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.D) then
                QFly.LeftRight = 0
            else
                QFly.LeftRight = 1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.A, Enum.KeyCode.Left)

    ContextActionService:BindAction("FlyRight", function(actionName, inputState, inputObj)
        if inputState == Enum.UserInputState.Begin then
            QFly.LeftRight = 1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.A) then
                QFly.LeftRight = 0
            else
                QFly.LeftRight = -1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.D, Enum.KeyCode.Right)

    ContextActionService:BindAction("FlyUp", function(actionName, inputState, inputObj)
        if inputState == Enum.UserInputState.Begin then
            QFly.UpDown = 1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and not UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
                QFly.UpDown = 0
            else
                QFly.UpDown = -1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.Space)

    ContextActionService:BindAction("FlyDown", function(actionName, inputState, inputObj)
        if inputState == Enum.UserInputState.Begin then
            QFly.UpDown = -1
        elseif inputState == Enum.UserInputState.End then
            if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                QFly.UpDown = 0
            else
                QFly.UpDown = 1
            end
        end
        return Enum.ContextActionResult.Sink
    end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)
end

local function UnbindFlyControls()
    ContextActionService:UnbindAction("FlyForward")
    ContextActionService:UnbindAction("FlyBack")
    ContextActionService:UnbindAction("FlyLeft")
    ContextActionService:UnbindAction("FlyRight")
    ContextActionService:UnbindAction("FlyUp")
    ContextActionService:UnbindAction("FlyDown")

    QFly.ForwardBack = 0
    QFly.LeftRight = 0
    QFly.UpDown = 0
end

local function StartQFly()
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then return end

    humanoid.PlatformStand = true
    humanoid.AutoRotate = false

    QFly.BodyGyro = Instance.new("BodyGyro")
    QFly.BodyGyro.Name = "QFly_Gyro"
    QFly.BodyGyro.P = 9e4
    QFly.BodyGyro.D = 500
    QFly.BodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    QFly.BodyGyro.CFrame = hrp.CFrame
    QFly.BodyGyro.Parent = hrp

    QFly.BodyVelocity = Instance.new("BodyVelocity")
    QFly.BodyVelocity.Name = "QFly_Velocity"
    QFly.BodyVelocity.Velocity = Vector3.zero
    QFly.BodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    QFly.BodyVelocity.P = 12500
    QFly.BodyVelocity.Parent = hrp

    BindFlyControls()

    QFly.Connection = RunService.RenderStepped:Connect(function()
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if not hrp or not humanoid then
            StopQFly()
            return
        end

        local camera = Workspace.CurrentCamera
        local flySpeed = QFly.Speed

        local camCF = camera.CFrame
        local camLook = camCF.LookVector
        local camRight = camCF.RightVector
        local camUp = Vector3.new(0, 1, 0)

        local fb = QFly.ForwardBack
        local lr = QFly.LeftRight
        local ud = QFly.UpDown

        local moveDir = humanoid.MoveDirection

        if moveDir.Magnitude > 0.1 then
            local flatLook = Vector3.new(camLook.X, 0, camLook.Z).Unit
            local flatRight = Vector3.new(camRight.X, 0, camRight.Z).Unit

            if flatLook.Magnitude > 0.1 and flatRight.Magnitude > 0.1 then
                fb = moveDir:Dot(flatLook)
                lr = moveDir:Dot(flatRight)
            end
        end

        local velocity = Vector3.zero

        if math.abs(fb) > 0.1 then
            velocity = velocity + (camLook * fb * flySpeed)
        end

        if math.abs(lr) > 0.1 then
            velocity = velocity + (camRight * lr * flySpeed)
        end

        if math.abs(ud) > 0.1 then
            velocity = velocity + (camUp * ud * flySpeed)
        end

        if velocity.Magnitude < 0.1 then
            velocity = Vector3.new(0, 0.1, 0)
        end

        QFly.BodyVelocity.Velocity = velocity
        QFly.BodyGyro.CFrame = CFrame.new(hrp.Position, hrp.Position + camLook)
    end)

    Library:Notify("QFly Enabled! (Q key or button to toggle)", 3)
end

local function StopQFly()
    if QFly.Connection then
        QFly.Connection:Disconnect()
        QFly.Connection = nil
    end
    if QFly.BodyGyro then
        QFly.BodyGyro:Destroy()
        QFly.BodyGyro = nil
    end
    if QFly.BodyVelocity then
        QFly.BodyVelocity:Destroy()
        QFly.BodyVelocity = nil
    end

    UnbindFlyControls()

    local char = player.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.PlatformStand = false
            humanoid.AutoRotate = true
        end
    end

    Library:Notify("QFly Disabled!", 2)
end

local function ToggleQFly()
    QFly.Enabled = not QFly.Enabled
    if QFly.Enabled then
        StartQFly()
    else
        StopQFly()
    end
end

-- PC keybind
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == QFly.FlyKey then
        ToggleQFly()
    end
end)

-- ============================================
-- WALKSPEED - FIXED (CFrame method like before)
-- ============================================

local WalkSpeed = {
    Enabled = false,
    Conn = nil,
    TargetSpeed = 16,
}

local function ToggleWalkSpeed(enabled, speed)
    WalkSpeed.Enabled = enabled
    if speed then WalkSpeed.TargetSpeed = speed end

    if enabled then
        WalkSpeed.Conn = RunService.Heartbeat:Connect(function()
            local char = player.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if not hrp or not humanoid then return end

            local moveDir = humanoid.MoveDirection
            if moveDir.Magnitude < 0.1 then return end

            local currentSpeed = humanoid.WalkSpeed
            local targetSpeed = WalkSpeed.TargetSpeed

            if targetSpeed > currentSpeed then
                local extraSpeed = targetSpeed - currentSpeed
                local velocity = moveDir * extraSpeed * 0.016
                hrp.CFrame = hrp.CFrame + Vector3.new(velocity.X, 0, velocity.Z)
            end
        end)
        Library:Notify("WalkSpeed Enabled! Speed: " .. tostring(WalkSpeed.TargetSpeed), 2)
    else
        if WalkSpeed.Conn then WalkSpeed.Conn:Disconnect() end
        WalkSpeed.Conn = nil
        Library:Notify("WalkSpeed Disabled!", 2)
    end
end

-- ============================================
-- MOBILE FLY TOGGLE BUTTON
-- ============================================

local MobileFlyBtn = nil
local function CreateMobileFlyButton()
    if MobileFlyBtn then return end
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FlyToggleGui"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui
    
    local btn = Instance.new("TextButton")
    btn.Name = "FlyToggleBtn"
    btn.Size = UDim2.new(0, 80, 0, 80)
    btn.Position = UDim2.new(1, -100, 0, 20)
    btn.BackgroundColor3 = Color3.fromRGB(55, 235, 255)
    btn.TextColor3 = Color3.fromRGB(0, 0, 0)
    btn.Text = "FLY\nOFF"
    btn.TextScaled = true
    btn.Font = Enum.Font.GothamBold
    btn.TextStrokeTransparency = 0.5
    btn.Parent = screenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = btn
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 2
    stroke.Parent = btn
    
    btn.MouseButton1Click:Connect(function()
        ToggleQFly()
        if QFly.Enabled then
            btn.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
            btn.Text = "FLY\nON"
        else
            btn.BackgroundColor3 = Color3.fromRGB(55, 235, 255)
            btn.Text = "FLY\nOFF"
        end
    end)
    
    MobileFlyBtn = btn
end

-- ============================================
-- UI
-- ============================================
local Window = Library:CreateWindow({
    Title = "Snow Shoveling Simulator",
    Footer = "by FrostyTools",
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

local Tabs = {
    Main = Window:AddTab("Main", "house"),
    Auto = Window:AddTab("Auto", "zap"),
    Aura = Window:AddTab("Aura", "sword"),
    Player = Window:AddTab("Player", "user"),
    UISettings = Window:AddTab("UI Settings", "settings")
}

-- MAIN TAB
local MainLeft = Tabs.Main:AddLeftGroupbox("Functions")
local MainRight = Tabs.Main:AddRightGroupbox("Info")
MainRight:AddLabel("Status: Ready")
local BackpackLabel = MainRight:AddLabel("Backpack: -- / --")

MainLeft:AddButton({
    Text = "Teleport & Sell",
    Func = function()
        Library:Notify("Selling...", 2)
        local s = teleportAndSellStay()
        Library:Notify(s and "Sold!" or "Fail", 2)
    end
})

MainLeft:AddButton({
    Text = "Teleport Only",
    Func = function()
        local hrp = getHRP()
        if hrp then hrp.CFrame = targetPart.CFrame + Vector3.new(0, 5, 0) end
    end
})

-- AUTO SELL
local AutoLeft = Tabs.Auto:AddLeftGroupbox("Auto Sell")
local autoSellEnabled = false
local autoSellThread = nil
local lastSellTime = 0
local sellCooldown = 2

AutoLeft:AddToggle("AutoSell", {
    Text = "Auto Sell When Full",
    Default = false,
    Callback = function(v)
        autoSellEnabled = v
        if v then
            autoSellThread = task.spawn(function()
                while autoSellEnabled do
                    local c, m = getBackpackNumbers()
                    if c and m then
                        BackpackLabel:SetText("Backpack: " .. c .. " / " .. m)
                        if c >= m and (tick() - lastSellTime) > sellCooldown then
                            Library:Notify("Full! Selling...", 1)
                            if teleportAndSellStay() then lastSellTime = tick() end
                        end
                    end
                    task.wait(0.3)
                end
            end)
        end
    end
})

AutoLeft:AddSlider("SellCD", {
    Text = "Cooldown", Default = 2, Min = 1, Max = 10, Rounding = 0,
    Callback = function(v) sellCooldown = v end,
})

-- AUTO BUY BACKPACKS
local AutoCenter = Tabs.Auto:AddLeftGroupbox("Auto Buy Backpacks")
local autoBuyEnabled = false
local autoBuyThread = nil
local buyCooldown = 2

local CurrentBPLabel = AutoCenter:AddLabel("Current: --")
local NextBPLabel = AutoCenter:AddLabel("Next: --")
local MoneyLabel = AutoCenter:AddLabel("Money: --")

local function refreshBP()
    local bp = getCurrentBackpack()
    local cap = getCurrentCapacity()
    local money = getCurrency("Snow")
    local nextBP = getNextBackpackToBuy()
    CurrentBPLabel:SetText("Current: " .. bp .. " (" .. cap .. ")")
    MoneyLabel:SetText("Money: " .. money .. " Snow")
    if nextBP then
        NextBPLabel:SetText("Next: " .. nextBP.Name .. " - " .. nextBP.Price .. " Snow")
    else
        NextBPLabel:SetText("Next: Nothing")
    end
end

AutoCenter:AddButton({
    Text = "Buy Next Backpack",
    Func = function()
        local nextBP = getNextBackpackToBuy()
        if not nextBP then Library:Notify("Nothing to buy!", 2) return end
        Library:Notify("Buying " .. nextBP.Name .. "...", 1)
        local s, e = buyBackpack(nextBP.Name)
        Library:Notify(s and "Bought!" or "Fail: " .. tostring(e), 2)
        refreshBP()
    end
})

AutoCenter:AddToggle("AutoBuyBP", {
    Text = "Auto Buy Backpack",
    Default = false,
    Callback = function(v)
        autoBuyEnabled = v
        if v then
            refreshBP()
            autoBuyThread = task.spawn(function()
                while autoBuyEnabled do
                    local money = getCurrency("Snow")
                    local nextBP = getNextBackpackToBuy()
                    MoneyLabel:SetText("Money: " .. money .. " Snow")
                    if nextBP then
                        NextBPLabel:SetText("Next: " .. nextBP.Name .. " - " .. nextBP.Price)
                        if money >= nextBP.Price then
                            Library:Notify("Buying " .. nextBP.Name .. "...", 1)
                            local s = buyBackpack(nextBP.Name)
                            if s then
                                Library:Notify("Bought " .. nextBP.Name .. "!", 2)
                                refreshBP()
                                task.wait(buyCooldown)
                            end
                        end
                    else
                        NextBPLabel:SetText("Next: Nothing")
                    end
                    task.wait(1)
                end
            end)
        end
    end
})

AutoCenter:AddSlider("BuyCD", {
    Text = "Cooldown", Default = 2, Min = 0, Max = 10, Rounding = 0,
    Callback = function(v) buyCooldown = v end,
})

AutoCenter:AddButton({
    Text = "Refresh",
    Func = function() refreshBP() end,
})

-- AUTO BUY SHOVELS
local AutoRight = Tabs.Auto:AddRightGroupbox("Auto Buy Shovels")
local autoShovelEnabled = false
local autoShovelThread = nil
local shovelCD = 2

local CurrentShovelLabel = AutoRight:AddLabel("Current: --")
local NextShovelLabel = AutoRight:AddLabel("Next: --")
local ShovelMoneyLabel = AutoRight:AddLabel("Money: --")

local function refreshShovel()
    local tools = getCurrentTools()
    local money = getCurrency("Snow")
    local nextS = getNextShovelToBuy()
    CurrentShovelLabel:SetText("Equipped: " .. (#tools > 0 and table.concat(tools, ", ") or "None"))
    ShovelMoneyLabel:SetText("Money: " .. money .. " Snow")
    if nextS then
        NextShovelLabel:SetText("Next: " .. nextS.Name .. " - " .. nextS.Price)
    else
        NextShovelLabel:SetText("Next: Nothing")
    end
end

AutoRight:AddButton({
    Text = "Buy Next Shovel",
    Func = function()
        local nextS = getNextShovelToBuy()
        if not nextS then Library:Notify("Nothing to buy!", 2) return end
        Library:Notify("Buying " .. nextS.Name .. "...", 1)
        local s, e = buyShovel(nextS.Name)
        Library:Notify(s and "Bought!" or "Fail: " .. tostring(e), 2)
        refreshShovel()
    end
})

AutoRight:AddToggle("AutoBuyShovel", {
    Text = "Auto Buy Shovel",
    Default = false,
    Callback = function(v)
        autoShovelEnabled = v
        if v then
            refreshShovel()
            autoShovelThread = task.spawn(function()
                while autoShovelEnabled do
                    local money = getCurrency("Snow")
                    local nextS = getNextShovelToBuy()
                    ShovelMoneyLabel:SetText("Money: " .. money .. " Snow")
                    if nextS then
                        NextShovelLabel:SetText("Next: " .. nextS.Name .. " - " .. nextS.Price)
                        if money >= nextS.Price then
                            Library:Notify("Buying " .. nextS.Name .. "...", 1)
                            local s = buyShovel(nextS.Name)
                            if s then
                                Library:Notify("Bought " .. nextS.Name .. "!", 2)
                                refreshShovel()
                                task.wait(shovelCD)
                            end
                        end
                    else
                        NextShovelLabel:SetText("Next: Nothing")
                    end
                    task.wait(1)
                end
            end)
        end
    end
})

AutoRight:AddSlider("ShovelCD", {
    Text = "Cooldown", Default = 2, Min = 0, Max = 10, Rounding = 0,
    Callback = function(v) shovelCD = v end,
})

AutoRight:AddButton({
    Text = "Refresh",
    Func = function() refreshShovel() end,
})

-- ============================================
-- AURA TAB
-- ============================================
local AuraLeft = Tabs.Aura:AddLeftGroupbox("Shovel Aura")
local AuraRight = Tabs.Aura:AddRightGroupbox("Aura Stats")

local AuraStatus = AuraRight:AddLabel("Status: Off")
local AuraTilesLabel = AuraRight:AddLabel("Tiles: 0")
local AuraRangeLabel = AuraRight:AddLabel("Range: 8.75")
local AuraBatchLabel = AuraRight:AddLabel("Batch: 1")

AuraLeft:AddToggle("AuraEnabled", {
    Text = "Enable Shovel Aura",
    Default = false,
    Callback = function(v)
        auraEnabled = v
        AuraStatus:SetText("Status: " .. (v and "ON" or "Off"))
        if v then
            startAura()
            Library:Notify("Aura ON! Hold shovel to auto-collect", 3)
        else
            stopAura()
            Library:Notify("Aura OFF", 2)
        end
    end
})

AuraLeft:AddSlider("AuraMultiplier", {
    Text = "Tile Multiplier",
    Default = 3,
    Min = 1,
    Max = 100,
    Rounding = 0,
    Callback = function(v)
        auraMultiplier = v
        updateAuraSize()
        local v6 = (5 * math.max(auraMultiplier, 1) / 2) + (math.max(auraMaxTiles, 1) * 0.5)
        AuraRangeLabel:SetText("Range: " .. string.format("%.2f", v6))
    end
})

AuraLeft:AddSlider("AuraMaxTiles", {
    Text = "Max Tiles",
    Default = 4,
    Min = 1,
    Max = 50,
    Rounding = 0,
    Callback = function(v)
        auraMaxTiles = v
        updateAuraSize()
        local v6 = (5 * math.max(auraMultiplier, 1) / 2) + (math.max(auraMaxTiles, 1) * 0.5)
        AuraRangeLabel:SetText("Range: " .. string.format("%.2f", v6))
    end
})

AuraLeft:AddSlider("AuraBatchSize", {
    Text = "Tiles Per Remote",
    Default = 1,
    Min = 1,
    Max = 2,
    Rounding = 0,
    Callback = function(v)
        auraBatchSize = v
        AuraBatchLabel:SetText("Batch: " .. v)
    end
})

AuraLeft:AddSlider("AuraCooldown", {
    Text = "Cooldown (sec)",
    Default = 0.005,
    Min = 0.001,
    Max = 2,
    Rounding = 3,
    Callback = function(v)
        auraCooldown = v
    end
})

-- Update stats
task.spawn(function()
    while true do
        if auraEnabled then
            local hrp = getHRP()
            if hrp then
                local allTiles = getAuraTiles(hrp.Position, nil)
                local closestTiles = getClosestTiles(allTiles, auraMaxTiles)
                AuraTilesLabel:SetText("Tiles: " .. #closestTiles .. "/" .. #allTiles)
            end
        end
        task.wait(0.5)
    end
end)

-- ============================================
-- PLAYER TAB (Fly + WalkSpeed + Vehicle Speed + VFly)
-- ============================================
local FlyBox = Tabs.Player:AddLeftGroupbox("QFly", "plane")
FlyBox:AddLabel("PC: Press Q to toggle fly")
FlyBox:AddButton("Toggle Fly", function() ToggleQFly() end)
FlyBox:AddSlider("FlySpeed", {
    Text = "Fly Speed",
    Default = 50,
    Min = 1,
    Max = 500,
    Rounding = 0,
    Callback = function(v) QFly.Speed = v end
})

FlyBox:AddToggle("MobileFlyBtn", {
    Text = "Mobile Fly Button",
    Default = false,
    Callback = function(v)
        if v then
            CreateMobileFlyButton()
            Library:Notify("Mobile fly button enabled! Top-right corner.", 3)
        else
            if MobileFlyBtn and MobileFlyBtn.Parent then
                MobileFlyBtn.Parent:Destroy()
                MobileFlyBtn = nil
            end
        end
    end
})

-- VEHICLE FLY SECTION - v5 NEW
local VFlyBox = Tabs.Player:AddLeftGroupbox("VFly (Vehicle Fly) v5", "car")
VFlyBox:AddLabel("Fly vehicle OR player character!")
VFlyBox:AddLabel("Auto-detects vehicle, falls back to player")
VFlyBox:AddButton("Toggle VFly", function() toggleVFly() end)
VFlyBox:AddSlider("VFlySpeed", {
    Text = "VFly Speed",
    Default = 50,
    Min = 1,
    Max = 500,
    Rounding = 0,
    Callback = function(v) VFly.Speed = v end
})

local MoveBox = Tabs.Player:AddRightGroupbox("Movement", "zap")
MoveBox:AddToggle("WalkSpd", {
    Text = "WalkSpeed",
    Default = false,
    Callback = function(v)
        local speed = 50 -- default boosted speed
        ToggleWalkSpeed(v, speed)
    end
})
MoveBox:AddSlider("WalkSpeedSlider", {
    Text = "Speed",
    Default = 50,
    Min = 16,
    Max = 200,
    Rounding = 0,
    Callback = function(v)
        if WalkSpeed.Enabled then
            ToggleWalkSpeed(false)
            ToggleWalkSpeed(true, v)
        end
    end
})

-- VEHICLE SPEED SECTION - v3 WITH MAXSPEED OVERRIDE
local VehicleBox = Tabs.Player:AddRightGroupbox("Vehicle Speed", "gauge")

VehicleBox:AddLabel("INFO: Exit & re-enter vehicle")
VehicleBox:AddLabel("after changing speed settings!")

VehicleBox:AddToggle("VehicleSpeed", {
    Text = "Vehicle Speed Boost",
    Default = false,
    Callback = function(v)
        toggleVehicleSpeed(v)
    end
})

VehicleBox:AddSlider("VehicleSpeedMult", {
    Text = "Motor Multiplier",
    Default = 1,
    Min = 1,
    Max = 20,
    Rounding = 1,
    Callback = function(v)
        VehicleSpeed.Multiplier = v
        if VehicleSpeed.Enabled then
            Library:Notify("Motor Multiplier: " .. v .. "x (Re-enter vehicle!)", 2)
        end
    end
})

VehicleBox:AddSlider("VehicleMaxSpeed", {
    Text = "MaxSpeed Override",
    Default = 0,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Callback = function(v)
        VehicleSpeed.MaxSpeedOverride = v
        if VehicleSpeed.Enabled then
            local msg = v > 0 and "MaxSpeed: " .. v .. " (Re-enter vehicle!)" or "MaxSpeed: OFF (Re-enter vehicle!)"
            Library:Notify(msg, 2)
        end
    end
})

-- ============================================
-- UI SETTINGS TAB
-- ============================================
local UISettingsLeft = Tabs.UISettings:AddLeftGroupbox("Script Management")

UISettingsLeft:AddButton({
    Text = "Fix Movement (Emergency)",
    Func = function()
        scheduleRestore()
        Library:Notify("Movement restored! Try moving now.", 3)
    end
})

UISettingsLeft:AddButton({
    Text = "Unload Script",
    Func = function()
        -- Stop all running loops/connections
        auraEnabled = false
        stopAura()
        autoSellEnabled = false
        autoBuyEnabled = false
        autoShovelEnabled = false
        if QFly.Enabled then StopQFly() end
        if VFly.Enabled then stopVFly() end
        if WalkSpeed.Enabled then ToggleWalkSpeed(false) end
        if VehicleSpeed.Enabled then toggleVehicleSpeed(false) end
        
        -- Remove aura part
        if AuraPart then
            AuraPart:Destroy()
        end
        
        -- Remove mobile button
        if MobileFlyBtn and MobileFlyBtn.Parent then
            MobileFlyBtn.Parent:Destroy()
            MobileFlyBtn = nil
        end
        
        -- Remove VFly mobile buttons
        destroyVFlyMobileButtons()
        
        -- Destroy the UI
        Library:Unload()
        
        -- Notify
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Unloaded",
            Text = "Snow Shoveling Tools has been unloaded.",
            Duration = 5
        })
    end
})

-- THEME & SAVE
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("FrostyTools")
SaveManager:SetFolder("FrostyTools/SnowShoveling")
SaveManager:BuildConfigSection(Tabs.UISettings)
ThemeManager:ApplyToTab(Tabs.UISettings)
SaveManager:LoadAutoloadConfig()

Library:Notify("Snow Shoveling Tools Loaded! (VFly v5 Added)", 4)
