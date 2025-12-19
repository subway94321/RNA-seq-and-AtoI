#!/bin/bash
#SBATCH -J add_anno          # 任务名（参考文件下载）
#SBATCH -p low               # 队列（与你的Nextflow任务队列一致）
#SBATCH -N 1                 # 单节点
#SBATCH --output=log.%j.out  # 标准输出日志（记录下载进度）
#SBATCH --error=log.%j.err   # 错误日志（排查下载失败原因）
#SBATCH --cpus-per-task=1    # 单线程任务，1核足够（避免资源浪费）
#SBATCH --mem=4G             # 指定内存（根据数据大小调整）

# 加载conda环境（添加时间戳和详细日志）
echo "$(date +'%Y-%m-%d %H:%M:%S') - 开始加载conda环境..."
source /cluster/home/sunxiaozhi/miniconda3/bin/activate my_tools || {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: 加载conda环境失败！请检查环境名称或conda路径" >&2
    exit 1
}
echo "$(date +'%Y-%m-%d %H:%M:%S') - 成功加载conda环境：my_tools"

# 验证关键依赖是否安装
echo "$(date +'%Y-%m-%d %H:%M:%S') - 验证依赖包..."
python3 -c "import pandas; print(f'pandas版本：{pandas.__version__}')" || {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR: pandas未安装！" >&2
    exit 1
}
echo "$(date +'%Y-%m-%d %H:%M:%S') - 依赖包验证通过"

python3 << 'EOF'
import os
import pandas as pd
from glob import glob
from pathlib import Path
import sys

def check_anno_files(anno_dir):
    """检查指定目录下*.anno.tsv文件数量，确保唯一"""
    anno_pattern = os.path.join(anno_dir, "*.anno.tsv")
    anno_files = glob(anno_pattern)
    
    file_count = len(anno_files)
    print(f"\n=== 注释文件检查 ===")
    print(f"检查目录：{anno_dir}")
    print(f"匹配模式：{anno_pattern}")
    
    if file_count == 0:
        print(f"❌ 错误：未找到*.anno.tsv文件")
        return None
    elif file_count > 1:
        print(f"❌ 错误：找到{file_count}个*.anno.tsv文件（仅允许1个）：")
        for f in anno_files:
            print(f"  - {os.path.basename(f)}")
        return None
    else:
        anno_file = anno_files[0]
        print(f"✅ 找到唯一注释文件：{os.path.basename(anno_file)}")
        return anno_file

def add_gene_name(deseq_file, anno_file):
    """为差异分析结果添加gene_name列（通用函数，兼容两类文件）"""
    try:
        deseq_df = pd.read_csv(
            deseq_file,
            sep='\t',
            encoding='utf-8',
            dtype={'gene_id': str},
            low_memory=False
        )
    except Exception as e:
        print(f"❌ 读取文件失败：{os.path.basename(deseq_file)}")
        print(f"错误信息：{str(e)}")
        raise
    
    # 读取注释文件并处理空值
    anno_df = pd.read_csv(
        anno_file,
        sep='\t',
        encoding='utf-8',
        usecols=['gene_id', 'gene_name'],
        dtype={'gene_id': str, 'gene_name': str},
        low_memory=False
    ).drop_duplicates(subset='gene_id', keep='first')
    anno_df['gene_name'] = anno_df['gene_name'].fillna("NA")
    gene_name_map = anno_df.set_index('gene_id')['gene_name'].to_dict()
    
    # 添加并填充gene_name列
    deseq_df['gene_name'] = deseq_df['gene_id'].map(gene_name_map).fillna("NA")
    
    # 调整列顺序
    col_order = ['gene_id', 'gene_name'] + [col for col in deseq_df.columns if col not in ['gene_id', 'gene_name']]
    deseq_anno_df = deseq_df[col_order]
    
    # 输出统计信息
    total_genes = len(deseq_df)
    matched_genes = (deseq_df['gene_name'] != "NA").sum()
    print(f"  - 总基因数：{total_genes}")
    print(f"  - 成功匹配gene_name：{matched_genes}")
    print(f"  - 未匹配基因数：{total_genes - matched_genes}")
    
    return deseq_anno_df

def get_contrasts_list(contrasts_file):
    """从对比文件中读取contrast列表"""
    print(f"\n=== 读取对比列表 ===")
    if not os.path.exists(contrasts_file):
        print(f"❌ 错误：对比文件不存在：{contrasts_file}")
        return None
    
    try:
        contrasts_df = pd.read_csv(contrasts_file, header=0, encoding='utf-8', low_memory=False)
    except Exception as e:
        print(f"❌ 读取对比文件失败：{str(e)}")
        return None
    
    if 'id' not in contrasts_df.columns:
        print(f"❌ 错误：对比文件缺少'id'列")
        return None
    
    contrasts_list = contrasts_df['id'].dropna().unique().tolist()
    print(f"✅ 成功读取{len(contrasts_list)}个对比组")
    return contrasts_list

def process_all_deseq_files(contrasts_list, differential_dir, output_dir, anno_file):
    """批量处理两类deseq2结果文件：普通版和filtered版"""
    # 定义要处理的文件后缀和输出后缀映射
    file_suffix_map = {
        ".deseq2.results.tsv": ".deseq2.results.anno.tsv",
        ".deseq2.results_filtered.tsv": ".deseq2.results_filtered.anno.tsv"
    }
    
    total_files = len(contrasts_list) * len(file_suffix_map)
    success_count = 0
    fail_list = []
    
    print(f"\n=== 开始批量处理（共{len(contrasts_list)}个对比组，{len(file_suffix_map)}类文件，总计{total_files}个文件）===")
    
    for suffix, output_suffix in file_suffix_map.items():
        print(f"\n--- 处理{suffix}类型文件 ---")
        for idx, contrast in enumerate(contrasts_list, 1):
            # 构建输入输出路径
            input_file = differential_dir / f"{contrast}{suffix}"
            output_file = output_dir / f"{contrast}{output_suffix}"
            
            print(f"\n[{idx}/{len(contrasts_list)}] 处理对比组：{contrast}")
            print(f"  输入文件：{input_file.name}")
            
            # 检查输入文件是否存在
            if not input_file.exists():
                print(f"  ❌ 跳过：文件不存在")
                fail_list.append(f"{contrast}{suffix}")
                continue
            
            # 执行注释添加
            try:
                anno_df = add_gene_name(str(input_file), anno_file)
                anno_df.to_csv(
                    str(output_file),
                    sep='\t',
                    index=False,
                    encoding='utf-8'
                )
                print(f"  ✅ 成功生成：{output_file.name}")
                success_count += 1
            except Exception as e:
                print(f"  ❌ 处理失败：{str(e)}")
                fail_list.append(f"{contrast}{suffix}")
                continue
    
    return success_count, fail_list, total_files

if __name__ == "__main__":
    print("="*50)
    print("          开始执行差异分析结果注释流程（双文件类型）")
    print(f"执行时间：{pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*50)
    
    # 1. 定义路径
    base_dir = Path(os.getcwd())
    summary_output_dir = base_dir / "nf_output_DA_basedon_ranseq" / "summary_for_visualization"
    DA_output_dir = base_dir / "nf_output_DA_basedon_ranseq" / "tables"
    anno_file_dir = DA_output_dir / "annotation"
    differential_files_dir = DA_output_dir / "differential"
    contrasts_file_path = base_dir / "contrasts_DA.csv"
    
    # 2. 创建输出目录
    summary_output_dir.mkdir(parents=True, exist_ok=True)
    print(f"\n=== 路径配置 ===")
    print(f"输出目录：{summary_output_dir}")
    print(f"差异文件目录：{differential_files_dir}")
    print(f"注释文件目录：{anno_file_dir}")
    print(f"对比文件：{contrasts_file_path}")
    
    # 3. 前置检查
    unique_anno_file = check_anno_files(str(anno_file_dir))
    contrasts_list = get_contrasts_list(str(contrasts_file_path))
    
    if not unique_anno_file or not contrasts_list:
        print(f"\n❌ 前置检查失败，程序终止")
        sys.exit(1)
    
    # 4. 批量处理两类文件
    success_count, fail_list, total_files = process_all_deseq_files(
        contrasts_list=contrasts_list,
        differential_dir=differential_files_dir,
        output_dir=summary_output_dir,
        anno_file=unique_anno_file
    )
    
    # 5. 执行总结
    print("\n" + "="*50)
    print("                    执行完成总结")
    print(f"完成时间：{pd.Timestamp.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*50)
    print(f"总文件数量：{total_files}")
    print(f"成功处理：{success_count} 个")
    print(f"处理失败：{len(fail_list)} 个")
    print(f"成功率：{success_count/total_files:.2%}" if total_files > 0 else "成功率：0%")
    
    if fail_list:
        print(f"\n失败的文件：")
        for fail_file in fail_list:
            print(f"  - {fail_file}")
    print(f"\n输出文件目录：{summary_output_dir}")
    print("="*50)
EOF

# 退出conda环境
echo "$(date +'%Y-%m-%d %H:%M:%S') - 退出conda环境"
conda deactivate
echo "$(date +'%Y-%m-%d %H:%M:%S') - 脚本执行完毕"