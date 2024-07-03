local addonName, addon = ...

if addon.gameVersion > 20000 then return end

local fmt, tinsert, ipairs, pairs, next, type, wipe, tonumber, strlower,
      sgmatch, tsort = string.format, table.insert, ipairs, pairs, next, type,
                       wipe, tonumber, strlower, string.gmatch, table.sort

local GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo,
                                        C_Item.GetItemInfoInstant

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
    session.buyList = {}
    RXPD = session
end

local function isEmpty(list) return not list or next(list) == nil end

function addon.marketFlips.LoadList(text)
    local list = addon.marketFlips:ParseList(text)

    -- Only mandatory field is .items, the rest are optional

    if not list or isEmpty(list.items) then return end

    -- TODO if bad list imported, should the existing one be preserved?
    session.shoppingList = list
    session.buyList = {}

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

        if item.itemId then
            -- Lookup itemLink now, for AH scanData comparisons
            -- Ignore null lookups if server overloaded
            item.name, item.itemLink = GetItemInfo(item.itemId)
        end
    end

    list.displayName = list.displayName or
                           fmt('%s - %s', addonName, L('Shopping List'))

    -- TODO validate each item has a parsed itemId
    -- TODO validate expansion
    -- TODO validate faction
    -- TODO validate realm
    return list
end

function addon.marketFlips.functions.itemId(itemId)
    if type(itemId) == "string" then -- on parse
        local id = tonumber(itemId)
        local lookupId = GetItemInfoInstant(itemId)
        -- print("itemId", id, itemId, lookupId, id == lookupId)
        -- Use this to check if itemId is valid
        return id == lookupId and id
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

function addon.marketFlips:PurchaseShoppingListItem()
    -- TODO this will be UI chosen, doesn't work with async querying
    for _, data in ipairs(session.shoppingList.items) do
        print("PurchaseShoppingListItem querying for", data.name)
        addon.auctionHouse:SearchForBuyoutItem(data)

        -- addon.auctionHouse:Query({scanCallback = addon.marketFlips.scanCallback,itemData = data})

        break -- TODO just search for first one, testing without UI
    end

end

function addon.marketFlips.scanCallback(data)
    -- scanData is itemLink ID, stemming from ItemUpgrades and randomized gear
    -- Trade Goods are all static, so we use itemId
    -- TODO don't overwrite all data, keep per itemId, now that querying instead of scanning
    session.scanData = data

    -- No shopping list so nothing to compare against
    if not session.shoppingList then return end
    -- [itemLink] = { count = 123, price = 23 }
    session.buyList = {}

    print("Checking", session.shoppingList.displayName,
          "against latest scan data")
    local foundCount, maxPrice, buyoutData, priceTable
    for _, item in ipairs(session.shoppingList.items) do

        -- First, make sure there's enough within range to satisfy order
        foundCount = 0
        maxPrice = addon.Round(item.scannedPrice * (item.priceThreshold or 1.2),
                               0)

        if not (item.name and item.itemLink) then
            item.name, item.itemLink = GetItemInfo(item.itemId)
        end
        -- TODO handle if item.name lookup fails again
        session.buyList[item.name] = {}

        -- Look through scanned data to ensure count under maxPrice
        if item.itemLink and session.scanData[item.itemLink] and
            session.scanData[item.itemLink].buyoutData then
            buyoutData = session.scanData[item.itemLink].buyoutData
        else
            buyoutData = {}
        end

        -- TODO optimize sorting logic
        -- Insert keys into table, then sort table
        priceTable = {}
        for price, _ in pairs(buyoutData) do tinsert(priceTable, price) end
        tsort(priceTable)

        print("Checking for", item.itemLink, "maxPrice", maxPrice, "count",
              item.count)
        for _, price in pairs(priceTable) do
            -- Since this is marketFlips, look past what list needs
            if price < maxPrice then
                -- Use table to preserve price order
                tinsert(session.buyList[item.name],
                        {price = price, count = buyoutData[price]})

                foundCount = foundCount + item.count
            end
            -- print("price", price, "count", buyoutData[price])

        end

        if foundCount >= item.count then
            print("Found enough for", item.name)
        else
            print("Error, not enough items available for shoppingList")
        end
    end
end

function addon.marketFlips.Test()
    if isEmpty(session.shoppingList) then
        addon.marketFlips.LoadList([[#expansion classic
--#displayName Foo - Defias Pillager
#faction Horde
#realm Defias Pillager

item --Linen Cloth
  .itemId 2589
  .scannedPrice 16
  .priceThreshold 1.2
  .count 4

]])
        --[[
item --Light Leather
  .itemId 2318
  .scannedPrice 32
  .priceThreshold 1.5
  .count 2
]]
    end

    -- if isEmpty(session.scanData) then addon.auctionHouse:Scan() end

    addon.marketFlips:PurchaseShoppingListItem()
end
