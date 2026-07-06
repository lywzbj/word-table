@echo off
setlocal enabledelayedexpansion
REM pack-commits.bat —— 提取指定提交的变更文件并打包 (Windows)
REM   用法: pack-commits.bat [-o output.tar.gz] <commit1> [commit2] [...]

set OUTPUT=commits-changes.tar.gz
set COMMIT_LIST=

REM ========== 参数解析 ==========
:parse
if "%~1"=="" goto :done_parse
if /i "%~1"=="-o" (
    set OUTPUT=%~2
    shift
    shift
    goto :parse
)
if /i "%~1"=="-h" (
    echo 用法: %~nx0 [-o output.tar.gz] ^<commit1^> [commit2] [...]
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
    echo [0x1b][31m错误：请至少指定一个提交哈希[0x1b][0m
    echo 用法: %~nx0 [-o output.tar.gz] ^<commit1^> [commit2] [...]
    exit /b 1
)

REM ========== 校验所有提交 ==========
for %%c in (!COMMIT_LIST!) do (
    git cat-file -e "%%c^{commit}" >nul 2>&1
    if errorlevel 1 (
        echo [0x1b][31m错误：%%c 不是有效的提交[0x1b][0m
        exit /b 1
    )
)

REM ========== 创建临时目录 ==========
set TEMP_DIR=%TEMP%\pack-commits-%RANDOM%
mkdir "!TEMP_DIR!" >nul 2>&1

REM ========== 按时间排序提交 ==========
echo [0x1b][36m解析提交...[0x1b][0m
set SORTED_FILE=%TEMP%\pack-commits-sorted-%RANDOM%.txt
git rev-list --no-walk --date-order --reverse !COMMIT_LIST! > "!SORTED_FILE!"

REM ========== 逐提交提取文件 ==========
for /f "tokens=*" %%c in (!SORTED_FILE!) do (
    for /f "tokens=*" %%a in ('git rev-parse --short %%c') do set SHORT=%%a
    echo [0x1b][36m处理 !SHORT! ...[0x1b][0m

    set CFILE=%TEMP%\pack-cf-%RANDOM%.txt
    git diff-tree --no-commit-id -r --name-only --diff-filter=ACMR %%c > "!CFILE!"

    for /f "tokens=*" %%f in (!CFILE!) do (
        set TARGET=!TEMP_DIR!\%%f
        for %%d in ("!TARGET!") do mkdir "%%~dpd" >nul 2>&1
        git show "%%c:%%f" > "!TARGET!" 2>nul
    )
    del "!CFILE!" >nul 2>&1
)

REM ========== 统计去重后文件数 ==========
set FILE_COUNT=0
for /f %%n in ('dir /b /s /a-d "!TEMP_DIR!" 2^>nul ^| find /c /v ""') do set FILE_COUNT=%%n

if !FILE_COUNT! equ 0 (
    echo [0x1b][36m指定提交中没有可提取的变更文件[0x1b][0m
    rmdir /s /q "!TEMP_DIR!" >nul 2>&1
    del "!SORTED_FILE!" >nul 2>&1
    exit /b 0
)

REM ========== 打包 ==========
echo [0x1b][36m打包到 !OUTPUT! ...[0x1b][0m
set OUT_FULL=%CD%\!OUTPUT!
pushd "!TEMP_DIR!"
tar -czf "!OUT_FULL!" .
popd

if errorlevel 1 (
    echo [0x1b][31m错误：tar 打包失败，请确认系统已安装 tar（Windows 10 1803+ 自带）[0x1b][0m
    rmdir /s /q "!TEMP_DIR!" >nul 2>&1
    del "!SORTED_FILE!" >nul 2>&1
    exit /b 1
)

REM ========== 输出摘要 ==========
set COMMIT_COUNT=0
for /f "tokens=*" %%a in (!SORTED_FILE!) do set /a COMMIT_COUNT+=1

for %%F in ("!OUTPUT!") do set SIZE=%%~zF
call :format_size !SIZE!
echo [0x1b][32m完成！!OUTPUT! ^(!FMT_SIZE!^) —— !COMMIT_COUNT! 个提交，去重后 !FILE_COUNT! 个文件[0x1b][0m

rmdir /s /q "!TEMP_DIR!" >nul 2>&1
del "!SORTED_FILE!" >nul 2>&1
exit /b 0

REM ========== 辅助函数 ==========

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
