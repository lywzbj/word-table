@echo off
setlocal enabledelayedexpansion
REM pack-branch-changes.bat —— 提取当前分支变更文件并打包 (Windows)
REM   用法: pack-branch-changes.bat [-n N] [output.tar.gz] [base-branch]

set OUTPUT=branch-changes.tar.gz
set COMMIT_COUNT=
set MAIN_BRANCH=
set GOT_OUTPUT=0

REM ========== 参数解析 ==========
:parse
if "%~1"=="" goto :done_parse
if /i "%~1"=="-n" (
    set COMMIT_COUNT=%~2
    shift
    shift
    goto :parse
)
if /i "%~1"=="-h" (
    echo 用法: %~nx0 [-n N] [output.tar.gz] [base-branch]
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

REM ========== 确定对比起点 ==========
if not "!COMMIT_COUNT!"=="" (
    echo [0x1b][36m提取最近 !COMMIT_COUNT! 个提交的变更[0x1b][0m
    set DIFF_BASE=HEAD~!COMMIT_COUNT!
    git rev-parse --verify "!DIFF_BASE!" >nul 2>&1
    if errorlevel 1 (
        echo [0x1b][31m错误：仓库历史不足 !COMMIT_COUNT! 个提交（!DIFF_BASE! 不存在）[0x1b][0m
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
            echo [0x1b][31m错误：无法自动检测主分支，请手动指定：%~nx0 output.tar.gz main[0x1b][0m
            exit /b 1
        )
        echo [0x1b][36m检测到主分支: !MAIN_BRANCH![0x1b][0m
    )
    for /f "tokens=*" %%a in ('git merge-base HEAD "!MAIN_BRANCH!" 2^>nul') do set DIFF_BASE=%%a
    if "!DIFF_BASE!"=="" (
        echo [0x1b][31m错误：无法确定当前分支与 !MAIN_BRANCH! 的分叉点[0x1b][0m
        exit /b 1
    )
    for /f "tokens=*" %%a in ('git rev-parse --short "!DIFF_BASE!"') do set SHORT_HASH=%%a
    echo [0x1b][36m分叉点: !SHORT_HASH![0x1b][0m
)

REM ========== 收集变更文件 ==========
echo [0x1b][36m收集变更文件...[0x1b][0m
set FILELIST=%TEMP%\pack-branch-files-%RANDOM%.txt
git diff --name-only --diff-filter=ACMR "!DIFF_BASE!" HEAD > "!FILELIST!"

call :count_lines "!FILELIST!"
set FILE_COUNT=!errorlevel!
if !FILE_COUNT! equ 0 (
    echo [0x1b][36m当前分支没有变更文件[0x1b][0m
    del "!FILELIST!" >nul 2>&1
    exit /b 0
)

REM ========== 打包 ==========
echo [0x1b][36m打包到 !OUTPUT! ...[0x1b][0m
tar -czf "!OUTPUT!" -T "!FILELIST!" >nul 2>&1
if errorlevel 1 (
    echo [0x1b][31m错误：tar 打包失败，请确认系统已安装 tar（Windows 10 1803+ 自带）[0x1b][0m
    del "!FILELIST!" >nul 2>&1
    exit /b 1
)

for %%F in ("!OUTPUT!") do set SIZE=%%~zF
call :format_size !SIZE!
echo [0x1b][32m完成！!OUTPUT! ^(!FMT_SIZE!^) —— 包含 !FILE_COUNT! 个文件[0x1b][0m

del "!FILELIST!" >nul 2>&1
exit /b 0

REM ========== 辅助函数 ==========

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
