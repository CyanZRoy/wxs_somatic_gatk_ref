# Quick Start
```
# 准备 samples.csv 文件
$ choppy samples choppy_migration_test/wxs_somatic_gatk_ref > samples.csv
# 准备无默认参数的samples.csv 文件
$ choppy samples --no-default choppy_migration_test/wxs_somatic_gatk_ref> samples.csv

# 提交任务
$ choppy batch choppy_migration_test/wxs_somatic_gatk_ref samples.csv -p Your_project_name -l Your_label

# 查询任务运行状况
$ choppy query -L Your_label | grep "status"

# 查询失败任务
$ choppy search -s Failed -p Your_project_name -u Your_name --short-format
```

# WXS/WGS Tumor-Normal Somatic GATK Pipeline

这个仓库维护一套基于 Cromwell + WDL 的肿瘤/正常配对体细胞突变分析流程，主要面向 `hg19` / `ucsc.hg19.fa` 参考基因组。流程支持 WGS 和 WES 两种模式：提供 `bed_file` 时按 WES 区域运行，不提供时按 WGS 模式运行。

## 主要流程

1. `fastp`：对 tumor/normal 双端 FASTQ 做接头和低质量序列过滤，并输出 HTML/JSON QC 报告。
2. `FastQC`：对过滤后的 FASTQ 做基础质量评估。
3. `BWA MEM + samtools`：比对到 `ucsc.hg19.fa`，生成排序 BAM 和索引。
4. `MarkDuplicatesSpark`：标记重复 reads，并输出 metrics。
5. `BaseRecalibratorSpark / ApplyBQSRSpark`：使用 dbSNP 和 Mills indel known-sites 做 BQSR。
6. `Mutect2`：进行 tumor-normal 配对体细胞突变检测，并使用 germline resource 和 F1R2 统计。
7. `GetPileupSummaries / CalculateContamination`：估计污染比例，并在 `FilterMutectCalls` 中使用。
8. `FilterMutectCalls`：使用 Mutect2 stats、污染估计和 read orientation model 过滤候选突变。
9. `ANNOVAR`：对 PASS VCF 做注释。
10. `Qualimap`：对最终 recalibrated BAM 做 BAM QC。

## 关键文件

- `workflow.wdl`：主 workflow，组织 tumor/normal 分支和后续体细胞突变分析。
- `tasks/`：各分析步骤的 WDL task。
- `defaults`：默认参数，包括参考资源、Docker 镜像和云资源规格。
- `inputs`：Choppy/Cromwell 输入模板。
- `schema.json`：输入参数 schema。
- `manifest.json`：流程元信息。

## 参考资源要求

当前流程按 `hg19` / `ucsc.hg19.fa` 设计。所有资源必须和该参考保持一致，包括：

- FASTA 及 BWA/GATK 索引文件。
- dbSNP known-sites。
- Mills and 1000G indel known-sites。
- Mutect2 germline resource。
- GetPileupSummaries 使用的 common biallelic variants。
- WES BED 文件。
- ANNOVAR `humandb` 中的 hg19 数据库。

如果更换到 b37、GRCh37 或 hg38，不能只替换 FASTA；需要同步替换 contig 命名、contig 长度和所有 VCF/BED/ANNOVAR 资源。

## WES 与 WGS 模式

- WGS：`bed_file` 为空，GATK 步骤不加 interval 限制。
- WES：`bed_file` 指向捕获区域 BED，BQSR、ApplyBQSR、Mutect2、GetPileupSummaries 和 Qualimap 会使用该区域。
- `interval_padding` 用于扩展 BED 区域边界。当前常用值是 `100`，会把分析范围扩展到目标区域上下游 100 bp。

## 主要输出

- `*.sorted.bam`：BWA 比对并排序后的 BAM。
- `*.dedup.bam`：标记重复后的 BAM。
- `*.recal.bam`：BQSR 后的 BAM。
- `*.mutect2.vcf.gz`：Mutect2 原始候选突变。
- `*.filtered.vcf.gz`：FilterMutectCalls 输出，保留所有位点及 FILTER 标记。
- `*.pass.vcf.gz`：只包含 PASS 位点的最终 VCF。
- `*.filteringStats.tsv`：FilterMutectCalls 过滤统计。
- `*.read-orientation-model.tar.gz`：read orientation model。
- `*.contamination.table` 和 `*.segments.table`：污染估计结果。
- `*.hg19_multianno.vcf` 和 `*.hg19_multianno.txt`：ANNOVAR 注释结果。
- `*.qualimap_results.tar.gz`：Qualimap BAM QC 报告。

## 维护注意事项

- `wdl修改部分*.txt`、测试结果目录和排查目录是本地工作文件，已经写入 `.gitignore`，不应提交到 Git。
- 如果真实样本出现 contig 长度越界或坐标异常，优先检查 BED/VCF 是否和 `ucsc.hg19.fa.fai` 一致。
- 如果 ANNOVAR 输入 VCF 没有 PASS 位点，当前 task 会输出空但合法的注释文件，避免 workflow 因空结果失败。
- 资源优化建议基于真实样本 metadata 的任务耗时、输入文件大小和是否重试来做；Cromwell metadata 通常不包含 CPU/内存/磁盘峰值。
