local addonName, addon = ...

if addon.gameVersion > 20000 then return end

local fmt, tinsert, ipairs, pairs, next, type, wipe, tonumber, strlower =
    string.format, table.insert, ipairs, pairs, next, type, wipe, tonumber,
    strlower

local CanSendAuctionQuery, QueryAuctionItems, SetSelectedAuctionItem =
    _G.CanSendAuctionQuery, _G.QueryAuctionItems, _G.SetSelectedAuctionItem
local GetNumAuctionItems, GetAuctionItemLink, GetAuctionItemInfo =
    _G.GetNumAuctionItems, _G.GetAuctionItemLink, _G.GetAuctionItemInfo

local AuctionFilterButtons = {["Consumable"] = 4, ["Trade Goods"] = 5}

addon.auctionHouse = addon:NewModule("AuctionHouse", "AceEvent-3.0")

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

function addon.auctionHouse:Setup()
    if session.isInitialized then return end

    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED")

    self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")

    session.isInitialized = true
    RXPD2 = session
end

function addon.auctionHouse:AUCTION_HOUSE_SHOW()
    session.windowOpen = true

    -- self:CreateEmbeddedGui()
end

function addon.auctionHouse:AUCTION_HOUSE_CLOSED()

    -- Reset session
    session.windowOpen = false
    session.sentQuery = false
    session.scanPage = 0
    session.scanResults = 0
    session.scanType = AuctionFilterButtons["Consumable"]
end

-- Helper function for scanning.xml RXP_IU_AH_BuyButton:OnClick
function addon.auctionHouse:SearchForSelectedItem()
    return self:SearchForBuyoutItem(session.selectedRow.nodeData)
end

local function getNameFromLink(itemLink)
    return string.match(itemLink, "h%[(.*)%]|h")
end

-- TODO generalize for itemUpgrades.AH use
function addon.auctionHouse:SearchForBuyoutItem(itemData)
    if not itemData.name then return end

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

    -- TODO handle Pagination, sorted by cheapest so unlikely
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
-- TODO revert to scan functionality
function addon.auctionHouse:Query(queryData)
    queryData = queryData or {} -- {callback, itemData}
    -- Prevent double calls
    if session.sentQuery then return end
    if not AuctionCategories then return end -- AH frame isn't loaded yet

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

        -- TODO check if BrowseSearchButton is re-enabled
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
