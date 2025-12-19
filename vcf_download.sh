#!/bin/bash
#SBATCH -J vcf_down             # 任务名修改为 vcf_down
#SBATCH -p low                  # 队列
#SBATCH -N 1                    # 单节点
#SBATCH --output=log_vcf.%j.out # 标准输出日志
#SBATCH --error=log_vcf.%j.err  # 错误日志
#SBATCH --cpus-per-task=1       # 1核足够
#SBATCH --mem=2G                # 仅下载，内存需求低

##############################################################################
# 1. 环境激活与工作目录设置
##############################################################################
# 激活conda环境 (用于确保wget等工具可用，若系统自带wget且版本较新，可忽略)
source /cluster/home/sunxiaozhi/miniconda3/bin/activate my_tools

# 定义参考文件存储目录
REF_DIR="$PWD"
echo "`date`: [INFO] 参考文件将保存到当前目录: $REF_DIR"

##############################################################################
# 2. 定义下载链接与文件名 (Ensembl Release 115 Mouse)
##############################################################################
# 主VCF文件 (包含所有变异，文件较大)
vcf_gz_URL="https://ftp.ensembl.org/pub/release-115/variation/vcf/mus_musculus/mus_musculus.vcf.gz"
vcf_gz_file="mus_musculus.vcf.gz"

# 索引文件 (CSI index)
vcf_csi_URL="https://ftp.ensembl.org/pub/release-115/variation/vcf/mus_musculus/mus_musculus.vcf.gz.csi"
vcf_csi_file="mus_musculus.vcf.gz.csi"

##############################################################################
# 3. 下载函数 (优化：断点续传 + 重试机制)
##############################################################################
download_with_retry() {
    local URL=$1
    local OUTPUT=$2
    local DESC=$3
    local MAX_RETRIES=10       # 增加重试次数，大文件容易断
    local RETRY_DELAY=10       # 重试间隔10秒
    local CURRENT_RETRY=0

    # 检查文件是否已经完整存在（简单的预检查，防止重复下载）
    if [ -f "$OUTPUT" ]; then
        echo "`date`: [INFO] $OUTPUT 已存在，将尝试断点续传以确保完整..."
    fi

    while [ $CURRENT_RETRY -lt $MAX_RETRIES ]; do
        echo "`date`: [START] 开始下载 $DESC (尝试 $((CURRENT_RETRY+1))/$MAX_RETRIES)..."
        
        # wget 参数优化：
        # -c: 断点续传 (核心)
        # -nv: No Verbose (不打印进度条，但打印关键日志，适合HPC)
        # --timeout: 链接超时时间
        # --tries: wget内部单次命令的重试次数
        wget -c \
             --timeout=60 \
             --tries=3 \
             -nv \
             "$URL" \
             -O "$OUTPUT"

        # 检查 wget 返回值
        if [ $? -eq 0 ]; then
            echo "`date`: [SUCCESS] $DESC 下载成功！"
            return 0
        else
            echo "`date`: [WARN] $DESC 下载中断或失败。"
            CURRENT_RETRY=$((CURRENT_RETRY+1))
            if [ $CURRENT_RETRY -lt $MAX_RETRIES ]; then
                echo "`date`: [WAIT] $RETRY_DELAY 秒后重试..."
                sleep $RETRY_DELAY
                # 关键修改：不要 rm -f $OUTPUT，以便下一次循环利用 -c 继续下载
            fi
        fi
    done

    echo "`date`: [ERROR] $DESC 在 $MAX_RETRIES 次尝试后彻底失败。" >&2
    exit 1
}

# 执行下载任务
# 1. 下载 VCF 主文件
download_with_retry "$vcf_gz_URL" "$vcf_gz_file" "VCF变异数据库(gz)"

# 2. 下载 CSI 索引文件
download_with_retry "$vcf_csi_URL" "$vcf_csi_file" "VCF索引文件(csi)"

##############################################################################
# 4. 完整性校验 (优化：区分gz和普通文件)
##############################################################################
check_integrity() {
    local FILE=$1
    local TYPE=$2  # "gz" 或 "binary"

    if [ ! -f "$FILE" ]; then
        echo "`date`: [ERROR] 文件 $FILE 未找到！" >&2
        exit 1
    fi

    if [ "$TYPE" == "gz" ]; then
        echo "`date`: [CHECK] 正在校验 gzip 完整性: $FILE ..."
        if gzip -t "$FILE"; then
            echo "`date`: [PASS] $FILE 完整性校验通过。"
        else
            echo "`date`: [FAIL] $FILE 压缩包已损坏！请删除文件后重新提交任务。" >&2
            # 损坏的文件应该重命名或删除，以免误用
            mv "$FILE" "${FILE}.corrupt"
            exit 1
        fi
    else
        # 对于 .csi 文件，gzip -t 会失败，这里只检查文件大小是否大于0
        if [ -s "$FILE" ]; then
             echo "`date`: [PASS] $FILE 存在且非空 (索引文件无法用gzip校验)。"
        else
             echo "`date`: [FAIL] $FILE 文件为空！" >&2
             exit 1
        fi
    fi
}

echo "----------------------------------------------------------------"
check_integrity "$vcf_gz_file" "gz"
check_integrity "$vcf_csi_file" "binary"

##############################################################################
# 5. 结束
##############################################################################
echo "----------------------------------------------------------------"
echo "`date`: 所有任务完成。"
echo "VCF路径: $REF_DIR/$vcf_gz_file"
echo "CSI路径: $REF_DIR/$vcf_csi_file"