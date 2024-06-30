return function(first)
    assert(first, "Cannot save instance (nil instance)");
    local reflection;
    
    --[[
    This takes a recently updated and formatted api dump
    of a majority of ROBLOX classes and parses it
    into a large table, which we can use for reference
    for instance properties/functions/etc.
    ]]
    local function loadreflection()
        --[[ Thanks MaximumADHD! ]]
        local raw = httpget("https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.txt");
        local rbxapi = {};
        local t = nil;
        local at = 1;
        local function nextkeyword()
            local keyword = "";
            while at < string.len(raw) and
                raw:sub(at, at) ~= ' ' and
                raw:sub(at, at) ~= '?' and
                raw:sub(at, at) ~= ':' and
                raw:sub(at, at) ~= '\t' and
                raw:sub(at, at) ~= '\r' and
                raw:sub(at, at) ~= '\n' do
                keyword = keyword .. raw:sub(at, at);
                at = at + 1;
            end
            if string.len(keyword) == 0 then
                keyword = "(null)"
            end
            return keyword;
        end
        while at < string.len(raw) do
            if (raw:sub(at, at + 5) == "Class ") then
                at = at + 6;
                local name = nextkeyword();
                t = {};
                t.Properties = {}
                t.Name = name;
                t.Type = "Class";
                t.BaseClass = "<<<ROOT>>>";
                at = at + 1;
                
                if (raw:sub(at, at) == ':') then
                    at = at + 2;
                    t.BaseClass = nextkeyword();
                    
                    local pnext = t;
                    while pnext do
                        if pnext.BaseClass == "<<<ROOT>>>" then break end
                        if not rbxapi[pnext.BaseClass] then break end
                        
                        for k,v in pairs(rbxapi[pnext.BaseClass].Properties) do
                            if v.Type == "Property" and not t.Properties[k] then
                                t.Properties[k] = v;
                            end
                        end
                        
                        pnext = rbxapi[pnext.BaseClass];
                    end
                end
                
                rbxapi[name] = t;
                --print("rbxapi['" .. name .. "'] = ", rbxapi[name]);
            elseif (raw:sub(at, at + 5) == "\nEnum ") then
                at = at + 6;
                local name = nextkeyword();
                t = {};
                t.Name = name;
                t.Type = "Enum";
                t.RawType = "Enum";
                rbxapi[name] = t;
            elseif (t and raw:sub(at, at + 9) == "\tEnumItem ") then
                at = at + 10;
                while raw:sub(at - 1, at - 1) ~= "." and at < string.len(raw) do
                    at = at + 1
                end
                local enumname = nextkeyword();
                at = at + 3
                local enumvalue = tonumber(nextkeyword()) or 0;
                local e = {};
                e.Name = enumname;
                e.Type = "EnumItem";
                e.RawType = "token";
                e.Value = enumvalue;
                t[enumname] = e;
            -- \/
            -- Property BasePart.LeftSurfaceInput: Enum.InputType [Hidden] [Deprecated]
            elseif (t and raw:sub(at, at + 9) == "\tProperty ") then
                at = at + 10
                --          V------->V
                -- Property BasePart.LeftSurfaceInput: Enum.InputType [Hidden] [Deprecated]
                -- Properties for a "Part" will be tagged with BasePart,
                -- as it's inherited from. Lets just go up to the next "."
                while raw:sub(at - 1, at - 1) ~= "." and at < string.len(raw) do
                    at = at + 1
                end
                local propertyname = nextkeyword();
                --[[
                --                V------->V
                -- \Property bool Instance.RobloxLocked [PluginSecurity]
                -- skip the current name to get to the property name
                ]]
                at = at + 2
                local propertytype = nextkeyword();
            
                -- We can safely assume t contains a Properties table
                -- since there had to be a Class before it
                local found = false
                for k,v in ipairs(t.Properties) do
                    if k:lower() == propertyname:lower() then
                        found = true
                        break
                    end
                end
                if not found then
                    local p = {};
                    -- Some properties can be enums, having "Enum." at the start
                    if (propertytype:sub(1,5) == "Enum.") then
                        --propertytype = propertytype:gsub("Enum.", "");
                        propertytype = "token"
                        p.IsEnum = true
                    end
                    p.Type = "Property";
                    p.Name = propertyname;
                    p.RawType = propertytype;
                    t.Properties[propertyname] = p;
                end
                -- Skip the related property tags, go to end of line
                while at < string.len(raw) do
                    if raw:sub(at, at) == '\n' or raw:sub(at, at) == '\r' then
                        break
                    end
                    at = at + 1
                end
            else
                at = at + 1;
            end
        end
        return rbxapi;
    end
    
    local function getreflection()
        if reflection ~= nil then return reflection end
        reflection = loadreflection();
        return reflection;
    end
    
    local function getproperties(object)
        if typeof(object) ~= "Instance" then error'Instance expected' end
        local rbxapi = getreflection();
        return rbxapi[object.ClassName];
    end
    
    local lookupValueToCharacter = buffer.create(64)
    local lookupCharacterToValue = buffer.create(256)

    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local padding = string.byte("=")

    for index = 1, 64 do
        local value = index - 1
        local character = string.byte(alphabet, index)

        buffer.writeu8(lookupValueToCharacter, value, character)
        buffer.writeu8(lookupCharacterToValue, character, value)
    end

    local function b64encode(input: buffer): buffer
        local inputLength = buffer.len(input)
        local inputChunks = math.ceil(inputLength / 3)

        local outputLength = inputChunks * 4
        local output = buffer.create(outputLength)

        -- Since we use readu32 and chunks are 3 bytes large, we can't read the last chunk here
        for chunkIndex = 1, inputChunks - 1 do
            local inputIndex = (chunkIndex - 1) * 3
            local outputIndex = (chunkIndex - 1) * 4

            local chunk = bit32.byteswap(buffer.readu32(input, inputIndex))

            -- 8 + 24 - (6 * index)
            local value1 = bit32.rshift(chunk, 26)
            local value2 = bit32.band(bit32.rshift(chunk, 20), 0b111111)
            local value3 = bit32.band(bit32.rshift(chunk, 14), 0b111111)
            local value4 = bit32.band(bit32.rshift(chunk, 8), 0b111111)

            buffer.writeu8(output, outputIndex, buffer.readu8(lookupValueToCharacter, value1))
            buffer.writeu8(output, outputIndex + 1, buffer.readu8(lookupValueToCharacter, value2))
            buffer.writeu8(output, outputIndex + 2, buffer.readu8(lookupValueToCharacter, value3))
            buffer.writeu8(output, outputIndex + 3, buffer.readu8(lookupValueToCharacter, value4))
        end

        local inputRemainder = inputLength % 3

        if inputRemainder == 1 then
            local chunk = buffer.readu8(input, inputLength - 1)

            local value1 = bit32.rshift(chunk, 2)
            local value2 = bit32.band(bit32.lshift(chunk, 4), 0b111111)

            buffer.writeu8(output, outputLength - 4, buffer.readu8(lookupValueToCharacter, value1))
            buffer.writeu8(output, outputLength - 3, buffer.readu8(lookupValueToCharacter, value2))
            buffer.writeu8(output, outputLength - 2, padding)
            buffer.writeu8(output, outputLength - 1, padding)
        elseif inputRemainder == 2 then
            local chunk = bit32.bor(
                bit32.lshift(buffer.readu8(input, inputLength - 2), 8),
                buffer.readu8(input, inputLength - 1)
            )

            local value1 = bit32.rshift(chunk, 10)
            local value2 = bit32.band(bit32.rshift(chunk, 4), 0b111111)
            local value3 = bit32.band(bit32.lshift(chunk, 2), 0b111111)

            buffer.writeu8(output, outputLength - 4, buffer.readu8(lookupValueToCharacter, value1))
            buffer.writeu8(output, outputLength - 3, buffer.readu8(lookupValueToCharacter, value2))
            buffer.writeu8(output, outputLength - 2, buffer.readu8(lookupValueToCharacter, value3))
            buffer.writeu8(output, outputLength - 1, padding)
        elseif inputRemainder == 0 and inputLength ~= 0 then
            local chunk = bit32.bor(
                bit32.lshift(buffer.readu8(input, inputLength - 3), 16),
                bit32.lshift(buffer.readu8(input, inputLength - 2), 8),
                buffer.readu8(input, inputLength - 1)
            )

            local value1 = bit32.rshift(chunk, 18)
            local value2 = bit32.band(bit32.rshift(chunk, 12), 0b111111)
            local value3 = bit32.band(bit32.rshift(chunk, 6), 0b111111)
            local value4 = bit32.band(chunk, 0b111111)

            buffer.writeu8(output, outputLength - 4, buffer.readu8(lookupValueToCharacter, value1))
            buffer.writeu8(output, outputLength - 3, buffer.readu8(lookupValueToCharacter, value2))
            buffer.writeu8(output, outputLength - 2, buffer.readu8(lookupValueToCharacter, value3))
            buffer.writeu8(output, outputLength - 1, buffer.readu8(lookupValueToCharacter, value4))
        end

        return output
    end

    local function b64decode(input: buffer): buffer
        local inputLength = buffer.len(input)
        local inputChunks = math.ceil(inputLength / 4)

        -- TODO: Support input without padding
        local inputPadding = 0
        if inputLength ~= 0 then
            if buffer.readu8(input, inputLength - 1) == padding then inputPadding += 1 end
            if buffer.readu8(input, inputLength - 2) == padding then inputPadding += 1 end
        end

        local outputLength = inputChunks * 3 - inputPadding
        local output = buffer.create(outputLength)

        for chunkIndex = 1, inputChunks - 1 do
            local inputIndex = (chunkIndex - 1) * 4
            local outputIndex = (chunkIndex - 1) * 3

            local value1 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, inputIndex))
            local value2 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, inputIndex + 1))
            local value3 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, inputIndex + 2))
            local value4 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, inputIndex + 3))

            local chunk = bit32.bor(
                bit32.lshift(value1, 18),
                bit32.lshift(value2, 12),
                bit32.lshift(value3, 6),
                value4
            )

            local character1 = bit32.rshift(chunk, 16)
            local character2 = bit32.band(bit32.rshift(chunk, 8), 0b11111111)
            local character3 = bit32.band(chunk, 0b11111111)

            buffer.writeu8(output, outputIndex, character1)
            buffer.writeu8(output, outputIndex + 1, character2)
            buffer.writeu8(output, outputIndex + 2, character3)
        end

        if inputLength ~= 0 then
            local lastInputIndex = (inputChunks - 1) * 4
            local lastOutputIndex = (inputChunks - 1) * 3

            local lastValue1 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, lastInputIndex))
            local lastValue2 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, lastInputIndex + 1))
            local lastValue3 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, lastInputIndex + 2))
            local lastValue4 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, lastInputIndex + 3))

            local lastChunk = bit32.bor(
                bit32.lshift(lastValue1, 18),
                bit32.lshift(lastValue2, 12),
                bit32.lshift(lastValue3, 6),
                lastValue4
            )

            if inputPadding <= 2 then
                local lastCharacter1 = bit32.rshift(lastChunk, 16)
                buffer.writeu8(output, lastOutputIndex, lastCharacter1)

                if inputPadding <= 1 then
                    local lastCharacter2 = bit32.band(bit32.rshift(lastChunk, 8), 0b11111111)
                    buffer.writeu8(output, lastOutputIndex + 1, lastCharacter2)

                    if inputPadding == 0 then
                        local lastCharacter3 = bit32.band(lastChunk, 0b11111111)
                        buffer.writeu8(output, lastOutputIndex + 2, lastCharacter3)
                    end
                end
            end
        end

        return output
    end

    function base64encode(str)
        return buffer.tostring(b64encode(buffer.fromstring(str)))
    end

    function base64decode(str)
        return buffer.tostring(b64decode(buffer.fromstring(str)))
    end
    
    local depthSpace = 4;
    local rbxapi = getreflection();
    
    local headerStart = '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n' .. string.rep(' ', depthSpace) .. "<External>null</External>\n" .. string.rep(' ', depthSpace) .. "<External>nil</External>\n";
    local headerEnd = "</roblox>";
    
    local cacheduids = {};
    local sharedStrings = {};
    
    local function generatesuid(instance)
        for i = 1, #cacheduids do
            if cacheduids[i].Instance == instance then
                return cacheduids[i].SUID;
            end
        end
        local suid = "RBX";
        for i = 1,32 do
            suid = suid .. string.char(0x30 + math.random(0,9));
        end
        table.insert(cacheduids, {["Instance"] = instance, ["SUID"] = suid});
        return suid;
    end
    
    local function serialize(object, depth)
        if (object.ClassName == "Terrain") then
            return "" -- not ready yet
        end
        if (object.ClassName == "DataModel") then
            local xml = "";
            local scan = { "Workspace", "Lighting", "Players", "ReplicatedFirst", "ReplicatedStorage", "StarterGui", "StarterPack", "StarterPlayer" };
            for i = 1,#scan do
                pcall(function()
                    local service = game:GetService(scan[i]);
                    if service then
                        --[[print("Indexing DataModel --> '" .. service.Name .. "'...");]]
                        xml = xml .. serialize(service, depth)
                    else
                        warn("DataModel->" .. service.Name .. " not found!");
                    end
                end);
            end
            return xml;
        elseif (object.Parent) then
            if (object.Parent.ClassName == "DataModel") then
                --[[
                local folder = Instance.new("Folder");
                folder.Name = object.Name;
                for _,v in pairs(object:GetChildren()) do
                    pcall(function()
                        v.Archivable = true;
                        v:Clone().Parent = folder; 
                    end);
                end
                object = folder;
                ]]
            end
        end

        local metadata = rbxapi[object.ClassName];
        if metadata == nil then
            error("Properties not found for class " .. object.ClassName)
            return ""
        else
            local properties = metadata.Properties
            local xml = "";
            local suid = generatesuid(object);
            
            local function addwhitespace(n)
                if type(n) == "number" then
                    depth = depth + n
                end
                xml = xml .. string.rep(' ', depth * depthSpace);
            end
            
            local function addtagstart(tagname, headers)
                addwhitespace()
                xml = xml .. '<' .. tagname;
                if headers then
                    for k,v in pairs(headers) do
                        xml = xml .. ' ' .. k .. '=';
                        if type(v) == "string" then
                            xml = xml .. '\"' .. v .. '\"';
                        else
                            xml = xml .. tostring(v)
                        end
                    end
                end
                xml = xml .. ">\n"
                depth = depth + 1
            end
            
            local function addtagfinish(tagname)
                addwhitespace(-1)
                xml = xml .. "</" .. tagname .. ">\n";
            end
            
            local function addsingletag(tagname, headers, rawvalue)
                addwhitespace()
                xml = xml .. '<' .. tagname;
                if headers then
                    for k,v in pairs(headers) do
                        xml = xml .. ' ' .. k .. '=';
                        if type(v) == "string" then
                            xml = xml .. '\"' .. v .. '\"';
                        else
                            xml = xml .. tostring(v)
                        end
                    end
                end
                xml = xml .. ">" .. tostring(rawvalue or "") .. "</" .. tagname .. ">\n";
            end
            
            addtagstart("Item", { ["class"] = object.ClassName, ["referent"] = suid });
            addtagstart("Properties");
            addsingletag("BinaryString", { ["name"] = "AttributesSerialize" });

            for k,v in pairs(properties) do
                local prop = nil;
                local proptype = v.RawType;
                local propname = k;
                local isenum = v.IsEnum;
                
                local ignore = false
                local ignoreList = { "ClassName", "EvaluationThrottled", "TileSize" }
                
                -- These properties are restricted if its a service
                if (object.Parent == game or object.Parent.ClassName == "DataModel") then
                    table.insert(ignoreList, "Parent");
                    table.insert(ignoreList, "Name");
                end

                for i = 1,#ignoreList do
                    if propname == ignoreList[i] then
                        ignore = true
                        break
                    end
                end
                
                if not ignore then
                    pcall(function()
                        prop = object[propname];
                    end);

                    if not prop then
                        --[[ Remove surrounding '\r' characters if present... ]]
                        pcall(function()
                            propname = propname:sub(1, string.len(propname) - 1); -- :gsub('\r', '')
                            prop = object[propname];
                        end);
                    end
                end
                
                --if not prop then
                --    error("Unable to find or access property " .. propname .. " of class " .. object.ClassName)
                --end
                
                if not ignore and prop and proptype then
                    local patches = {
                        ["CFrame"] = "CoordinateFrame",
                        ["Object"] = "Ref",
                        ["Instance"] = "Ref",
                        ["Color"] = "Color3",
                        ["BrickColor"] = function() propname = "Color3uint8"; return propname end,
                        ["string"] = function()
                            local n = tostring(prop):find("://")
                            if n and (n or 0) <= 255 then
                                return "Content";
                            end
                            return "string"
                        end,
                    }
                    
                    if patches[proptype] then
                        proptype = patches[proptype]
                        if (type(proptype) == "function") then
                            proptype = proptype()
                        end
                    end
                    
                    local function translateInstance(proptype, propname, prop)
                        local temp = "";

                        local function addwhitespace(n)
                            if type(n) == "number" then
                                depth = depth + n
                            end
                            temp = temp .. string.rep(' ', depth * depthSpace);
                        end

                        local function addpropertytag(tagtype, tagname, data)
                            addwhitespace();
                            temp = temp .. "<" .. tagtype .. " name=\"" .. tagname .. "\">";
                            if type(data) == "table" then
                                for k,v in pairs(data) do
                                    temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                                    temp = temp .. "<" .. k .. ">" ..tostring(v).. "</" .. k .. ">";
                                end
                                temp = temp .. '\n'
                                addwhitespace();
                            else
                                temp = temp .. tostring(data)
                            end
                            temp = temp .. "</" .. tagtype .. ">\n";
                        end
                        
                        -- [Optimization]
                        -- By comparing the object's properties with their default
                        -- values (i.e. they're all zero), we can skip setting most
                        -- of them.
                        local typesDefault = {
                            ["Vector2"] = {
                                ["X"] = 0,
                                ["Y"] = 0
                            },
                            ["Vector3"] = {
                                ["X"] = 0,
                                ["Y"] = 0,
                                ["Z"] = 0,
                            }
                        }
                        
                        local propsDefault = {
                            ["Terrain"] = {
                                ["MaterialColors"] = function()
                                    return ""
                                end,
                                ["PhysicsGrid"] = function()
                                    return ""
                                end,
                                ["SmoothGrid"] = function()
                                    return ""
                                end
                            }
                        }

                        local descriptors = {
                            ["Axes"] = function(p)
                                local function tobitn(...)
                                    local res = 0
                                    for i,n in pairs({...}) do
                                        if n then
                                            res = res + 2 ^ (i - 1)
                                        end
                                    end
                                    return res
                                end
                                return "<axes>" .. tostring(tobitn(p.X, p.Y, p.Z)) .. "</axes>"
                            end,
                            ["BrickColor"] = function(p)
                                return p.Number
                            end,
                            ["Color3uint8"] = function(p)
                                return bit32.bor(bit32.bor(bit32.bor(bit32.lshift(0xFF, 24), bit32.lshift(0xFF * p.r, 16)), bit32.lshift(0xFF * p.g, 8)), 0xFF * p.b)
                            end,
                            ["Color3"] = function(p)
                                return {
                                    ["R"] = p.R,
                                    ["G"] = p.G,
                                    ["B"] = p.B
                                }
                            end,
                            ["ColorSequence"] = function(p)
                                local res = ""
                                for _,v in pairs(p.Keypoints) do
                                    res = res .. table.concat({tostring(v.Time), tostring(v.Value.R), tostring(v.Value.G), tostring(v.Value.B)}, ' ') .. " 0 "
                                end
                                return res
                            end,
                            ["Content"] = function(p)
                                return (string.len(p) > 0) and ("<url>" .. tostring(p) .. "</url>") or "<null></null>"
                            end,
                            ["CoordinateFrame"] = function(p)
                                local c = { p:GetComponents() };
                                return { 
                                    ["X"] = c[1],
                                    ["Y"] = c[2],
                                    ["Z"] = c[3],
                                    ["R00"] = c[4],--p.RightVector.x,
                                    ["R01"] = c[5],--p.RightVector.y,
                                    ["R02"] = c[6],--p.RightVector.z,
                                    ["R10"] = c[7],--p.UpVector.x,
                                    ["R11"] = c[8],--p.UpVector.y,
                                    ["R12"] = c[9],--p.UpVector.z,
                                    ["R20"] = c[10],--math.abs(p.LookVector.x),
                                    ["R21"] = c[11],--math.abs(p.LookVector.y),
                                    ["R22"] = c[12]--math.abs(p.LookVector.z)
                                }
                            end,
                            ["Faces"] = function(p)
                                return {
                                    ["Bottom"] = p.Bottom,
                                    ["Top"] = p.Top,
                                    ["Left"] = p.Left,
                                    ["Right"] = p.Right,
                                    ["Back"] = p.Back,
                                    ["Front"] = p.Front
                                }
                            end,
                            ["FontFace"] = function(p)
                                return {
                                    ["Family"] = "<url>" .. tostring(p.Family) .. "</url>",
                                    ["Weight"] = p.Weight.Value,
                                    ["Style"] = p.Style.Name
                                }
                            end,
                            ["NumberRange"] = function(p)
                                return tostring(p.Min) .. " " .. tostring(p.Max)
                            end,
                            ["NumberSequence"] = function(p)
                                local res = ""
                                for _,v in pairs(p.Keypoints) do
                                    res = res .. table.concat({tostring(v.Time), tostring(v.Value), tostring(v.Envelope)}, ' ') .. ' '
                                end
                                return res
                            end,
                            ["PhysicalProperties"] = function(p)
                                return {
                                    ["CustomPhysics"] = tostring(true),
                                    ["Density"] = tostring(p.Density),
                                    ["Friction"] = tostring(p.Friction),
                                    ["Elasticity"] = tostring(p.Elasticity),
                                    ["FrictionWeight"] = tostring(p.FrictionWeight),
                                    ["ElasticityWeight"] = tostring(p.ElasticityWeight)
                                }
                            end,
                            ["Ray"] = function(p)
                                return {
                                    ["origin"] = "<X>" .. tostring(p.Origin.X) .. "</X><Y>" .. tostring(p.Origin.Y) .. "</Y><Z>" .. tostring(p.Origin.Z) .. "</Z>",
                                    ["direction"] = "<X>" .. tostring(p.Direction.X) .. "</X><Y>" .. tostring(p.Direction.Y) .. "</Y><Z>" .. tostring(p.Direction.Z) .. "</Z>"
                                }
                            end,
                            ["Rect"] = function(p)
                                return {
                                    ["min"] = "<X>" .. tostring(p.Min.X) .. "</X><Y>" .. tostring(p.Min.Y) .. "</Y><Z>" .. tostring(p.Min.Z) .. "</Z>",
                                    ["max"] = "<X>" .. tostring(p.Max.X) .. "</X><Y>" .. tostring(p.Max.Y) .. "</Y><Z>" .. tostring(p.Max.Z) .. "</Z>"
                                }
                            end,
                            ["Ref"] = function(p)
                                if p == object then
                                    return suid;
                                else
                                    local refsuid = generatesuid(p);
                                    if refsuid ~= nil then
                                        return refsuid;
                                    else
                                        return "null"
                                    end
                                end
                            end,
                            ["SharedString"] = function(p)
                                warn("SharedString not implemented yet")
                                return ""
                            end,
                            ["token"] = function(p)
                                return p.Value
                            end,
                            ["UDim2"] = function(p)
                                return {
                                    ["XS"] = p.X.Scale,
                                    ["XO"] = p.X.Offset,
                                    ["YS"] = p.Y.Scale,
                                    ["YO"] = p.Y.Offset
                                }
                            end,
                            ["Vector2"] = function(p)
                                return {
                                    ["X"] = p.X,
                                    ["Y"] = p.Y
                                }
                            end,
                            ["Vector2int16"] = function(p)
                                return {
                                    ["X"] = p.X,
                                    ["Y"] = p.Y
                                }
                            end,
                            ["Vector3"] = function(p)
                                return {
                                    ["X"] = p.X,
                                    ["Y"] = p.Y,
                                    ["Z"] = p.Z
                                }
                            end,
                            ["Vector3int16"] = function(p)
                                return {
                                    ["X"] = p.X,
                                    ["Y"] = p.Y,
                                    ["Z"] = p.Z
                                }
                            end,
                            ["default"] = function(p)
                                return tostring(p)
                            end
                        }

                        xpcall(function()
                            local shouldSet = true
                            if typesDefault[proptype] then
                                local isDefault = true
                                for k,v in pairs(typesDefault[proptype]) do
                                    --print("is " ..propname.. "." ..k.. ", ", prop[k], " == " .. v .. "?")
                                    -- ie. prop["X"] == v (or, defaultPropValue["X"])
                                    if prop[k] ~= v then
                                        isDefault = false
                                        break
                                    end
                                end
                                if isDefault then
                                    --warn("Property " .. propname .. " was not set because the values were default")
                                    shouldSet = false
                                end
                            end
                            if shouldSet then
                                local customSet = false;
                                if propsDefault[object.ClassName] then
                                    local defaultValue = propsDefault[object.ClassName][propname];
                                    if defaultValue then
										prop = defaultValue()
                                        --for k,v in pairs(defaultValues) do
                                        --    prop[k] = v;
                                        --end
                                        --warn("Set property to default hard-coded values")
                                        customSet = true;
                                    end
                                end
                                if not customSet then
                                    if not descriptors[proptype] then
                                        addpropertytag(proptype, propname, descriptors["default"](prop))
                                    else
                                        addpropertytag(proptype, propname, descriptors[proptype](prop))
                                    end
                                end
                            end
                        end, function(err)
                            warn(err)
                            temp = ""
                        end)
                        
                        return temp
                    end
                    
                    xml = xml .. translateInstance(proptype, propname, prop)
                end
            end

            addsingletag("BinaryString", { ["name"] = "Tags" });
            addtagfinish("Properties");

            --[[ serialize the instance's children ]]
            for _,v in ipairs(object:GetChildren()) do
                xpcall(function()
                    xml = xml .. serialize(v, depth)
                end, function(e)
                    warn(e)
                end);
            end

            addtagfinish("Item");
            return xml;
        end
    end
    
    return headerStart .. serialize(first, 1) .. headerEnd;
end
