#!/bin/bash

# 定义管道根目录（根据你的实际路径自动定位）
PIPELINE_ROOT="$PWD"


if [ ! -f "samplesheet.csv" ] && [ ! -d "work" ]; then
    echo "⚠️ 警告：当前目录可能不是管道根目录（未找到 samplesheet.csv 或 work 目录）"
    read -p "是否继续？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 创建全局临时目录（若不存在）
GLOBAL_TMP="/cluster/home/sunxiaozhi/rna_seq/global_tmp"
mkdir -p "$GLOBAL_TMP" && chmod 777 "$GLOBAL_TMP"

# 在管道根目录创建并写入 nextflow.config
cat > "$PIPELINE_ROOT/nextflow.config" << EOF
process {
    // 全局指定临时目录，避免依赖系统 /tmp
    env.TMPDIR = "$GLOBAL_TMP"
    
    // 针对 FASTQC 任务的优化配置
    withName: FASTQC {
        cpus = 15 
        memory = 80.GB 
        errorStrategy = "retry"
        maxRetries = 1
    }
    
    // 其他任务的通用配置（可选）
    withLabel: 'process_low' {
        cpus = 15
        memory = 80.GB
    }
}

// Singularity 容器配置
singularity {
    enabled = true
    autoMounts = true           // 自动挂载宿主目录，确保临时目录可访问
    cacheDir = "$PIPELINE_ROOT/singularity_cache"  // 容器缓存目录（避免重复下载）
}

// 资源调度优化（集群环境适用）
executor {
    name = 'local'              // 若使用集群调度器，可改为 'slurm' 或 'sge'
    queueSize = 8               // 并行任务数量限制（根据集群性能调整）
}
EOF

# 提示完成
echo "✅ nextflow.config 创建成功，路径：$PIPELINE_ROOT/nextflow.config"
echo "✅ 全局临时目录已准备：$GLOBAL_TMP"
echo "请重新运行管道时添加 -resume 参数"