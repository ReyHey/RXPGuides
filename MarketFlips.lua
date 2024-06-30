local addonName, addon = ...

if addon.gameVersion > 20000 then return end

local fmt, tinsert, ipairs, pairs, next, type, wipe, tonumber, strlower, sgmatch =
    string.format, table.insert, ipairs, pairs, next, type, wipe, tonumber,
    strlower, string.gmatch

local GetItemInfoInstant = C_Item.GetItemInfoInstant

local L = addon.locale.Get

addon.marketFlips = addon:NewModule("MarketFlips", "AceEvent-3.0")
addon.marketFlips.functions = {}

local session = {shoppingList = {}}

function addon.marketFlips:Setup()
    if not addon.settings.profile.enableMarketFlips or
        not addon.settings.profile.enableTips then return end

    if not addon.settings.profile.enableBetaFeatures then return end

    -- Requires AH support
    if not addon.auctionHouse then return end

    addon.auctionHouse:Setup()
    session.shoppingList = {}
    RXPD = session
end

function addon.marketFlips.LoadList(text)
    local list = addon.marketFlips:ParseList(text)

    -- Only mandatory field is .items, the rest are optional

    if not list or not list.items or next(list.items) == nil then return end

    -- TODO if bad list imported, should the existing one be preserved?
    session.shoppingList = list

    return list
end

function addon.marketFlips:ParseList(text)
    if not text then return end

    local list = {items = {}}

    local item = {}
    local linenumber = 0
    local currentStep = 0
    local discardReturn

    -- Loop over each line in guide
    for line in sgmatch(text, "[^\n\r]+") do
        line = line:gsub("^%s+", "")
        line = line:gsub("%s+$", "")
        linenumber = linenumber + 1

        if line:sub(1, 4) == "item" then
            currentStep = currentStep + 1
            list.items[currentStep] = {}

            item = list.items[currentStep]
            -- print("Starting new step", currentStep)

        elseif currentStep > 0 then -- Parse metadata tags first
            -- Unlike leveling, farming, and talent guides, .Foo are properties here
            -- Parse function calls
            discardReturn = line:gsub("^%.(%S+)%s*(.*)",
                                      function(command, lineArgs)
                -- print("Processing guide command", command, "with (", lineArgs, ")")
                if self.functions[command] then
                    local element = self.functions[command](lineArgs)

                    if not element then return end
                    item[command] = element
                else
                    addon.error(L("Error parsing guide") .. " " ..
                                    (item.displayName or 'Unknown') ..
                                    ": Invalid function call (." .. command ..
                                    ")\n" .. line)
                end
            end)

        elseif line ~= "" or currentStep > 0 then
            -- Parse metadata tags
            discardReturn = line:gsub("^#(%S+)%s*(.*)", function(tag, value)
                -- print("Parsing tag at", linenumber, tag, value)
                -- Set metadata without overwriting
                if tag and tag ~= "" and not list[tag] then
                    list[tag] = value
                end
            end)

        end
    end

    list.displayName = list.displayName or
                           fmt('%s - %s', addonName, L('Shopping List'))

    -- TODO validate expansion
    -- TODO validate faction
    -- TODO validate realm
    return list
end

function addon.marketFlips.functions.itemId(itemId)
    if type(itemId) == "string" then -- on parse
        local id = tonumber(itemId)
        local lookup = GetItemInfoInstant(itemId)

        -- Use this to check if itemId is valid
        if id == lookup then return id end
    end

    return true
end

function addon.marketFlips.functions.number(number)
    if type(number) == "string" then -- on parse
        local n = tonumber(number)

        if n > 0 then return n end
    end

    return true
end

addon.marketFlips.functions.scannedPrice = addon.marketFlips.functions.number
addon.marketFlips.functions.priceThreshold = addon.marketFlips.functions.number
addon.marketFlips.functions.count = addon.marketFlips.functions.number

function addon.marketFlips.scanCallback(data)
    print("marketFlips scanCallback")
    RXPD3 = data

    -- TODO process scanData, looking for sequential increasing costs for items in current shopping list
end

function addon.marketFlips.Test()
    local l = {}
    l.list = addon.marketFlips.LoadList([[#expansion classic
--#displayName Foo - Defias Pillager
#faction Horde
#realm Defias Pillager

item
  .itemId 123456
  .scannedPrice 123
  .priceThreshold 1.1
  .count 60
item
  .itemId 23456
  .scannedPrice 234
  .priceThreshold 2.3
  .count 9
]])

    l.scan = addon.auctionHouse:Scan(addon.marketFlips.scanCallback)
end
