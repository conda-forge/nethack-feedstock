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

REM Disable the network fetch path; pdcursesmod source is staged at
REM lib\pdcursesmod\ and lua headers staged above. Override LUALIB so
REM nethack links against conda-forge's lua DLL via its import lib.
nmake ^
    INTERNET_AVAILABLE=N ^
    GIT_AVAILABLE=N ^
    LUA_VERSION=%LUA_VERSION% ^
    "LUALIB=%LIBRARY_LIB%\lua.lib" ^
    binary
if errorlevel 1 exit /b 1

REM Move artifacts into the conda layout. The `binary` target writes
REM into ..\binary (top-level binary/). We only ship NetHack.exe (TTY
REM console build); NetHackW.exe is intentionally dropped.
cd %SRC_DIR%
if not exist "%LIBRARY_PREFIX%\share\nethack" mkdir "%LIBRARY_PREFIX%\share\nethack"
if not exist "%LIBRARY_BIN%" mkdir "%LIBRARY_BIN%"

copy /Y binary\NetHack.exe "%LIBRARY_BIN%\nethack.exe" || exit /b 1
for %%F in (nhdat370 nhdat sysconf license symbols Guidebook.txt opthelp) do (
    if exist "binary\%%F" copy /Y "binary\%%F" "%LIBRARY_PREFIX%\share\nethack\" >nul
)
if exist binary\recover.exe copy /Y binary\recover.exe "%LIBRARY_PREFIX%\share\nethack\" >nul
