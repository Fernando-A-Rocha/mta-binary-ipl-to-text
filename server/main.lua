--[[
    Converts a binary IPL file to a text IPL file
    (GTA San Andreas format)

    by Nando (https://github.com/Fernando-A-Rocha/mta-modloader-reborn)
]]

-- Function to read binary data from the file
local function readBinaryIPL(filepath)
    local file = fileOpen(filepath, true) -- read-only mode
    if not file then
        outputServerLog("Failed to open file: " .. filepath)
        return nil
    end

    local fileSize = fileGetSize(file)
    local binaryData = fileRead(file, fileSize)
    fileClose(file)
    
    return binaryData
end

-- Function to read a 32-bit integer from a binary string
local function readInt32(data, offset)
    if offset + 3 > #data then return nil end
    local b1, b2, b3, b4 = string.byte(data, offset, offset + 3)
    local value = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    if (value >= 0x80000000) then
        value = -((0xFFFFFFFF - value) + 1)
    end
    return value
end

-- Function to read a float from a binary string (assuming little-endian format)
local function readFloat(data, offset)
    if offset + 3 > #data then return nil end
    local b1, b2, b3, b4 = string.byte(data, offset, offset + 3)
    if not b1 or not b2 or not b3 or not b4 then return nil end
    local sign = (b4 > 0x7F) and -1 or 1
    local exponent = (b4 % 0x80) * 2 + math.floor(b3 / 0x80)
    local mantissa = (b3 % 0x80) * 65536 + b2 * 256 + b1
    if exponent == 0 then
        return 0
    elseif exponent == 255 then
        return sign * math.huge
    else
        return sign * (1 + mantissa / 8388608) * 2^(exponent - 127)
    end
end

-- Function to parse the header of the binary IPL data
local function parseHeader(binaryData)
    if string.sub(binaryData, 1, 4) ~= "bnry" then
        outputServerLog("Invalid header: Expected 'bnry'")
        return nil
    end

    local header = {
        itemInstances = readInt32(binaryData, 5),
        unknown1 = readInt32(binaryData, 9),
        unknown2 = readInt32(binaryData, 13),
        unknown3 = readInt32(binaryData, 17),
        parkedCars = readInt32(binaryData, 21),
        unknown4 = readInt32(binaryData, 25),
        offsetItemInstances = readInt32(binaryData, 29), -- Should be 76
        unused1 = readInt32(binaryData, 33),
        offsetUnknown1 = readInt32(binaryData, 37),
        unused2 = readInt32(binaryData, 41),
        offsetUnknown2 = readInt32(binaryData, 45),
        unused3 = readInt32(binaryData, 49),
        offsetUnknown3 = readInt32(binaryData, 53),
        unused4 = readInt32(binaryData, 57),
        offsetParkedCars = readInt32(binaryData, 61),
        unused5 = readInt32(binaryData, 65),
        offsetUnknown4 = readInt32(binaryData, 69),
        unused6 = readInt32(binaryData, 73)
    }

    return header
end

-- Function to parse binary IPL data
local function parseBinaryIPL(binaryData)
    local header = parseHeader(binaryData)
    if not header then
        return {}
    end

    local objects, cars = {}, {}

    local offset = header.offsetItemInstances
    local objectSize = 40

    for i = 1, header.itemInstances do
        if offset + objectSize > #binaryData then
            outputServerLog("Offset exceeds data length at object " .. i)
            break
        end

        --[[
            4b  - FLOAT    - PosX
            4b  - FLOAT    - PosY
            4b  - FLOAT    - PosZ
            4b  - FLOAT    - RotX
            4b  - FLOAT    - RotY
            4b  - FLOAT    - RotZ
            4b  - FLOAT    - RotW
            4b  - INT32    - Object ID
            4b  - INT32    - (always 0) could be interior flag ? 
            4b  - UINT32   - Flags: supposedly LOD index
        --]]
        local obj = {
            x = readFloat(binaryData, offset + 1),
            y = readFloat(binaryData, offset + 5),
            z = readFloat(binaryData, offset + 9),
            rx = readFloat(binaryData, offset + 13),
            ry = readFloat(binaryData, offset + 17),
            rz = readFloat(binaryData, offset + 21),
            rw = readFloat(binaryData, offset + 25),
            id = readInt32(binaryData, offset + 29),
            interiorFlag = readInt32(binaryData, offset + 33),  -- always 0
            flags = readInt32(binaryData, offset + 37)
        }

        table.insert(objects, obj)
        offset = offset + objectSize
    end

    if header.parkedCars > 0 then
        offset = header.offsetParkedCars
        local carSize = 48

        for i = 1, header.parkedCars do
            if offset + carSize > #binaryData then
                outputServerLog("Offset exceeds data length at car " .. i)
                break
            end
            --[[
                4b  - FLOAT    - PosX
                4b  - FLOAT    - PosY
                4b  - FLOAT    - PosZ
                4b  - FLOAT    - Angle (Around Z-Axis)
                4b  - INT32    - Object ID (See Vehicle ID List)
                28b - INT32[7] - Unknown flags (See IPL file specification)
            --]]
            local car = {
                x = readFloat(binaryData, offset + 1),
                y = readFloat(binaryData, offset + 5),
                z = readFloat(binaryData, offset + 9),
                angle = readFloat(binaryData, offset + 13),
                id = readInt32(binaryData, offset + 17),
                unknown = {
                    readInt32(binaryData, offset + 21),
                    readInt32(binaryData, offset + 25),
                    readInt32(binaryData, offset + 29),
                    readInt32(binaryData, offset + 33),
                    readInt32(binaryData, offset + 37),
                    readInt32(binaryData, offset + 41),
                    readInt32(binaryData, offset + 45)
                }
            }

            table.insert(cars, car)
            offset = offset + carSize
        end
    end
    
    return objects, cars
end

-- Function to convert objects to text IPL format
local function convertToTextIPL(objects, cars)
    local lines = {"# IPL generated with mta-binary-ipl-to-text by Nando", "inst"}
    
    for _, obj in ipairs(objects) do
        local modelName = MODEL_NAMES[obj.id] or "unknown"
        local line = string.format(
            "%d, %s, %d, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %d",
            obj.id, modelName, obj.interiorFlag, obj.x, obj.y, obj.z, obj.rx, obj.ry, obj.rz, obj.rw, obj.flags
        )
        table.insert(lines, line)
    end
    
    table.insert(lines, "end")

    if #cars > 0 then

        table.insert(lines, "cars")

        for _, car in ipairs(cars) do
            local line = string.format(
                "%.6f, %.6f, %.6f, %.6f, %d, %d, %d, %d, %d, %d, %d",
                car.x, car.y, car.z, car.angle, car.id, car.unknown[1], car.unknown[2], car.unknown[3], car.unknown[4], car.unknown[5], car.unknown[6]
            )
            table.insert(lines, line)
        end

        table.insert(lines, "end")
    end
    
    return table.concat(lines, "\n")
end

-- Function to write text IPL data to a file
local function writeTextIPL(filepath, textData)
    local file = fileCreate(filepath)
    if not file then
        outputServerLog("Failed to create file: " .. filepath)
        return false
    end
    
    fileWrite(file, textData)
    fileClose(file)
    
    return true
end

-- Main function to convert binary IPL to text IPL
local function convertBinaryIPLtoText(inputFilePath, outputFilePath)
    local binaryData = readBinaryIPL(inputFilePath)
    if not binaryData then return end
    
    local objects, cars = parseBinaryIPL(binaryData)
    local textData = convertToTextIPL(objects, cars)
    
    return writeTextIPL(outputFilePath, textData)
end

local function outputMsg(msg, executor, r, g, b)
    if getElementType(executor) == "player" then
        outputChatBox(msg, executor, r, g, b)
    else
        outputServerLog(msg)
    end
end

local function convertOneBinaryIPL(executor, command, inputFileName)
    if not inputFileName then
        outputMsg("Syntax: /" .. command .. " <input file name>", executor)
        return
    end
    local outputFilePath = "output/"..inputFileName
    local inputFilePath = "input/"..inputFileName

    if not fileExists(inputFilePath) then
        outputMsg("File not found: " .. inputFilePath, executor, 255, 0, 0)
        return
    end
    if fileExists(outputFilePath) then
        -- outputMsg("Output file already exists (will be replaced): " .. outputFilePath, executor, 255, 126, 0)
    end
    
    if convertBinaryIPLtoText(inputFilePath, outputFilePath) then
        outputMsg("Binary IPL file converted successfully!", executor, 0, 255, 0)
        outputMsg("Output file: " .. outputFilePath, executor)
    else
        outputMsg("Failed to convert binary IPL file: " .. inputFilePath, executor, 255, 0, 0)
    end
end
addCommandHandler("binaryipl", convertOneBinaryIPL, false, false)

local function convertAllBinaryIPLs(executor)
    if not pathIsDirectory("input") then
        outputMsg("Folder 'input' not found", executor, 255, 0, 0)
        return
    end
    for _, fileName in pairs(pathListDir("input" or {})) do
        convertOneBinaryIPL(executor, "binaryipl", fileName)
    end

    outputMsg("Finished converting binary IPL files in 'input' folder!", executor, 0, 255, 0)
end
addCommandHandler("binaryiplall", convertAllBinaryIPLs, false, false)
