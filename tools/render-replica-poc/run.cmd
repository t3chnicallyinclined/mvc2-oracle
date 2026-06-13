@echo off
REM Option-C PoC: generate -> build -> run all validations (single vcvars init).
setlocal
cd /d "%~dp0"
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

echo === [1/6] LIFT: generate C from SH4 disasm ===
python gen_leaf.py >nul 2>&1 || goto :err
python gen_walker.py || goto :err
python gen_transform.py || goto :err
python make_transform_test.py || goto :err

echo.
echo === [2/6] LEAF loc_8C11E460 (bit-exact vs reference floorf) ===
del *.obj >nul 2>&1
cl /nologo /O2 /fp:precise /Fe:test_leaf.exe gen_leaf.c test_leaf.c >nul 2>&1
.\test_leaf.exe | findstr /C:"exact"

echo.
echo === [3/6] TRANSFORM-CORE loc_8c0347c8..864 (vs ASMTRACE; bit-exact vs ref float) ===
del *.obj >nul 2>&1
cl /nologo /O2 /fp:precise /Fe:test_transform.exe gen_transform.c test_transform.c >nul 2>&1
.\test_transform.exe | findstr /C:"BIT-EXACT" /C:"X:" /C:"Y:"

echo.
echo === [4/6] FULL WALKER loc_8c0344d4 (compile+link+run, stack-balanced) ===
del *.obj >nul 2>&1
cl /nologo /O2 /fp:precise /Fe:test_walker.exe gen_walker.c gen_leaf.c leaves.c test_walker_compile.c >nul 2>&1
.\test_walker.exe | findstr /C:"FULL-WALKER"

echo.
echo === [5/6] FULL WALKER NUMERIC (REAL dump descriptors @0x8C1F9F9C; 0.00px vs ASMTRACE) ===
python build_image_dump.py | findstr /C:"REAL descriptors" /C:"rec sel"
del *.obj >nul 2>&1
cl /nologo /O2 /fp:precise /Fe:test_walker_dump.exe gen_walker.c gen_leaf.c test_walker_dump.c >nul 2>&1
echo   -- with REAL descriptors:
.\test_walker_dump.exe | findstr /C:"FULL-WALKER NUMERIC" /C:"RESULT"
echo   -- negative control [descriptors zeroed; MUST fail, proves non-circular]:
.\test_walker_dump.exe zerodesc | findstr /C:"FULL-WALKER NUMERIC" /C:"RESULT"

echo.
echo === [6/6] TA-EMIT: walker -^> submit-corners -^> NATIVE PVR TA QUADS ===
python gen_submit.py || goto :err
del *.obj >nul 2>&1
cl /nologo /O2 /fp:precise /Fe:test_ta_emit.exe gen_walker.c gen_leaf.c gen_submit.c test_ta_emit.c >nul 2>&1
.\test_ta_emit.exe | findstr /C:"TA-EMIT" /C:"CORNER-CHECK" /C:"RESULT"
echo   -- verify the emitted ta_buffer.bin parses through the REAL web ta-parser.mjs:
where node >nul 2>&1 && node verify_ta.mjs | findstr /C:"ta-parser" /C:"VERIFY"
echo   [NOTE] step [6]'s TCW/TSP-BITEXACT uses build_image_dump.py's idxtab[sel] indexing
echo          which is STALE (pal28); the UN-PINNED Phase-1 path below (step [7]) supersedes it.

echo.
echo === [7/7] PHASE-1: render_object_full -- FULLY CODE-DERIVED per-object (NO pinning) ===
echo     loc_8c03093c transform(+0xE0/E4) + scale(+0xEC/F0) + submit-params(PCW/ISP/TSP/TCW)
echo     ALL computed from resident RAM; ZERO engine-TA reads.
python gen_render_object.py >nul 2>&1 || goto :err
python build_image_full.py | findstr /C:"discovered base" /C:"node+0xE0"
del *.obj >nul 2>&1
cl /nologo /O2 /fp:precise /Fe:test_render_object_full.exe gen_render_object.c gen_transform_obj.c gen_submit_params.c gen_walker.c gen_leaf.c test_render_object_full.c >nul 2>&1
.\test_render_object_full.exe | findstr /C:"ANCHOR" /C:"SCALE" /C:"byte-exact vs engine" /C:"WALKER produced" /C:"RESULT"
echo   -- pixel converge: fully-computed TA vs engine GT through the gold-standard renderer:
where node >nul 2>&1 && node converge_full_computed.mjs | findstr /C:"PARAM byte-exact"
where node >nul 2>&1 && node render_ta.mjs --ta ta_computed.bin --vram ..\..\_ryu_capture\mc_vram_dump.bin --pvr ..\..\_ryu_capture\mc_pvr_regs.bin --out PNG_computed.png >nul 2>&1
where node >nul 2>&1 && node render_ta.mjs --ta ta_engine_corners.bin --vram ..\..\_ryu_capture\mc_vram_dump.bin --pvr ..\..\_ryu_capture\mc_pvr_regs.bin --out PNG_gt_full.png >nul 2>&1
where node >nul 2>&1 && node diff_png.mjs PNG_gt_full.png PNG_computed.png --tol 0 | findstr /C:"match" /C:"diff pixels" /C:"max"

echo.
echo === [8/8] PHASE-2: render_frame -- WHOLE-FRAME slot-walk (loc_8c0308c2), ALL bodies ===
echo     transpiled root walk + CURSOR-DERIVED per-object rectab base (node+0xDC prefix-sum).
python gen_walker_root.py >nul 2>&1 || goto :err
python build_image_frame.py | findstr /C:"body object" /C:"body L"
del *.obj >nul 2>&1
cl /nologo /O2 /fp:precise /Fe:render_frame_test.exe gen_walker_root.c render_frame.c gen_render_object.c gen_transform_obj.c gen_submit_params.c gen_walker.c gen_leaf.c render_frame_test.c >nul 2>&1
.\render_frame_test.exe | findstr /C:"render_frame:" /C:"CURSOR PROOF" /C:"byte-exact" /C:"SYNTH" /C:"RESULT"
echo   -- pixel converge: whole-scene BODY TA vs engine bodies through the gold renderer:
where node >nul 2>&1 && node converge_frame.mjs | findstr /C:"PARAM byte-exact"
where node >nul 2>&1 && node render_ta.mjs --ta ta_frame_render.bin --vram ..\..\_ryu_capture\mc_vram_dump.bin --pvr ..\..\_ryu_capture\mc_pvr_regs.bin --out PNG_frame_render.png >nul 2>&1
where node >nul 2>&1 && node render_ta.mjs --ta ta_frame_engine.bin --vram ..\..\_ryu_capture\mc_vram_dump.bin --pvr ..\..\_ryu_capture\mc_pvr_regs.bin --out PNG_frame_engine.png >nul 2>&1
where node >nul 2>&1 && node diff_png.mjs PNG_frame_engine.png PNG_frame_render.png --tol 0 | findstr /C:"match" /C:"diff pixels"
goto :eof
:err
echo GEN FAILED
exit /b 1
