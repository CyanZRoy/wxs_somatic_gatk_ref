task fastp_qc {

    File fastq1_gz      # 输入文件 R1，WDL 中用 File 类型表示
    File fastq2_gz      # 输入文件 R2
    String sample_id    # 样本名，用于命名输出文件
    # --- 平台特定输入 ---
    String docker_image
    String cluster_config # e.g., "ecs.g6.4xlarge" for 16c/32GB

    # 根据输入文件大小估算所需磁盘空间，这是一个好习惯
    # 公式：输入文件大小之和 * 2 (预估输出) + 20GB (额外缓冲)
    Int disk_gb = ceil(size(fastq1_gz, "GB") + size(fastq2_gz, "GB")) * 2 + 80

    # command 块中是实际要执行的 shell 命令
    command <<<
        # -e 表示命令失败时任务立即失败，增强健壮性
        set -e

        # 执行 fastp 命令
        # WDL 会自动将输入文件拉取到任务的工作目录
        fastp --thread $(nproc) \
              -i ${fastq1_gz} \
              -I ${fastq2_gz} \
              -o "${sample_id}_1.trimmed.fq.gz" \
              -O "${sample_id}_2.trimmed.fq.gz" \
              -h "${sample_id}.html" \
              -j "${sample_id}.json"
    >>>

    # output 块定义任务成功后要输出的文件
    output {
        File trimmed_fastq1 = "${sample_id}_1.trimmed.fq.gz"
        File trimmed_fastq2 = "${sample_id}_2.trimmed.fq.gz"
        File html_report = "${sample_id}.html"
        File json_report = "${sample_id}.json"
    }

    # runtime 块定义任务运行所需的环境和资源
    runtime {
        docker: docker_image
        cluster: cluster_config
        systemDisk: "cloud_ssd 40"
        dataDisk: "cloud_ssd " + disk_gb + " /cromwell_root/"
    }
}