return function(first)
    assert(first, "Cannot save instance (instance is nil)");
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
        local t;
        local at = 1;
        local function nextkeyword()
            local keyword = "";
            while (raw:sub(at, at) ~= ' ' and raw:sub(at, at) ~= '\n') do
                keyword = keyword .. raw:sub(at, at);
                at = at + 1;
            end
            return keyword;
        end
        while at < string.len(raw) do
            if (raw:sub(at, at + 5) == "Class ") then
                at = at + 6;
                local name = nextkeyword();
                t = {};
                t.Name = name;
                t.Type = "Class";
                t.BaseClass = name;
                at = at + 1;
                if (raw:sub(at, at) == ':') then
                    at = at + 2;
                    local inheritedclass = "";
                    while (raw:sub(at, at) ~= ' ' and raw:sub(at, at) ~= '\n' and raw:sub(at, at) ~= '\r') do
                        inheritedclass = inheritedclass .. raw:sub(at, at);
                        at = at + 1;
                    end
                    t.BaseClass = inheritedclass;
                    local x = t;
                    while x.BaseClass ~= x.Name and rbxapi[x.BaseClass] do
                        for k,v in pairs(rbxapi[x.BaseClass]) do
                            if (v.Type == "Property") then
                                --[[ warn("Adding " .. v.Name .. " to rbxapi['" .. name .. "']") ]]
                                t[k] = v;
                            end
                        end
                        x = rbxapi[x.BaseClass];
                    end
                end
                rbxapi[name] = t;
                --[[ print("rbxapi['" .. name .. "'] = ", rbxapi[name]); ]]
            elseif (raw:sub(at, at + 5) == "\nEnum ") then
                at = at + 6;
                local name = "";
                while (raw:sub(at, at) ~= ' ' and raw:sub(at, at) ~= '\n' and raw:sub(at, at) ~= '\r') do
                    name = name .. raw:sub(at, at);
                    at = at + 1;
                end
                t = {};
                t.Name = name;
                t.Type = "EnumItem";
                t.RawType = "EnumItem";
                rbxapi[name] = t;
            end
            if (t and raw:sub(at, at + 9) == "\tEnumItem ") then
                if type(t.Name) == "string" then 
                    at = at + 10;
                    at = at + string.len(t.Name);
                    local enumname = nextkeyword();
                    local e = {};
                    e.Name = enumname;
                    e.Type = "EnumItem";
                    e.RawType = "EnumItem";
                    t[enumname] = e;
                end
            end
            if (t and raw:sub(at, at + 9) == "\tProperty ") then
                if type(t.Name) == "string" then
                    at = at + 10;
                    local propertytype = nextkeyword();
                    --[[
                    --               V-------->V
                    -- \Property bool Instance.RobloxLocked [PluginSecurity]
                    -- skip the current name to get to the property name
                    ]]
                    at = at + string.len(t.Name) + 2;
                    local propertyname = nextkeyword();
                    local p = {};
                    p.Type = "Property";
                    p.Name = propertyname;
                    p.RawType = propertytype;
                    t[propertyname] = p;
                end
            end
            at = at + 1;
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
    
    local depthSpace = 4;
    local rbxapi = getreflection();
    local header = '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n';
    header = header .. string.rep(' ', depthSpace) .. "<External>null</External>\n";
    header = header .. string.rep(' ', depthSpace) .. "<External>nil</External>\n";
    
    local cacheduids = {};

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
        if (object.ClassName == "DataModel") then
            local xml = "";
            local scan = { "Workspace", "Lighting", "Players", "ReplicatedFirst", "ReplicatedStorage", "StarterGui", "StarterPack", "StarterPlayer" }; 
            for i = 1,#scan do
                local service = game:GetService(scan[i]);
                if service then
                    --[[print("Indexing DataModel --> '" .. service.Name .. "'...");]]
                    pcall(function()
                        xml = xml .. serialize(service, depth)
                    end);
                --[[else
                    warn("DataModel --> '" .. service.Name .. "' not found!");]]
                end
            end
            return xml;
        end
    
        if (object.Parent) then
            if (object.Parent.ClassName == "DataModel") then
                local folder = Instance.new("Folder");
                folder.Name = object.Name;
                for _,v in pairs(object:GetChildren()) do
                    pcall(function()
                        v.Archivable = true;
                        v:Clone().Parent = folder; 
                    end);
                end
                object = folder;
            end
        end

        local properties = rbxapi[object.ClassName];
        local xml = string.rep(' ', depth * depthSpace);
        local suid = generatesuid(object);
    
        xml = xml .. "<Item class=\"" .. object.ClassName .. "\" referent=\"" .. suid .. "\">\n";
        depth = depth + 1;
        xml = xml .. string.rep(' ', depth * depthSpace);
        xml = xml .. "<Properties>\n";
        depth = depth + 1;
        xml = xml .. string.rep(' ', depth * depthSpace);
        xml = xml .. "<BinaryString name=\"AttributesSerialize\"></BinaryString>\n";
        xml = xml .. string.rep(' ', depth * depthSpace);
    
        for k,v in pairs(properties) do
            local prop = nil;
            local proptype = properties[k].RawType;
            local propname = k;

			local ignore = false
			local ignoreList = { "EvaluationThrottled", "TileSize" }

			for i = 1,#ignoreList do
				if propname == ignoreList[i] then
					ignore = true
					break
				end
			end

			if ignore then continue end
            
            pcall(function()
                prop = object[propname];
            end);
        
            if not prop then
                --[[ splice the '\r' character, if present ]]
                pcall(function()
                    propname = propname:sub(1, string.len(propname) - 1);
                    prop = object[propname];
                end);
            end
            
            if prop and proptype then
                --[[ Adjust some labels from the api dump to RBX format ]]
                --[[ TO-DO: Move this to the parser ]]
                if (proptype:sub(1, 5) == "Enum.") then --[[ enum? let's use the "token" type ]]
                    proptype = "token";
                elseif (proptype == "CFrame") then --[[ cframe? let's use CoordinateFrame ]]
                    proptype = "CoordinateFrame";
                elseif (proptype == "Object" or proptype == "Instance") then
                    proptype = "Ref";
                elseif (proptype == "Color") then
                    proptype = "Color3";
                elseif (proptype == "BrickColor") then
                    --[[ It should look like: ]]
                    --[[ <Color3uint8 name="Color3uint8">4280374457</Color3uint8> ]] 
                    proptype = "Color3uint8";
                    propname = proptype;
                end
                
				local temp = "";
				
				xpcall(function()
					temp = temp .. "<" .. proptype .. " name=\"" .. propname .. "\">";
					
					if (proptype == "Vector2") then
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<X>" ..tostring(prop.X).. "</X>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<Y>" ..tostring(prop.Y).. "</Y>";
					    temp = temp .. "\n" .. string.rep(' ', depth * depthSpace);
					elseif (proptype == "Vector3") then
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<X>" ..tostring(prop.X).. "</X>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<Y>" ..tostring(prop.Y).. "</Y>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<Z>" ..tostring(prop.Z).. "</Z>";
					    temp = temp .. "\n" .. string.rep(' ', depth * depthSpace);
					elseif (proptype == "Color3") then
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<R>" ..tostring(prop.R).. "</R>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<G>" ..tostring(prop.G).. "</G>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<B>" ..tostring(prop.B).. "</B>";
					    temp = temp .. "\n" .. string.rep(' ', depth * depthSpace);
                    elseif (proptype == "CoordinateFrame") then
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<X>" ..tostring(prop.X).. "</X>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<Y>" ..tostring(prop.Y).. "</Y>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<Z>" ..tostring(prop.Z).. "</Z>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<R00>" .. tostring(prop.RightVector.x) .. "</R00>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<R01>" .. tostring(prop.RightVector.y) .. "</R01>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<R02>" .. tostring(prop.RightVector.z) .. "</R02>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<R10>" .. tostring(prop.UpVector.x) .. "</R10>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<R11>" .. tostring(prop.UpVector.y) .. "</R11>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<R12>" .. tostring(prop.UpVector.z) .. "</R12>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<R20>" .. tostring(prop.LookVector.x) .. "</R20>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<R21>" .. tostring(prop.LookVector.y) .. "</R21>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<R22>" .. tostring(prop.LookVector.z) .. "</R22>";
					    temp = temp .. "\n" .. string.rep(' ', depth * depthSpace);
					elseif (proptype == "Faces") then
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<Bottom>" .. tostring(prop.Bottom) .. "</Bottom>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<Top>" .. tostring(prop.Top) .. "</Top>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<Left>" .. tostring(prop.Left) .. "</Left>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<Right>" .. tostring(prop.Right) .. "</Right>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<Back>" .. tostring(prop.Back) .. "</Back>";
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
						temp = temp .. "<Front>" .. tostring(prop.Front) .. "</Front>";
					    temp = temp .. "\n" .. string.rep(' ', depth * depthSpace);
                    elseif (proptype == "UDim2") then
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<XS>" .. tostring(prop.X.Scale) .. "</XS>"
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<XO>" .. tostring(prop.X.Offset) .. "</XO>"
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<YS>" .. tostring(prop.Y.Scale) .. "</YS>"
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<YO>" .. tostring(prop.Y.Offset) .. "</YO>"
					    temp = temp .. "\n" .. string.rep(' ', depth * depthSpace);
                    elseif (proptype == "FontFace") then
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<Family><url>" .. tostring(prop.Family) .. "</url></Family>"
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<Weight>" .. tostring(prop.Weight.Value) .. "</Weight>"
                        temp = temp .. "\n" .. string.rep(' ', (depth + 1) * depthSpace);
                        temp = temp .. "<Style>" .. tostring(prop.Style.Name) .. "</Style>"
					    temp = temp .. "\n" .. string.rep(' ', depth * depthSpace);
                        --[[ temp = temp .. "<CachedFaceId><url></url></CachedFaceId>" ]]
					elseif (proptype == "Color3uint8") then
						local rgbavalue = bit32.bor(bit32.bor(bit32.bor(bit32.lshift(0xFF, 24), bit32.lshift(0xFF * prop.r, 16)), bit32.lshift(0xFF * prop.g, 8)), 0xFF * prop.b);
						temp = temp .. tostring(rgbavalue);
					elseif (proptype == "BrickColor") then
						temp = temp .. tostring(prop.Number)
					elseif (proptype == "Content") then
						temp = temp .. "<url>" ..tostring(prop).. "</url>";
					elseif (proptype == "Ref") then
						if prop == object then
							temp = temp .. suid;
						else
							local refsuid = generatesuid(prop);
							if refsuid ~= nil then
								temp = temp .. refsuid;
							end
						end
					elseif (proptype == "token") then
						temp = temp .. tostring(prop.Value); --[[ Use the enum number value]]
					else --[[ string, int, float, etc. use tostring ]]
						temp = temp .. tostring(prop);
					end
					
					temp = temp .. "</" .. proptype .. ">\n";
					temp = temp .. string.rep(' ', depth * depthSpace);
				end, function(err)
					temp = ""
				end) 

				if string.len(temp) > 0 then
					xml = xml .. temp
				end
            end
        end
        
        xml = xml .. "<BinaryString name=\"Tags\"></BinaryString>\n";
        depth = depth - 1;
        xml = xml .. string.rep(' ', depth * depthSpace);
        xml = xml .. "</Properties>\n";
        
        --[[ serialize the instance's children ]]
        for _,v in ipairs(object:GetChildren()) do
            pcall(function()
                xml = xml .. serialize(v, depth)
            end);
        end
        
        depth = depth - 1;
        xml = xml .. string.rep(' ', depth * depthSpace);
        xml = xml .. "</Item>\n";
        return xml;
    end
    
    local xml = serialize(first, 1);
    xml = header .. xml .. '</roblox>';
    return xml;
end
