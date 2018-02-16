----game variables
local puyoTypes = {"blue","red","green","yellow","purple"}
local puyoInfo = {["blue"] = {["color"] = colors.blue, ["symbol"] = "B"},
                  ["red"] = {["color"] = colors.red, ["symbol"] = "R"},
                  ["green"] = {["color"] = colors.green, ["symbol"] = "G"},
                  ["yellow"] = {["color"] = colors.yellow, ["symbol"] = "Y"},
                  ["purple"] = {["color"] = colors.purple, ["symbol"] = "P"},
                  ["garbage"] = {["color"] = colors.lightGray, ["symbol"] = "."}}
local gameSpeed = (1.2)*20 --1.2 seconds between the puyo dropping and 20 tps
local score = 0
local queuedPuyos = {}
local isPaused = false

--playing status variables
local opponentBoard --board of the opponent
local clientID --id of the opponent
local isMultiplayer = false --disallows

--board variables
local puyoBoard = {} --represents the puyo board, 6x12 by default.
local boardWidth = 6 
local boardHeight = 12

---display variables
local tempOffX, tempOffY = term.getSize()
local boardOffset = {["x"] = (tempOffX-2-boardWidth)/2, ["y"] = (tempOffY-2-boardHeight)/2}
tempOffX = nil  tempOffY = nil

---dropper variables and functions
local puyoDropper = {["x"] = 3, ["y"] = 1, ["rotation"] = 2}
local dropperTimer = gameSpeed

local function dropperGetRotOffset(dropper)
    if (dropper.rotation == 0) then return 0,1 end
    if (dropper.rotation == 1) then return 1,0 end
    if (dropper.rotation == 2) then return 0,-1 end
    if (dropper.rotation == 3) then return -1,0 end
end

local function dropperIntersectsBoard(dropper)
    
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
    return not ((puyoBoard[loc] == nil) and (puyoBoard[rotX..";"..rotY] == nil)) 
end

local function dropperMoveRight(dropper) 
    dropper["x"] = dropper.x + 1 
    if (dropperIntersectsBoard(dropper)) then 
        dropper["x"] = dropper.x - 1
    end
end
local function dropperMoveLeft(dropper) 
    dropper["x"] = dropper.x - 1 
    if (dropperIntersectsBoard(dropper)) then
        dropper["x"] = dropper.x + 1
    end
end
local function dropperRotateRight(dropper) 
    dropper["rotation"] = (dropper.rotation - 1)%4
    
    if (dropperIntersectsBoard(dropper)) then 
        --[[newly rotated intersects board
        -move the opposite of the offset. 
        -   (moves up if intersects from bottom)
        -   (moves right if intersects from left, etc)
        --]]
        local xRot, yRot = dropperGetRotOffset(dropper)
        dropper["x"] = dropper.x - xRot
        dropper["y"] = dropper.y - yRot
        
        if (dropperIntersectsBoard(dropper)) then --still intersects, move back
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

puyoDropper.controls = {[keys.right] = dropperMoveRight, 
    [keys.left] = dropperMoveLeft, [keys.up] = dropperRotateRight,
    [keys.down] = dropperQuickDrop}

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


local function getPuyoChains(chain, startX, startY, puyoType)
    for x=-1,1 do
        for y=-1,1 do
            if not (x ~= 0 and y ~= 0) then --remove the corners
                if not (x == 0 and y == 0) then --remove the center
                    local toCheckX = startX+x
                    local toCheckY = startY+y
                    local toCheckLocation = toCheckX..";"..toCheckY
                    
                    if not (tableHasValue(chain, toCheckLocation)) then
                        if (puyoType == puyoBoard[toCheckLocation]) then
                            table.insert(chain, toCheckLocation) 
                            getPuyoChains(chain, toCheckX, toCheckY, puyoType)
                        elseif (puyoBoard[toCheckLocation] == "garbage") then
                            table.insert(chain, toCheckLocation)
                        end
                    end                    
                end
            end
        end
    end
end

local function getMatchingPuyos()
    local checked = {}
    local matching = {}
    for x=1,boardWidth do
        for y=1,boardHeight do
            local location = x..";"..y
            if (puyoBoard[location] ~= null) then --if the location is a puyo or nil
                if not (tableHasValue(checked,location)) then --if the location was checked already
                    --this puyo was not checked... check for other surrounding puyos
                    local chain = {} --new table, stores puyos in the chain to this one
                    getPuyoChains(chain, x, y, puyoBoard[location])
                    
                    local length = 0
                    for k,v in pairs(chain) do
                        if (puyoBoard[v] ~= "garbage") then 
                            length = length + 1
                            table.insert(checked, k)--the key is the location 
                        end
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

local function dropFloatingPuyos()
    local returnval = false --if any puyo fell: return true
    for x=1,boardWidth do
        local supportedBy = boardHeight+1
        for yTmp=0,boardHeight do --why 0? so if you stack one above the top it doesnt disappear
            local y = (boardHeight+1)-yTmp 
            local stringLoc = x..";"..y
            
            if (puyoBoard[stringLoc] ~= nil) then
                supportedBy = supportedBy-1
                if (y ~= supportedBy) then --the support ISNT under current puyo
                    puyoBoard[x..";"..supportedBy] = puyoBoard[stringLoc]
                    puyoBoard[stringLoc] = nil
                    returnval = true
                end
            end
        end
    end
    return returnval
end


local function renderBoard()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    --render individual puyos
    for x=1,boardWidth do
        for y=1,boardHeight do
            local loc = x..";"..y
           
            if (puyoBoard[loc] ~= nil) then
                local info = puyoInfo[puyoBoard[loc]]
                if (term.isColor()) then
                    paintutils.drawPixel(x+boardOffset.x,y+boardOffset.y,info.color)
                    --drawStringAt(x+boardOffset.x,y+boardOffset.y,"o",info.color,colors.black)
                else
                    drawStringAt(x+boardOffset.x,y+boardOffset.y,info.symbol,colors.lightGray,colors.black)
                end
            end
        end
    end
    
    --render puyo dropper
    if not (puyoDropper.disabled) and (puyoDropper.main ~= nil) then
        local mainPuyo = puyoInfo[puyoDropper.main]
        local otherPuyo = puyoInfo[puyoDropper.other]
            
        local drawX = boardOffset.x + puyoDropper.x
        local drawY = boardOffset.y + puyoDropper.y
        
        local xRotOffset, yRotOffset = dropperGetRotOffset(puyoDropper)
        if (term.isColor()) then
            paintutils.drawPixel(drawX, drawY, mainPuyo.color)
            paintutils.drawPixel(drawX + xRotOffset, drawY + yRotOffset, otherPuyo.color) 
        else
            drawStringAt(drawX, drawY, mainPuyo.symbol, colors.lightGray, colors.black)
            drawStringAt(drawX+xRotOffset, drawY+yRotOffset, mainPuyo.symbol, colors.lightGray, colors.black)
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
    drawStringAt(boardOffset.x,boardOffset.y+boardHeight+2,"Score: " .. score,colors.white,colors.black)
end

local function queuePuyos()
    local new1, new2 = getRandomPuyoPair()
    table.insert(queuedPuyos, {["main"] = new1, ["other"] = new2})
    --TODO: send rednet message 
end

local function resetDropper()
    while (tableLength(queuedPuyos) < 2) do
        queuePuyos()
    end
    local pulled = queuedPuyos[1]
    
    puyoDropper.main = pulled.main
    puyoDropper.other = pulled.other
    puyoDropper.x = 3
    puyoDropper.y = 1
    puyoDropper.rotation = 2
    puyoDropper.disabled = true
    
    table.remove(queuedPuyos,1)
end

local function onDropperLanding()
    local scoreMultiplier = 0
    
    puyoDropper.disabled = true
    local x = puyoDropper.x
    local y = puyoDropper.y
    puyoBoard[x..";"..y] = puyoDropper.main
    local xRot, yRot = dropperGetRotOffset(puyoDropper)
    puyoBoard[(x+xRot)..";"..(y+yRot)] = puyoDropper.other
    
    resetDropper()
    dropFloatingPuyos()
    local contLoop = true
    while contLoop do
        sleep(0.4)
        scoreMultiplier = scoreMultiplier + 1
        local matched = getMatchingPuyos() --todo: seems to have more pairs, score is messed up
        for k,v in pairs(matched) do
            score = score + (tableLength(v)*scoreMultiplier)
            for _,loc in pairs(v) do
                puyoBoard[loc] = nil
            end
            
            renderBoard()
            sleep(0.2)
        end
        renderBoard()
        contLoop = dropFloatingPuyos()
        sleep(0.4)
        renderBoard()
    end
    puyoDropper.disabled = false
    renderBoard()
end

--< MAIN PROGRAM LOOPS >--
--check for keys will halt, hence why we have to use parallel.waitForAny
local function thrd_checkForKeys()
    local event, key, held = os.pullEvent("key")
    local keyMethod = puyoDropper.controls[key]
    
    if (puyoDropper.disabled) then
        sleep(1)
        return
    end
    if (key == keys.p) and not (isMultiplayer) then
       paused = not paused
       return 
    end
    if (keyMethod ~= nil) then
        keyMethod(puyoDropper)
        renderBoard()
    end
    sleep(1)
end

local function thrd_playGame()
    if (puyoDropper.disable) then
        return 
    end
    dropperTimer = dropperTimer - 1
    if (dropperTimer <= 0) then
       puyoDropper["y"] = puyoDropper.y + 1
       renderBoard()
       if (dropperIntersectsBoard(puyoDropper)) then
           puyoDropper["y"] = puyoDropper.y - 1
           renderBoard()
           onDropperLanding()
       end
       dropperTimer = gameSpeed 
    end
    sleep(0.05)
end


--singleplayer
term.clear()
renderBoard()
resetDropper()
puyoDropper.disabled = false
while true do
    if (isPaused) then 
        local xSiz, ySiz = term,getSize()
        term.setCursorPos((xSiz/2)-3, ySiz/2)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.gray)
        print("PAUSED")
        return
    end
    parallel.waitForAny(thrd_checkForKeys, thrd_playGame)
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
