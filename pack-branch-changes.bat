@echo off
setlocal enabledelayedexpansion
 REM pack-branch-changes.bat —— Package changed files from current branch (Windows)
 REM   Usage: pack-branch-changes.bat [-n N] [-o output.tar.gz] [base-branch]

set OUTPUT=branch-changes.tar.gz
set COMMIT_COUNT=
set MAIN_BRANCH=
set GOT_OUTPUT=0

 REM ========== Argument parsing ==========
:parse
if "%~1"=="" goto :done_parse
if /i "%~1"=="-n" (
    set COMMIT_COUNT=%~2
    shift
    shift
    goto :parse
)
if /i "%~1"=="-h" (
     echo Usage: %~nx0 [-n N] [-o output.tar.gz] [base-branch]
    exit /b 0
)
if !GOT_OUTPUT! equ 0 (
    set OUTPUT=%~1
    set GOT_OUTPUT=1
    shift
    goto :parse
)
set MAIN_BRANCH=%~1
shift
goto :parse

:done_parse

 REM ========== Determine diff base ==========
if not "!COMMIT_COUNT!"=="" (
     echo [0x1b][36mPackaging changes from last !COMMIT_COUNT! commit(s)[0x1b][0m
    set DIFF_BASE=HEAD~!COMMIT_COUNT!
    git rev-parse --verify "!DIFF_BASE!" >nul 2>&1
    if errorlevel 1 (
         echo [0x1b][31mError: not enough history for !COMMIT_COUNT! commits (!DIFF_BASE! does not exist)[0x1b][0m
        exit /b 1
    )
) else (
    if "!MAIN_BRANCH!"=="" (
        for /f "tokens=2 delims=:" %%a in ('git remote show origin 2^>nul ^| findstr "HEAD branch"') do (
            for /f "tokens=*" %%b in ("%%a") do set MAIN_BRANCH=origin/%%b
        )
        if "!MAIN_BRANCH!"=="" (
            git show-ref --verify --quiet refs/heads/main >nul 2>&1 && set MAIN_BRANCH=main
        )
        if "!MAIN_BRANCH!"=="" (
            git show-ref --verify --quiet refs/heads/master >nul 2>&1 && set MAIN_BRANCH=master
        )
        if "!MAIN_BRANCH!"=="" (
             echo [0x1b][31mError: cannot auto-detect main branch, specify manually: %~nx0 -o output.tar.gz main[0x1b][0m
            exit /b 1
        )
         echo [0x1b][36mDetected base branch: !MAIN_BRANCH![0x1b][0m
    )
    for /f "tokens=*" %%a in ('git merge-base HEAD "!MAIN_BRANCH!" 2^>nul') do set DIFF_BASE=%%a
    if "!DIFF_BASE!"=="" (
         echo [0x1b][31mError: cannot determine merge-base with !MAIN_BRANCH![0x1b][0m
        exit /b 1
    )
    for /f "tokens=*" %%a in ('git rev-parse --short "!DIFF_BASE!"') do set SHORT_HASH=%%a
     echo [0x1b][36mMerge base: !SHORT_HASH![0x1b][0m
)

 REM ========== Collect changed files ==========
 echo [0x1b][36mCollecting changed files...[0x1b][0m
set FILELIST=%TEMP%\pack-branch-files-%RANDOM%.txt
git diff --name-only --diff-filter=ACMR "!DIFF_BASE!" HEAD > "!FILELIST!"

call :count_lines "!FILELIST!"
set FILE_COUNT=!errorlevel!
if !FILE_COUNT! equ 0 (
     echo [0x1b][36mNo changed files[0x1b][0m
    del "!FILELIST!" >nul 2>&1
    exit /b 0
)

 REM ========== Package ==========
 echo [0x1b][36mPackaging to !OUTPUT! ...[0x1b][0m
tar -czf "!OUTPUT!" -T "!FILELIST!" >nul 2>&1
if errorlevel 1 (
     echo [0x1b][31mError: tar failed, make sure tar is installed (built-in since Windows 10 1803)[0x1b][0m
    del "!FILELIST!" >nul 2>&1
    exit /b 1
)

for %%F in ("!OUTPUT!") do set SIZE=%%~zF
call :format_size !SIZE!
 echo [0x1b][32mDone: !OUTPUT! ^(!FMT_SIZE!^) -- !FILE_COUNT! file(s)[0x1b][0m

del "!FILELIST!" >nul 2>&1
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
