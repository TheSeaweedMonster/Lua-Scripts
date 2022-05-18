# decompile.lua (Luau Disassembler)

I wrote this over the span of 2-3 days, and as of right now it ONLY produces disassembly output (psuedo-decompilation), and it's not entirely a decompiler just yet.<br>

It features bulletin for reference + clear identification of jumps, and for statements.<br>
Instructions also include references to them.<br>

Although it does not have scope control, it naturally supports function scopes.<br>

Credits are much appreciated, though I don't require them.<br>
I ONLY require that you don't claim originality for writing it<br>

Before I move onto scope/flow control, it's important to note that a disassembler of some degree is needed to be fully capable and readable first, supporting all opcodes, so that even if the decompiler does not produce the expected output, there will be an option for disassembly. Because,  as you may know, decompilers will always be far from perfect and can never be expected to produce perfect output.<br>

This script produces 2 local functions, disassemble and decompile.<br>
As of right now, "decompile" is set to the disassemble function, mainly for DexV2 and other scripts that support a "decompile" function.<br>

The first arg is the script, or bytecode, which can be either an encoded string or a byte table.<br>
The second arg is optional, and it's a boolean. If you want to include luau opcodes in the output, pass true as the second arg.<br>

This is a free/public project, intended for educational purposes.<br>
Enjoy
