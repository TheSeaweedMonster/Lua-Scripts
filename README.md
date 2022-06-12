# decompile.lua (Luau Disassembler)

I wrote this over the last 3 days because I wanted a simple base for decompilation in Lua

It features bulletin for reference + clear identification of jumps, and for statements.<br>
Instructions also include references to them.<br>

Although it does not have scope control, it naturally supports function scopes.<br>

Credits are much appreciated, though I don't require them.<br>
I ONLY require that you don't claim originality for writing it<br>

Before I move onto scope/flow control, it's important to note that a disassembler of some degree is needed to be fully capable first, and so even if the decompiler doesn't produce the output expected, there will be an option for disassembly<br>

This script produces 2 local functions, disassemble and decompile.<br>
As of right now, "decompile" is set to the disassemble function, mainly for DexV2 and other scripts that support a "decompile" function.<br>

The first arg is the script, or bytecode, which can be either an encoded string or a byte table.<br>
The second arg is optional, and it's a boolean. If you want to include luau opcodes in the output, pass true as the second arg.<br>

This is a free/public project, intended for educational purposes.<br>
Enjoy



# Change Log

- 6/12/22 -
I removed the line `local decompile = disassemble`, so it is up to you to choose wheter to set this as the default decompilation method
