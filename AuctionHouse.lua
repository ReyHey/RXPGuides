local addonName, addon = ...

if addon.gameVersion > 20000 then return end

local fmt, tinsert, ipairs, pairs, next, type, wipe, tonumber, strlower, tsort,
      sgmatch = string.format, table.insert, ipairs, pairs, next, type, wipe,
                tonumber, strlower, table.sort, string.gmatch

local CanSendAuctionQuery, QueryAuctionItems, SetSelectedAuctionItem =
    _G.CanSendAuctionQuery, _G.QueryAuctionItems, _G.SetSelectedAuctionItem
local GetNumAuctionItems, GetAuctionItemLink, GetAuctionItemInfo =
    _G.GetNumAuctionItems, _G.GetAuctionItemLink, _G.GetAuctionItemInfo

local GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo,
                                        C_Item.GetItemInfoInstant

-- TODO generalize for ItemUpgrades
local AuctionFilterButtons = {["Consumable"] = 4, ["Trade Goods"] = 5}

local L = addon.locale.Get

addon.auctionHouse = addon:NewModule("AuctionHouse", "AceEvent-3.0")
addon.auctionHouse.shoppingList = addon:NewModule("MarketFlips", "AceEvent-3.0")
addon.auctionHouse.shoppingList.functions = {}

local session = {
    isInitialized = false,

    -- TODO cache data to RXPData
    scanData = {},

    windowOpen = false,
    scanPage = 0,
    scanResults = 0,
    scanType = AuctionFilterButtons["Consumable"],

    selectedRow = nil
}

local function isEmpty(list) return not list or next(list) == nil end

function addon.auctionHouse:Setup()
    if session.isInitialized then return end

    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")

    self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")

    addon.auctionHouse.shoppingList:Setup()

    session.isInitialized = true
    RXPD2 = session

end

function addon.auctionHouse:AUCTION_HOUSE_SHOW()
    session.windowOpen = true

    addon.auctionHouse.shoppingList:CreateGui(_G.AuctionFrame)
end

function addon.auctionHouse:AUCTION_HOUSE_CLOSED()

    -- Reset session
    session.windowOpen = false
    session.sentQuery = false
    session.scanPage = 0
    session.scanResults = 0
    session.scanType = AuctionFilterButtons["Consumable"]

    if session.shoppingListUI then session.shoppingListUI:Hide() end
end

-- TODO generalize for itemUpgrades.AH use
function addon.auctionHouse:SearchForBuyoutItem(itemData)
    if not itemData.name then return end

    if not session.windowOpen then return end

    print("SearchForBuyoutItem", itemData.name)

    if _G.BrowseResetButton then _G.BrowseResetButton:Click() end

    _G.BrowseName:SetText('"' .. itemData.name .. '"')

    if itemData.itemLevel then
        _G.BrowseMinLevel:SetText(itemData.itemLevel)
        _G.BrowseMaxLevel:SetText(itemData.itemLevel)
    end

    -- Sort to make item very likely on first page
    -- sortTable, sortColumn, oppositeOrder
    _G.AuctionFrame_SetSort("list", "bid", false);
    _G.AuctionFrameTab1:Click()

    -- Pre-populates UI, so let user retry if server overloaded
    if CanSendAuctionQuery() then
        session.sentQuery = true
        _G.AuctionFrameBrowse_Search()
    end

    -- TODO scan page handling
end

function addon.auctionHouse:FindItemAuction(itemData, recursive)
    if not itemData then
        -- print("FindItemAuction error: itemData nil")
        return
    end
    if not (itemData.ItemID and itemData.ItemLink and itemData.BuyoutMoney) then
        return
    end

    local resultCount, totalAuctions = GetNumAuctionItems("list")

    if resultCount == 0 then
        print("FindItemAuction no results, recursive =", recursive)
        return
    end

    -- print("FindItemAuction", itemData.Name, resultCount)
    local itemLink, buyoutPrice, itemID

    for i = 1, resultCount do
        itemLink = GetAuctionItemLink("list", i)

        -- name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemId, hasAllInfo = GetAuctionItemInfo(type, index)
        _, _, _, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, itemID, _ =
            GetAuctionItemInfo("list", i)
        -- print("Evaluating", i, itemLink, buyoutPrice)

        if itemID == itemData.ItemID and itemLink == itemData.ItemLink and
            buyoutPrice == itemData.BuyoutMoney and false then
            SetSelectedAuctionItem("list", i)
            return i
        end

    end

    -- Rely on BrowseNextPageButton:IsEnabled() for easy pagination handling
    if _G.BrowseNextPageButton:IsEnabled() then
        -- If next button is enabled, and we're down here; then auction not found
        -- Additionally, the next page button is disabled on final page, so no need to track count
        _G.BrowseNextPageButton:Click()
        return self:FindItemAuction(itemData, true)
    else
        -- If next page not enabled, and we're here; then no results at all
        print("FindItemAuction no matches in", totalAuctions, "results")
        return nil
    end
end

-- Triggers each time the scroll panel is updated
-- Scrolling, initial population
-- Blizzard's standard auction house view overcomes this problem by reacting to AUCTION_ITEM_LIST_UPDATE and re-querying the items.
function addon.auctionHouse:AUCTION_ITEM_LIST_UPDATE()
    if not session.sentQuery then return end

    local resultCount, totalAuctions = GetNumAuctionItems("list")

    -- TODO track scan progress, (50 * scanPage) / totalAuctions
    print("AUCTION_ITEM_LIST_UPDATE", resultCount, totalAuctions,
          addon.Round((50 * session.scanPage) / totalAuctions * 100, 2))

    -- session.displayFrame.scanButton:SetText(_G.SEARCHING)

    -- TODO generalize for itemUpgrades
    if resultCount == 0 or totalAuctions == 0 then
        session.sentQuery = false
        session.scanPage = 0 -- TODO show scanPage on UI

        -- TODO generalize
        if session.scanType == AuctionFilterButtons["Consumable"] then
            session.scanType = AuctionFilterButtons["Trade Goods"]
            self:Query(session.queryData)
        else
            session.scanType = AuctionFilterButtons["Consumable"]

            if session.queryData.scanCallback then
                session.queryData['scanCallback'](session.scanData)

                -- Reset session callback
                session.queryData.scanCallback = nil
            end
            -- self:Analyze()
            -- session.displayFrame.scanButton:SetText(_G.SEARCH)
            -- self:DisplayEmbeddedResults()
        end

        return
    end

    local itemLink
    local name, texture, count, level, buyoutPrice, itemID

    for i = 1, resultCount do
        itemLink = GetAuctionItemLink("list", i)

        -- name, texture, count, quality, canUse, level, levelColHeader, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemId, hasAllInfo = GetAuctionItemInfo(type, index)
        name, texture, count, _, _, level, _, _, _, buyoutPrice, _, _, _, _, _, _, itemID, _ =
            GetAuctionItemInfo("list", i)

        if session.scanData[itemLink] then
            -- Track lowestPrice separately
            -- buyoutPrice == 0 when bid-only
            if buyoutPrice > 0 and buyoutPrice <
                session.scanData[itemLink].lowestPrice then
                session.scanData[itemLink].lowestPrice = buyoutPrice
            end

            -- Track historical data
            if session.scanData[itemLink].buyoutData[buyoutPrice] then
                -- Keep track of count for same price
                session.scanData[itemLink].buyoutData[buyoutPrice] =
                    session.scanData[itemLink].buyoutData[buyoutPrice] + count
            else
                session.scanData[itemLink].buyoutData[buyoutPrice] = count
            end
        elseif buyoutPrice > 0 then -- bid-only is buyout = 0
            session.scanData[itemLink] = {
                name = name,
                lowestPrice = buyoutPrice,
                itemID = itemID,
                level = level,
                scanType = session.scanType, -- TODO propagate scanType for proper filters
                itemIcon = texture,
                buyoutData = {
                    [buyoutPrice] = count -- Count for exactly this price
                }
            }
        end

        -- print("scan", itemLink, itemID, hasAllInfo, buyoutPrice)
    end

    session.sentQuery = false

    session.scanPage = session.scanPage + 1

    session.scanResults = session.scanResults + resultCount

    self:Query(session.queryData)
end

-- Async processing with AUCTION_ITEM_LIST_UPDATE actually handling the analysis
function addon.auctionHouse:Query(queryData)
    queryData = queryData or {} -- {callback, itemData}
    -- Prevent double calls
    if session.sentQuery then return end
    if not AuctionCategories then return end -- AH frame isn't loaded yet

    RXPD3 = queryData
    if not queryData.itemData then
        print("Query error: itemData nil")
        return
    end
    local item = queryData.itemData

    if not item.name then return end
    print("Query", item.name)

    -- Track callback between calls
    if not session.scanCallback then
        session.scanCallback = queryData.callback
    end

    -- TODO use better queueing
    -- TODO abort on multiple retries
    if not CanSendAuctionQuery() then
        -- print("addon.auctionHouse:Search() - queued", session.scanPage, session.scanType)

        C_Timer.After(0.35, function() self:Search() end)
        return
    end
    -- print("addon.auctionHouse:Search()", session.scanType, session.scanPage)

    session.sentQuery = true

    -- text, minLevel, maxLevel, page, usable, rarity, getAll, exactMatch, filterData
    QueryAuctionItems(fmt('"%s"', item.name), nil, nil, session.scanPage, true,
                      Enum.ItemQuality.Standard, false, false,
                      AuctionCategories[session.scanType].filters)
end

function addon.auctionHouse.shoppingList:Setup()
    if not addon.settings.profile.enableShoppingList or
        not addon.settings.profile.enableTips then return end

    if not addon.settings.profile.enableBetaFeatures then return end

    session.shoppingList = {}
    session.buyList = {}
    session.clickedListRow = nil
    RXPD = session

end

local function getColorizedName(itemLink, itemName)
    local quality = C_Item.GetItemQualityByID(itemLink)
    local h = ITEM_QUALITY_COLORS[quality].hex

    return h .. itemName .. '|r'
end

local function Initializer(row, data)
    -- Data references
    row.itemData = data

    row.itemLink = data.itemLink
    -- Frame elements
    row.Name:SetText(getColorizedName(data.itemLink, data.name))
    -- TODO count nil for MarketFlips, just buy as much as you want/can/care
    row.ItemFrame:SetNormalTexture(data.itemTexture)
    row.Status:SetText(fmt("(??/%d)", data.count))

    row:Show()

end

-- Executed when AuctionFrame opens
-- TODO hide if SideDressUpFrame pops up
function addon.auctionHouse.shoppingList:CreateGui(attachment)
    if not addon.settings.profile.enableShoppingList then return end
    if session.shoppingListUI then return end
    if not attachment then return end

    session.shoppingListUI = _G["RXP_IU_AH_ShoppingList_Frame"]
    if not session.shoppingListUI then return end

    session.shoppingListUI:SetParent(attachment)
    session.shoppingListUI:SetPoint("TOPLEFT", attachment, "TOPRIGHT", 0, -30)
    session.shoppingListUI:SetHeight(_G.AuctionFrame:GetHeight() * 0.9)

    -- fmt("%s - %s", addon.title, L('Shopping List'))
    _G.RXP_IU_AH_ShoppingList_Title:SetText(L('Shopping List'))

    -- session.shoppingListUI.ScrollBox.ScrollBar:SetHideIfUnscrollable(true)

    local DataProvider = CreateDataProvider()
    local ScrollView = CreateScrollBoxListLinearView()
    ScrollView:SetDataProvider(DataProvider)
    session.shoppingListUI.DataProvider = DataProvider

    ScrollUtil.InitScrollBoxListWithScrollBar(session.shoppingListUI.ScrollBox,
                                              session.shoppingListUI.ScrollBox
                                                  .ScrollBar, ScrollView)

    ScrollView:SetElementInitializer("RXP_IU_AH_ShoppingList_ItemRow",
                                     Initializer)

    -- Triggers when clicking on tabs or using _G.AuctionFrameTab1:Click()
    hooksecurefunc(_G, "AuctionFrameTab_OnClick", function(button, ...)
        -- No shopping list, so don't do anything
        if isEmpty(session.shoppingList) then return end

        -- Show sidebar only if RXPGuides tab selected
        if button.isRXP and session.shoppingListUI then
            if _G.SideDressUpFrame and _G.SideDressUpFrame:IsShown() then
                _G.SideDressUpFrame:Hide()
            end
            session.shoppingListUI:Show()
        else
            -- If selected row, then likely purchasing an item so don't hide
            if not session.clickedListRow then
                session.shoppingListUI:Hide()
            end

        end
    end)

    if _G.SideDressUpFrame then
        -- Hide Shopping List if dressup sidebar appears
        hooksecurefunc(_G.SideDressUpFrame, "Show", function()
            if session.shoppingListUI:IsShown() then
                session.shoppingListUI:Hide()
            end
        end)
    end

    addon.auctionHouse.shoppingList:DisplayList()
end

function addon.auctionHouse.shoppingList.RowOnEnter(row)
    if session.clickedListRow == row then return end
end

function addon.auctionHouse.shoppingList.RowOnLeave(row)
    if session.clickedListRow == row then return end
end

function addon.auctionHouse.shoppingList.RowOnClick(this)
    if session.clickedListRow == this then
        session.clickedListRow = nil
    else
        session.clickedListRow = this

        addon.auctionHouse:SearchForBuyoutItem(this.itemData)
    end
end

function addon.auctionHouse.shoppingList:DisplayList()
    if not session.shoppingListUI then return end

    session.shoppingListUI.DataProvider:Flush()

    if not session.shoppingList.items then return end

    for _, data in ipairs(session.shoppingList.items) do
        session.shoppingListUI.DataProvider:Insert(data)
    end
end

function addon.auctionHouse.shoppingList.LoadList(text)
    local list = addon.auctionHouse.shoppingList:ParseList(text)

    -- Only mandatory field is .items, the rest are optional

    if not list or isEmpty(list.items) then return end

    -- TODO if bad list imported, should the existing one be preserved?
    session.shoppingList = list
    session.buyList = {}

    addon.auctionHouse.shoppingList:DisplayList()

    return list
end

function addon.auctionHouse.shoppingList:ParseList(text)
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
            item.name, item.itemLink, _, _, _, _, _, _, _, item.itemTexture =
                GetItemInfo(item.itemId)
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

function addon.auctionHouse.shoppingList.functions.itemId(itemId)
    if type(itemId) == "string" then -- on parse
        local id = tonumber(itemId)
        local lookupId = GetItemInfoInstant(itemId)
        -- print("itemId", id, itemId, lookupId, id == lookupId)
        -- Use this to check if itemId is valid
        return id == lookupId and id
    end

    return true
end

-- TODO also scan current bags and count those against .count
-- TODO see if we can query bank inventory remotely
function addon.auctionHouse.shoppingList.functions.number(number)
    if type(number) == "string" then -- on parse
        local n = tonumber(number)

        if n > 0 then return n end
    end

    return true
end

addon.auctionHouse.shoppingList.functions.scannedPrice = addon.auctionHouse
                                                             .shoppingList
                                                             .functions.number
addon.auctionHouse.shoppingList.functions.priceThreshold = addon.auctionHouse
                                                               .shoppingList
                                                               .functions.number
addon.auctionHouse.shoppingList.functions.count = addon.auctionHouse
                                                      .shoppingList.functions
                                                      .number

function addon.auctionHouse.shoppingList.scanCallback(callbackData)
    -- scanData is itemLink ID, stemming from ItemUpgrades and randomized gear
    -- Trade Goods are all static, so we use itemId

    -- TODO cache callbackData?
    -- No shopping list so nothing to compare against
    if not session.shoppingList then return end
    -- [itemLink] = { count = 123, price = 23 }
    session.buyList = {}

    print("Checking", session.shoppingList.displayName,
          "against latest scan data")
    local foundCount, maxPrice, buyoutData, priceTable
    for _, item in ipairs(session.shoppingList.items) do

        -- First, make sure there's enough within range to satisfy order
        -- TODO handle .count == nil for Market Flips
        foundCount = 0
        maxPrice = addon.Round(item.scannedPrice * (item.priceThreshold or 1.2),
                               0)

        if not (item.name and item.itemLink) then
            -- itemName, itemLink, _, _, _, _, _, _, _, itemTexture,
            item.name, item.itemLink, _, _, _, _, _, _, _, item.itemTexture =
                GetItemInfo(item.itemId)
        end
        -- TODO handle if item.name lookup fails again
        session.buyList[item.name] = {}

        -- Look through scanned data to ensure count under maxPrice
        if item.itemLink and callbackData[item.itemLink] and
            callbackData[item.itemLink].buyoutData then
            buyoutData = callbackData[item.itemLink].buyoutData
        else
            buyoutData = {}
        end

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

function addon.auctionHouse.shoppingList.Test()
    if isEmpty(session.shoppingList) then
        addon.auctionHouse.shoppingList.LoadList(
            [[#expansion classic
--#displayName Foo - Defias Pillager
#faction Horde
#realm Defias Pillager

item --Linen Cloth
  .itemId 2589
  .scannedPrice 16
  .priceThreshold 1.2
  .count 12

item --Light Leather
  .itemId 2318
  .scannedPrice 32
  .priceThreshold 1.5
  .count 23

item --Rough Stone
  .itemId 2835
  .scannedPrice 4
  .priceThreshold 1.5
  .count 14

item --Strange Dust
  .itemId 10940
  .scannedPrice 100
  .priceThreshold 1.3
  .count 9

item --Copper Ore
  .itemId 2770
  .scannedPrice 600
  .priceThreshold 1.3
  .count 3
]])
    end

    addon.auctionHouse.shoppingList:DisplayList()
end
