# 批量构建脚本 (Batch Build Script)

这是一个用于在 OBS (Open Build Service) 和 EulerMaker 平台上批量创建包并触发构建的自动化脚本。

## 原理

该脚本采用**双仓库架构**来管理源码和补丁：

### 核心架构

1. **主仓库 (.git)**：管理项目的配置文件、spec 文件等构建相关文件
2. **子仓库 (.gits)**：专门管理需要修改打补丁的源码文件，与主仓库并行管理

### 工作流程

```
源码仓库 → 克隆到本地 → 创建双仓库结构 → 分支开发 → 生成补丁 → 推送构建
```

1. **初始化阶段**：
   - 克隆基础仓库到 `base_repo` 目录
   - 在同一目录下创建独立的 `.gits` 仓库用于源码管理
   - 利用git自动生成的 exclude 文件来分离不同类型的文件

2. **开发阶段**：
   - 主仓库和子仓库同步切换分支
   - 在子仓库中修改源码文件

3. **构建阶段**：
   - 生成补丁文件（基于子仓库的差异）
   - 提交本次修改
   - 推送到远程仓库并触发 OBS/EulerMaker 构建

## 功能特性

### 项目管理
- **gen**: 生成项目结构和配置文件模板 TODO
- **init**: 初始化项目，克隆仓库并设置双仓库结构
- **status**: 查看主仓库和子仓库的状态

### 仓库操作
- **switch**: 同步切换主仓库和子仓库的分支
- **patch**: 生成补丁文件到主仓库
- **commit**: 提交主仓库和子仓库的更改
- **push**: 推送分支到远程仓库并自动触发构建

### 构建管理
- **create-obs/create-euler**: 创建 OBS/EulerMaker 包并触发构建
- **build-obs/build-euler**: 重新构建指定的包
- **query-obs/query-euler**: 查询构建状态
- **query-euler-look-good**: 友好格式显示构建结果

## 使用方法

### 1. 初始化项目
```bash
# 生成项目结构
# ./batch_build.sh gen

# # 编辑配置文件
# vim .batch_build_config

# 初始化项目
./batch_build.sh init

#然后手动解压源码压缩包文件，并打上已有的补丁，如果需要的话。
#tar -zxvf helloworld-1.0.tar.gz

# 创建子仓库基础内容，作为基准
./batch_build.sh start
```

### 2. 配置文件示例
```bash
# 仓库配置
REPO_URL="https://gitee.com/your-username/your-repo.git"
REPO_URL_SSH="git@gitee.com:your-username/your-repo.git"
PACKAGE_BASE_NAME="your-package"
BRANCHES=("main" "dev" "feature")

# OBS配置
OBS_PROJECT="home:your-username:branches:openEuler:24.03:SP2:Everything"

# EulerMaker配置
EULER_PROJECT="your-username:openEuler-24.03-LTS-SP1:everything"
```

### 3. 开发流程
```bash
# 切换到开发分支
./batch_build.sh switch feature-branch

# 修改源码文件（在子仓库中）
# 修改配置文件（在主仓库中）

# 提交更改
./batch_build.sh commit "修复某个问题"

# 推送并构建
./batch_build.sh push
```

### 4. 构建管理
```bash
# 创建所有包
./batch_build.sh create-all

# 查询构建状态
./batch_build.sh query-euler-look-good

# 重新构建指定分支
./batch_build.sh build-obs fix1 fix2
```

## 核心特性

### 智能补丁处理
- 自动生成基于基准分支的差异补丁
- 智能处理补丁路径，去除多余的目录层次
- 支持复杂的目录结构

### 双平台支持
- **OBS**: 使用 osc 工具管理构建
- **EulerMaker**: 使用 ccb 工具管理构建
- 统一的状态查询和构建触发

### 批量操作
- 支持多分支并行构建
- 批量状态查询
- 灵活的参数传递

## 依赖工具

- `git`: 版本控制
- `osc`: OBS 命令行工具
- `ccb`: EulerMaker 命令行工具
- `jq`: JSON 处理

## TODO

### 架构改进
- [ ] **脚本安装化**：支持系统级安装，在任意目录都能使用
- [ ] **配置文件驱动**：完全基于配置文件工作，而非修改脚本源码
- [ ] **项目初始化**：在空白文件夹使用 `gen` 命令生成标准项目结构

### 用户体验
- [ ] 添加交互式分支选择
- [ ] 改进错误处理和提示信息
- [ ] 添加构建进度显示
- [ ] 支持配置文件验证
- [ ] 添加命令补全功能


### 技术优化
- [ ] 优化补丁生成
- [ ] 添加单元测试
- [ ] 重构代码结构，提高可维护性
- [ ] 添加配置文件模板管理

### 监控与调试
- [ ] 添加详细的日志记录

## 贡献

欢迎提交 Issue 和 Pull Request！

- **Issue**: 报告 bug、提出功能需求或改进建议
- **Pull Request**: 贡献代码、修复问题或添加新功能

现有的使用流程：
1.复制此脚本到一个空白目录
修改git地址和分支和两个构建网站的project名称
```sh
REPO_URL="https://gitee.com/yyjeqhc/hello-world.git"
REPO_BRANCH="master"
OBS_PROJECT="home:yyjeqhc:branches:openEuler:24.03:SP2:Everything"
EULER_PROJECT="swjnxyf:openEuler-24.03-LTS-SP1:everything"
```
其它的配置当然也可以修改，主要是这4个。
2. ./batch_build.sh init
会自己克隆该git仓库
3. ./batch_build.sh start
需要你先解压/打补丁，再运行这个命令
4. ./batch_build.sh switch fix1
基于最开始克隆的master分支创建新的分支作为工作区
5. ./batch_build.sh patch patch_name
修改解压的源码或者spec文件，正常修改流程
6. ./batch_build.sh commit "message"
一切修改完毕，就可以提交修改到git仓库
7. ./batch_build.sh push
提交到git，并在两个网站创建构建

其中，4 5 6 7是可以重复的，之前请务必完成1 2 3
一切操作基于git管理，熟悉git操作的话，当然也可以跳出脚本的流程束缚