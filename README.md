# Luau Decompiler

I wrote this over the span of 2-3 days, and as of right now it ONLY produces disassembly output (psuedo-decompilation), so it's not entirely a decompiler yet.\n

It features bulletin for reference + clear identification of jumps, and for statements.\n
Instructions also include references to them.\n

Although it does not have scope control, it naturally supports function scopes.\n

Credits are much appreciated, though I don't require them.\n
I ONLY require that you don't claim originality, or say that it was written by yourself.\n

Before I move onto scope/flow control, it's important to note that a disassembler of some degree is needed to be fully capable and readable first, supporting all opcodes, so that even if the decompiler does not produce the expected output, there will be an option for disassembly. Because,  as you may know, decompilers will always be far from perfect and can never be expected to produce perfect output.\n

This script produces 2 local functions, disassemble and decompile.\n
As of right now, "decompile" is set to the disassemble function, mainly for DexV2 and other scripts that support a "decompile" function.\n

The first arg is the script, or bytecode, which can be either an encoded string or a byte table.\n
The second arg is optional, and it's a boolean. If you want to include luau opcodes in the output, pass true as the second arg.\n

Enjoy. This is a free/public project for use in any executor.\n
(my decompiler will most likely remain private)
