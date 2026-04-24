task fastq_screen_contamination {

    # 输入与我们上游的 fastp task 输出保持一致
    File trimmed_fastq1
    File trimmed_fastq2

    # 配置文件是必须的输入
    File fastq_screen_conf

    # 将线程数和抽样数作为可配置的输入，并提供默认值
    Int threads = 16
    Int subset_n = 1000000


    # 使用 WDL 内置函数获取输入文件的基本名称，这比之前的 basename(basename(...)) 写法更简洁
    String base_name_1 = basename(trimmed_fastq1, ".fq.gz")
    String base_name_2 = basename(trimmed_fastq2, ".fq.gz")

    # WDL 标准的磁盘空间估算
    Int disk_gb = ceil(size(trimmed_fastq1, "GB") + size(trimmed_fastq2, "GB")) + 80

    command <<<
        set -e

        # 执行 screening
        # --outdir 未指定，默认输出到当前目录，这是 WDL 的推荐做法
        # 使用 nproc 自动获取分配到的 CPU 核心数，这是一个非常好的实践
        fastq_screen --aligner bowtie2 \
                     --conf ${fastq_screen_conf} \
                     --subset ${subset_n} \
                     --threads $(nproc) \
                     ${trimmed_fastq1}

        fastq_screen --aligner bowtie2 \
                     --conf ${fastq_screen_conf} \
                     --subset ${subset_n} \
                     --threads $(nproc) \
                     ${trimmed_fastq2}
    >>>

    output {
        # 根据 fastq_screen 的实际输出捕获文件
        # 注意：fastq_screen 通常只生成 .png 和 .txt 文件，不生成 .html
        File screen_txt_1 = "${base_name_1}_screen.txt"
        File screen_png_1 = "${base_name_1}_screen.png"

        File screen_txt_2 = "${base_name_2}_screen.txt"
        File screen_png_2 = "${base_name_2}_screen.png"
    }

    runtime {
        # 使用一个公开的、包含 fastq_screen 和 bowtie2 的 Docker 镜像
        # 将 Docker 镜像固定下来，而不是作为输入，能保证流程的稳定性
        docker: "quay.io/biocontainers/fastq_screen:0.14.1--pl5262h1b792b2_2"
        memory: "16 GB"
        cpu: threads  # 请求的 CPU 数量，$(nproc) 会在容器内使用这个数量
        disks: "local-disk " + disk_gb + " SSD" # 标准的磁盘定义
    }
}