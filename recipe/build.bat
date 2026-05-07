@echo on
setlocal enabledelayedexpansion

REM Stage conda-forge's lua headers under the path that NetHack's
REM Makefile.nmake's LUA_MAY_PROCEED EXIST check looks at, so the
REM makefile is willing to proceed without trying to fetch lua
REM source from the network. The objects compiled from these files
REM are unused at link time because we override LUALIB to point at
REM conda-forge's import lib (see patch 0004).
mkdir lib\lua-%LUA_VERSION%\src
for %%H in (lua.h lualib.h lauxlib.h luaconf.h) do (
    copy /Y "%LIBRARY_INC%\%%H" "lib\lua-%LUA_VERSION%\src\%%H" || exit /b 1
)

REM Drop in stub .c files matching every name in LUASRCFILES so the
REM per-file compile rules in Makefile.nmake have something to read.
REM None of these objects are used at link time (see LUALIB override).
for %%S in (lapi lauxlib lbaselib lcode lcorolib lctype ldblib ldebug ^
            ldo ldump lfunc lgc linit liolib llex lmathlib lmem ^
            loadlib lobject lopcodes loslib lparser lstate lstring ^
            lstrlib ltable ltablib ltm lundump lutf8lib lvm lzio) do (
    echo /* stub */ > lib\lua-%LUA_VERSION%\src\%%S.c
)

REM NetHack expects nmake to run from src/ (where ..\lib resolves to
REM the top-level lib/). nhsetup.bat copies Makefile.nmake into src
REM as the file `Makefile`, so plain `nmake` finds it there.
cd sys\windows
call nhsetup.bat
if errorlevel 1 exit /b 1
cd %SRC_DIR%\src

REM ----------------------------------------------------------------
REM Detect cross-compile. When VSCMD_ARG_TGT_ARCH != VSCMD_ARG_HOST_ARCH
REM (e.g. building win-arm64 on a win-64 runner), the host utility
REM binaries (makedefs.exe, dlb.exe, tile2bmp.exe, uudecode.exe,
REM tilemap.exe) get built for the target arch and can't run on the
REM build host, which makedefs has to do during the build to generate
REM headers and data files.
REM
REM Workaround: do a first nmake pass in a sub-shell after activating
REM the host-arch MSVC env, building only the utility binaries; then
REM the original (cross) shell does the second pass with
REM PRECOMPILED_HOST_UTILS=Y so the makefile's util .exe rules are
REM excluded by patch 0004 and the existing .exe files are used as-is.
REM ----------------------------------------------------------------
set CROSS_COMPILE=0
if not "%VSCMD_ARG_TGT_ARCH%"=="%VSCMD_ARG_HOST_ARCH%" set CROSS_COMPILE=1

if %CROSS_COMPILE%==1 (
    echo Cross-compile detected: host=%VSCMD_ARG_HOST_ARCH% target=%VSCMD_ARG_TGT_ARCH%
    echo Pass 1: building host utility binaries with the host-arch toolchain.

    REM Run pass 1 in a separate cmd.exe so the env switch doesn't
    REM contaminate the cross-compile env we still need for pass 2.
    cmd /c "call ""%VSINSTALLDIR%VC\Auxiliary\Build\vcvarsall.bat"" %VSCMD_ARG_HOST_ARCH% && cd /d ""%SRC_DIR%\src"" && nmake INTERNET_AVAILABLE=N GIT_AVAILABLE=N LUA_VERSION=%LUA_VERSION% ""LUALIB=%LIBRARY_LIB%\lua.lib"" $(U)makedefs.exe $(U)dlb.exe $(U)tile2bmp.exe $(U)uudecode.exe $(U)tilemap.exe"
    if errorlevel 1 exit /b 1

    REM The host utility binaries are now in ..\util\ as host-arch
    REM (e.g. x64) executables. Pass 2 will see them and skip rebuild
    REM thanks to PRECOMPILED_HOST_UTILS=Y + patch 0004.
    set EXTRA_NMAKE_ARGS=PRECOMPILED_HOST_UTILS=Y
) else (
    echo Native build: host == target == %VSCMD_ARG_TGT_ARCH%.
    set EXTRA_NMAKE_ARGS=
)

echo Pass 2: building NetHack for %VSCMD_ARG_TGT_ARCH%.
nmake ^
    INTERNET_AVAILABLE=N ^
    GIT_AVAILABLE=N ^
    LUA_VERSION=%LUA_VERSION% ^
    "LUALIB=%LIBRARY_LIB%\lua.lib" ^
    %EXTRA_NMAKE_ARGS% ^
    binary
if errorlevel 1 exit /b 1

REM Move artifacts into the conda layout. The `binary` target writes
REM into ..\binary (top-level binary/). We only ship NetHack.exe (TTY
REM console build); NetHackW.exe is intentionally dropped.
cd %SRC_DIR%
if not exist "%LIBRARY_PREFIX%\share\nethack" mkdir "%LIBRARY_PREFIX%\share\nethack"
if not exist "%LIBRARY_BIN%" mkdir "%LIBRARY_BIN%"

copy /Y binary\NetHack.exe "%LIBRARY_BIN%\nethack.exe" || exit /b 1

REM Copy the data files NetHack expects at runtime: the dat archive
REM (named nhdat500 in NetHack 5.0), license, sysconf.template,
REM symbols, docs, and config templates.
xcopy /Y /E /I binary "%LIBRARY_PREFIX%\share\nethack\" || exit /b 1

REM Drop the GUI build and debug symbols that we don't ship.
del /Q "%LIBRARY_PREFIX%\share\nethack\NetHackW.exe" 2>nul
del /Q "%LIBRARY_PREFIX%\share\nethack\NetHack.PDB" 2>nul
del /Q "%LIBRARY_PREFIX%\share\nethack\NetHackW.PDB" 2>nul
