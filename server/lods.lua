-- This scripts links High Level of Detail model IDs to the Low Level of Detail model IDs
-- by reading the IPLs (both plaintext and binary converted to plaintext)

-- How it works:
-- Each object line has a LOD-index at the end of the line, which is the index of the LOD model in the same IPL file.
-- However, objects in binary IPL files have LOD-indexes that correspond to IPL entires in another file
-- that has with the same name, except the _streamX suffix.

local lodTable = {}
local lodsPending = {}

local function stringRemoveSpaces(str)
    return str:gsub("%s+", "")
end

local identityMatrix = {
	[1] = {1, 0, 0},
	[2] = {0, 1, 0},
	[3] = {0, 0, 1}
}

local function QuaternionTo3x3(x,y,z,w)
	local matrix3x3 = {[1] = {}, [2] = {}, [3] = {}}
	local symetricalMatrix = {
		[1] = {(-(y*y)-(z*z)), x*y, x*z},
		[2] = {x*y, (-(x*x)-(z*z)), y*z},
		[3] = {x*z, y*z, (-(x*x)-(y*y))} 
	}

	local antiSymetricalMatrix = {
		[1] = {0, -z, y},
		[2] = {z, 0, -x},
		[3] = {-y, x, 0}
	}
	for i = 1, 3 do
		for j = 1, 3 do
			matrix3x3[i][j] = identityMatrix[i][j]+(2*symetricalMatrix[i][j])+(2*w*antiSymetricalMatrix[i][j])
		end
	end
	return matrix3x3
end

local function getEulerAnglesFromMatrix(x1,y1,z1,x2,y2,z2,x3,y3,z3)
	local nz1,nz2,nz3
	nz3 = math.sqrt(x2*x2+y2*y2)
	nz1 = -x2*z2/nz3
	nz2 = -y2*z2/nz3
	local vx = nz1*x1+nz2*y1+nz3*z1
	local vz = nz1*x3+nz2*y3+nz3*z3
	return math.deg(math.asin(z2)),-math.deg(math.atan2(vx,vz)),-math.deg(math.atan2(x2,y2))
end

-- Convert a quaternion representation of rotation into Euler angles
local function fromQuaternion(x, y, z, w)
    local matrix = QuaternionTo3x3(x,y,z,w)
	local ox,oy,oz = getEulerAnglesFromMatrix(
		matrix[1][1], matrix[1][2], matrix[1][3],
		matrix[2][1], matrix[2][2], matrix[2][3],
		matrix[3][1], matrix[3][2], matrix[3][3]
	)

	return ox,oy,oz
end

function getObjectsFromIPL(filePath)
    local file = fileOpen(filePath, true)
    if not file then
        return false, "Failed to open file"
    end
    local fileContent = fileRead(file, fileGetSize(file))
    fileClose(file)
    if not fileContent then
        return false, "Failed to read file"
    end

    local lines = split(fileContent, "\n")
    local objects = {}
    local lodObjInfoToFind = {}

    local readingObjects = false
    for i=1, #lines do
        while true do
            local line = lines[i]
            line = stringRemoveSpaces(line)

            -- Ignore comments
            if string.sub(line, 1, 1) == "#" then
                break
            end

            -- Check if inst section is starting
            if string.sub(line, 1, 4) == "inst" then
                readingObjects = true
                break
            end

            if readingObjects then

                -- Check if inst section is ending
                if line == "end" then
                    readingObjects = false
                    break
                end

                local objectData = split(line, ",")
                if #objectData < 10 then
                    break
                end

                -- Model ID, Model Name (useless), Interior ID, X, Y, Z, RX, RY, RZ, RW, LOD Number (optional)
                local modelID = tonumber(objectData[1])
                local modelName = objectData[2]
                local interiorID = tonumber(objectData[3])
                local x = tonumber(objectData[4])
                local y = tonumber(objectData[5])
                local z = tonumber(objectData[6])
                local rx = tonumber(objectData[7])
                local ry = tonumber(objectData[8])
                local rz = tonumber(objectData[9])
                local rw = tonumber(objectData[10])
                local lodIndex = tonumber(objectData[11])

                if not modelID or not modelName or not interiorID or not x or not y or not z or not rx or not ry or not rz or not rw then
                    break
                end
                local objTableIndex = #objects + 1
                objects[objTableIndex] = {modelID, modelName, interiorID, x, y, z, rx, ry, rz, rw}

                -- LOD number is used to determine which object is the LOD of this object, based on the order they are read
                if lodIndex and lodIndex ~= -1 then
                    lodObjInfoToFind[lodIndex] = objTableIndex
                end
            end

            break
        end
    end
    return objects, lodObjInfoToFind
end

local function getObjModelName(id, full)
    local name = MODEL_NAMES[id] or "(?)"
    if not full then return name end
    return id .. " ("..name..")"
end

local function assignLod(hLODObjId, lLODObjId, iplName)
    local currAssignment = lodTable[hLODObjId]
    if currAssignment then
        print("Trying to assign LLOD " .. getObjModelName(lLODObjId, true).." to HLOD " .. getObjModelName(hLODObjId, true) .. ", which already has LLOD ".. getObjModelName(currAssignment[1], true) .. " - "..currAssignment[2])
        return
    end
    lodTable[hLODObjId] = {lLODObjId, iplName}
end

local function parseIPLLODs(parentPath, fileName, isBinary)
    local objects, lodObjInfoToFind = getObjectsFromIPL(parentPath .. "/" .. fileName)
    if not objects then
        outputDebugString("Error parsing " .. fileName.." : "..lodObjInfoToFind, 1)
        return
    end

    if not isBinary then
        local iplName = fileName:sub(1, -5)
        local thisIPL = iplName:lower()
        for lodIndex, objTableIndex in pairs(lodObjInfoToFind) do
            local objectData = objects[objTableIndex]
            local lodObjInfo = objects[lodIndex + 1]
            if lodObjInfo then
                assignLod(objectData[1], lodObjInfo[1], iplName)
            end
        end

        local thisLodsPending = lodsPending[thisIPL]
        if not thisLodsPending then
            return
        end
        for lodIndex, objId in pairs(thisLodsPending) do
            local lodObjInfo = objects[lodIndex + 1]
            if lodObjInfo then
                assignLod(objId, lodObjInfo[1], iplName)
            end
        end
    else
        local suffixStart = fileName:find("_stream")
        if not suffixStart then
            return
        end
        local otherIPL = fileName:sub(1, suffixStart - 1)
        otherIPL = otherIPL:lower()
        if not lodsPending[otherIPL] then
            lodsPending[otherIPL] = {}
        end
        for lodIndex, objTableIndex in pairs(lodObjInfoToFind) do
            local objectData = objects[objTableIndex]
            lodsPending[otherIPL][lodIndex] = objectData[1]
        end
    end
end


addCommandHandler("lodmodels", function()
    outputDebugString("Started...")
    local folderPath = "output"
    for _, entry in pairs(pathListDir(folderPath) or {}) do
        local path = folderPath .. "/" .. entry
        if pathIsFile(path) then
            parseIPLLODs(folderPath, entry, true)
        end
    end

    folderPath = "other_stuff/normal_ipls"
    for _, entry in pairs(pathListDir(folderPath) or {}) do
        local path = folderPath .. "/" .. entry
        if pathIsFile(path) then
            parseIPLLODs(folderPath, entry, false)
        else
            for _, subEntry in pairs(pathListDir(path) or {}) do
                path = folderPath .. "/" .. entry .. "/" .. subEntry
                if pathIsFile(path) then
                    parseIPLLODs(folderPath .. "/" .. entry, subEntry, false)
                end
            end
        end
    end

    local lodTableStr = "OBJ_LOD_MODELS = {{\n"
    local count = 0
    for obj, v in pairsByKeys(lodTable) do
        local lod, iplFn = v[1], v[2]
        local modelName = getObjModelName(obj)
        local lodModelName = getObjModelName(lod)
        lodTableStr = lodTableStr .. "{" .. obj .. ", " .. lod .. "}, // "..modelName.." => "..lodModelName.." ("..iplFn..")\n"
        count = count + 1
    end
    lodTableStr = lodTableStr .. "}};"
    lodTableStr = "// Total: "..count.."\n" .. lodTableStr

    local file = fileCreate("server/lod_table.hpp")
    if not file then
        outputDebugString("Failed to create file", 1)
        return
    end
    fileWrite(file, lodTableStr)
    fileClose(file)
    outputDebugString("LOD table written to file")
end, false, false)

function pairsByKeys(t)
    local a = {}
    for n in pairs(t) do
        table.insert(a, n)
    end
    table.sort(a)
    local i = 0
    local iter = function()
        i = i + 1
        if a[i] == nil then
            return nil
        else
            return a[i], t[a[i]]
        end
    end
    return iter
end
