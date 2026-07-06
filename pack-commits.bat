@echo off
setlocal enabledelayedexpansion
REM pack-commits.bat -- Package changed files from specified commits (Windows)
REM   Usage: pack-commits.bat [-o output.tar.gz] <commit1> [commit2] [...]

set OUTPUT=commits-changes.tar.gz
set COMMIT_LIST=

REM ========== Argument parsing ==========
:parse
if "%~1"=="" goto :done_parse
if /i "%~1"=="-o" (
    set OUTPUT=%~2
    shift
    shift
    goto :parse
)
if /i "%~1"=="-h" (
    echo Usage: %~nx0 [-o output.tar.gz] ^<commit1^> [commit2] [...]
    exit /b 0
)
if "!COMMIT_LIST!"=="" (
    set COMMIT_LIST=%~1
) else (
    set COMMIT_LIST=!COMMIT_LIST! %~1
)
shift
goto :parse

:done_parse

if "!COMMIT_LIST!"=="" (
    echo [0x1b][31mError: at least one commit hash is required[0x1b][0m
    exit /b 1
)

REM ========== Validate commits ==========
for %%c in (!COMMIT_LIST!) do (
    git cat-file -e "%%c^{commit}" >nul 2>&1
    if errorlevel 1 (
        echo [0x1b][31mError: %%c is not a valid commit[0x1b][0m
        exit /b 1
    )
)

REM ========== Create temp directory ==========
set TEMP_DIR=%TEMP%\pack-commits-%RANDOM%
mkdir "!TEMP_DIR!" >nul 2>&1

REM ========== Sort commits by date ==========
echo [0x1b][36mResolving commits...[0x1b][0m
set SORTED_FILE=%TEMP%\pack-commits-sorted-%RANDOM%.txt
git rev-list --no-walk --date-order --reverse !COMMIT_LIST! > "!SORTED_FILE!"

REM ========== Extract files per commit ==========
for /f "tokens=*" %%c in (!SORTED_FILE!) do (
    for /f "tokens=*" %%a in ('git rev-parse --short %%c') do set SHORT=%%a
    echo [0x1b][36mProcessing !SHORT! ...[0x1b][0m

    set CFILE=%TEMP%\pack-cf-%RANDOM%.txt
    git diff-tree --no-commit-id -r --name-only --diff-filter=ACMR %%c > "!CFILE!"

    for /f "tokens=*" %%f in (!CFILE!) do (
        set TARGET=!TEMP_DIR!\%%f
        for %%d in ("!TARGET!") do mkdir "%%~dpd" >nul 2>&1
        git show "%%c:%%f" > "!TARGET!" 2>nul
    )
    del "!CFILE!" >nul 2>&1
)

REM ========== Count unique files ==========
set FILE_COUNT=0
for /f %%n in ('dir /b /s /a-d "!TEMP_DIR!" 2^>nul ^| find /c /v ""') do set FILE_COUNT=%%n

if !FILE_COUNT! equ 0 (
    echo [0x1b][36mNo changed files[0x1b][0m
    rmdir /s /q "!TEMP_DIR!" >nul 2>&1
    del "!SORTED_FILE!" >nul 2>&1
    exit /b 0
)

REM ========== Build CHANGELOG.md ==========
set CL_FILE=!TEMP_DIR!\CHANGELOG.md
(
    echo # Change Log
    echo(
    echo Generated: %date% %time%
) > "!CL_FILE!"

for /f "tokens=*" %%a in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set BRANCH=%%a
if "!BRANCH!"=="" set BRANCH=(detached)
echo Branch: !BRANCH!>> "!CL_FILE!"
echo(>> "!CL_FILE!"

set COMMIT_COUNT=0
for /f "tokens=*" %%a in (!SORTED_FILE!) do set /a COMMIT_COUNT+=1
echo ## Commits (!COMMIT_COUNT!)>> "!CL_FILE!"
echo(>> "!CL_FILE!"

for /f "tokens=*" %%c in (!SORTED_FILE!) do call :write_commit_entry %%c "!CL_FILE!"

REM ========== Package ==========
echo [0x1b][36mPackaging to !OUTPUT! ...[0x1b][0m
set OUT_FULL=%CD%\!OUTPUT!
pushd "!TEMP_DIR!"
tar -czf "!OUT_FULL!" .
popd

if errorlevel 1 (
    echo [0x1b][31mError: tar failed[0x1b][0m
    rmdir /s /q "!TEMP_DIR!" >nul 2>&1
    del "!SORTED_FILE!" >nul 2>&1
    exit /b 1
)

for %%F in ("!OUTPUT!") do set SIZE=%%~zF
call :format_size !SIZE!
echo [0x1b][32mDone: !OUTPUT! ^(!FMT_SIZE!^) -- !COMMIT_COUNT! commit(s), !FILE_COUNT! unique file(s)[0x1b][0m

rmdir /s /q "!TEMP_DIR!" >nul 2>&1
del "!SORTED_FILE!" >nul 2>&1
exit /b 0

REM ========== Subroutine: write one commit to changelog ==========
:write_commit_entry
set CH=%~1
set CLF=%~2

for /f "tokens=*" %%s in ('git rev-parse --short !CH!') do set HSHORT=%%s
for /f "tokens=*" %%b in ('git log --format^=%%s -n1 !CH!') do set SUBJ=%%b
(
    echo ### !HSHORT! - !SUBJ!
    echo(
) >> "!CLF!"

set CF_TMP=%TEMP%\pack-cf2-%RANDOM%.txt
git diff-tree --no-commit-id -r --name-only --diff-filter=ACMR !CH! > "!CF_TMP!" 2>nul

call :count_lines "!CF_TMP!"
if !errorlevel! gtr 0 (
    (
        echo ^| File ^|
        echo ^|------^|
    ) >> "!CLF!"
    for /f "tokens=*" %%f in (!CF_TMP!) do (
        echo ^| `%%f` ^|>> "!CLF!"
    )
) else (
    echo - no files ->> "!CLF!"
)
echo(>> "!CLF!"
del "!CF_TMP!" >nul 2>&1
exit /b 0

REM ========== Helpers ==========

:count_lines
setlocal
set /a cnt=0
for /f "tokens=*" %%a in (%~1) do set /a cnt+=1
endlocal & exit /b %cnt%

:format_size
setlocal
set bytes=%1
if %bytes% lss 1024 (
    set size_str=%bytes%B
) else if %bytes% lss 1048576 (
    set /a kb=%bytes%/1024
    set size_str=!kb!K
) else (
    set /a mb=%bytes%/1048576
    set size_str=!mb!M
)
endlocal & set FMT_SIZE=%size_str%
exit /b 0
