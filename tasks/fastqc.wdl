task fastqc {

    # 输入是两个经过 trim 的 FASTQ 文件
    File trimmed_fastq1
    File trimmed_fastq2
    String sample_id
    # --- 平台特定输入 ---
    String docker_image
    String cluster_config


    # 从输入文件名中提取基本名称，用于构造输出文件名
    # 例如，从 "sample1_1.trimmed.fq.gz" 提取 "sample1_1.trimmed"
    String base_name_1 = basename(trimmed_fastq1, ".fq.gz")
    String base_name_2 = basename(trimmed_fastq2, ".fq.gz")

    # 估算磁盘空间
    Int disk_gb = ceil(size(trimmed_fastq1, "GB") + size(trimmed_fastq2, "GB")) + 50

    command <<<
        set -e

        # fastqc 会自动在指定的输出目录中创建报告文件
        # -o . 表示将输出文件生成在当前工作目录中
        # 这在 WDL 中是标准做法，不需要再手动创建目录
        fastqc -t $(nproc) \
               ${trimmed_fastq1} \
               ${trimmed_fastq2} \
               -o .
    >>>

    output {
        # fastqc 为每个输入文件生成一个 html 报告和一个 zip 压缩包
        # 我们使用之前定义的 base_name 变量来捕获正确的输出文件名
        File html_report_1 = "${base_name_1}_fastqc.html"
        File zip_archive_1 = "${base_name_1}_fastqc.zip"
        File html_report_2 = "${base_name_2}_fastqc.html"
        File zip_archive_2 = "${base_name_2}_fastqc.zip"
    }

    # runtime 块定义任务运行所需的环境和资源
    runtime {
        docker: docker_image
        cluster: cluster_config
        systemDisk: "cloud_ssd 40"
        dataDisk: "cloud_ssd " + disk_gb + " /cromwell_root/"
    }
}