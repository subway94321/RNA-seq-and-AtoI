#!/bin/bash

#SBATCH -J nf_rnaseq         # 任务名（参考文件下载）
#SBATCH -p high               # 队列（与你的Nextflow任务队列一致）
#SBATCH -N 1                 # 单节点
#SBATCH --output=log.%j.out  # 标准输出日志（记录下载进度）
#SBATCH --error=log.%j.err   # 错误日志（排查下载失败原因）
#SBATCH --cpus-per-task=15    
#SBATCH --mem=80G            

# nextflow 配置需求
# 小鼠基因组（GRCm39）需要72G内存，12个CPU

# 加载 conda 环境
source /cluster/home/sunxiaozhi/miniconda3/bin/activate env_nf

#####TODO 修改
# 定义输入文件路径
FASTA_FILE="$PWD/Mus_musculus.GRCm39.dna_sm.primary_assembly.fa.gz"
GTF_FILE="$PWD/Mus_musculus.GRCm39.115.gtf.gz"

# samplesheet.csv 
samplesheet="$PWD/samplesheet.csv"

#output目录
output_dir="$PWD/nf_output_rnaseq"
mkdir -p "$output_dir"

#创建fastqc global temp目录
tmpdir="$PWD/global_tmp"
mkdir -p "$tmpdir"

# parameters文件
custom_configuration_file="$PWD/nextflow_ranseq.config"

# 检查输入文件是否存在
if [ ! -f "$FASTA_FILE" ] || [ ! -f "$GTF_FILE" ] || [ ! -f "$samplesheet" ]; then
    echo "custom_configuration文件不存在或路径错误"
    exit 1
fi

# 运行 nf-core/rnaseq 流程
nextflow run nf-core/rnaseq \
    -r 3.21.0 \
    -profile singularity \
    --input "$samplesheet" \
    --outdir "$output_dir" \
	--fasta "$FASTA_FILE" \
	--gtf "$GTF_FILE" \
	--aligner star_salmon \
	-c "$custom_configuration_file" \
	-resume
