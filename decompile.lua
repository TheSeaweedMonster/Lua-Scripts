local function deserialize(bytecode)
    local reader do
        reader = {}
        pos = 1
        function reader:pos() return pos end
        function reader:nextByte()
            local v = bytecode:byte(pos, pos)
            pos = pos + 1
            return v
        end
        function reader:nextChar()
            return string.char(reader:nextByte());
        end
        function reader:nextInt()
            local b = { reader:nextByte(), reader:nextByte(), reader:nextByte(), reader:nextByte() }
            return (
                bit32.bor(bit32.lshift(b[4], 24), 
                bit32.bor(bit32.lshift(b[3], 16),
                bit32.bor(bit32.lshift(b[2], 8),
                b[1])))
            )
        end
        function reader:nextVarInt()
            local c1, c2, b, r = 0, 0, 0, 0
            repeat
                c1 = reader:nextByte()
                c2 = bit32.band(c1, 0x7F)
                r = bit32.bor(r, bit32.lshift(c2, b))
                b = b + 7
            until not bit32.btest(c1, 0x80)
            return r;
        end
        function reader:nextString()
            local result = ""
            local len = reader:nextVarInt();
            for i = 1, len do
                result = result .. reader:nextChar();
            end
            return result;
        end
        function reader:nextDouble()
            local b = {};
            for i = 1, 8 do
                table.insert(b, reader:nextByte());
            end
            local str = '';
            for i = 1, 8 do
                str = str .. string.char(b[i]);
            end
            return string.unpack("<d", str)
        end
    end

    local bytecode_version = reader:nextByte()
    if (bytecode_version ~= 0) then
        local protoTable = {}
        local stringTable = {}
        
        reader:nextByte();
        
        local sizeStrings = reader:nextVarInt()
        for i = 1,sizeStrings do
            stringTable[i] = reader:nextString()
        end
        
        local sizeProtos = reader:nextVarInt();
        for i = 1,sizeProtos do
            protoTable[i] = {} -- pre-initialize an entry
            protoTable[i].codeTable = {}
            protoTable[i].kTable = {}
            protoTable[i].pTable = {}
            protoTable[i].smallLineInfo = {}
            protoTable[i].largeLineInfo = {}
        end
        
        for i = 1,sizeProtos do
            local proto = protoTable[i]
            proto.maxStackSize = reader:nextByte()
            proto.numParams = reader:nextByte()
            proto.numUpValues = reader:nextByte()
            proto.isVarArg = reader:nextByte()
            
            if (bytecode_version >= 4) then
                proto.flags = reader:nextByte()
                proto.typeinfo = reader:nextVarInt()
            end
            
            proto.sizeCode = reader:nextVarInt()
            for j = 1,proto.sizeCode do
                proto.codeTable[j] = reader:nextInt()
            end
            
            proto.sizeConsts = reader:nextVarInt();
            for j = 1,proto.sizeConsts do
                local k = {};
                k.type = reader:nextByte();
                if k.type == 1 then -- boolean
                    k.value = (reader:nextByte() == 1 and true or false)
                elseif k.type == 2 then -- number
                    k.value = reader:nextDouble()
                elseif k.type == 3 then -- string
                    k.value = stringTable[reader:nextVarInt()]
                elseif k.type == 4 then -- cache
                    k.value = reader:nextInt()
                elseif k.type == 5 then -- table
                    k.value = { ["size"] = reader:nextVarInt(), ["ids"] = {} }
                    for s = 1,k.value.size do
                        table.insert(k.value.ids, reader:nextVarInt() + 1)
                    end
                elseif k.type == 6 then -- closure
                    k.value = reader:nextVarInt() + 1 -- closure id
                elseif k.type ~= 0 then
                    error(string.format("Unrecognized constant type: %i", k.type))
                end
                proto.kTable[j] = k
            end
            
            proto.sizeProtos = reader:nextVarInt();
            for j = 1,proto.sizeProtos do
                proto.pTable[j] = protoTable[reader:nextVarInt() + 1]
            end
            
            proto.lineDefined = reader:nextVarInt()
            
            local protoSourceId = reader:nextVarInt()
            proto.source = stringTable[protoSourceId]
            
            if (reader:nextByte() == 1) then -- Has Line info?
                local compKey = reader:nextVarInt()
                for j = 1,proto.sizeCode do
                    proto.smallLineInfo[j] = reader:nextByte()
                end
                
                local n = bit32.band(proto.sizeCode + 3, -4)
                local intervals = bit32.rshift(proto.sizeCode - 1, compKey) + 1
                
                for j = 1,intervals do
                    proto.largeLineInfo[j] = reader:nextInt()
                end
            end
            
            if (reader:nextByte() == 1) then -- Has Debug info?
                error'disassemble() can only be called on ROBLOX scripts'
            end
        end
        
        local mainProtoId = reader:nextVarInt()
        return protoTable[mainProtoId + 1], protoTable, stringTable;
    else
        error(string.format("Invalid bytecode (version: %i)", bytecode_version))
        return nil;
    end
end

local function getluauoptable()
    return {
        -- I could use case multiplier, but that depends only on how accurate
        -- our ordering of the opcodes are -- so if we really want to rely on
        -- the latest updated luau source, then we could do it that way.
        { ["name"] = "NOP", ["type"] = "none", ["case"] = 0, ["number"] = 0x00 },
        { ["name"] = "BREAK", ["type"] = "none", ["case"] = 1, ["number"] = 0xE3 },
        { ["name"] = "LOADNIL", ["type"] = "iA", ["case"] = 2, ["number"] = 0xC6 },
        { ["name"] = "LOADB", ["type"] = "iABC", ["case"] = 3, ["number"] = 0xA9 },
        { ["name"] = "LOADN", ["type"] = "iABx", ["case"] = 4, ["number"] = 0x8C },
        { ["name"] = "LOADK", ["type"] = "iABx", ["case"] = 5, ["number"] = 0x6F },
        { ["name"] = "MOVE", ["type"] = "iAB", ["case"] = 6, ["number"] = 0x52 },
        { ["name"] = "GETGLOBAL", ["type"] = "iAC", ["case"] = 7, ["number"] = 0x35, ["aux"] = true },
        { ["name"] = "SETGLOBAL", ["type"] = "iAC", ["case"] = 8, ["number"] = 0x18, ["aux"] = true },
        { ["name"] = "GETUPVAL", ["type"] = "iAB", ["case"] = 9, ["number"] = 0xFB },
        { ["name"] = "SETUPVAL", ["type"] = "iAB", ["case"] = 10, ["number"] = 0xDE },
        { ["name"] = "CLOSEUPVALS", ["type"] = "iA", ["case"] = 11, ["number"] = 0xC1 },
        { ["name"] = "GETIMPORT", ["type"] = "iABx", ["case"] = 12, ["number"] = 0xA4, ["aux"] = true },
        { ["name"] = "GETTABLE", ["type"] = "iABC", ["case"] = 13, ["number"] = 0x87 },
        { ["name"] = "SETTABLE", ["type"] = "iABC", ["case"] = 14, ["number"] = 0x6A },
        { ["name"] = "GETTABLEKS", ["type"] = "iABC", ["case"] = 15, ["number"] = 0x4D, ["aux"] = true },
        { ["name"] = "SETTABLEKS", ["type"] = "iABC", ["case"] = 16, ["number"] = 0x30, ["aux"] = true },
        { ["name"] = "GETTABLEN", ["type"] = "iABC", ["case"] = 17, ["number"] = 0x13 },
        { ["name"] = "SETTABLEN", ["type"] = "iABC", ["case"] = 18, ["number"] = 0xF6 },
        { ["name"] = "NEWCLOSURE", ["type"] = "iABx", ["case"] = 19, ["number"] = 0xD9 },
        { ["name"] = "NAMECALL", ["type"] = "iABC", ["case"] = 20, ["number"] = 0xBC, ["aux"] = true },
        { ["name"] = "CALL", ["type"] = "iABC", ["case"] = 21, ["number"] = 0x9F },
        { ["name"] = "RETURN", ["type"] = "iAB", ["case"] = 22, ["number"] = 0x82 },
        { ["name"] = "JUMP", ["type"] = "isBx", ["case"] = 23, ["number"] = 0x65 },
        { ["name"] = "JUMPBACK", ["type"] = "isBx", ["case"] = 24, ["number"] = 0x48 },
        { ["name"] = "JUMPIF", ["type"] = "iAsBx", ["case"] = 25, ["number"] = 0x2B },
        { ["name"] = "JUMPIFNOT", ["type"] = "iAsBx", ["case"] = 26, ["number"] = 0x0E },
        { ["name"] = "JUMPIFEQ", ["type"] = "iAsBx", ["case"] = 27, ["number"] = 0xF1, ["aux"] = true },
        { ["name"] = "JUMPIFLE", ["type"] = "iAsBx", ["case"] = 28, ["number"] = 0xD4, ["aux"] = true },
        { ["name"] = "JUMPIFLT", ["type"] = "iAsBx", ["case"] = 29, ["number"] = 0xB7, ["aux"] = true },
        { ["name"] = "JUMPIFNOTEQ", ["type"] = "iAsBx", ["case"] = 30, ["number"] = 0x9A, ["aux"] = true },
        { ["name"] = "JUMPIFNOTLE", ["type"] = "iAsBx", ["case"] = 31, ["number"] = 0x7D, ["aux"] = true },
        { ["name"] = "JUMPIFNOTLT", ["type"] = "iAsBx", ["case"] = 32, ["number"] = 0x60, ["aux"] = true },
        { ["name"] = "ADD", ["type"] = "iABC", ["case"] = 33, ["number"] = 0x43 },
        { ["name"] = "SUB", ["type"] = "iABC", ["case"] = 34, ["number"] = 0x26 },
        { ["name"] = "MUL", ["type"] = "iABC", ["case"] = 35, ["number"] = 0x09 },
        { ["name"] = "DIV", ["type"] = "iABC", ["case"] = 36, ["number"] = 0xEC },
        { ["name"] = "MOD", ["type"] = "iABC", ["case"] = 37, ["number"] = 0xCF },
        { ["name"] = "POW", ["type"] = "iABC", ["case"] = 38, ["number"] = 0xB2 },
        { ["name"] = "ADDK", ["type"] = "iABC", ["case"] = 39, ["number"] = 0x95 },
        { ["name"] = "SUBK", ["type"] = "iABC", ["case"] = 40, ["number"] = 0x78 },
        { ["name"] = "MULK", ["type"] = "iABC", ["case"] = 41, ["number"] = 0x5B },
        { ["name"] = "DIVK", ["type"] = "iABC", ["case"] = 42, ["number"] = 0x3E },
        { ["name"] = "MODK", ["type"] = "iABC", ["case"] = 43, ["number"] = 0x21 },
        { ["name"] = "POWK", ["type"] = "iABC", ["case"] = 44, ["number"] = 0x04 },
        { ["name"] = "AND", ["type"] = "iABC", ["case"] = 45, ["number"] = 0xE7 },
        { ["name"] = "OR", ["type"] = "iABC", ["case"] = 46, ["number"] = 0xCA },
        { ["name"] = "ANDK", ["type"] = "iABC", ["case"] = 47, ["number"] = 0xAD },
        { ["name"] = "ORK", ["type"] = "iABC", ["case"] = 48, ["number"] = 0x90 },
        { ["name"] = "CONCAT", ["type"] = "iABC", ["case"] = 49, ["number"] = 0x73 },
        { ["name"] = "NOT", ["type"] = "iAB", ["case"] = 50, ["number"] = 0x56 },
        { ["name"] = "UNM", ["type"] = "iAB", ["case"] = 51, ["number"] = 0x39 },
        { ["name"] = "LEN", ["type"] = "iAB", ["case"] = 52, ["number"] = 0x1C },
        { ["name"] = "NEWTABLE", ["type"] = "iAB", ["case"] = 53, ["number"] = 0xFF, ["aux"] = true },
        { ["name"] = "DUPTABLE", ["type"] = "iABx", ["case"] = 54, ["number"] = 0xE2 },
        { ["name"] = "SETLIST", ["type"] = "iABC", ["case"] = 55, ["number"] = 0xC5, ["aux"] = true },
        { ["name"] = "NFORPREP", ["type"] = "iABx", ["case"] = 56, ["number"] = 0xA8 },
        { ["name"] = "NFORLOOP", ["type"] = "iABx", ["case"] = 57, ["number"] = 0x8B },
        { ["name"] = "TFORLOOP", ["type"] = "iABx", ["case"] = 58, ["number"] = 0x6E, ["aux"] = true },
        { ["name"] = "IPAIRSPREP", ["type"] = "none", ["case"] = 59, ["number"] = 0x51 },
        { ["name"] = "IPAIRSLOOP", ["type"] = "none", ["case"] = 60, ["number"] = 0x34 },
        { ["name"] = "PAIRSPREP", ["type"] = "none", ["case"] = 61, ["number"] = 0x17 },
        { ["name"] = "PAIRSLOOP", ["type"] = "none", ["case"] = 62, ["number"] = 0xFA },
        { ["name"] = "GETVARARGS", ["type"] = "iAB", ["case"] = 63, ["number"] = 0xDD },
        { ["name"] = "DUPCLOSURE", ["type"] = "iABx", ["case"] = 64, ["number"] = 0xC0 },
        { ["name"] = "PREPVARARGS", ["type"] = "iA", ["case"] = 65, ["number"] = 0xA3 },
        { ["name"] = "LOADKX", ["type"] = "iA", ["case"] = 66, ["number"] = 0x86 },
        { ["name"] = "JUMPX", ["type"] = "isAx", ["case"] = 67, ["number"] = 0x69 },
        { ["name"] = "FASTCALL", ["type"] = "iAC", ["case"] = 68, ["number"] = 0x4C },
        { ["name"] = "COVERAGE", ["type"] = "isAx", ["case"] = 69, ["number"] = 0x2F },
        { ["name"] = "CAPTURE", ["type"] = "iAB", ["case"] = 70, ["number"] = 0x12 },
        { ["name"] = "JUMPIFEQK", ["type"] = "iABx", ["case"] = 71, ["number"] = 0xF5, ["aux"] = true  },
        { ["name"] = "JUMPIFNOTEQK", ["type"] = "iABx", ["case"] = 72, ["number"] = 0xD8, ["aux"] = true  },
        { ["name"] = "FASTCALL1", ["type"] = "iABC", ["case"] = 73, ["number"] = 0xBB },
        { ["name"] = "FASTCALL2", ["type"] = "iABC", ["case"] = 74, ["number"] = 0x9E, ["aux"] = true },
        { ["name"] = "FASTCALL2K", ["type"] = "iABC", ["case"] = 75, ["number"] = 0x81, ["aux"] = true },
        { ["name"] = "COUNT", ["type"] = "none", ["case"] = 76, ["number"] = 0x64 }
    };
end

local luau = {};
luau.SIZE_A = 8
luau.SIZE_C = 8
luau.SIZE_B = 8
luau.SIZE_Bx = (luau.SIZE_C + luau.SIZE_B)
luau.SIZE_OP = 8
luau.POS_OP = 0
luau.POS_A = (luau.POS_OP + luau.SIZE_OP)
luau.POS_B = (luau.POS_A + luau.SIZE_A)
luau.POS_C = (luau.POS_B + luau.SIZE_B)
luau.POS_Bx = luau.POS_B
luau.MAXARG_A = (bit32.lshift(1, luau.SIZE_A) - 1)
luau.MAXARG_B = (bit32.lshift(1, luau.SIZE_B) - 1)
luau.MAXARG_C = (bit32.lshift(1, luau.SIZE_C) - 1)
luau.MAXARG_Bx = (bit32.lshift(1, luau.SIZE_Bx) - 1)
luau.MAXARG_sBx = bit32.rshift(luau.MAXARG_Bx, 1)
luau.BITRK = bit32.lshift(1, (luau.SIZE_B - 1))
luau.MAXINDEXRK = (luau.BITRK - 1)
luau.ISK = function(x) return bit32.band(x, luau.BITRK) end
luau.INDEXK = function(x) return bit32.band(x, bit32.bnot(luau.BITRK)) end
luau.RKASK = function(x) return bit32.bor(x, luau.BITRK) end
luau.MASK1 = function(n,p) return bit32.lshift(bit32.bnot(bit32.lshift(bit32.bnot(0), n)), p) end
luau.MASK0 = function(n,p) return bit32.bnot(luau.MASK1(n, p)) end
luau.GETARG_A = function(i) return bit32.band(bit32.rshift(i, luau.POS_A), luau.MASK1(luau.SIZE_A, 0)) end
luau.GETARG_B = function(i) return bit32.band(bit32.rshift(i, luau.POS_B), luau.MASK1(luau.SIZE_B, 0)) end
luau.GETARG_C = function(i) return bit32.band(bit32.rshift(i, luau.POS_C), luau.MASK1(luau.SIZE_C, 0)) end
luau.GETARG_Bx = function(i) return bit32.band(bit32.rshift(i, luau.POS_Bx), luau.MASK1(luau.SIZE_Bx, 0)) end
luau.GETARG_sBx = function(i) local Bx = luau.GETARG_Bx(i) local sBx = Bx + 1; if Bx > 0x7FFF and Bx <= 0xFFFF then sBx = -(0xFFFF - Bx); sBx = sBx - 1; end return sBx end
luau.GETARG_sAx = function(i) return bit32.rshift(i, 8) end
luau.GET_OPCODE = function(i) return bit32.band(bit32.rshift(i, luau.POS_OP), luau.MASK1(luau.SIZE_OP, 0)) end

local function disassemble(a1, showOps)
    if (typeof(a1):lower() == "instance") then
        if not getscriptbytecode then error("Executor does not support getscriptbytecode") end
        a1 = getscriptbytecode(a1);
    end
    
    if type(a1) == "table" then
        -- I just prefer bytecode strings
        local t = a1;
        at = "";
        for i = 1,#t do
            a1 = a1 .. string.char(t[i]);
        end
    end
    
    local output = ""
    local mainProto, protoTable, stringTable = deserialize(a1)
    local luauOpTable = getluauoptable();
    
    local function getOpCode(opName)
        for _,v in pairs(luauOpTable) do 
            if v.name == opName then 
                return v.number;
            end
        end
        return 0;
    end

    mainProto.source = "main"
    mainScope = {}; -- scope control, coming soon
    
    
    local function readProto(proto, depth)
        local output = "";
        
        local function addTabSpace(depth)
            output = output .. string.rep("    ", depth)
        end
        
        -- using function name (this will be removed & done outside of readProto)
        if proto.source then
            output = output .. proto.source .. " = function("
        else
            output = output .. "function("
        end
        
        for i = 1,proto.numParams do
            output = output .. "arg" .. (i - 1) -- args coincide with stack index
            if i < proto.numParams then
                output = output .. ", "
            end
        end
        
        if proto.isVarArg ~= 0 then
            if proto.numParams > 0 then
                output = output .. ", "
            end
            output = output .. "..."
        end
        
        output = output .. ")\n"

        depth = depth + 1
        
        for i = 1,proto.numParams do
            addTabSpace(depth);
            output = output .. string.format("local var%i = arg%i\n", i - 1, i - 1);
        end
        
        local refData = {}
        local nameCall = nil
        local markedAux = false
        local codeIndex = 1
        while codeIndex < proto.sizeCode do
            local i = proto.codeTable[codeIndex]
            local opc = luau.GET_OPCODE(i)
            local A = luau.GETARG_A(i)
            local B = luau.GETARG_B(i)
            local Bx = luau.GETARG_Bx(i)
            local C = luau.GETARG_C(i)
            local sBx = luau.GETARG_sBx(i)
            local sAx = luau.GETARG_sAx(i)
            local aux = proto.codeTable[codeIndex + 1]
            
            if markedAux then
                markedAux = false
            else
                addTabSpace(depth);
                
                local opinfo;
                
                for _,v in pairs(luauOpTable) do 
                    if v.number == opc then 
                        opinfo = v
                        break;
                    end
                end
                
                output = output .. tostring(codeIndex) .. ".   " 
                
                if showOps and opinfo then
                    local str = opinfo.name .. string.rep(" ", 16 - string.len(opinfo.name))
                    
                    if opinfo.type == "iA" then
                        str = str .. string.format("%i", A)
                    elseif opinfo.type == "iAB" then
                        str = str .. string.format("%i %i", A, B)
                    elseif opinfo.type == "iAC" then
                        str = str .. string.format("%i %i", A, C)
                    elseif opinfo.type == "iABx" then
                        str = str .. string.format("%i %i", A, Bx)
                    elseif opinfo.type == "iAsBx" then
                        str = str .. string.format("%i %i", A, sBx)
                    elseif opinfo.type == "isBx" then
                        str = str .. string.format("%i", sBx)
                    elseif opinfo.type == "iABC" then
                        str = str .. string.format("%i %i %i", A, B, C)
                    end
                    
                    if opinfo.aux then
                        str = str .. " [aux]";
                        markedAux = true
                    end
                    
                    output = output .. str .. string.rep(" ", 40 - string.len(str))
                else
                    if opinfo then
                        if opinfo.aux then
                            markedAux = true;
                        end
                    end
                end
                
                -- continue with disassembly (rough decompilation -- no scope/flow control)
                -- 
                local varsDefined = {};
                
                local function defineVar(index, name)
                    table.insert(varsDefined, { ["name"] = name, ["stackIndex"] = index });
                end
                
                local function isVarDefined(index)
                    return true;
                    --[[for _,v in pairs(varsDefined) do
                        if v.stackIndex == index then
                            return true
                        end
                    end
                    return false;
                    ]]
                end
                
                local function addReference(refStart, refEnd)
                    for _,v in pairs(refData) do
                        if v.codeIndex == refEnd then
                            table.insert(v.refs, refStart);
                            return;
                        end
                    end
                    table.insert(refData, { ["codeIndex"] = refEnd, ["refs"] = { refStart } });
                end
                
                local nilValue = { ["type"] = "nil", ["value"] = "nil" }
                
                
                --[[ TO-DO: we could make getOpCode faster by using the opcode
                numbers directly, or just getting it by table index and the 
                case-to-opcode multiplier (op * 227)
                but tbh this runs just fine
                ]]
                if opc == getOpCode("LOADNIL") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = nil", A)
                elseif opc == getOpCode("BREAK") then
                    output = output .. "break"
                elseif opc == getOpCode("LOADK") then
                    local k = proto.kTable[Bx + 1] or nilValue;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = %s", A, (type(k.value) == "string") and ("\"" .. k.value .. "\"") or tostring(k.value))
                elseif opc == getOpCode("LOADKX") then
                    local k = proto.kTable[aux + 1] or nilValue;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = %s", A, (type(k.value) == "string") and ("\"" .. k.value .. "\"") or tostring(k.value))
                elseif opc == getOpCode("LOADB") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = %s", A, tostring(B == 1))
                elseif opc == getOpCode("LOADN") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = %s", A, tostring(Bx))
                elseif opc == getOpCode("GETUPVAL") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = upvalues[%i]", A, B)
                elseif opc == getOpCode("SETUPVAL") then
                    output = output .. string.format("upvalues[%i] = var%i", B, A)
                elseif opc == getOpCode("MOVE") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i", A, B)
                elseif opc == getOpCode("LEN") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = #var%i", A, B)
                elseif opc == getOpCode("UNM") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = -var%i", A, B)
                elseif opc == getOpCode("NOT") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = not var%i", A, B)
                elseif opc == getOpCode("GETVARARGS") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = ...", A)
                elseif opc == getOpCode("CONCAT") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i .. var%i", A, B, C)
                elseif opc == getOpCode("AND") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i and var%i", A, B, C)
                elseif opc == getOpCode("OR") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i or var%i", A, B, C)
                elseif opc == getOpCode("ANDK") then
                    local k = proto.kTable[C + 1] or nilValue;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i and %s", A, B, tostring(k.value))
                elseif opc == getOpCode("ORK") then
                    local k = proto.kTable[C + 1] or nilValue;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i or %s", A, B, tostring(k.value))
                elseif opc == getOpCode("FASTCALL") then
                    output = output .. string.format("FASTCALL[id=%i]()", A, B);
                elseif opc == getOpCode("FASTCALL2") then
                    output = output .. string.format("FASTCALL[id=%i]()", A, B);
                elseif opc == getOpCode("FASTCALL2K") then
                    output = output .. string.format("FASTCALL[id=%i]()", A, B);
                elseif opc == getOpCode("GETIMPORT") then
                    local indexCount = bit32.band(bit32.rshift(aux, 30), 0x3FF) -- 0x40000000 --> 1, 0x80000000 --> 2
                    local cacheIndex1 = bit32.band(bit32.rshift(aux, 20), 0x3FF)
                    local cacheIndex2 = bit32.band(bit32.rshift(aux, 10), 0x3FF)
                    local cacheIndex3 = bit32.band(bit32.rshift(aux, 0), 0x3FF)
                    
                    if indexCount == 1 then
                        local k1 = proto.kTable[cacheIndex1 + 1];
                        
                        output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = %s", A, tostring(k1.value))
                    elseif indexCount == 2 then
                        local k1 = proto.kTable[cacheIndex1 + 1];
                        local k2 = proto.kTable[cacheIndex2 + 1];
                        
                        output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = %s[\"%s\"]", A, k1.value, tostring(k2.value))
                    elseif indexCount == 3 then
                        local k1 = proto.kTable[cacheIndex1 + 1];
                        local k2 = proto.kTable[cacheIndex2 + 1];
                        local k3 = proto.kTable[cacheIndex3 + 1];
                        
                        output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = %s[\"%s\"][\"%s\"]", A, k1.value, tostring(k2.value), tostring(k3.value))
                    else
                        error("[GETIMPORT] Too many entries");
                    end
                elseif opc == getOpCode("GETGLOBAL") then
                    local k = proto.kTable[aux + 1] or nilValue;
                    output = output .. string.format("var%i = %s", A, tostring(k.value))
                elseif opc == getOpCode("SETGLOBAL") then
                    local k = proto.kTable[aux + 1] or nilValue;
                    output = output .. string.format("%s = var%i", tostring(k.value), A)
                elseif opc == getOpCode("GETTABLE") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i[var%i]", A, B, C)
                elseif opc == getOpCode("SETTABLE") then
                    output = output .. string.format("var%i[var%i] = var%i", B, C, A)
                elseif opc == getOpCode("GETTABLEN") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i[%i]", A, B, C - 1)
                elseif opc == getOpCode("SETTABLEN") then
                    output = output .. string.format("var%i[%i] = var%i", B, C - 1, A)
                elseif opc == getOpCode("GETTABLEKS") then
                    local k = proto.kTable[aux + 1] or nilValue;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i[%s]", A, B, (type(k.value) == "string") and ("\"" .. k.value .. "\"") or tostring(k.value))
                elseif opc == getOpCode("SETTABLEKS") then
                    local k = proto.kTable[aux + 1] or nilValue;
                    output = output .. string.format("var%i[%s] = var%i", B, (type(k.value) == "string") and ("\"" .. k.value .. "\"") or tostring(k.value), A)
                elseif opc == getOpCode("NAMECALL") then
                    local k = proto.kTable[aux + 1] or nilValue;
                    nameCall = string.format("var%i:%s", B, tostring(k.value))
                    markedAux = true;
                elseif opc == getOpCode("NFORPREP") then
                    output = output .. string.format("nforprep start - [escape at #%i] -- var%i = iterator", (codeIndex + sBx) + 1, A + 3);
                elseif opc == getOpCode("NFORLOOP") then
                    output = output .. string.format("nforloop end - iterate + goto #%i", codeIndex + sBx);
                elseif opc == getOpCode("PAIRSPREP") then
                    output = output .. string.format("pairsprep start - [escape at #%i] -- var%i = key, var%i = value", (codeIndex + sBx) + 1, A + 3, A + 4);
                elseif opc == getOpCode("PAIRSLOOP") then
                    output = output .. string.format("pairsloop end - iterate + goto #%i", codeIndex + sBx);
                elseif opc == getOpCode("IPAIRSPREP") then
                    output = output .. string.format("ipairsprep start [escape at #%i] -- var%i = key, var%i = value", (codeIndex + sBx) + 1, A + 3, A + 4);
                elseif opc == getOpCode("IPAIRSLOOP") then
                    output = output .. string.format("ipairsloop end - iterate + goto #%i", codeIndex + sBx);
                elseif opc == getOpCode("TFORLOOP") then
                    output = output .. string.format("gforloop - iterate + goto #%i", codeIndex + aux);
                elseif opc == getOpCode("JUMP") then
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i", codeIndex + sBx);
                elseif opc == getOpCode("JUMPBACK") then
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i", codeIndex + sBx);
                elseif opc == getOpCode("JUMPX") then
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i", codeIndex + sAx);
                elseif opc == getOpCode("JUMPIFEQK") then
                    local k = proto.kTable[aux + 1] or nilValue;
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i if var%i == %s", codeIndex + sBx, A, (type(k.value) == "string") and ("\"" .. k.value .. "\"") or tostring(k.value));
                elseif opc == getOpCode("JUMPIFNOTEQK") then
                    local k = proto.kTable[aux + 1] or nilValue;
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i if var%i ~= %s", codeIndex + sBx, A, (type(k.value) == "string") and ("\"" .. k.value .. "\"") or tostring(k.value));
                elseif opc == getOpCode("JUMPIF") then
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i if var%i", codeIndex + sBx, A);
                elseif opc == getOpCode("JUMPIFNOT") then
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i if not var%i", codeIndex + sBx, A);
                elseif opc == getOpCode("JUMPIFEQ") then
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i if var%i == var%i", codeIndex + sBx, A, aux);
                elseif opc == getOpCode("JUMPIFNOTEQ") then
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i if var%i ~= var%i", codeIndex + sBx, A, aux);
                elseif opc == getOpCode("JUMPIFLE") then
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i if var%i <= var%i", codeIndex + sBx, A, aux);
                elseif opc == getOpCode("JUMPIFNOTLE") then
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i if var%i > var%i", codeIndex + sBx, A, aux);
                elseif opc == getOpCode("JUMPIFLT") then
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i if var%i < var%i", codeIndex + sBx, A, aux);
                elseif opc == getOpCode("JUMPIFNOTLT") then
                    addReference(codeIndex, codeIndex + sBx);
                    output = output .. string.format("goto #%i if var%i >= var%i", codeIndex + sBx, A, aux);
                elseif opc == getOpCode("ADD") then
                    output = output .. string.format("var%i = var%i + var%i", A, B, C);
                elseif opc == getOpCode("ADDK") then
                    local k = proto.kTable[C + 1] or nilValue;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i + %s", A, B, tostring(k.value));
                elseif opc == getOpCode("SUB") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i - var%i", A, B, C);
                elseif opc == getOpCode("SUBK") then
                    local k = proto.kTable[C + 1] or nilValue;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i - %s", A, B, tostring(k.value));
                elseif opc == getOpCode("MUL") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i * var%i", A, B, C);
                elseif opc == getOpCode("MULK") then
                    local k = proto.kTable[C + 1] or nilValue;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i * %s", A, B, tostring(k.value));
                elseif opc == getOpCode("DIV") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i / var%i", A, B, C);
                elseif opc == getOpCode("DIVK") then
                    local k = proto.kTable[C + 1] or nilValue;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i / %s", A, B, tostring(k.value));
                elseif opc == getOpCode("MOD") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i %% var%i", A, B, C);
                elseif opc == getOpCode("MODK") then
                    local k = proto.kTable[C + 1] or nilValue;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i %% %s", A, B, tostring(k.value));
                elseif opc == getOpCode("POW") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i ^ var%i", A, B, C);
                elseif opc == getOpCode("POWK") then
                    local k = proto.kTable[C + 1] or nilValue;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = var%i ^ %s", A, B, tostring(k.value));
                elseif opc == getOpCode("CALL") then
                    if C > 1 then
                        for j = 1, C - 1 do
                            output = output .. string.format("var%i", A + j - 1)
                            if j < C - 1 then output = output .. ", " end
                        end
                        output = output .. " = "
                    elseif C == 0 then
                        output = output .. string.format("var%i, ...", A);
                        output = output .. " = "
                        --for j = 1, proto.maxStackSize do
                        --    output = output .. string.format("var%i", A + j - 1)
                        --    if j < proto.maxStackSize - 1 then output = output .. ", " end
                        --end
                    end
                    if nameCall then
                        output = output .. nameCall .. "(";
                    else
                        output = output .. string.format("var%i(", A)
                    end
                    if B > 1 then
                        if nameCall then
                            for j = 1, B - 2 do
                                output = output .. string.format("var%i", A + 1 + j) -- exclude self
                                if j < B - 2 then output = output .. ", " end
                            end
                        else
                            for j = 1, B - 1 do
                                output = output .. string.format("var%i", A + j)
                                if j < B - 1 then output = output .. ", " end
                            end
                        end
                    elseif B == 0 then
                        output = output .. string.format("var%i, ...", A + 1);
                        --for j = 1, proto.maxStackSize do
                        --    if nameCall then
                        --        output = output .. string.format("var%i", A + 1 + j) -- exclude self
                        --    else
                        --        output = output .. string.format("var%i", A + j)
                        --    end
                        --    if j < proto.maxStackSize - 1 then output = output .. ", " end
                        --end
                    end
                    nameCall = nil;
                    output = output .. ")";
                elseif opc == getOpCode("NEWTABLE") then
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = {}", A)
                elseif opc == getOpCode("DUPTABLE") then
                    local t = proto.kTable[Bx + 1].value;
                    output = output .. (isVarDefined(A) and "" or "local ") .. string.format("var%i = { ", A)
                    for j = 1,t.size do
                        local id = t.ids[j];
                        local k = proto.kTable[id];
                        output = output .. ((type(k.value) == "string") and ("\"" .. k.value .. "\"") or tostring(k.value))
                        if j < t.size then
                            output = output .. ", ";
                        end
                    end
                    output = output .. "}";
                elseif opc == getOpCode("SETLIST") then
                    local fieldSize = aux;
                    output = output .. "\n"
                    for j = 1, C do
                        addTabSpace(depth);
                        output = output .. string.format("var%i[%i] = var%i\n", A, j + fieldSize - 1, B + j - 1);
                    end
                elseif opc == getOpCode("CAPTURE") then
                    markedAux = true;
                elseif opc == getOpCode("NEWCLOSURE") then
                    output = output .. "\n"
                    
                    local nCaptures = 0;
                    for j = codeIndex + 1, proto.sizeCode do
                        if luau.GET_OPCODE(proto.codeTable[j]) ~= getOpCode("CAPTURE") then
                            break
                        else
                            local upvalueIndex = j - codeIndex - 1;
                            local captureType = luau.GETARG_A(proto.codeTable[j]);
                            local captureIndex = luau.GETARG_Bx(proto.codeTable[j]);
                            
                            nCaptures = nCaptures + 1;
                            
                            addTabSpace(depth);
                            if captureType == 0 or captureType == 1 then
                                output = output .. string.format("-- V nested upvalues[%i] = var%i\n", upvalueIndex, captureIndex)
                            elseif captureType == 2 then
                                output = output .. string.format("-- V nested upvalues[%i] = upvalues[%i]\n", upvalueIndex, captureIndex)
                            else
                                error("[NEWCLOSURE] Invalid capture type");
                            end
                        end
                    end
                    codeIndex = codeIndex + nCaptures;
                    
                    addTabSpace(depth);
                    local nextProto = proto.pTable[Bx + 1]
                    if nextProto.source then
                        output = output .. readProto(nextProto, depth)
                        addTabSpace(depth);
                        output = output .. string.format("var%i = ", A) .. nextProto.source
                    else
                        nextProto.source = nil;
                        output = output .. string.format("var%i = ", A) .. readProto(nextProto, depth)
                    end
                elseif opc == getOpCode("DUPCLOSURE") then
                    output = output .. "\n"
                    
                    local nCaptures = 0;
                    for j = codeIndex + 1, proto.sizeCode do
                        if luau.GET_OPCODE(proto.codeTable[j]) ~= getOpCode("CAPTURE") then
                            break
                        else
                            local upvalueIndex = j - codeIndex - 1;
                            local captureType = luau.GETARG_A(proto.codeTable[j]);
                            local captureIndex = luau.GETARG_Bx(proto.codeTable[j]);
                            
                            nCaptures = nCaptures + 1;
                            
                            addTabSpace(depth);
                            if captureType == 0 or captureType == 1 then
                                output = output .. string.format("-- V nested upvalues[%i] = var%i\n", upvalueIndex, captureIndex)
                            elseif captureType == 2 then
                                output = output .. string.format("-- V nested upvalues[%i] = upvalues[%i]\n", upvalueIndex, captureIndex)
                            else
                                error("[DUPCLOSURE] Invalid capture type");
                            end
                        end
                    end
                    codeIndex = codeIndex + nCaptures;
                    
                    addTabSpace(depth);
                    local nextProto = protoTable[proto.kTable[Bx + 1].value]
                    if nextProto.source then
                        output = output .. readProto(nextProto, depth)
                        addTabSpace(depth);
                        output = output .. string.format("var%i = ", A) .. nextProto.source
                    else
                        nextProto.source = nil;
                        output = output .. string.format("var%i = ", A) .. readProto(nextProto, depth)
                    end
                elseif opc == getOpCode("RETURN") then
                    if B > 1 then
                        output = output .. "return ";
                        for j = 1, B - 1 do
                            output = output .. string.format("var%i", A + j)
                            if j < B - 1 then output = output .. ", " end
                        end
                    elseif B == 0 then
                        output = output .. string.format("var%i, ...", A)
                    end
                end
                
                for _,v in pairs(refData) do
                    if v.codeIndex == codeIndex then
                        output = output .. " -- referenced by "
                        for j = 1,#v.refs do
                            output = output .. "#" .. v.refs[j]
                            if j < #v.refs then
                                output = output .. ", "
                            end
                        end
                    end
                end
                
                output = output .. "\n"
            end
            
            codeIndex = codeIndex + 1
        end
        
        depth = depth - 1
        
        addTabSpace(depth)
        output = output .. "end\n"
        return output;
    end
    
    local startDepth = 0;
    output = output .. readProto(mainProto, startDepth)
    
    return output
end

return disassemble
