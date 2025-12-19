#!/bin/bash

# ==============================================================================
# SLURM 资源配置 (根据你的要求调整为 24核 + 40G)
# ==============================================================================
#SBATCH -J reditools_smart
#SBATCH -p high
#SBATCH -N 1
#SBATCH --output=log_smart.%j.out
#SBATCH --error=log_smart.%j.err
#SBATCH --cpus-per-task=24     # 申请 24 个 CPU 核心
#SBATCH --mem=40G              # 申请 40G 内存
#SBATCH --time=96:00:00        # 增加时间到 4 天，防止大样本超时

# ==============================================================================
# 配置变量
# ==============================================================================

reference_fasta_gz="$PWD/Mus_musculus.GRCm39.dna_sm.primary_assembly.fa.gz"
reference_fasta="${reference_fasta_gz%.gz}"
samples_file="$PWD/samplesheet.csv"

# 阈值设置
DEPTH_THRESHOLD=20000          # 超过 20000X 深度的视为“重症样本”

# 资源分配逻辑
# 1. 普通样本：并行跑，总核数24，设并发为6，则每个任务4核
NORMAL_JOBS_PARALLEL=6
NORMAL_THREADS_PER_TASK=4

# 2. 重症样本：串行跑，独占所有资源
HEAVY_THREADS_PER_TASK=24

# Reditools 参数
MIN_READ_QUALITY=25
MIN_READ_DEPTH=10
WINDOW_SIZE=1000000

CONDA_ENV_PATH="/cluster/home/sunxiaozhi/miniconda3"
CONDA_ENV_NAME="reditools"
OUT_DIR="$PWD/reditools_output"
BAM_DIR="$PWD/nf_output_rnaseq/star_salmon"

# ==============================================================================
# 初始化
# ==============================================================================

echo "🚀 初始化智能分级处理脚本..."
echo "📦 资源池: CPU=${HEAVY_THREADS_PER_TASK} 核, MEM=40G"

source "${CONDA_ENV_PATH}/bin/activate" "${CONDA_ENV_NAME}" || exit 1
mkdir -p "$OUT_DIR" || exit 1

# 检查 Parallel
if ! command -v parallel &> /dev/null; then
    echo "❌ Error: parallel not found." >&2; exit 1
fi

# 准备参考基因组 (保持原有逻辑，简化显示)
prepare_reference() {
    if [ ! -f "$reference_fasta" ]; then
        gunzip -c "$reference_fasta_gz" > "$reference_fasta"
        samtools faidx "$reference_fasta"
    elif [ ! -f "${reference_fasta}.fai" ]; then
        samtools faidx "$reference_fasta"
    fi
}
prepare_reference || { echo "❌ 参考基因组准备失败"; exit 1; }

# 读取样本列表
if [ ! -f "$samples_file" ]; then echo "❌ 样本表不存在"; exit 1; fi
samples=$(awk -F ',' 'NR>1 {print $1}' "$samples_file" | grep -v '^$')
if [ -z "$samples" ]; then echo "❌ 没找到样本"; exit 1; fi

# ==============================================================================
# 第一阶段：分诊 (检测深度)
# ==============================================================================

echo "----------------------------------------------------------------"
echo "🏥 第一阶段：样本体检与分流 (检测 BAM 深度)"
echo "----------------------------------------------------------------"

# 定义数组
normal_samples=()
heavy_samples=()

for sample in $samples; do
    bam_file="${BAM_DIR}/${sample}.markdup.sorted.bam"
    
    if [ ! -f "$bam_file" ]; then
        echo "⚠️  样本 $sample 的 BAM 文件不存在，跳过。"
        continue
    fi

    echo -n "🔍 检测 $sample ... "
    
    # 使用 samtools depth 快速检测最大深度
    # 为了速度，我们不遍历全基因组，只看是否有任何位点超过阈值
    # 这里的逻辑是：只要发现有位点超过阈值，立刻停止并判定为 Heavy
    # 注意：如果文件很大，这一步可能需要几分钟，但比跑死机要好
    
    # 优化技巧：如果已知问题出在 MT，可以只检测 MT。如果未知，则全检。
    # 这里使用 awk 只要遇到大于阈值的行就退出返回 1
    samtools depth "$bam_file" | awk -v limit="$DEPTH_THRESHOLD" '$3 > limit {exit 1}'
    is_heavy=$?

    # awk 退出码：正常跑完是0，中途exit 1是1
    if [ $is_heavy -eq 1 ]; then
        echo "🛑 判定为重症 (深度 > $DEPTH_THRESHOLD) -> 加入重症组"
        heavy_samples+=("$sample")
    else
        echo "✅ 判定为普通 -> 加入普通组"
        normal_samples+=("$sample")
    fi
done

echo "----------------------------------------------------------------"
echo "📊 分流结果统计："
echo "   普通样本 (${#normal_samples[@]} 个): ${normal_samples[*]}"
echo "   重症样本 (${#heavy_samples[@]} 个): ${heavy_samples[*]}"
echo "----------------------------------------------------------------"

# ==============================================================================
# 核心处理函数 (接受两个参数：样本名，线程数)
# ==============================================================================

process_sample() {
    local sample="$1"
    local threads="$2"
    
    # 再次激活环境，确保并行环境正常
    source "${CONDA_ENV_PATH}/bin/activate" "${CONDA_ENV_NAME}"

    echo "--- [CPU分配: $threads] 开始处理：${sample} ---"
    
    local bam_file="${BAM_DIR}/${sample}.markdup.sorted.bam"
    local analyze_output="${OUT_DIR}/${sample}_analyze_reditools.txt"
    local index_output="${OUT_DIR}/${sample}_index_reditools.txt"
    
    # 检查索引
    if [ ! -f "${bam_file}.bai" ]; then
        samtools index "$bam_file"
    fi
    
    # 运行 analyze
    # 注意：对于 heavy 样本，我们依然跑全基因组，利用多线程暴力破解
    python3 -m reditools analyze \
        "$bam_file" \
        -r "$reference_fasta" \
        -o "$analyze_output" \
        --strand 0 \
        --min-read-quality "$MIN_READ_QUALITY" \
        --min-read-depth "$MIN_READ_DEPTH" \
        --threads "$threads" \
        --window "$WINDOW_SIZE" \
        --variants all
    
    status=$?
    if [ $status -ne 0 ]; then
        echo "❌ [ERROR] $sample analyze 失败 (Code $status)"
        return 1
    fi
    
    # 运行 index
    python3 -m reditools index \
        "$analyze_output" \
        -o "$index_output" \
        --strand 0
        
    status=$?
    if [ $status -ne 0 ]; then
        echo "❌ [ERROR] $sample index 失败 (Code $status)"
        return 1
    fi
    
    echo "✅ [SUCCESS] $sample 处理完成"
    return 0
}

export -f process_sample
export OUT_DIR reference_fasta BAM_DIR MIN_READ_QUALITY MIN_READ_DEPTH WINDOW_SIZE CONDA_ENV_PATH CONDA_ENV_NAME PATH

# ==============================================================================
# 第二阶段：处理普通样本 (并行)
# ==============================================================================

if [ ${#normal_samples[@]} -gt 0 ]; then
    echo "🎬 第二阶段：并行处理普通样本 (每任务 $NORMAL_THREADS_PER_TASK 核)..."
    
    # 将数组转为空格分隔的字符串供 parallel 使用
    normal_str="${normal_samples[*]}"
    
    # 使用 parallel
    # --jobs 6: 同时跑6个
    # 传递参数：{} 是样本名，第二个参数固定为 NORMAL_THREADS_PER_TASK
    echo "$normal_str" | tr ' ' '\n' | parallel --jobs "$NORMAL_JOBS_PARALLEL" --joblog "$OUT_DIR/normal_jobs.log" process_sample {} "$NORMAL_THREADS_PER_TASK"
else
    echo "无普通样本，跳过第二阶段。"
fi

# ==============================================================================
# 第三阶段：处理重症样本 (串行，暴力独占)
# ==============================================================================

if [ ${#heavy_samples[@]} -gt 0 ]; then
    echo "🔥 第三阶段：集中火力处理重症样本 (每任务 $HEAVY_THREADS_PER_TASK 核，串行)..."
    
    for heavy in "${heavy_samples[@]}"; do
        echo "⚔️  正在全力攻击样本: $heavy ..."
        # 直接调用函数，不通过 parallel，确保独占资源
        process_sample "$heavy" "$HEAVY_THREADS_PER_TASK"
        
        if [ $? -eq 0 ]; then
            echo "🎉 样本 $heavy 攻克成功！"
        else
            echo "☠️ 样本 $heavy 处理失败，可能需要更极端的资源。"
        fi
    done
else
    echo "无重症样本，跳过第三阶段。"
fi

echo "🎉 所有流程结束。结果目录：$OUT_DIR"
conda deactivate