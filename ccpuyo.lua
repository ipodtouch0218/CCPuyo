----game variables
local puyoTypes = {"blue","red","green","yellow","purple"}
local puyoInfo = {["blue"] = {["color"] = colors.blue, ["symbol"] = "B"},
                  ["red"] = {["color"] = colors.red, ["symbol"] = "R"},
                  ["green"] = {["color"] = colors.green, ["symbol"] = "G"},
                  ["yellow"] = {["color"] = colors.yellow, ["symbol"] = "Y"},
                  ["purple"] = {["color"] = colors.purple, ["symbol"] = "P"},
                  ["garbage"] = {["color"] = colors.lightGray, ["symbol"] = "."}}
local gameSpeed = (1.2)*20 --1.2 seconds between the puyo dropping and 20 tps
local queuedPuyos = {}
local isPaused = false
local gameover = false
local puyosDropped = 0
local exitgame = false

--multiplayer status variables
local opponentBoard --board of the opponent
local clientID --id of the opponent
local isMultiplayer = false --disallows pausing and displays the other board
local protocolVersion = "1a" --DO NOT CHANGE OR MULTIPLAYER WILL NOT WORK 

--board variables
local puyoBoard = {} --represents the puyo board, 6x12 by default.
local boardWidth = 6 
local boardHeight = 12

---display variables
local tempOffX, tempOffY = term.getSize()
local boardOffset = {["x"] = (tempOffX-2-boardWidth)/2, ["y"] = (tempOffY-2-boardHeight)/2}
tempOffX = nil  tempOffY = nil

---dropper variables and functions
local dropperTimer = gameSpeed
local landingTimer = 10

local function dropperGetRotOffset(dropper)
    if (dropper.rotation == 0) then return 0,1 end
    if (dropper.rotation == 1) then return 1,0 end
    if (dropper.rotation == 2) then return 0,-1 end
    if (dropper.rotation == 3) then return -1,0 end
end

local function dropperIntersectsBoard(board, dropper)
    
    local loc = dropper.x..";"..dropper.y --first puyo loc
    local rotX, rotY = dropperGetRotOffset(dropper)
    rotX = dropper.x + rotX
    rotY = dropper.y + rotY
    
    --if the dropper intersects the border of the board itself.
    if (dropper.x < 1 or rotX < 1) then return true end
    if (dropper.x > boardWidth or rotX > boardWidth) then return true end
    --if (dropper.y < 1 or rotY < 1) then return true end --IGNORE ROOF.
    if (dropper.y > boardHeight or rotY > boardHeight) then return true end
    
    --if the dropper intersects puyos on the board
    return not ((board.puyos[loc] == nil) and (board.puyos[rotX..";"..rotY] == nil)) 
end

local function dropperMoveRight(dropper) 
    dropper["x"] = dropper.x + 1 
    if (dropperIntersectsBoard(puyoBoard, dropper)) then 
        dropper["x"] = dropper.x - 1
    end
end
local function dropperMoveLeft(dropper) 
    dropper["x"] = dropper.x - 1 
    if (dropperIntersectsBoard(puyoBoard, dropper)) then
        dropper["x"] = dropper.x + 1
    end
end
local function dropperRotateRight(dropper) 
    dropper["rotation"] = (dropper.rotation - 1)%4
    
    if (dropperIntersectsBoard(puyoBoard, dropper)) then 
        --[[newly rotated intersects board
        -move the opposite of the offset. 
        -   (moves up if intersects from bottom)
        -   (moves right if intersects from left, etc)
        --]]
        local xRot, yRot = dropperGetRotOffset(dropper)
        dropper["x"] = dropper.x - xRot
        dropper["y"] = dropper.y - yRot
        
        if (dropperIntersectsBoard(puyoBoard, dropper)) then --still intersects, move back
            dropper["x"] = dropper.x + xRot
            dropper["y"] = dropper.y + yRot
            --undo rotation, no space
            dropper["rotation"] = (dropper.rotation + 1)%4 
        end
    end
end
local function dropperQuickDrop(dropper)
    dropperTimer = 1
end

local localTime = 20

----API FUNCTIONS----
local function openRednet()
    for _,side in ipairs(rs.getSides()) do
        if (peripheral.isPresent(side)) and (peripheral.getType(side) == "modem") then
            rednet.open(side) 
            return side
        end
    end
end

local function drawStringAt(x,y,char,fg,bg)
    term.setCursorPos(x, y) 
    if (bg ~= nil) then term.setBackgroundColor(bg) end
    if (fg ~= nil) then term.setTextColor(fg) end
    print(char)
end

local function drawStringCentered(y,str,fg,bg,clearline)
    local x = (term.getSize()-string.len(str))/2
    if (bg ~= nil) then term.setBackgroundColor(bg) end
    if (fg ~= nil) then term.setTextColor(fg) end
    term.setCursorPos(x,y)
    if (clearline) then term.clearLine() end
    print(str)
end

local function tableLength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

local function tableHasValue(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

----GAME FUNCTIONS----
local function getRandomPuyoPair()
    local mainPuyo = puyoTypes[math.random(1,5)]
    local otherPuyo = puyoTypes[math.random(1,5)]
    
    return mainPuyo, otherPuyo
end


local function getPuyoChains(board, chain, startX, startY, puyoType)
    for x=-1,1 do
        for y=-1,1 do
            if not (x ~= 0 and y ~= 0) then --remove the corners
                if not (x == 0 and y == 0) then --remove the center
                    local toCheckX = startX+x
                    local toCheckY = startY+y
                    local toCheckLocation = toCheckX..";"..toCheckY
                    
                    if not (tableHasValue(chain, toCheckLocation)) then
                        if (puyoType == board.puyos[toCheckLocation]) then
                            table.insert(chain, toCheckLocation) 
                            getPuyoChains(board, chain, toCheckX, toCheckY, puyoType)
                        elseif (board.puyos[toCheckLocation] == "garbage") then
                            table.insert(chain, toCheckLocation)
                        end
                    end                    
                end
            end
        end
    end
end

local function getMatchingPuyos(board)
    local checked = {}
    local matching = {}
    for x=1,boardWidth do
        for y=1,boardHeight do
            local location = x..";"..y
            if (board.puyos[location] ~= nil) then --if the location is a puyo or nil
                if not (tableHasValue(checked,location)) then --if the location was checked already
                    --this puyo was not checked... check for other surrounding puyos
                    local chain = {} --new table, stores puyos in the chain to this one
                    getPuyoChains(board, chain, x, y, board.puyos[location])
                    
                    local length = 0
                    for k,v in pairs(chain) do
                        if (board.puyos[v] ~= "garbage") then 
                            length = length + 1
                        end
                        table.insert(checked, v)
                    end
                    
                    if (length >= 4) then
                        table.insert(matching,chain)
                    end
                end
            else
                table.insert(checked,location) --if nil, we already checked here.
            end
        end 
    end
    return matching
end

local function dropFloatingPuyos(board)
    local returnval = false --if any puyo fell: return true
    for x=1,boardWidth do
        local supportedBy = boardHeight+1
        for yTmp=0,boardHeight do 
            local y = (boardHeight)-yTmp 
            local stringLoc = x..";"..y
            
            if (board.puyos[stringLoc] ~= nil) then
                supportedBy = supportedBy-1
                if (y ~= supportedBy) then --the support ISNT under current puyo
                    board.puyos[x..";"..supportedBy] = board.puyos[stringLoc]
                    board.puyos[stringLoc] = nil
                    returnval = true
                end
            end
        end
    end
    return returnval
end


local function renderBoard(board)
    term.setBackgroundColor(colors.black)
    term.clear()
    
    --render individual puyos
    for x=1,boardWidth do
        for y=1,boardHeight do
            local loc = x..";"..y
            
            if (board.puyos[loc] ~= nil) then
                local info = puyoInfo[board.puyos[loc]]
                if (term.isColor()) then
                    paintutils.drawPixel(x+boardOffset.x,y+boardOffset.y,info.color)
                    --drawStringAt(x+boardOffset.x,y+boardOffset.y,"o",info.color,colors.black)
                else
                    if (board.puyos[loc] == "garbage") then
                        drawStringAt(x+boardOffset.x,y+boardOffset.y,info.symbol,colors.white,colors.gray)
                    else
                        drawStringAt(x+boardOffset.x,y+boardOffset.y,info.symbol,colors.lightGray,colors.black)
                    end
                end
            end
        end
    end
    
    
    --render outline of the board
    paintutils.drawBox(boardOffset.x, boardOffset.y, boardOffset.x+boardWidth+1, 
        boardOffset.y+boardHeight+1, colors.white)
        
    --the next two puyos
    local nextX = boardOffset.x+boardWidth+1
    local nextY = boardOffset.y+2
    paintutils.drawBox(nextX, nextY, nextX+5, nextY+5)
    drawStringAt(nextX+1, nextY+1, "N", colors.white, colors.black)
    drawStringAt(nextX+1, nextY+2, "E", colors.white, colors.black)
    drawStringAt(nextX+1, nextY+3, "X", colors.white, colors.black)
    drawStringAt(nextX+1, nextY+4, "T", colors.white, colors.black)
    
    if (queuedPuyos[1] ~= nil) then
        if (term.isColor()) then
            paintutils.drawPixel(nextX+3, nextY+2, puyoInfo[queuedPuyos[1].other].color)
            paintutils.drawPixel(nextX+3, nextY+3, puyoInfo[queuedPuyos[1].main].color) 
        else
            drawStringAt(nextX+3, nextY+2, puyoInfo[queuedPuyos[1].other].symbol, 
                colors.lightGray, colors.black)
            drawStringAt(nextX+3, nextY+3, puyoInfo[queuedPuyos[1].main].symbol,
                colors.lightGray, colors.black)
        end
    end
    
    --render score
    drawStringAt(boardOffset.x,boardOffset.y+boardHeight+2,"Score: " .. board.score,colors.white,colors.black)
    
    --render queued garbage
    if (board.garbage > 0) then
        local tempGarbage = board.garbage
        local garbageString = ""
        
        while (tempGarbage > 0) do
            if (tempGarbage > boardWidth*5) then
                garbageString = garbageString.."O"
                tempGarbage = tempGarbage - (boardWidth*5)
            elseif (tempGarbage > boardWidth) then
                garbageString = "o"..garbageString
                tempGarbage = tempGarbage - (boardWidth)
            else
                garbageString = "."..garbageString
                tempGarbage = tempGarbage - 1
            end
        end
        drawStringAt(boardOffset.x,boardOffset.y-1,garbageString,colors.lightGray,colors.black)
    end
    
    --render garbage timer
    if not (isMultiplayer) then
        drawStringAt(boardOffset.x+boardWidth+2,boardOffset.y+10,tostring(math.ciel(puyoBoard.garbagetimer)),colors.white,colors.black)
    end
end

local function renderDropper(dropper)
    if not (dropper.disabled) and (dropper.main ~= nil) then
        local mainPuyo = puyoInfo[dropper.main]
        local otherPuyo = puyoInfo[dropper.other]
            
        local drawX = boardOffset.x + dropper.x
        local drawY = boardOffset.y + dropper.y
     
        if (dropper.lastLocs ~= nil) then
            for _,loc in pairs(dropper.lastLocs) do
                paintutils.drawPixel(loc.x, loc.y, colors.black)
            end
        end
        
        local xRotOffset, yRotOffset = dropperGetRotOffset(dropper)
        if (term.isColor()) then
            paintutils.drawPixel(drawX, drawY, mainPuyo.color)
            paintutils.drawPixel(drawX + xRotOffset, drawY + yRotOffset, otherPuyo.color) 
        else
            drawStringAt(drawX, drawY, mainPuyo.symbol, colors.lightGray, colors.black)
            drawStringAt(drawX+xRotOffset, drawY+yRotOffset, otherPuyo.symbol, colors.lightGray, colors.black)
        end
        
        dropper.lastLocs = {{["x"] = drawX, ["y"] = drawY}, {["x"] = drawX+xRotOffset, ["y"] = drawY+yRotOffset}}
    end
    
    paintutils.drawBox(boardOffset.x, boardOffset.y, boardOffset.x+boardWidth+1, 
    boardOffset.y+boardHeight+1, colors.white)
end

local function queuePuyos()
    local new1, new2 = getRandomPuyoPair()
    table.insert(queuedPuyos, {["main"] = new1, ["other"] = new2})
    --TODO: send rednet message 
end

local function resetDropper(board)
    while (tableLength(queuedPuyos) < 2) do
        queuePuyos()
    end
    local pulled = queuedPuyos[1]
    
    if (board.dropper == nil) then board.dropper = {} end
    
    board.dropper.main = pulled.main
    board.dropper.other = pulled.other
    board.dropper.x = 3
    board.dropper.y = 1
    board.dropper.rotation = 2
    board.dropper.disabled = true
    board.dropper.lastLocs = nil
    
    table.remove(queuedPuyos,1)
end

local function resetBoard(isPlayerBoard)
    local board = {}
    
    board.dropper = {}
    board.puyos = {}
    board.garbage = 0
    board.score = 0
    
    if (isPlayerBoard) then
        board.dropper.controls = {[keys.right] = dropperMoveRight, 
    [keys.left] = dropperMoveLeft, [keys.up] = dropperRotateRight,
    [keys.down] = dropperQuickDrop}
    end
    
    return board
end

local function sendGarbage(board, amount)
    if (amount == 0) then
        return
    end
    
    if (board.garbage < amount) then
        amount = amount - board.garbage
        board.garbage = 0
        
        --rednet.send(clientID, )
        
        --[[todo: 
        if (isMultiplayer) then
            local msg = {["message"] = "board.sendgarbage", ["amount"] = amount}
        
            rednet.send(clientID, textutils.serialize(msg))
        end
        ]]--
    else -- >=
        board.garbage = board.garbage - amount
        
        --[[
        if (isMultiplayer) then
            local msg = {["message"] = "board.setgarbage", ["amount"] = amount}
        ]]--
    end
end

local function dropGarbage(board)
    if (board.garbage <= 0) then
        return
    end
    
    if (board.garbage > (boardWidth)) then
        local counter = 0
        while (board.garbage > (boardWidth)) and (counter < 5) do
            counter = counter + 1 
            for x=1,boardWidth do
                if (board.puyos[x..";1"] == nil) then
                    board.puyos[x..";1"] = "garbage"
                    board.garbage = board.garbage - 1
                end 
            end
            dropFloatingPuyos(board)
        end
    else
        local possibleLocs = {1,2,3,4,5,6}
        for _=1,boardWidth-board.garbage do
            table.remove(possibleLocs, math.random(tableLength(possibleLocs)))
        end
        for x in ipairs(possibleLocs) do
            if (board.puyos[x..";1"] == nil) then
                board.puyos[x..";1"] = "garbage"
                board.garbage = board.garbage - 1
            end
        end
    end
        
    dropFloatingPuyos(board)
end

--board dropping puyos, making matches.
local function simulateBoard(board)
    
    dropFloatingPuyos(board) --drop puyos before starting matches
    
    local scoreMultiplier = 1
    local continueDropping = true
    
    while (continueDropping) do
        renderBoard(puyoBoard)
        sleep(0.2)
        local matches = getMatchingPuyos(board)
        
        for _,chain in pairs(matches) do
            local chainScore = 0
            for __,location in pairs(chain) do
                if (board.puyos[location] ~= "garbage") then
                    chainScore = chainScore + 10
                end
                board.puyos[location] = nil
            end
            board.score = board.score + (chainScore*scoreMultiplier)
            renderBoard(puyoBoard)
            sleep(0.2)
        end
        
        scoreMultiplier = scoreMultiplier + 1
        continueDropping = dropFloatingPuyos(board)
    end
    
    renderBoard(puyoBoard)
end
    
    
--the dropper landing on the main board
local function onDropperLanding()
    local prevScore = puyoBoard.score
    local scoreMultiplier = 0
    local drop = puyoBoard.dropper
    
    drop.disabled = true
    local x = drop.x
    local y = drop.y
    puyoBoard.puyos[x..";"..y] = drop.main
    local xRot, yRot = dropperGetRotOffset(drop)
    puyoBoard.puyos[(x+xRot)..";"..(y+yRot)] = drop.other
    
    resetDropper(puyoBoard)
    simulateBoard(puyoBoard)
    
    sendGarbage(puyoBoard, (puyoBoard.score - prevScore)/40)
    
    if (isMultiplayer) then
        dropGarbage(puyoBoard)
        --TODO: send packets
    else
        puyoBoard.garbagetimer = puyoBoard.garbagetimer - 1
        if (puyoBoard.garbagetimer <= 0) then
            dropGarbage(puyoBoard)
            puyoBoard.garbagetimer = gameSpeed
            puyoBoard.garbage = (1.4-(gameSpeed/20))*2
        end
    end
    
    puyosDropped = puyosDropped + 1
    
    if (puyoBoard.puyos["3;1"] ~= nil) then
        gameover = true
        if (isMultiplayer) then
        end
    end
    
    renderBoard(puyoBoard)
end

--< REDNET MESSAGE HANDLER >--
local messageTable = {
    ["board.setpuyos"] = nil,
    ["board.simulate"] = nil}

--< MAIN PROGRAM LOOPS >--
--check for keys will halt, hence why we have to use parallel.waitForAny
local function thrd_checkForKeys()
    local event, key, held = os.pullEvent("key")
    local keyMethod = puyoBoard.dropper.controls[key]
    
    if (key == keys.p) and not (held) then
         if (isPaused) then
            isPaused = false 
            renderBoard(puyoBoard)
            renderDropper(puyoBoard.dropper)
         else
            isPaused = true
         end
         return
    end
    
    if (isPaused) then
        return
    end
    
    if (puyoBoard.dropper.disabled) then
        sleep(100)
        return
    end
    if (keyMethod ~= nil) then
        keyMethod(puyoBoard.dropper)
        renderDropper(puyoBoard.dropper)
    end
    sleep(100)
end

local function thrd_playGame()
    if (puyoBoard.dropper.disabled) then
        return 
    end
    local drop = puyoBoard.dropper
    
    dropperTimer = dropperTimer - 1
    if (dropperTimer <= 0) then
        drop.y = drop.y + 1
        if (dropperIntersectsBoard(puyoBoard, drop)) then
             drop.y = drop.y - 1
             landingTimer = landingTimer - 1
             if (landingTimer <= 0) then
                 onDropperLanding()
                 drop.disabled = false
                 
                 gameSpeed = math.max(0.2, math.min((-(1/40)*puyosDropped)+1.7, 1.2))*20
                 
                 dropperTimer = gameSpeed
                 landingTimer = 10
             end
        else
            dropperTimer = gameSpeed
        end
        renderDropper(drop)
    end
    sleep(0.05)
end

local function thrd_receiveRednetMessages()
    
    
    
end

--singleplayer
local function playGame()
    puyosDropped = 0
    gameover = false
    term.clear()
    puyoBoard = resetBoard(true)
    resetDropper(puyoBoard)
    puyoBoard.dropper.disabled = false
    gameSpeed = 1.2*20
    puyoBoard.garbagetimer = gameSpeed
    renderBoard(puyoBoard)
    
    if not (isMultiplayer) then
        puyoBoard.garbage = (1.4-gameSpeed/20)*10
    end
    
    while true do
        if (gameover) then 
            if (isMultiplayer) then
                --send board.gameover message 
            end
            term.setBackgroundColor(colors.black)
            term.clear()
            return
        end 
        
        if (isPaused) then
            local xSiz, ySiz = term.getSize()
            drawStringAt((xSiz/2)-3, (ySiz)/2, "PAUSED", colors.white, colors.gray)
            --todo: change term.getSize to a 4th 
            --also think about the portable
        end 
        
        if not (isMultiplayer) then
            if not (isPaused) then
                parallel.waitForAny(thrd_playGame, thrd_checkForKeys)
            else
                thrd_checkForKeys()
            end
        end
    end
end

--[[
--multiplayer
term.clear()
renderBoard()
if (openRednet() == nil) then
    print("Cannot find a modem! Exiting...")
    exit()
end
clientID = rednet.lookup("puyo-puyo","puyogame")
if (clientID == nil) then --todo: hosting shiz
    rednet.host("puyo-puyo", "puyogame")
]]

--< MENU SYSTEM >--
local function playSingleplayer()
    playGame()
end

local function playMultiplayer()
    --display connecting menu
    
    --TODO: connecting stuff 
end

local menuItems = {{["name"] = "Play Solo", ["color"] = colors.white, ["runfunction"] = playSingleplayer},
                   {["name"] = "Play Online MP", ["color"] = colors.lightGray, ["runfunction"] = nil--[[playMultiplayer]]}, 
                   {["name"] = "Exit", ["color"] = colors.red, ["runfunction"] = shell.exit}}
local selectedItem = 1

local function drawMenu()
    term.setTextColor(colors.white)
    drawStringCentered(1,"CCPuyo - v1.0.0",colors.white,colors.black,true)
    for value,item in pairs(menuItems) do
        local color = item.color 
        if (selectedItem == value) then
            drawStringCentered(value*2+2,"> "..item.name.."  ",color,colors.black,true)
        else
            drawStringCentered(value*2+2,"  "..item.name.."  ",color,colors.black,true)
        end
    end
end

local function menuKeyListener()
    local event, key, held = os.pullEvent("key")
    if (key == keys.enter) then
        if (menuItems[selectedItem].runfunction ~= nil) then
            menuItems[selectedItem].runfunction()
        end
        return
    elseif (key == keys.down) then
         selectedItem = selectedItem + 1
         if (selectedItem > tableLength(menuItems)) then
             selectedItem = tableLength(menuItems)
         end
    elseif (key == keys.up) then
         selectedItem = selectedItem - 1
         if (selectedItem < 1) then
             selectedItem = 1
         end
         
    end
end

local function openMenu()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawMenu()
    while true do
        menuKeyListener()
        drawMenu()
    end
end

--------START MAIN GAME FUNCTION CALLS--------
--playGame(true)
openMenu()
