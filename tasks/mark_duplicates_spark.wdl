task mark_duplicates_spark {

    # 输入来自 bwa_mem_and_sort task
    File input_bam
    File input_bam_index  # GATK tools require the index file
    String sample_id

    # --- 平台特定输入 ---
    String docker_image
    String cluster_config # e.g., "ecs.g6.4xlarge" for 16c/32GB


    # 定义输出文件的名称
    String output_bam_name = "${sample_id}.dedup.bam"
    String metrics_file_name = "${sample_id}.metrics.txt"

    # 磁盘空间估算：输入 BAM * 2.5 (为 shuffle 空间和输出留足余量) + 20GB 缓冲
    Int disk_gb = ceil(size(input_bam, "GB") * 4) + 420

    # 机器有 16 核，全部分配给 Spark Executor
    Int spark_executor_cores = 16
    # 机器有 32GB 内存，为主进程留 6GB，剩下 26GB 给 Spark
    Int java_driver_memory_gb = 6
    Int spark_executor_memory_gb = 26

    command <<<
        set -e

        # GATK Spark 工具需要通过 --java-options 为主进程分配内存
        # 并通过 --conf 为 Spark 的执行器 (executors) 分配资源
        gatk --java-options "-Xmx${java_driver_memory_gb}G" MarkDuplicatesSpark \
            -I ${input_bam} \
            -O ${output_bam_name} \
            -M ${metrics_file_name} \
            --conf 'spark.executor.cores=${spark_executor_cores}' \
            --conf 'spark.executor.memory=${spark_executor_memory_gb}g'
    >>>

    output {
        # MarkDuplicatesSpark 会自动为输出的 BAM 文件生成索引
        File dedup_bam = output_bam_name
        File dedup_bam_index = "${output_bam_name}.bai"
        File dedup_metrics = metrics_file_name
    }

    runtime {
        docker: docker_image
        cluster: cluster_config
        systemDisk: "cloud_ssd 40"
        dataDisk: "cloud_ssd " + disk_gb + " /cromwell_root/"
    }
}