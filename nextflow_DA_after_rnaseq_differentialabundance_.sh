#!/bin/bash
# 功能：运行nf-core/differentialabundance 1.5.0版本，基于RNA-seq定量结果进行差异丰度分析
# 依赖：conda环境（env_nf）、singularity容器、前置RNA-seq流程输出的计数矩阵和转录本长度矩阵

#SBATCH -J nf_DA              # 任务名：nf-core/differentialabundance分析
#SBATCH -p high               # 队列：需与Nextflow任务队列保持一致
#SBATCH -N 1                 # 节点数：单节点运行
#SBATCH --output=log.%j.out  # 标准输出日志：记录流程运行进度和详细信息
#SBATCH --error=log.%j.err   # 错误日志：记录报错信息，用于排查运行失败原因
#SBATCH --cpus-per-task=15    # 每个任务CPU数：满足流程最低12核要求，预留冗余
#SBATCH --mem=80G             # 内存：满足小鼠基因组（GRCm39）分析72G内存需求，预留冗余

# 环境配置：加载运行所需的conda环境
# 注：env_nf需提前安装nextflow及流程依赖的基础工具
source /cluster/home/sunxiaozhi/miniconda3/bin/activate env_nf

##### TODO：根据实际项目修改以下输入路径（确保文件存在且格式正确）
# 基因组注释文件：小鼠GRCm39版本的GTF文件（压缩格式）
GTF_FILE="$PWD/Mus_musculus.GRCm39.115.gtf.gz"

# 样本表：需包含样本ID、分组等信息，可新增batch列用于批次效应校正（格式参考nf-core/differentialabundance文档）
samplesheet="$PWD/samplesheet_DA_basedon_ranseq.csv"

# 对比文件：定义差异分析的分组对比（格式参考nf-core/differentialabundance文档）
contrasts_file="$PWD/contrasts_DA.csv"

# 输出目录：存储流程所有输出结果，不存在则自动创建
output_dir="$PWD/nf_output_DA_basedon_ranseq"
mkdir -p "$output_dir"

# 容器缓存目录：指定singularity镜像缓存路径，避免重复下载
NXF_SINGULARITY_CACHEDIR="$HOME/singularity_cache"
export NXF_SINGULARITY_CACHEDIR  # 导出为环境变量，供Nextflow读取

# 前置RNA-seq流程输出路径：需确保star_salmon模块生成了对应的矩阵文件
nf_rnaseq_output_dir="$PWD/nf_output_rnaseq"
matrix_file_path="$nf_rnaseq_output_dir/star_salmon/salmon.merged.gene_counts.tsv"  # 基因计数矩阵
transcript_length_matrix_path="$nf_rnaseq_output_dir/star_salmon/salmon.merged.gene_lengths.tsv"  # 转录本长度矩阵

# 前置文件存在性检查：确保所有输入文件均存在，避免流程中途失败
if [ ! -f "$samplesheet" ]; then
    echo "Error: 样本表文件不存在 -> $samplesheet"
    exit 1
fi
if [ ! -f "$contrasts_file" ]; then
    echo "Error: 对比文件不存在 -> $contrasts_file"
    exit 1
fi
if [ ! -f "$matrix_file_path" ]; then
    echo "Error: 基因计数矩阵不存在 -> $matrix_file_path"
    exit 1
fi
if [ ! -f "$transcript_length_matrix_path" ]; then
    echo "Error: 转录本长度矩阵不存在 -> $transcript_length_matrix_path"
    exit 1
fi
echo "✅ 所有输入文件检查通过，开始启动差异丰度分析流程"

custom_configuration_file="$PWD/nextflow_DA_after_rnaseq_differentialabundance.config"

# 检查custom_configuration_file是否存在
if [ ! -f "$custom_configuration_file" ]; then
    echo "Error: custom_configuration文件不存在 -> $custom_configuration_file"
    exit 1
fi
# 运行 nf-core/differentialabundance 流程

nextflow run nf-core/differentialabundance \
    -r 1.5.0 \
    --input "$samplesheet" \
    --contrasts "$contrasts_file" \
    --matrix "$matrix_file_path" \
    --transcript_length_matrix "$transcript_length_matrix_path" \
    --outdir "$output_dir" \
    --gtf "$GTF_FILE" \
    -c "$custom_configuration_file" \
    -resume

# 流程运行状态提示
if [ $? -eq 0 ]; then
    echo "🎉 差异丰度分析流程运行完成！输出结果已保存至：$output_dir"
else
    echo "❌ 差异丰度分析流程运行失败！请查看错误日志：log.$SLURM_JOB_ID.err"
    exit 1
fi