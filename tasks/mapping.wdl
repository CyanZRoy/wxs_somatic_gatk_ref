task bwa_mem_and_sort {

    # 输入来自于 fastp 的输出
    File trimmed_fastq1
    File trimmed_fastq2
    String sample_id

    # 基因组参考文件和相关索引
    # 重要：BWA 需要 .amb, .ann, .bwt, .pac, .sa 索引文件
    # 这些文件必须和 ref_fasta 位于同一个目录下，WDL 才会自动将它们一起定位
    File ref_dir
    String fasta

    # 可配置的参数
    String platform
    # --- 平台特定输入 ---
    String docker_image
    String cluster_config # e.g., "ecs.g6.8xlarge" for 32c/64GB


    # 构造 RG (Read Group) 字符串，这是下游分析 (特别是 GATK) 的标准要求
    String read_group = "@RG\\tID:${sample_id}\\tSM:${sample_id}\\tPL:${platform}"

    # 定义输出文件名
    String output_bam_name = "${sample_id}.sorted.bam"

    # 磁盘空间估算：(输入 FQ x 2.5) + 参考基因组大小 + 20GB 缓冲
    Int disk_gb = ceil(size(trimmed_fastq1, "GB") + size(trimmed_fastq2, "GB")) * 2 + 320

    # `command` 块中复现 shell 管道
    command <<<
        # -e: 命令失败则任务失败
        # -o pipefail: 管道中任何一个命令失败，整个管道都视为失败。这对于发现 bwa 的错误至关重要！
        set -e -o pipefail

        # BWA 比对 -> SAM 转 BAM -> BAM 排序
        bwa mem -M \
                -R '${read_group}' \
                -t $(nproc) \
                ${ref_dir}/${fasta} \
                ${trimmed_fastq1} \
                ${trimmed_fastq2} | \
        samtools view -bS -@ $(nproc) - | \
        samtools sort -@ $(nproc) -o ${output_bam_name} -

        # 为生成的 BAM 文件创建索引，这是后续步骤必需的
        samtools index -@ $(nproc) ${output_bam_name}
    >>>

    output {
        File sorted_bam = output_bam_name
        File sorted_bam_index = "${output_bam_name}.bai"
    }

    runtime {
        docker: docker_image
        cluster: cluster_config
        systemDisk: "cloud_ssd 40"
        dataDisk: "cloud_ssd " + disk_gb + " /cromwell_root/"
    }
}