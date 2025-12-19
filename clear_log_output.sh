#!/bin/bash
#SBATCH -J clear          # 任务名（参考文件下载）
#SBATCH -p low               # 队列（与你的Nextflow任务队列一致）
#SBATCH -N 1                 # 单节点
#SBATCH --output=log.%j.out  # 标准输出日志（记录下载进度）
#SBATCH --error=log.%j.err   # 错误日志（排查下载失败原因）
#SBATCH --cpus-per-task=1    # wget单线程任务，1核足够（避免资源浪费）

OUTPUT_DIR="$PWD/nf_output"
# 检查输出目录是否存在
if [ -d "$OUTPUT_DIR" ]; then
    echo "`date`: 输出目录 $OUTPUT_DIR 存在，开始清理..."
    # 遍历输出目录下的所有文件和子目录
    for item in "$OUTPUT_DIR"/*; do
        # 检查是否为文件
        if [ -f "$item" ]; then
            # 删除文件
            echo "`date`: 删除文件 $item"
            rm "$item"
        elif [ -d "$item" ]; then
            # 删除目录
            echo "`date`: 删除目录 $item"
            rm -r "$item"
        fi
    done
    echo "`date`: 输出目录清理完成！"
else
    echo "`date`: 输出目录 $OUTPUT_DIR 不存在，无需清理。"
fi

#清除log文件
echo "`date`: 开始清除log文件..."
rm .nextflow.log
rm .nextflow.log.*
echo "`date`: log文件清除完成！"