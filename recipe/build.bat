@echo on
setlocal enabledelayedexpansion

REM Stage conda-forge's lua headers under the path that NetHack's
REM Makefile.nmake's LUA_MAY_PROCEED EXIST check looks at, so the
REM makefile is willing to proceed without trying to fetch lua
REM source from the network. The objects it would compile from these
REM headers are unused at link time because we override LUALIB to
REM point at conda-forge's import lib (see patch 0004).
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

REM nmake will pick up Makefile.nmake from sys/windows. We disable
REM the network fetch path; pdcursesmod source is already staged at
REM lib\pdcursesmod\ and lua headers are staged above. Override LUALIB
REM to link against conda-forge's lua import lib.
cd sys\windows
nmake /f Makefile.nmake ^
    INTERNET_AVAILABLE=N ^
    GIT_AVAILABLE=N ^
    LUA_VERSION=%LUA_VERSION% ^
    "LUALIB=%LIBRARY_LIB%\lua.lib" ^
    install
if errorlevel 1 exit /b 1

REM Move artifacts into the conda layout.
REM Makefile.nmake's `install` target writes into ..\binary by default.
cd %SRC_DIR%
if not exist "%LIBRARY_PREFIX%\share\nethack" mkdir "%LIBRARY_PREFIX%\share\nethack"
if not exist "%LIBRARY_BIN%" mkdir "%LIBRARY_BIN%"

copy /Y binary\NetHack.exe "%LIBRARY_BIN%\nethack.exe" || exit /b 1
xcopy /Y /E /I binary "%LIBRARY_PREFIX%\share\nethack\" || exit /b 1
