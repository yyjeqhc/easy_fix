#!/bin/bash

# 批量构建脚本
# 用于在OBS和EulerMaker平台创建包并触发构建

set -e

# 默认配置文件路径
CONFIG_FILE=".batch_build_config"
WORKDIR=$(pwd)

# 默认配置（可被配置文件覆盖）
REPO_URL="https://gitee.com/yyjeqhc/hello-world.git"
REPO_BRANCH="master"
REPO_URL_SSH="git@gitee.com:yyjeqhc/hello-world.git"
BRANCHES=("fix1" "fix2" "fix3")
PACKAGE_BASE_NAME="hello-world"
OBS_PROJECT="home:yyjeqhc:branches:openEuler:24.03:SP2:Everything"
EULER_PROJECT="swjnxyf:openEuler-24.03-LTS-SP1:everything"
BASE_REPO_DIR="base_repo"
WORK_REPO_DIR="work_repo"
GIT_DIR=".git"
GITS_DIR=".gits"
GIT_EXCLUDE_FILE="$GIT_DIR/info/exclude"
GITS_EXCLUDE_FILE="$GITS_DIR/info/exclude"

# 加载配置文件
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "加载配置文件: $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

create_obs_package() {
    if [ $# -ne 1 ]; then
        echo "用法: create_obs_package branch_name"
        return 1
    fi

    local branch="$1";
    local package_name="${PACKAGE_BASE_NAME}-${branch}"
        log_info "创建OBS包: $package_name"
        
        # 创建包元数据
        echo "<package name=\"$package_name\" project=\"$OBS_PROJECT\">
  <title>$package_name</title>
  <description>Auto-generated package for branch $branch</description>
</package>" | osc meta pkg "$OBS_PROJECT" "$package_name" -F - || true
        
        # 创建_service文件
        cat > "/tmp/obs_service_${PACKAGE_BASE_NAME}_${branch}_$$" << EOF
<services>
        <service name="tar_scm">
                <param name="scm">git</param>
                <param name="url">${REPO_URL_SSH}</param>
                <param name="revision">${branch}</param>
                <param name="exclude">*</param>
                <param name="extract">*</param>
        </service>
</services>
EOF
        
        # # 检出包并上传_service文件
        # rm -rf "${OBS_PROJECT}" || true
        osc checkout "$OBS_PROJECT" "$package_name" || true
        
        if [[ -d "${OBS_PROJECT}/${package_name}" ]]; then
            cd "${OBS_PROJECT}/${package_name}"
            cp "/tmp/obs_service_${PACKAGE_BASE_NAME}_${branch}_$$" _service
            osc add _service || true
            osc commit -m "创建${package_name}包，分支${branch}" || true
            cd ../..
        else
            log_error "无法检出包: $package_name"
        fi
        
        # 清理临时文件
        rm -f "/tmp/obs_service_${PACKAGE_BASE_NAME}_${branch}_$$"
        
        log_info "OBS包创建完成: $package_name"
}
# 创建OBS包
create_obs_packages() {
    log_info "开始创建OBS包..."
    if [ $# -gt 0 ]; then
        for arg in "$@"; do
            echo "处理参数：$arg"
            create_obs_package $arg
        done
    else
        for branch in "${BRANCHES[@]}"; do
            create_obs_package "$branch"
        done
    fi
}

create_euler_package() {
    if [ $# -ne 1 ]; then
        echo "用法: create_euler_package branch_name"
        return 1
    fi

    local branch="$1";

    local package_name="${PACKAGE_BASE_NAME}-${branch}"
        log_info "创建EulerMaker包: $package_name"
        
        # 创建包的JSON配置
        cat > "/tmp/euler_config_${PACKAGE_BASE_NAME}_${branch}_$$" << EOF
{
  "package_repos+": [
    {
      "spec_name": "$package_name",
      "spec_url": "$REPO_URL",
      "spec_branch": "$branch",
      "spec_description": "Auto-generated package for branch $branch"
    }
  ]
}
EOF
        
        # 向项目添加包
        log_info "向项目添加包..."
        ccb update projects "$EULER_PROJECT" --json "/tmp/euler_config_${PACKAGE_BASE_NAME}_${branch}_$$" || true
        
        # 等待一下让包创建完成
        sleep 2
        
        # 触发构建
        log_info "触发构建..."
        ccb build-single os_project="$EULER_PROJECT" packages="$package_name" || true
        
        log_info "EulerMaker包创建完成: $package_name"
        
        # 清理临时文件
        rm -f "/tmp/euler_config_${PACKAGE_BASE_NAME}_${branch}_$$"
}
# 创建EulerMaker包
create_euler_packages() {
    log_info "开始创建EulerMaker包..."
    
    if [ $# -gt 0 ]; then
        for arg in "$@"; do
            echo "处理参数：$arg"
            create_euler_package $arg
        done
    else
        for branch in "${BRANCHES[@]}"; do
            create_euler_package "$branch"
        done
    fi
}

# 查询OBS构建状态
query_obs_status() {
    log_info "查询OBS构建状态..."
    local package_name
    if [ $# -gt 0 ]; then
        for arg in "$@"; do
            package_name="${PACKAGE_BASE_NAME}-${arg}"
            log_info "查询OBS包状态: $package_name"
            osc results "$OBS_PROJECT" "$package_name" || true
            echo "---"
        done
    else
        for branch in "${BRANCHES[@]}"; do
            package_name="${PACKAGE_BASE_NAME}-${branch}"
            log_info "查询OBS包状态: $package_name"
            osc results "$OBS_PROJECT" "$package_name" || true
            echo "---"
        done
    fi
}

#obs进行构建包
build_obs() {
    log_info "在OSB平台进行构建..."
    local package_name
    if [ $# -gt 0 ]; then
        for arg in "$@"; do
            package_name="${PACKAGE_BASE_NAME}-${arg}"
            osc rebuildpac $OBS_PROJECT $package_name
        done
    else
        for branch in "${BRANCHES[@]}"; do
            package_name="${PACKAGE_BASE_NAME}-${branch}"
            osc rebuildpac $OBS_PROJECT $package_name
        done
    fi
}

#euler进行构建包
build_euler() {
    log_info "在EulerMaker平台进行构建..."
    local package_name
    if [ $# -gt 0 ]; then
        for arg in "$@"; do
            package_name="${PACKAGE_BASE_NAME}-${arg}"
            ccb build-single os_project="$EULER_PROJECT" packages="$package_name"
        done
    else
        for branch in "${BRANCHES[@]}"; do
            package_name="${PACKAGE_BASE_NAME}-${branch}"
            ccb build-single os_project="$EULER_PROJECT" packages="$package_name"
        done
    fi
}

query_euler() {
    local branch="$1"
    local package_name="${PACKAGE_BASE_NAME}-${branch}"
    echo "[$package_name]"
    
    # 查询包的最新构建记录，按架构分组
    local builds_result=$(ccb select builds packages="$package_name" \
        -s create_time:desc 2>/dev/null || echo '[]')
    
    if command -v jq >/dev/null 2>&1 && [[ "$builds_result" != "[]" ]]; then
        # 按架构分组，显示每个架构的最新状态
        echo "$builds_result" | jq -r '
            if length > 0 then
                [.[] | ._source] |
                sort_by(.create_time) | reverse |
                group_by(.build_target.architecture) |
                map(.[0]) |
                .[] |
                .build_target.architecture + ": " + 
                (if .status == 201 then "succeeded"
                    elif .status == 202 then "failed"  
                    elif .status == 200 then "building"
                    elif .status == 203 then
                    if .published_status == 2 then "succeeded" else "finished" end
                    else (.status | tostring) end)
            else
                "无构建记录"
            end
        ' 2>/dev/null | sort
    else
        echo "无构建记录"
    fi
    echo ""
}
# 查询EulerMaker构建状态
query_euler_status() {
    log_info "查询EulerMaker构建状态..."
    local package_name
    if [ $# -gt 0 ]; then
        for arg in "$@"; do
            # package_name="${PACKAGE_BASE_NAME}-${arg}"
            query_euler $arg
        done
    else
        for branch in "${BRANCHES[@]}"; do
            # package_name="${PACKAGE_BASE_NAME}-${branch}"
            query_euler $branch
        done
    fi
}

query_euler_look_good() {
    log_info "聚合查询状态汇总..."

    local targets=()

    if [ $# -gt 0 ]; then
        targets=("$@")   # 使用传入参数
    else
        targets=("${BRANCHES[@]}")   # 使用默认列表
    fi       
    # 表头
    printf "%-20s %-15s %-15s %-15s %-15s\n" "包名" "架构" "系统版本" "状态" "时间"
    echo "$(printf '%.80s' "$(printf '%*s' 80 | tr ' ' '-')")"
    
    for branch in "${targets[@]}"; do
        local package_name="${PACKAGE_BASE_NAME}-${branch}"
        
        # 使用builds表查询
        local query_result=$(ccb select builds packages="$package_name" os_project="$EULER_PROJECT" 2>/dev/null)
        
        if [[ -n "$query_result" ]]; then
            echo "$query_result" | jq -r --arg pkg "$package_name" '
                if length > 0 then
                    .[] | 
                    select(._source.os_project == "'"$EULER_PROJECT"'") |
                    ._source as $build |
                    [$pkg, $build.build_target.architecture, $build.build_target.os_variant, 
                        (if $build.status == 201 then "成功" 
                        elif $build.status == 202 then "失败"
                        elif $build.status == 203 then "已完成"
                        elif $build.status == 103 then "构建中"
                        elif $build.status == 200 then "构建成功"
                        else ($build.status | tostring) end),
                        ($build.create_time // "未知")] | 
                    @tsv
                else
                    [$pkg, "N/A", "N/A", "无数据", "N/A"] | @tsv
                end
            ' 2>/dev/null | sort -k5 -r | sort -k2,2 -k3,3 -u | while IFS=$'\t' read -r pkg arch os status time; do
                # 根据状态着色
                case "$status" in
                    "成功") color="$GREEN" ;;
                    "失败") color="$RED" ;;
                    "构建中") color="$YELLOW" ;;
                    *) color="$NC" ;;
                esac
                printf "%-20s %-15s ${color}%-15s${NC} %-15s\n" "$pkg" "$arch" "$status" "$time"
            done
        else
            printf "%-20s %-15s %-15s %-15s %-15s\n" "$package_name" "N/A" "N/A" "无数据" "N/A"
        fi
    done
}

# 查询详细构建状态
query_builds_detail() {
    log_info "详细查询构建状态..."
    
    for branch in "${BRANCHES[@]}"; do
        local package_name="${PACKAGE_BASE_NAME}-${branch}"
        log_info "=== 包: $package_name ==="
        
        # 查询包的基本信息
        log_info "包的基本信息:"
        ccb select projects os_project="$EULER_PROJECT" | grep -A3 -B3 "$package_name" || echo "未找到包信息"
        
        # 查询构建状态
        log_info "构建状态查询:"
        ccb select builds packages="$package_name" || echo "未找到构建记录"
        
        # 查询job信息
        log_info "Job信息查询:"
        ccb select jobs packages="$package_name" -f job_id,status,start_time,end_time,architecture || echo "未找到job信息"
        
        echo "=================================================="
    done
}

# 生成项目结构
gen_project() {
    log_info "生成批量构建项目结构..."
    
    # 创建项目目录
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"
    
    # 创建配置文件模板
    cat > "$CONFIG_FILE" << EOF
# 批量构建配置文件
# 仓库配置
REPO_URL="https://gitee.com/your-username/your-repo.git"
REPO_URL_SSH="git@gitee.com:your-username/your-repo.git"
PACKAGE_BASE_NAME="your-package"
BRANCHES=("main" "dev" "feature")

# OBS配置
OBS_PROJECT="home:your-username:branches:openEuler:24.03:SP2:Everything"

# EulerMaker配置  
EULER_PROJECT="your-username:openEuler-24.03-LTS-SP1:everything"

# 仓库目录配置
BASE_REPO_DIR="base_repo"
WORK_REPO_DIR="work_repo"
EOF

    # 创建目录结构
    mkdir -p logs
    mkdir -p tmp
    
    log_info "项目结构生成完成!"
    log_info "请编辑 $CONFIG_FILE 配置文件，然后运行 'init' 初始化项目"
}

# 初始化项目
init_project() {
    log_info "初始化批量构建项目..."
    
    # 加载配置
    load_config
    
    # 验证配置
    if [[ -z "$REPO_URL" || "$REPO_URL" == *"your-"* ]]; then
        log_error "请先编辑 $CONFIG_FILE 配置文件，设置正确的仓库地址"
        return 1
    fi
    
    log_info "配置验证通过:"
    echo "  仓库: $REPO_URL"
    echo "  包名: $PACKAGE_BASE_NAME"
    echo "  分支: ${BRANCHES[*]}"
    echo "  OBS项目: $OBS_PROJECT"
    echo "  EulerMaker项目: $EULER_PROJECT"
    
    # 克隆基准仓库
    clone_base_repo
    
    # 设置工作仓库
    # setup_work_repo
    
    log_info "项目初始化完成,请手动解压压缩包并打上补丁"
    log_info "简而言之，准备好.gits仓库的基准分支的内容"
    log_info "准备好后，请运行 start子命令"
}

create_sub_repo() {
    cd "$BASE_REPO_DIR"
    
    # 检查当前分支
    local current_branch=$(git --git-dir=$GITS_DIR branch --show-current 2>/dev/null || echo "")
    if [[ -n "$current_branch" && "$current_branch" != "$REPO_BRANCH" ]]; then
        log_error "当前分支 ($current_branch) 不是基准分支 ($REPO_BRANCH)"
        return 1
    fi
    
    # 添加所有文件
    git --git-dir=$GITS_DIR add .
    
    # 检查是否有实际要提交的内容
    if git --git-dir=$GITS_DIR diff --cached --quiet; then
        log_warn "没有要提交的内容"
        return 0
    fi
    
    git --git-dir=$GITS_DIR commit -m "commit as the basic branch"
}
# 设置基准仓库
clone_base_repo() {
    log_info "设置基准仓库..."
    if [[ -d "$BASE_REPO_DIR" ]]; then
        log_warn "基准仓库目录已存在，跳过克隆"
        return 0
    fi
    
    # 克隆仓库
    log_info "克隆基准仓库: $REPO_URL"
    git clone "$REPO_URL" "$BASE_REPO_DIR" --branch "$REPO_BRANCH" --depth 1 
    cd "$BASE_REPO_DIR"


    git --git-dir=$GITS_DIR --work-tree=. init -b "$REPO_BRANCH"

    # 创建必要的目录结构
    mkdir -p "$GITS_DIR/info"

    # 收集扩展名（文件类型）
    exts=$(find . -type f -not -path "./.gits/*" | sed -n 's/.*\.\([a-zA-Z0-9]\+\)$/\1/p' | sort -u)

    # 收集一级目录名（不含 .gits）
    dirs=$(find . -mindepth 1 -maxdepth 1 -type d ! -name ".gits" -printf "%P\n")

    # 开始写入 exclude 文件
    {
        echo "# Auto-generated by gen_gits_exclude.sh"
        echo

        # 忽略所有类型文件
        for ext in $exts; do
            echo "*.$ext"
        done

        # 忽略所有目录
        for dir in $dirs; do
            echo "/$dir"
        done

        # 忽略主仓库自己的 .git
        echo "/.gits"
    } > "$GITS_EXCLUDE_FILE"

    {
        echo "# Auto-generated by gen_gits_exclude.sh"
        echo

        # 忽略所有类型文件
        for ext in $exts; do
            echo "!*.$ext"
        done

        # 忽略所有目录
        for dir in $dirs; do
            echo "!/$dir"
        done

        # 忽略所有新建的目录
        echo "*/"

        # 忽略主仓库自己的 .git
        echo "/.gits"
    } > "$GIT_EXCLUDE_FILE"
}

# 设置工作仓库
# setup_work_repo() {
#     log_info "设置工作仓库..."
    
#     if [[ -d "$WORK_REPO_DIR" ]]; then
#         log_warn "工作仓库目录已存在，跳过设置"
#         return 0
#     fi
    
#     # 克隆仓库
#     log_info "克隆工作仓库: $REPO_URL"
#     git clone "$REPO_URL" "$WORK_REPO_DIR"
    
#     cd "$WORK_REPO_DIR"
    
#     # 设置git配置
#     git config user.name "$(git config --global user.name || echo 'Batch Builder')"
#     git config user.email "$(git config --global user.email || echo 'builder@example.com')"
    
#     cd "$WORKDIR"
#     log_info "工作仓库设置完成: $WORK_REPO_DIR"
# }

# 切换到指定分支
switch_branch() {
    local branch="$1"
    
    if [[ -z "$branch" ]]; then
        log_warn "未指定分支名称，TODO: 实现分支列表显示功能"
        return 0
    fi
    
    log_info "切换到分支: $branch"
    
    # 检查主仓库是否干净
    cd "$BASE_REPO_DIR"
    if ! git diff --quiet || ! git diff --cached --quiet; then
        log_error "主仓库有未提交的更改，请先提交或保存"
        git status
        return 1
    fi
    
    # 检查子仓库是否干净
    if ! git --git-dir=$GITS_DIR diff --quiet || ! git --git-dir=$GITS_DIR diff --cached --quiet; then
        log_error "子仓库有未提交的更改，请先提交或保存"
        git --git-dir=$GITS_DIR status
        return 1
    fi
    
    # 处理主仓库分支切换
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        # 主仓库本地分支存在，直接切换
        git checkout "$branch"
        log_info "主仓库已切换到分支: $branch"
    elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        # 远程分支存在，创建本地分支
        git checkout -b "$branch" "origin/$branch"
        log_info "主仓库创建并切换到分支: $branch (基于远程分支)"
    else
        # 创建新分支（基于当前分支，通常是基准分支）
        git checkout -b "$branch"
        log_info "主仓库创建新分支: $branch"
    fi
    
    # 处理子仓库分支切换
    if git --git-dir=$GITS_DIR show-ref --verify --quiet "refs/heads/$branch"; then
        # 子仓库本地分支存在，直接切换
        git --git-dir=$GITS_DIR checkout "$branch"
        log_info "子仓库已切换到分支: $branch"
    else
        # 创建新分支（基于当前分支，通常是基准分支）
        git --git-dir=$GITS_DIR checkout -b "$branch"
        log_info "子仓库创建新分支: $branch"
    fi
    
    cd "$WORKDIR"
    log_info "分支切换完成: $branch"
}

#应该取基准分支，然后diff
patch_repo() {
    local patch_file="$1"
    
    # 检查参数
    if [[ -z "$patch_file" ]]; then
        log_error "请指定补丁文件名"
        return 1
    fi
    
    # 检查文件扩展名
    if [[ "$patch_file" != *.patch ]]; then
        log_error "补丁文件必须以 .patch 结尾"
        return 1
    fi
    
    log_info "生成补丁文件: $patch_file"
    
    cd "$BASE_REPO_DIR"
    
    # 生成子仓库的 diff 到指定文件
    git --git-dir=$GITS_DIR diff $REPO_BRANCH> "$patch_file"
    
    # 检查是否生成了内容
    if [[ ! -s "$patch_file" ]]; then
        log_warn "补丁文件为空，没有差异需要导出"
        rm -f "$patch_file"
        return 0
    fi
    
    log_info "补丁文件已生成: $patch_file"
    # log_info "文件大小: $(wc -l < "$patch_file") 行"
}
# 提交更改
commit_changes() {
    local message="$1"
    
    if [[ -z "$message" ]]; then
        message="for build"
    fi
    
    log_info "提交更改: $message"
    
    cd "$BASE_REPO_DIR"
    
    # 处理主仓库提交
    local main_has_changes=false
    
    # 检查主仓库是否有更改（包括未跟踪的文件）
    if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git status --porcelain)" ]]; then
        main_has_changes=true
        log_info "主仓库有更改，准备提交"
        
        # 添加所有更改
        git add .
        
        # 提交
        git commit -m "$message"
        log_info "主仓库更改已提交"
    else
        log_info "主仓库没有更改需要提交"
    fi
    
    # 处理子仓库提交
    local sub_has_changes=false
    
    # 检查子仓库是否有更改（包括未跟踪的文件）
    if ! git --git-dir=$GITS_DIR diff --quiet || ! git --git-dir=$GITS_DIR diff --cached --quiet || [[ -n "$(git --git-dir=$GITS_DIR status --porcelain)" ]]; then
        sub_has_changes=true
        log_info "子仓库有更改，准备提交"
        
        # 添加所有更改
        git --git-dir=$GITS_DIR add .
        
        # 提交
        git --git-dir=$GITS_DIR commit -m "$message"
        log_info "子仓库更改已提交"
    else
        log_info "子仓库没有更改需要提交"
    fi
    
    cd "$WORKDIR"
    
    if [[ "$main_has_changes" == true || "$sub_has_changes" == true ]]; then
        log_info "提交完成: $message"
    else
        log_info "没有更改需要提交"
    fi
}

# 推送到远程仓库
push_changes() {
    log_info "开始推送当前分支到远程仓库"
    
    cd "$BASE_REPO_DIR"
    
    # 获取当前分支名称
    local current_branch=$(git branch --show-current)
    if [[ -z "$current_branch" ]]; then
        log_error "无法获取当前分支名称或处于分离头指针状态"
        return 1
    fi
    
    log_info "当前分支: $current_branch"
    
    # 检查是否有远程origin
    if ! git remote | grep -q "origin"; then
        log_error "没有找到远程仓库origin"
        return 1
    fi
    
    # 检查当前分支是否有未提交的更改
    if ! git diff --quiet HEAD; then
        log_error "当前分支有未提交的更改，请先提交"
        return 1
    fi
    
    # 推送到远程仓库并设置上游跟踪
    log_info "推送分支 $current_branch 到远程origin并设置上游跟踪..."
    if git push --set-upstream origin "$current_branch"; then
        log_info "分支 $current_branch 已成功推送并设置上游跟踪"
    else
        log_error "推送分支失败"
        return 1
    fi
    
    log_info "推送操作完成"
    create_euler_package "$current_branch"
    create_obs_package "$current_branch"
    log_info "OBS和EulerMaker包已创建并开始构建"
}

# 编辑文件（在工作仓库中）
edit_file() {
    local file_path="$1"
    local content="$2"
    
    if [[ -z "$file_path" ]]; then
        log_error "请指定文件路径"
        return 1
    fi
    
    local full_path="$WORK_REPO_DIR/$file_path"
    local dir_path=$(dirname "$full_path")
    
    # 创建目录（如果不存在）
    mkdir -p "$dir_path"
    
    if [[ -n "$content" ]]; then
        # 写入内容
        echo "$content" > "$full_path"
        log_info "文件已更新: $file_path"
    else
        # 编辑文件（使用默认编辑器）
        ${EDITOR:-nano} "$full_path"
        log_info "文件编辑完成: $file_path"
    fi
}

# 查看工作区状态
status_work_repo() {
    log_info "工作仓库状态:"
    
    cd "$WORK_REPO_DIR"
    
    echo "当前分支: $(git branch --show-current)"
    echo "工作区状态:"
    git status --short
    
    echo "最近提交:"
    git log --oneline -5
    
    cd "$WORKDIR"
}

# 主函数
main() {
    # 加载配置文件
    load_config
    
    case "${1:-help}" in
        "gen")
            gen_project
            ;;
        "init")
            init_project
            ;;
        "start")
            create_sub_repo
            ;;
        "switch")
            switch_branch "$2"
            ;;
        "patch")
            patch_repo "$2"
            ;;
        "commit")
            commit_changes "$2"
            ;;
        "push")
            push_changes
            ;;
        "edit")
            edit_file "$2" "$3"
            ;;
        "status")
            status_work_repo
            ;;
        "create-obs")
            shift   # 去掉 $1（即"create-obs"）
            create_obs_packages "$@"
            ;;
        "create-euler")
            shift
            create_euler_packages "$@"
            ;;
        "create-all")
            create_obs_packages
            create_euler_packages
            ;;
        "query-obs")
            shift
            query_obs_status "$@"
            ;;
        "query-euler")
            shift
            query_euler_status "$@"
            ;;
        "query-all")
            query_obs_status
            query_euler_status
            ;;
        "build-obs")
            shift
            build_obs "$@"
            ;;
        "build-euler")
            shift
            build_euler "$@"
            ;;
        "build-all")
            build_obs
            build_euler
            ;;
        "query-quler-look-good")
            shift
            query_euler_look_good "$@"
            ;;
        #功能无效
        # "status-summary")
        #     log_info "构建状态汇总..."
            
        #     echo "=========================================="
        #     echo "               构建状态汇总"
        #     echo "=========================================="
        #     printf "%-20s %-10s %-15s %-15s\n" "包名" "架构" "总体状态" "包构建状态"
        #     echo "------------------------------------------"
            
        #     for branch in "${BRANCHES[@]}"; do
        #         local package_name="${PACKAGE_BASE_NAME}-${branch}"
                
        #         # 使用ccb select查询构建状态
        #         local builds_result=$(ccb select builds packages="$package_name" os_project="$EULER_PROJECT" \
        #             -f build_target,status,build_packages \
        #             -s create_time:desc 2>/dev/null || echo '[]')
                
        #         if command -v jq >/dev/null 2>&1 && [[ "$builds_result" != "[]" ]]; then
        #             # 按架构分组，取每个架构的最新记录
        #             echo "$builds_result" | jq -r '
        #                 group_by(._source.build_target.architecture) | 
        #                 .[] | .[0] |
        #                 ._source.build_target.architecture + " " +
        #                 (if ._source.status == 201 then "构建中"
        #                  elif ._source.status == 203 then "已完成"
        #                  else (._source.status | tostring) end) + " " +
        #                 (if ._source.build_packages then
        #                     (._source.build_packages | to_entries[0].value.build.status |
        #                     if . == 103 then "构建中"
        #                     elif . == 200 then "成功"
        #                     elif . >= 400 then "失败"
        #                     else (. | tostring) end)
        #                  else "无包构建信息" end)
        #             ' 2>/dev/null | while read arch overall_status pkg_status; do
        #                 if [[ -n "$arch" ]]; then
        #                     printf "%-20s %-10s %-15s %-15s\n" "$package_name" "$arch" "$overall_status" "$pkg_status"
        #                 fi
        #             done
        #         else
        #             printf "%-20s %-10s %-15s %-15s\n" "$package_name" "未知" "无记录" "无记录"
        #         fi
        #     done
            
        #     echo "=========================================="
        #     ;;
        #功能无效
        # "query-precise-status")
        #     log_info "精确查询构建状态..."
            
        #     for branch in "${BRANCHES[@]}"; do
        #         local package_name="${PACKAGE_BASE_NAME}-${branch}"
        #         echo "========================================"
        #         echo "包名: $package_name"
        #         echo "========================================"
                
        #         # 使用正确的ccb select语法查询构建状态
        #         log_info "查询最新构建记录..."
        #         local builds_result=$(ccb select builds packages="$package_name" os_project="$EULER_PROJECT" \
        #             -f build_id,status,create_time,build_target,build_packages \
        #             -s create_time:desc 2>/dev/null || echo '[]')
                
        #         if command -v jq >/dev/null 2>&1 && [[ "$builds_result" != "[]" ]]; then
        #             # 从ccb select的结果中提取_source字段
        #             echo "$builds_result" | jq -r '.[0:3][] | 
        #                 "架构: " + ._source.build_target.architecture + 
        #                 " | 总体状态: " + 
        #                 (if ._source.status == 201 then "构建中" 
        #                  elif ._source.status == 203 then "已完成" 
        #                  else (._source.status | tostring) end) +
        #                 " | 包构建状态: " +
        #                 (if ._source.build_packages then
        #                     (._source.build_packages | to_entries[0].value.build.status |
        #                     if . == 103 then "构建中"
        #                     elif . == 200 then "成功"
        #                     elif . >= 400 then "失败"
        #                     else (. | tostring) end)
        #                  else "无包构建信息" end) +
        #                 " | 创建时间: " + ._source.create_time +
        #                 " | 构建ID: " + ._source.build_id' 2>/dev/null || echo "JSON解析失败"
        #         else
        #             echo "未找到构建记录或需要安装jq"
        #         fi
                
        #         echo ""
        #     done
        #     ;;
        #功能无效
        # "query-status-friendly")
        #     log_info "友好显示构建状态..."
            
        #     for branch in "${BRANCHES[@]}"; do
        #         local package_name="${PACKAGE_BASE_NAME}-${branch}"
        #         echo "========================================"
        #         echo "包名: $package_name"
        #         echo "========================================"
                
        #         # 查询最新构建状态
        #         local builds_json=$(ccb select builds packages="$package_name" -s create_time:desc | head -20)
                
        #         if [[ -n "$builds_json" && "$builds_json" != "[]" ]]; then
        #             echo "$builds_json" | jq -r '.[] | select(._source.create_time != null) | "架构: " + ._source.build_target.architecture + 
        #                 " | 状态: " + (._source.status | tostring) + 
        #                 " | 创建时间: " + ._source.create_time + 
        #                 " | 构建ID: " + ._source.build_id' 2>/dev/null || echo "JSON解析失败"
        #         else
        #             echo "未找到构建记录"
        #         fi
                
        #         echo ""
        #     done
        #     ;;
        # "query-builds-detail")
        #     #太细节了
        #     query_builds_detail
        #     ;;
        # "debug-projects")
        #     log_info "查询可用的项目..."
            
        #     # 查询所有项目
        #     ccb select projects || echo "无法查询项目"
            
        #     # 查询包含当前用户的项目
        #     ccb select projects | grep -i "swjnxyf\|yyjeqhc" || echo "未找到相关项目"
        #     ;;
#         "test-obs-single")
#             log_info "测试创建单个OBS包..."
#             local test_branch="fix1"
#             local package_name="${PACKAGE_BASE_NAME}-${test_branch}"
            
#             # 创建包元数据
#             echo "<package name=\"$package_name\" project=\"$OBS_PROJECT\">
#   <title>$package_name</title>
#   <description>Test package for branch $test_branch</description>
# </package>" | osc meta pkg "$OBS_PROJECT" "$package_name" -F - || true
            
#             log_info "OBS包元数据创建完成: $package_name"
#             ;;
#         "test-euler-single")
#             log_info "测试创建单个EulerMaker包..."
#             local test_branch="fix1"
#             local package_name="${PACKAGE_BASE_NAME}-${test_branch}"
            
#             # 创建包的JSON配置
#             cat > "/tmp/test_euler_config_$$" << EOF
# {
#   "package_repos+": [
#     {
#       "spec_name": "$package_name",
#       "spec_url": "$REPO_URL",
#       "spec_branch": "$test_branch",
#       "spec_description": "Test package for branch $test_branch"
#     }
#   ]
# }
# EOF
            
#             # 向项目添加包
#             log_info "向项目添加包..."
#             ccb update projects "$EULER_PROJECT" --json "/tmp/test_euler_config_$$" || true
            
#             # 清理临时文件
#             rm -f "/tmp/test_euler_config_$$"
#             ;;
#         "test-build-single")
#             log_info "测试触发单个包构建..."
#             local test_branch="fix1"
#             local package_name="${PACKAGE_BASE_NAME}-${test_branch}"
            
#             # 触发EulerMaker构建
#             log_info "触发EulerMaker构建..."
#             ccb build-single os_project="$EULER_PROJECT" packages="$package_name" || true
#             ;;
#         "test-query-single")
#             log_info "测试查询单个包状态..."
#             local test_branch="fix1"
#             local package_name="${PACKAGE_BASE_NAME}-${test_branch}"
            
#             # 查询OBS状态
#             log_info "查询OBS状态..."
#             osc results "$OBS_PROJECT" "$package_name" || true
            
#             echo "---"
            
#             # 查询EulerMaker状态
#             log_info "查询EulerMaker状态..."
#             ccb select builds os_project="$EULER_PROJECT" package_name="$package_name" || true
#             ;;
#         "status-codes")
#             cat << EOF
# EulerMaker构建状态码说明:

# 构建状态 (status):
#   201 - 构建进行中
#   203 - 构建已完成
  
# 包构建状态 (build_packages.*.build.status):
#   103 - 包构建进行中
#   200 - 包构建成功
#   400+ - 包构建失败
  
# 发布状态 (published_status):
#   0 - 未发布
#   1 - 发布中
#   2 - 已发布
# EOF
#             ;;
        # "cleanup")
        #     log_info "清理测试数据..."
            
        #     # 清理临时文件
        #     rm -f /tmp/obs_service_${PACKAGE_BASE_NAME}_*
        #     rm -f /tmp/euler_config_${PACKAGE_BASE_NAME}_*
        #     rm -f /tmp/test_euler_config_*
            
        #     # 清理OBS检出目录
        #     rm -rf "${OBS_PROJECT}" || true
            
        #     log_info "清理完成"
        #     ;;
        # "debug-euler")
        #     log_info "调试EulerMaker配置..."
        #     echo "项目: $EULER_PROJECT"
        #     echo "仓库: $REPO_URL"
        #     echo "分支: ${BRANCHES[*]}"
            
        #     # 查询项目是否存在
        #     log_info "查询项目信息..."
        #     ccb select projects | grep "$EULER_PROJECT" || echo "项目不存在或无权限"
            
        #     # 测试ccb工具
        #     log_info "测试ccb工具..."
        #     ccb --help || echo "ccb工具有问题"
        #     ;;
        # "debug-query")
        #     log_info "调试查询结果..."
            
        #     local package_name="hello-world-fix3"
        #     log_info "测试查询包: $package_name"
            
        #     # 测试基本查询
        #     echo "=== 基本查询 ==="
        #     ccb select builds packages="$package_name" || echo "基本查询失败"
            
        #     echo "=== 带项目名查询 ==="
        #     ccb select builds packages="$package_name" os_project="$EULER_PROJECT" || echo "带项目名查询失败"
            
        #     echo "=== 带字段过滤查询 ==="
        #     ccb select builds packages="$package_name" os_project="$EULER_PROJECT" \
        #         -f build_target,status,build_packages || echo "字段过滤查询失败"
            
        #     echo "=== 带排序查询 ==="
        #     ccb select builds packages="$package_name" os_project="$EULER_PROJECT" \
        #         -f build_target,status,build_packages \
        #         -s create_time:desc || echo "排序查询失败"
        #     ;;
        #不好用
        # "query-aggregated")
        #     log_info "使用聚合查询构建状态..."
            
        #     for branch in "${BRANCHES[@]}"; do
        #         local package_name="${PACKAGE_BASE_NAME}-${branch}"
        #         log_info "=== 聚合查询包: $package_name ==="
                
        #         # 先尝试基本jobs查询
        #         log_info "基本jobs查询..."
        #         local basic_jobs=$(ccb select jobs packages="$package_name" 2>/dev/null)
        #         if [[ -n "$basic_jobs" && "$basic_jobs" != "[]" ]]; then
        #             echo "基本jobs查询有结果，解析中..."
        #             echo "$basic_jobs" | jq -r '
        #                 if type == "array" and length > 0 then
        #                     .[] | 
        #                     "Job ID: " + (._source.job_id // "未知") + 
        #                     " | 状态: " + (._source.status | tostring) + 
        #                     " | 架构: " + (._source.architecture // "未知") + 
        #                     " | 开始时间: " + (._source.start_time // "未知")
        #                 else
        #                     "jobs查询结果为空或格式不符合预期"
        #                 end
        #             ' 2>/dev/null || echo "jobs查询解析失败"
        #         else
        #             log_info "基本jobs查询无结果，尝试builds查询..."
        #             local basic_builds=$(ccb select builds packages="$package_name" 2>/dev/null)
        #             if [[ -n "$basic_builds" && "$basic_builds" != "[]" ]]; then
        #                 echo "builds查询有结果，解析中..."
        #                 echo "$basic_builds" | jq -r '
        #                     if type == "array" and length > 0 then
        #                         .[] | 
        #                         "Build ID: " + (._source.build_id // "未知") + 
        #                         " | 状态: " + (._source.status | tostring) + 
        #                         " | 架构: " + (._source.build_target.architecture // "未知") + 
        #                         " | 创建时间: " + (._source.create_time // "未知")
        #                     else
        #                         "builds查询结果为空或格式不符合预期"
        #                     end
        #                 ' 2>/dev/null || echo "builds查询解析失败"
        #             else
        #                 log_warn "包 $package_name 在jobs和builds表中都无记录"
        #             fi
        #         fi
                
        #         # 尝试聚合查询（如果基本查询有结果）
        #         if [[ -n "$basic_jobs" && "$basic_jobs" != "[]" ]] || [[ -n "$basic_builds" && "$basic_builds" != "[]" ]]; then
        #             log_info "尝试聚合查询..."
        #             local query_result=$(ccb select jobs packages="$package_name" os_project="$EULER_PROJECT" \
        #                 -a group_by_architecture/group_by_os_variant/latest_build_info 2>/dev/null)
                    
        #             if [[ -n "$query_result" ]]; then
        #                 echo "$query_result" | jq -r '
        #                     if type == "object" and has("aggregations") then
        #                         .aggregations.group_by_architecture.buckets[] | 
        #                         "架构: " + .key + " (" + (.doc_count | tostring) + " 个构建)" |
        #                         . as $arch_info |
        #                         (.group_by_os_variant.buckets[] | 
        #                             "  系统版本: " + .key + " (" + (.doc_count | tostring) + " 个构建)" |
        #                             . as $os_info |
        #                             (.latest_build_info.hits.hits[]._source | 
        #                                 "    状态: " + (.status | tostring) + " (" + 
        #                                 (if .status == 201 then "成功" 
        #                                  elif .status == 202 then "失败" 
        #                                  elif .status == 103 then "构建中" 
        #                                  else "未知" end) + ")" +
        #                                 " 时间: " + (.create_time // "未知")
        #                             )
        #                         )
        #                     else
        #                         "无聚合数据或数据格式不符合预期"
        #                     end
        #                 ' 2>/dev/null || echo "聚合查询解析失败"
        #             else
        #                 log_info "聚合查询无结果"
        #             fi
        #         fi
        #         echo
        #     done
        #     ;;
        #重复了，只是查Eulermaker的包
        # "status-overview")
        #     log_info "构建状态总览..."
            
        #     # 统计各状态的数量
        #     local total_packages=0
        #     local success_count=0
        #     local failed_count=0
        #     local building_count=0
        #     local completed_count=0
            
        #     echo "包名               总体状态     x86_64       aarch64      riscv64      "
        #     echo "--------------------------------------------------------------------------------"
            
        #     for branch in "${BRANCHES[@]}"; do
        #         local package_name="${PACKAGE_BASE_NAME}-${branch}"
        #         local query_result=$(ccb select builds packages="$package_name" os_project="$EULER_PROJECT" 2>/dev/null)
                
        #         if [[ -n "$query_result" ]]; then
        #             # 统计各架构的状态
        #             local arch_status=$(echo "$query_result" | jq -r '
        #                 if length > 0 then
        #                     [.[] | select(._source.os_project == "'"$EULER_PROJECT"'") | ._source] |
        #                     sort_by(.create_time) | reverse |
        #                     group_by(.build_target.architecture) |
        #                     map({
        #                         arch: .[0].build_target.architecture,
        #                         status: .[0].status,
        #                         status_text: (if .[0].status == 201 then "成功" 
        #                                      elif .[0].status == 202 then "失败"
        #                                      elif .[0].status == 203 then "完成"
        #                                      elif .[0].status == 103 then "构建中"
        #                                      elif .[0].status == 200 then "构建成功"
        #                                      else (.[0].status | tostring) end)
        #                     }) |
        #                     {
        #                         x86_64: (map(select(.arch == "x86_64")) | if length > 0 then .[0].status_text else "无" end),
        #                         aarch64: (map(select(.arch == "aarch64")) | if length > 0 then .[0].status_text else "无" end),
        #                         riscv64: (map(select(.arch == "riscv64")) | if length > 0 then .[0].status_text else "无" end)
        #                     } |
        #                     [.x86_64, .aarch64, .riscv64] | @tsv
        #                 else
        #                     ["无", "无", "无"] | @tsv
        #                 end
        #             ' 2>/dev/null)
                    
        #             if [[ -n "$arch_status" ]]; then
        #                 IFS=$'\t' read -r x86_status aarch64_status riscv64_status <<< "$arch_status"
                        
        #                 # 判断总体状态
        #                 local overall_status="未知"
        #                 if [[ "$x86_status" == "成功" && "$aarch64_status" == "成功" ]]; then
        #                     overall_status="✅ 全部成功"
        #                     success_count=$((success_count + 1))
        #                 elif [[ "$x86_status" == "失败" || "$aarch64_status" == "失败" ]]; then
        #                     overall_status="❌ 有失败"
        #                     failed_count=$((failed_count + 1))
        #                 elif [[ "$x86_status" == "构建中" || "$aarch64_status" == "构建中" ]]; then
        #                     overall_status="🔄 构建中"
        #                     building_count=$((building_count + 1))
        #                 elif [[ "$x86_status" == "完成" || "$aarch64_status" == "完成" ]]; then
        #                     overall_status="✅ 已完成"
        #                     completed_count=$((completed_count + 1))
        #                 fi
                        
        #                 printf "%-20s %-15s %-12s %-12s %-12s\n" "$package_name" "$overall_status" "$x86_status" "$aarch64_status" "$riscv64_status"
        #             else
        #                 printf "%-20s %-15s %-12s %-12s %-12s\n" "$package_name" "无数据" "无" "无" "无"
        #             fi
        #         else
        #             printf "%-20s %-15s %-12s %-12s %-12s\n" "$package_name" "无数据" "无" "无" "无"
        #         fi
        #         total_packages=$((total_packages + 1))
        #     done
            
        #     echo "--------------------------------------------------------------------------------"
        #     echo "总计: $total_packages 个包 | 成功: $success_count | 失败: $failed_count | 构建中: $building_count | 已完成: $completed_count"
        #     ;;
        #还是重复了，不如look-good
        # "results")
        #     log_info "类似osc results的构建状态查询..."
            
        #     # 简洁的构建状态表格，类似osc results
        #     printf "%-20s %-12s %-15s\n" "包名" "架构" "状态"
        #     echo "---------------------------------------------------"
            
        #     for branch in "${BRANCHES[@]}"; do
        #         local package_name="${PACKAGE_BASE_NAME}-${branch}"
                
        #         # 查询最新构建状态
        #         local builds_result=$(ccb select builds packages="$package_name" \
        #             -s create_time:desc 2>/dev/null || echo '[]')
                
        #         if command -v jq >/dev/null 2>&1 && [[ "$builds_result" != "[]" ]]; then
        #             # 按架构分组，每个架构只显示最新状态
        #             echo "$builds_result" | jq -r --arg pkg "$package_name" '
        #                 if length > 0 then
        #                     [.[] | ._source] |
        #                     sort_by(.create_time) | reverse |
        #                     group_by(.build_target.architecture) |
        #                     map(.[0]) |
        #                     .[] |
        #                     [$pkg, .build_target.architecture, 
        #                      (if .status == 201 then "已成功"
        #                       elif .status == 202 then "已失败"
        #                       elif .status == 200 then "构建中"
        #                       elif .status == 203 then
        #                         # 构建已完成（旧版本），检查发布状态
        #                         if .published_status == 2 then "已成功" else "已完成" end
        #                       else (.status | tostring) end)] | 
        #                     @tsv
        #                 else
        #                     [$pkg, "N/A", "无记录"] | @tsv
        #                 end
        #             ' 2>/dev/null | while IFS=$'\t' read -r pkg arch status; do
        #                 # 根据状态着色
        #                 case "$status" in
        #                     "已成功"|"成功"|"已完成") color="$GREEN" ;;
        #                     "已失败"|"失败") color="$RED" ;;
        #                     "构建中") color="$YELLOW" ;;
        #                     *) color="$NC" ;;
        #                 esac
        #                 printf "%-20s %-12s ${color}%-15s${NC}\n" "$pkg" "$arch" "$status"
        #             done
        #         else
        #             printf "%-20s %-12s %-15s\n" "$package_name" "N/A" "无记录"
        #         fi
        #     done
        #     ;;
        #还是重复的
        # "results-detailed")
        #     log_info "详细构建状态查询（类似osc results -v）..."
            
        #     printf "%-20s %-12s %-15s %-15s %-20s\n" "包名" "架构" "状态" "构建ID" "创建时间"
        #     echo "--------------------------------------------------------------------------------"
            
        #     for branch in "${BRANCHES[@]}"; do
        #         local package_name="${PACKAGE_BASE_NAME}-${branch}"
                
        #         # 查询详细构建状态
        #         local builds_result=$(ccb select builds packages="$package_name" os_project="$EULER_PROJECT" \
        #             -f build_id,status,create_time,build_target,build_packages \
        #             -s create_time:desc 2>/dev/null || echo '[]')
                
        #         if command -v jq >/dev/null 2>&1 && [[ "$builds_result" != "[]" ]]; then
        #             # 显示详细信息
        #             echo "$builds_result" | jq -r --arg pkg "$package_name" '
        #                 if length > 0 then
        #                     [.[] | ._source] |
        #                     sort_by(.create_time) | reverse |
        #                     group_by(.build_target.architecture) |
        #                     map(.[0]) |
        #                     .[] |
        #                     [$pkg, .build_target.architecture, 
        #                      (if .status == 201 then "已成功"
        #                       elif .status == 202 then "已失败"
        #                       elif .status == 200 then "构建中"
        #                       elif .status == 203 then
        #                         # 构建已完成（旧版本），检查发布状态
        #                         if .published_status == 2 then "已成功" else "已完成" end
        #                       else (.status | tostring) end),
        #                      .build_id[0:12],
        #                      (.create_time // "未知")] | 
        #                     @tsv
        #                 else
        #                     [$pkg, "N/A", "无记录", "N/A", "N/A"] | @tsv
        #                 end
        #             ' 2>/dev/null | while IFS=$'\t' read -r pkg arch status build_id create_time; do
        #                 # 根据状态着色
        #                 case "$status" in
        #                     "已成功"|"成功"|"已完成") color="$GREEN" ;;
        #                     "已失败"|"失败") color="$RED" ;;
        #                     "构建中") color="$YELLOW" ;;
        #                     *) color="$NC" ;;
        #                 esac
        #                 printf "%-20s %-12s ${color}%-15s${NC} %-15s %-20s\n" "$pkg" "$arch" "$status" "$build_id" "$create_time"
        #             done
        #         else
        #             printf "%-20s %-12s %-15s %-15s %-20s\n" "$package_name" "N/A" "无记录" "N/A" "N/A"
        #         fi
        #     done
        #     ;;
#     query-builds-detail  详细查询构建状态
#   query-status-friendly  友好显示构建状态
#   query-precise-status   精确查询构建状态(推荐)
#   query-aggregated       聚合查询构建状态(最新)
#   query-aggregated-summary  聚合查询状态汇总表(推荐)
#   status-summary         构建状态汇总表
#   status-overview        构建状态总览
  
# 测试命令:
#   test-obs-single     测试创建单个OBS包
#   test-euler-single   测试创建单个EulerMaker包
#   test-build-single   测试触发单个包构建
#   test-query-single   测试查询单个包状态
#   cleanup             清理测试数据

  
# 调试命令:
#   debug-projects  调试项目查询
#   debug-euler     调试EulerMaker配置
#   debug-query     调试查询结果
#   status-codes    显示状态码说明
# results         简洁构建状态查询（类似osc results）
        "help"|*)
            cat << EOF
批量构建脚本使用说明:

项目管理命令:
  gen             生成项目结构和配置文件
  init            初始化项目，克隆仓库
  status          查看工作仓库状态
  
仓库操作命令:
  switch <branch> 切换到指定分支
  edit <file>     编辑工作仓库中的文件
  commit <branch> [message] 提交更改
  push <branch>   推送分支到远程仓库

构建管理命令:
  create-obs      创建所有OBS包，并构建
  create-euler    创建所有EulerMaker包，并构建
  create-all      创建所有平台的包，并构建
  query-obs       查询OBS构建状态
  query-euler     查询EulerMaker构建状态
  query-all       查询所有平台构建状态
  build-obs       构建OBS包
  build-euler     构建EulerMaker包
  build-all       构建所有平台的包
  query-quler-look-good 友好展示构建结果

示例:
  $0 create-all   # 创建所有包
  $0 query-all    # 查询所有状态
  $0 debug-euler  # 调试EulerMaker
EOF
            ;;
    esac
}

main "$@"
