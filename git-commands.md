 ## 低频但至关重要的 Git 操作
 
 以下命令场景不常用，但遇到时能省去大量手动排查时间。
 
 > 每个功能提供三种实现：Shell 脚本（Linux/macOS）、Batch 脚本（Windows）、Python（全平台通用）。
 
 ### 1. 提取当前分支变更文件并打包
 
 **场景**：从主分支拉出特性分支后，想把当前分支上新增/修改的所有文件（保留原目录结构）打成压缩包，支持两种粒度：
 
 - **默认模式**：找到当前分支与主分支的 `merge-base`，提取全部分支变更。
 - **`-n N` 模式**：以 `HEAD~N` 为起点，只提取最近 N 个提交的变更。
 
 **脚本文件**：[pack-branch-changes.sh](pack-branch-changes.sh) / [pack-branch-changes.bat](pack-branch-changes.bat) / [pack-branch-changes.py](pack-branch-changes.py)
 
 | 参数 | 说明 |
 |------|------|
| `-n N` | 只提取最近 N 个提交的变更 |
| `-o file` | 输出文件名，默认 `branch-changes.tar.gz` |
| `base-branch` | 主分支名，默认自动检测（main / master / origin HEAD） |

 **用法**
 
 ```bash
 # Shell
 ./pack-branch-changes.sh -n 3
 
 # Python
 python pack-branch-changes.py -n 3
 ```
 
 ```cmd
 REM Windows
 pack-branch-changes.bat -n 3
 ```
 
 ```bash
 # 提取当前分支全部变更
 ./pack-branch-changes.sh
 
 # 指定输出文件名
 ./pack-branch-changes.sh -n 5 -o hotfix.tar.gz
 
 # 手动指定主分支
 ./pack-branch-changes.sh -o output.tar.gz develop
 
 # 查看压缩包
 tar -tzf branch-changes.tar.gz
```
 
 ### 2. 提取指定提交（可不连续）的变更文件并打包
 
 **场景**：在历史中挑选几个不连续的提交，把每个提交涉及的变更文件按当时版本提取出来，打包交付。如果同一个文件在多个指定提交中出现过，保留提交时间上最新的版本。
 
 **原理**：对传入的哈希列表按提交时间排序（最早在前），逐提交用 `git diff-tree` 列出变更文件，再用 `git show <commit>:<file>` 提取文件内容到临时目录。同文件多次出现时，后处理的（时间上更新的）覆盖先处理的，最终打包。
 
 **脚本文件**：[pack-commits.sh](pack-commits.sh) / [pack-commits.bat](pack-commits.bat) / [pack-commits.py](pack-commits.py)
 
 | 参数 | 说明 |
 |------|------|
| `-o file` | 输出文件名，默认 `commits-changes.tar.gz` |
| `commit ...` | 一个或多个提交哈希（支持短哈希和完整哈希） |

 **用法**
 
 ```bash
 # Shell
 ./pack-commits.sh a1b2c3d e4f5g6h
 
 # Python
 python pack-commits.py a1b2c3d e4f5g6h
 ```
 
 ```cmd
 REM Windows
 pack-commits.bat a1b2c3d e4f5g6h
 ```
 
 ```bash
 # 指定输出文件名
 ./pack-commits.sh -o selected-fixes.tar.gz abc123 def456 789xyz
 
 # 查看压缩包
 tar -tzf commits-changes.tar.gz
 ```

**行为细节**

| 条件 | 说明 |
 |------|------|
 | 提交排序 | 按提交时间从早到晚，同文件保留最新版本 |
 | 文件过滤 | 只提取新增/修改/重命名的文件（`--diff-filter=ACMR`） |
 | 目录结构 | 完全保留，解压后可直接覆盖到对应仓库路径 |
