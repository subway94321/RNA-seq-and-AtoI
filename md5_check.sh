#!/bin/bash
#SBATCH -J MD5_check          # 任务名
#SBATCH -p low               # 队列（与Nextflow任务队列一致）
#SBATCH -N 1                 # 单节点
#SBATCH --output=log.%j.out  # 标准输出日志
#SBATCH --error=log.%j.err   # 错误日志
#SBATCH --cpus-per-task=1    # 单线程任务，1核足够

# 定义原始数据目录（包含测序数据和md5文件）
raw_data_dir="$PWD/raw_data"
# 定义md5校验文件路径（假设md5文件名为md5.md5，根据实际情况修改）
md5_file="$raw_data_dir/md5.md5"

# 检查原始数据目录是否存在
if [ ! -d "$raw_data_dir" ]; then
    echo "错误：原始数据目录 $raw_data_dir 不存在！" >&2
    exit 1
fi

# 检查md5文件是否存在
if [ ! -f "$md5_file" ]; then
    echo "错误：md5校验文件 $md5_file 不存在！" >&2
    exit 1
fi

# 进入原始数据目录（确保md5文件中记录的路径与当前目录匹配）
cd "$raw_data_dir" || {
    echo "错误：无法进入目录 $raw_data_dir！" >&2
    exit 1
}

# 执行MD5校验（-w 忽略文件名中的空格警告，-c 校验模式）
echo "开始MD5校验，文件路径：$md5_file"
md5sum -w -c "$md5_file"

# 捕获校验结果并输出对应日志
if [ $? -eq 0 ]; then
    echo "所有文件MD5校验通过！"
    exit 0
else
    echo "错误：部分或全部文件MD5校验失败，请检查文件完整性！" >&2
    exit 1
fi