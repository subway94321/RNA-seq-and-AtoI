#!/bin/bash
#SBATCH -J pigz          # 任务名
#SBATCH -p low           # 队列
#SBATCH -N 1             # 单节点
#SBATCH --output=log.%j.out  # 标准输出日志
#SBATCH --error=log.%j.err   # 错误日志
#SBATCH --cpus-per-task=16   # 分配16核（pigz会自动利用，不手动指定-p参数）

# 加载conda环境
echo "$(date +'%Y-%m-%d %H:%M:%S') - 开始加载conda环境..."
source /cluster/home/sunxiaozhi/miniconda3/bin/activate compress || {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: 加载conda环境失败！" >&2
    exit 1
}

# 检查pigz是否可用
echo "$(date +'%Y-%m-%d %H:%M:%S') - 检查pigz是否安装..."
if ! command -v pigz &> /dev/null; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: pigz未安装在当前环境中！" >&2
    exit 1
fi
echo "$(date +'%Y-%m-%d %H:%M:%S') - pigz已就绪，版本信息: $(pigz --version | head -n1)"

# 定义待压缩目录
rnaseq_output_folder="$PWD/nf_output_rnaseq"
DA_output_folder="$PWD/nf_output_DA_basedon_ranseq"
reditools_output_folder="$PWD/reditools_output"

# 检查目录是否存在
check_directory() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: 目录不存在: $dir" >&2
        exit 1
    fi
    echo "$(date +'%Y-%m-%d %H:%M:%S') - 确认目录存在: $dir"
}

# 压缩并验证函数
compress_and_verify() {
    local src_dir=$1
    local dest_tar=$2
    echo "$(date +'%Y-%m-%d %H:%M:%S') - 开始压缩: $src_dir -> $dest_tar"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - 可用CPU核心数: $SLURM_CPUS_PER_TASK（pigz将自动利用）"
    
    # 执行压缩（不指定-p参数，让pigz自动使用所有可用核心）
    tar -I pigz -cf "$dest_tar" "$src_dir"
    
    # 检查压缩是否成功
    if [ $? -ne 0 ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: 压缩失败: $src_dir" >&2
        exit 1
    fi
    
    # 验证压缩文件完整性（使用pigz的测试功能）
    echo "$(date +'%Y-%m-%d %H:%M:%S') - 开始验证压缩文件完整性: $dest_tar"
    pigz -t "$dest_tar"  # 测试压缩文件是否完好
    
    if [ $? -eq 0 ]; then
        local file_size=$(du -h "$dest_tar" | awk '{print $1}')
        echo "$(date +'%Y-%m-%d %H:%M:%S') - 压缩成功且文件完整！文件: $dest_tar (大小: $file_size)"
    else
        echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: 压缩文件损坏: $dest_tar" >&2
        rm -f "$dest_tar"  # 删除损坏的文件
        exit 1
    fi
}

# 主流程
echo "$(date +'%Y-%m-%d %H:%M:%S') - 开始压缩任务"

# 检查目录
check_directory "$rnaseq_output_folder"
check_directory "$DA_output_folder"
check_directory "$reditools_output_folder"

# 执行压缩和验证
compress_and_verify "$rnaseq_output_folder" "nf_output_rnaseq.tar.gz"
compress_and_verify "$DA_output_folder" "nf_output_DA_basedon_ranseq.tar.gz"
compress_and_verify "$reditools_output_folder" "reditools_output.tar.gz"

echo "$(date +'%Y-%m-%d %H:%M:%S') - 所有压缩任务完成，文件均通过完整性验证！"
exit 0