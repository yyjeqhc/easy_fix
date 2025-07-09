#!/bin/bash

# 批量构建脚本
# 用于在OBS和EulerMaker平台创建包并触发构建

set -e

# 默认配置文件路径
CONFIG_FILE=".easy_fix.yml"
WORKDIR=$(pwd)

# 从YAML配置文件读取配置
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        log_error "请先运行 'ef gen' 命令生成配置文件"
        return 1
    fi
    
    log_info "加载配置文件: $CONFIG_FILE"
    
    # 读取YAML配置（使用简单的grep和awk解析）
    REPO_URL=$(grep "^  url:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    REPO_BRANCH=$(grep "^  branch:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    
    # 从仓库URL推导包名和目录名
    PACKAGE_BASE_NAME=$(basename "$REPO_URL" .git)
    BASE_REPO_DIR="${PACKAGE_BASE_NAME}"
    
    # 读取分支列表（简单解析YAML数组）
    BRANCHES=($(sed -n '/^branches:/,/^[^ ]/p' "$CONFIG_FILE" | grep "^  - " | awk '{print $2}' | tr -d '"'))
    
    # 读取构建项目配置
    OBS_PROJECT=$(grep "^    project:" "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '"')
    EULER_PROJECT=$(grep "^    project:" "$CONFIG_FILE" | tail -1 | awk '{print $2}' | tr -d '"')
    
    # 固定的目录配置
    GIT_DIR=".git"
    GITS_DIR=".gits"
    GIT_EXCLUDE_FILE="$GIT_DIR/info/exclude"
    GITS_EXCLUDE_FILE="$GITS_DIR/info/exclude"
    
    # 验证必需的配置
    if [[ -z "$REPO_URL" || "$REPO_URL" == *"your-"* ]]; then
        log_error "配置文件中的仓库地址无效，请编辑 $CONFIG_FILE"
        return 1
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

    # 检查OBS包是否已经存在
    if [[ -f "$OBS_PROJECT/$package_name/_service" ]]; then
        log_info "OBS包已经存在，直接构建"
        osc rebuildpac $OBS_PROJECT $package_name
        return 0
    fi
    
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
                <param name="url">${REPO_URL}</param>
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
    log_info "在当前目录生成配置文件..."
    
    # 创建YAML配置文件
    cat > "$CONFIG_FILE" << 'EOF'
# Easy Fix 批量构建配置文件
# 只需填写一个git URL即可，系统会自动推导包名和基础目录

repository:
  url: "https://gitee.com/your-username/your-repo.git"
  branch: "master"

# 分支列表（初始为空，使用 ef swicth 命令会自动添加）
branches: []

build:
  obs:
    project: "home:your-username:branches:openEuler:24.03:SP2:Everything"
  euler:
    project: "your-username:openEuler-24.03-LTS-SP1:everything"

EOF

    # 创建必要的目录
    mkdir -p logs
    mkdir -p tmp
    
    log_info "配置文件已生成: $CONFIG_FILE"
    log_info "请编辑配置文件，只需设置正确的 git URL 即可"
    log_info "然后运行 'ef init' 初始化项目"
}

# 安装脚本到系统
install_script() {
    local script_path="$0"
    local install_dir="/usr/local/bin"
    local script_name="ef"
    
    log_info "安装脚本到系统..."
    
    # 检查权限
    if [[ ! -w "$install_dir" ]]; then
        log_error "需要管理员权限安装到 $install_dir"
        log_error "请运行: sudo $0 install"
        return 1
    fi
    
    # 复制脚本并创建软链接
    cp "$script_path" "$install_dir/easy_fix"
    chmod +x "$install_dir/easy_fix"
    
    # 创建短命令软链接
    ln -sf "$install_dir/easy_fix" "$install_dir/$script_name"
    
    log_info "脚本已安装到: $install_dir/easy_fix"
    log_info "短命令链接: $install_dir/$script_name"
    
    # 自动安装补全功能
    install_completion
    
    log_info "现在可以使用 'ef' 或 'easy_fix' 命令"
    log_info "支持Tab键自动补全命令和参数"
}

# 添加分支到配置文件
add_branch() {
    local branch="$1"
    
    if [[ -z "$branch" ]]; then
        log_error "请指定分支名称"
        return 1
    fi
    
    # 检查分支是否已存在
    if grep -q "^  - \"*$branch\"*$" "$CONFIG_FILE"; then
        log_warn "分支 $branch 已存在于配置文件中"
        return 0
    fi
    
    # 添加分支到YAML文件
    if grep -q "^branches: \[\]$" "$CONFIG_FILE"; then
        # 如果branches是空数组，替换为包含新分支的数组
        sed -i "s/^branches: \[\]$/branches:\n  - \"$branch\"/" "$CONFIG_FILE"
    else
        # 在branches部分添加新分支
        sed -i "/^branches:/a\\  - \"$branch\"" "$CONFIG_FILE"
    fi
    
    log_info "分支 $branch 已添加到配置文件"
}

# 移除分支从配置文件
remove_branch() {
    local branch="$1"
    
    if [[ -z "$branch" ]]; then
        log_error "请指定分支名称"
        return 1
    fi
    
    # 移除分支
    sed -i "/^  - \"*$branch\"*$/d" "$CONFIG_FILE"
    
    # 如果没有分支了，恢复为空数组
    if ! grep -q "^  - " "$CONFIG_FILE"; then
        sed -i "s/^branches:$/branches: []/" "$CONFIG_FILE"
    fi
    
    log_info "分支 $branch 已从配置文件中移除"
}

# 列出配置的分支
list_branches() {
    log_info "配置的分支列表:"
    if grep -q "^branches: \[\]$" "$CONFIG_FILE"; then
        echo "  无分支配置"
    else
        grep "^  - " "$CONFIG_FILE" | sed 's/^  - "*/  /' | sed 's/"*$//'
    fi
}

# 初始化项目
init_project() {
    log_info "初始化批量构建项目..."
    
    # 验证配置
    if [[ -z "$REPO_URL" || "$REPO_URL" == *"your-"* ]]; then
        log_error "请先编辑 $CONFIG_FILE 配置文件，设置正确的仓库地址"
        return 1
    fi
    
    log_info "配置验证通过:"
    echo "  仓库: $REPO_URL"
    echo "  包名: $PACKAGE_BASE_NAME"
    echo "  基础目录: $BASE_REPO_DIR"
    echo "  分支: ${BRANCHES[*]:-无}"
    echo "  OBS项目: $OBS_PROJECT"
    echo "  EulerMaker项目: $EULER_PROJECT"
    
    # 克隆基准仓库
    clone_base_repo
    
    log_info "项目初始化完成"
    log_info "请手动解压源码包并打上补丁，然后运行 'easy_fix start'"
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

        echo "/$OBS_PROJECT"
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

        echo "/$OBS_PROJECT"

        # 忽略主仓库自己的 .git
        echo "/.gits"
    } > "$GIT_EXCLUDE_FILE"
}

# 查看工作区状态
status_repo() {
    log_info "仓库状态:"
    
    cd "$BASE_REPO_DIR"
    
    echo "当前分支: $(git branch --show-current)"
    echo "主仓库状态:"
    git status 
    echo "子仓库状态:"
    git --git-dir=$GITS_DIR status
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
    
    # 检查分支是否在配置文件中，如果不在则自动添加
    local branch_exists=false
    for configured_branch in "${BRANCHES[@]}"; do
        if [[ "$configured_branch" == "$branch" ]]; then
            branch_exists=true
            break
        fi
    done
    
    if [[ "$branch_exists" == false ]]; then
        log_info "分支 $branch 不在配置中，自动添加到配置文件"
        add_branch "$branch"
        # 重新加载配置以更新BRANCHES数组
        load_config
    fi
    
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
        git checkout -b "$branch" "$REPO_BRANCH"
        log_info "主仓库创建新分支: $branch"
    fi
    
    # 处理子仓库分支切换
    if git --git-dir=$GITS_DIR show-ref --verify --quiet "refs/heads/$branch"; then
        # 子仓库本地分支存在，直接切换
        git --git-dir=$GITS_DIR checkout "$branch"
        log_info "子仓库已切换到分支: $branch"
    else
        # 创建新分支（基于当前分支，通常是基准分支）
        git --git-dir=$GITS_DIR checkout -b "$branch" "$REPO_BRANCH"
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
    
    # 使用sed处理补丁文件，去掉多余的目录层次
    # 也可以考虑--releactive之类的，但是不能cd进去，还要考虑遍历文件夹
    # 只去掉第一层目录：a/dir/file → a/file, a/dir1/dir2/file → a/dir2/file a/file → a/file
    sed -i -E \
    -e 's#^diff --git ([ab])/[^/]+/(.*) ([ab])/[^/]+/(.*)$#diff --git \1/\2 \3/\4#' \
    -e 's#^(\+\+\+|---) ([ab])/[^/]+/(.*)$#\1 \2/\3#' \
    "$patch_file"
    
    log_info "补丁文件已生成并处理路径: $patch_file"
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
# edit_file() {
#     local file_path="$1"
#     local content="$2"
    
#     if [[ -z "$file_path" ]]; then
#         log_error "请指定文件路径"
#         return 1
#     fi
    
#     local full_path="$WORK_REPO_DIR/$file_path"
#     local dir_path=$(dirname "$full_path")
    
#     # 创建目录（如果不存在）
#     mkdir -p "$dir_path"
    
#     if [[ -n "$content" ]]; then
#         # 写入内容
#         echo "$content" > "$full_path"
#         log_info "文件已更新: $file_path"
#     else
#         # 编辑文件（使用默认编辑器）
#         ${EDITOR:-nano} "$full_path"
#         log_info "文件编辑完成: $file_path"
#     fi
# }

# 生成bash自动补全脚本
generate_completion() {
    cat << 'EOF'
# Bash completion for Easy Fix (ef) script
_ef_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # 主命令列表
    opts="install install-completion gen init add-branch remove-branch list-branches start switch patch commit push status create-obs create-euler create-all query-obs query-euler query-all build-obs build-euler build-all query-euler-look-good help"

    # 根据前一个命令提供特定补全
    case "${prev}" in
        switch|remove-branch)
            # 从配置文件读取分支列表进行补全
            if [[ -f ".easy_fix.yml" ]]; then
                local branches=$(grep "^  - " .easy_fix.yml 2>/dev/null | sed 's/^  - "*//' | sed 's/"*$//' | tr '\n' ' ')
                COMPREPLY=( $(compgen -W "${branches}" -- ${cur}) )
            fi
            return 0
            ;;
        patch)
            # 补丁文件补全
            COMPREPLY=( $(compgen -f -X '!*.patch' -- ${cur}) )
            return 0
            ;;
        add-branch)
            # 不提供补全，用户需要输入新分支名
            return 0
            ;;
        commit)
            # 提供一些常用的提交信息
            local commit_msgs="'for build' 'fix bug' 'update patch' 'add feature'"
            COMPREPLY=( $(compgen -W "${commit_msgs}" -- ${cur}) )
            return 0
            ;;
    esac

    # 默认补全主命令
    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
}

# 注册补全函数
complete -F _ef_completion ef
complete -F _ef_completion easy_fix
EOF
}

# 安装自动补全
install_completion() {
    local completion_dir="/etc/bash_completion.d"
    local completion_file="$completion_dir/ef"
    
    log_info "安装bash自动补全..."
    
    # 检查权限
    if [[ ! -w "$completion_dir" ]] && [[ ! -w "/usr/share/bash-completion/completions" ]]; then
        log_error "需要管理员权限安装自动补全"
        log_error "请运行: sudo $0 install-completion"
        return 1
    fi
    
    # 优先使用新的补全目录
    if [[ -d "/usr/share/bash-completion/completions" ]] && [[ -w "/usr/share/bash-completion/completions" ]]; then
        completion_dir="/usr/share/bash-completion/completions"
        completion_file="$completion_dir/ef"
    fi
    
    # 生成并安装补全脚本
    generate_completion > "$completion_file"
    
    log_info "自动补全已安装到: $completion_file"
    log_info "请重新加载shell或运行: source $completion_file"
}

# 主函数
main() {
    case "${1:-help}" in
        "install")
            install_script
            ;;
        "install-completion")
            install_completion
            ;;
        "gen")
            gen_project
            ;;
        "init")
            load_config
            init_project
            ;;
        "add-branch")
            add_branch "$2"
            ;;
        "remove-branch")
            remove_branch "$2"
            ;;
        "list-branches")
            list_branches
            ;;
        "start")
            load_config
            create_sub_repo
            ;;
        "switch")
            load_config
            switch_branch "$2"
            ;;
        "patch")
            load_config
            patch_repo "$2"
            ;;
        "commit")
            load_config
            commit_changes "$2"
            ;;
        "push")
            load_config
            push_changes
            ;;
        "status")
            load_config
            status_repo
            ;;
        "create-obs")
            load_config
            shift
            create_obs_packages "$@"
            ;;
        "create-euler")
            load_config
            shift
            create_euler_packages "$@"
            ;;
        "create-all")
            load_config
            create_obs_packages
            create_euler_packages
            ;;
        "query-obs")
            load_config
            shift
            query_obs_status "$@"
            ;;
        "query-euler")
            load_config
            shift
            query_euler_status "$@"
            ;;
        "query-all")
            load_config
            query_obs_status
            query_euler_status
            ;;
        "build-obs")
            load_config
            shift
            build_obs "$@"
            ;;
        "build-euler")
            load_config
            shift
            build_euler "$@"
            ;;
        "build-all")
            load_config
            build_obs
            build_euler
            ;;
        "query-euler-look-good")
            load_config
            shift
            query_euler_look_good "$@"
            ;;
        "help"|*)
            cat << EOF
Easy Fix (ef) - 批量构建脚本使用说明:

安装命令:
  install         安装脚本到系统路径，支持 ef 简写命令（自动安装补全）
  install-completion 单独安装bash自动补全功能

项目管理命令:
  gen             在当前目录生成配置文件 (.easy_fix.yml)
  init            根据配置文件初始化项目
  status          查看工作仓库状态
  
分支管理命令:
  add-branch      添加分支到配置文件
  remove-branch   从配置文件移除分支  
  list-branches   列出配置的分支
  
仓库操作命令:
  start           创建子仓库基础内容
  switch <branch> 切换到指定分支（自动添加新分支到配置）
  patch <file>    生成补丁文件
  commit [msg]    提交更改
  push            推送分支到远程仓库

构建管理命令:
  create-obs      创建OBS包并构建
  create-euler    创建EulerMaker包并构建
  create-all      创建所有平台的包并构建
  query-obs       查询OBS构建状态
  query-euler     查询EulerMaker构建状态
  query-all       查询所有平台构建状态
  build-obs       重新构建OBS包
  build-euler     重新构建EulerMaker包
  build-all       重新构建所有平台的包
  query-euler-look-good 友好展示构建结果

使用流程:
  1. sudo ef install         # 安装到系统（包含自动补全）
  2. ef gen                  # 生成配置文件
  3. 编辑 .easy_fix.yml      # 只需填写一个 git URL
  4. ef init                 # 初始化项目
  5. ef start                # 创建子仓库
  6. ef switch mybranch      # 切换分支（自动添加到配置）
  7. ef push                 # 推送并构建

配置说明:
  - 只需在 .easy_fix.yml 中填写一个 git URL
  - 系统会自动推导包名和基础目录
  - 切换分支时自动添加新分支到配置文件
  - 所有操作基于当前目录的配置文件
  - 支持Tab键自动补全命令和参数

自动补全功能:
  - ef <Tab>              显示所有可用命令
  - ef switch <Tab>       显示配置的分支列表
  - ef remove-branch <Tab> 显示可删除的分支
  - ef patch <Tab>        显示.patch文件
  - ef commit <Tab>       显示常用提交信息
EOF
            ;;
    esac
}

main "$@"
