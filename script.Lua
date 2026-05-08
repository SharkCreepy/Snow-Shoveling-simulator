-- ============================================
-- Snow Shoveling Simulator - COMPACT VERSION
-- Fixes: No TileSelector require, uses direct logic instead
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
  
  -- Remove all non-numeric chars except / and . and K/M
  text = text:gsub(",", "")  -- remove commas
  
  -- Try pattern: number / number (handles spaces, K, M)
  local currentStr, maxStr = text:match("([%d%.%s]+)%s*/%s*([%d%.%s]+)")
  
  if currentStr and maxStr then
      -- Trim spaces
      currentStr = currentStr:gsub("%s", "")
      maxStr = maxStr:gsub("%s", "")
      
      -- Handle K/M suffixes
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
  
  -- Fallback: just grab all numbers
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

local function unfreeze()
  local hrp = getHRP()
  local hum = getHumanoid()
  if hrp then hrp.Anchored = false end
  if hum then
      hum.WalkSpeed = 16
      hum.JumpPower = 50
      hum.PlatformStand = false
      hum.Sit = false
  end
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
  unfreeze()
  return success
end

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
      if mod then require(mod)(player, data) else Network:FireServer(interactName, data.Name) end
  end)
  task.wait(0.5)
  unfreeze()
  return true
end

local function openBackpackStore() return openShop(backpackStorePart) end
local function openToolsStore() return openShop(toolsStorePart) end

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
      -- Handle K/M suffixes and commas for large money numbers
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
  if not s then closeShop() unfreeze() return false, "No folder" end
  local targetItem = nil
  for _, item in ipairs(folder:GetChildren()) do
      local info = item:FindFirstChild("Info")
      if info then
          local n = info:FindFirstChild("ItemName")
          if n and n.Value == itemName then targetItem = item break end
      end
  end
  if not targetItem then closeShop() unfreeze() return false, "Not found" end
  local shopInfo = nil
  pcall(function() shopInfo = GetShopItemInfo(targetItem) end)
  if shopInfo and (shopInfo.GamePass or shopInfo.DevProduct) then closeShop() unfreeze() return false, "Robux" end
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
  unfreeze()
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
-- UI SETTINGS TAB
-- ============================================
local UISettingsLeft = Tabs.UISettings:AddLeftGroupbox("Script Management")

UISettingsLeft:AddButton({
  Text = "Unload Script",
  Func = function()
      -- Stop all running loops/connections
      auraEnabled = false
      stopAura()
      autoSellEnabled = false
      autoBuyEnabled = false
      autoShovelEnabled = false
      
      -- Remove aura part
      if AuraPart then
          AuraPart:Destroy()
      end
      
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

Library:Notify("Snow Shoveling Tools Loaded!", 4)
