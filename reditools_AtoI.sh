#!/bin/bash

# ==============================================================================
# SLURM 资源配置
# ==============================================================================
#SBATCH -J reditools_parallel
#SBATCH -p high
#SBATCH -N 1
#SBATCH --output=log.%j.out
#SBATCH --error=log.%j.err
#SBATCH --cpus-per-task=8      # 请求 8 个 CPU 核心
#SBATCH --mem=16G
#SBATCH --time=48:00:00        # 设置一个合理的运行时间限制 (例如 48 小时)

# ... (Configuration Variables remain the same) ...

# ==============================================================================
# 配置变量
# ==============================================================================

reference_fasta_gz="$PWD/Mus_musculus.GRCm39.dna_sm.primary_assembly.fa.gz"
reference_fasta="${reference_fasta_gz%.gz}"
samples_file="$PWD/samplesheet.csv"

THREADS_PER_TASK=1         # 每个 reditools 任务使用的线程数
MAX_PARALLEL_JOBS=8        # 最大并行任务数
MIN_READ_QUALITY=25
MIN_READ_DEPTH=10
WINDOW_SIZE=1000000

CONDA_ENV_PATH="/cluster/home/sunxiaozhi/miniconda3"
CONDA_ENV_NAME="reditools"
OUT_DIR="$PWD/reditools_output"
BAM_DIR="$PWD/nf_output_rnaseq/star_salmon"

# ==============================================================================
# 初始化与检查
# ==============================================================================

echo "🚀 初始化 reditools 批处理脚本..."

# 1. 加载conda环境
source "${CONDA_ENV_PATH}/bin/activate" "${CONDA_ENV_NAME}" || {
    echo "❌ 致命错误：无法激活conda环境 ${CONDA_ENV_NAME}。请检查路径或名称。" >&2
    exit 1
}

# 2. 检查 parallel 命令是否存在
if ! command -v parallel &> /dev/null
then
    echo "❌ 致命错误：parallel 命令未找到。请运行 'conda install -c conda-forge parallel' 安装它。" >&2
    exit 1
else
    echo "✅ parallel 命令已找到。"
fi

# ... (The rest of the script remains the same) ...

# 3. 创建输出目录
mkdir -p "$OUT_DIR" || {
    echo "❌ 致命错误：无法创建输出目录 $OUT_DIR" >&2
    exit 1
}

# 4. 检查并准备参考基因组 (函数 prepare_reference 略，但需保留在脚本中)
prepare_reference() {
    # Function body from previous response...
    echo "🔬 检查并准备参考基因组..."
    if [ ! -f "$reference_fasta_gz" ]; then
        echo "❌ 致命错误：参考基因组压缩文件不存在 -> $reference_fasta_gz" >&2
        return 1
    fi
    if [ ! -f "$reference_fasta" ]; then
        echo "正在解压参考基因组到 $reference_fasta ..."
        gunzip -c "$reference_fasta_gz" > "$reference_fasta" || {
            echo "❌ 致命错误：解压失败，请检查压缩包完整性。" >&2
            return 1
        }
        if ! head -n 1 "$reference_fasta" | grep -q "^>"; then
            echo "❌ 致命错误：解压后的文件 $reference_fasta 不是有效的FASTA格式。" >&2
            return 1
        fi
    else
        echo "参考基因组文件 $reference_fasta 已存在，跳过解压。"
    fi
    if [ ! -f "${reference_fasta}.fai" ]; then
        echo "正在创建参考基因组索引..."
        samtools faidx "$reference_fasta" || {
            echo "❌ 致命错误：创建参考基因组索引失败。" >&2
            return 1
        }
    else
        echo "参考基因组索引已存在，跳过创建。"
    fi
    return 0
}
prepare_reference || exit 1

# 5. 检查样本列表 (代码略，但需保留在脚本中)
# ... (Sample list checking code) ...
if [ ! -f "$samples_file" ]; then
    echo "❌ 致命错误：样本列表文件 $samples_file 不存在。" >&2
    exit 1
fi
samples=$(awk -F ',' 'NR>1 {print $1}' "$samples_file" | grep -v '^$')
if [ -z "$samples" ]; then
    echo "❌ 致命错误：样本列表文件 $samples_file 中没有找到有效的样本名。" >&2
    exit 1
fi
duplicates=$(echo "$samples" | sort | uniq -d)
if [ -n "$duplicates" ]; then
    echo "❌ 致命错误：样本名存在重复：" >&2
    echo "$duplicates" >&2
    exit 1
fi

TOTAL_SAMPLES=$(echo "$samples" | wc -l)
echo "✅ 环境检查完毕。共发现 $TOTAL_SAMPLES 个样本，将以 $MAX_PARALLEL_JOBS 个并行任务运行。"

# ==============================================================================
# 核心处理函数 (process_sample function remains the same)
# ==============================================================================

process_sample() {
    local sample="$1"
    
    echo "--- 开始处理样本：${sample} ---"
    
    local bam_file="${BAM_DIR}/${sample}.markdup.sorted.bam"
    local analyze_output="${OUT_DIR}/${sample}_analyze_reditools.txt"
    local index_output="${OUT_DIR}/${sample}_index_reditools.txt"
    
    # 1. 检查BAM文件和索引
    if [ ! -f "$bam_file" ]; then
        echo "⚠️ 警告：BAM文件不存在，跳过 -> $bam_file"
        return 0
    fi
    if [ ! -f "${bam_file}.bai" ]; then
        echo "正在为BAM文件创建索引..."
        samtools index "$bam_file" || {
            echo "❌ 错误：BAM索引创建失败，跳过该样本 ${sample}" >&2
            return 0
        }
    fi
    
    # 2. 运行 analyze
    echo "🤖 运行 analyze..."
    python3 -m reditools analyze \
        "$bam_file" \
        -r "$reference_fasta" \
        -o "$analyze_output" \
        --strand 0 \
        --min-read-quality "$MIN_READ_QUALITY" \
        --min-read-depth "$MIN_READ_DEPTH" \
        --threads "$THREADS_PER_TASK" \
        --window "$WINDOW_SIZE" \
        --variants all || {
        echo "❌ 错误：analyze 失败，跳过该样本 ${sample}" >&2
        [ -f "$analyze_output" ] && rm -f "$analyze_output"
        return 0
    }
    
    # 3. 运行 index
    echo "🤖 运行 index..."
    python3 -m reditools index \
        "$analyze_output" \
        -o "$index_output" \
        --strand 0 || {
        echo "❌ 错误：index 失败，跳过该样本 ${sample}" >&2
        [ -f "$index_output" ] && rm -f "$index_output"
        return 0
    }
    
    echo "✅ 样本处理完成：${sample}"
    return 0
}

# 导出函数和变量
export -f process_sample
export OUT_DIR reference_fasta BAM_DIR MIN_READ_QUALITY MIN_READ_DEPTH WINDOW_SIZE THREADS_PER_TASK

# ==============================================================================
# 批量并行执行
# ==============================================================================

echo "🎬 开始批量并行处理样本..."

echo "$samples" | parallel --jobs "$MAX_PARALLEL_JOBS" process_sample {}

echo "🎉 所有样本处理结束，结果目录：$OUT_DIR"
conda deactivate