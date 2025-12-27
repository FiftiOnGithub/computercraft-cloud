-- PROGRAMMING computer id 34 file lavafarm.lua

function chestInteractor()
  if turtle.getFuelLevel() < 500 then
  -- Refuel
    for i=1,16 do
      item=turtle.getItemDetail(i)
      if item ~= nil and item.name == "minecraft:lava_bucket" then
        turtle.select(i)
        turtle.refuel()
        break
      end
    end
  end
  -- First: deposit all full buckets and stack empty buckets together
  for i=1,16 do
    item = turtle.getItemDetail(i)
    if item ~= nil then 
      if item.name == "minecraft:lava_bucket" then
        turtle.select(i)
        while not turtle.dropUp() do
          sleep(10)
        end
      elseif item.name == "minecraft:bucket" then
        if i ~= 1 then 
          turtle.select(i)
          turtle.transferTo(1)
          
          if turtle.getItemCount() > 0 then
            turtle.dropDown()
          end
        end
      end
    end
  end
  turtle.select(1)
  while turtle.getItemCount(1) < 10 do
    if not turtle.suckDown(16 - turtle.getItemCount(1)) then sleep(10) end
  end
end

function handleBlock(block) 
  print(block)
  if not block then
    blockabove, detailabove = turtle.inspectUp()
    if not blockabove or detailabove.name ~= "minecraft:chest" then error("Illegal location") end
    turtle.down()
  elseif block == "minecraft:cobblestone" then
    blockabove, detailabove = turtle.inspectUp()
    if blockabove and detailabove and detailabove.name == "minecraft:lava_cauldron" then
      turtle.select(1)
      if turtle.getItemDetail() and turtle.getItemDetail().name == "minecraft:bucket" then
        turtle.placeUp()
      end
    end
    turtle.forward()
  elseif block == "minecraft:stone_bricks" then
    turtle.turnRight()
    turtle.forward()
  elseif block == "minecraft:deepslate_bricks" then
    turtle.turnLeft()
    turtle.forward()
  elseif block == "minecraft:polished_deepslate" then
    turtle.up()
    turtle.forward()
  elseif block == "minecraft:chest" then
    chestInteractor()
    -- find the front
    while true do
      local front, frontblock = turtle.inspect()
      if front and frontblock and frontblock.name == "minecraft:hopper" then break end
      turtle.turnRight()
    end
    turtle.turnLeft()
    turtle.forward()
    turtle.down()
  else
    error("Illegal location")
  end
end

while true do
  local block, detail = turtle.inspectDown()
  
  
  if block then
    handleBlock(detail.name)
  else
    handleBlock(nil)
  end
end