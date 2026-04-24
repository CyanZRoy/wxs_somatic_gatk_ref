task bsrq_apply_bqsr_spark {

    # 输入来自 mark_duplicates_spark 的 BAM
    File dedup_bam
    File dedup_bam_index
    File? intervals_bed
    String interval_padding

    # 输入来自 bqsr_base_recalibrator_spark 的 table
    File recalibration_table

    # 参考基因组
    File ref_dir
    String fasta

    String sample_id

    # --- 平台特定输入 ---
    String docker_image
    String cluster_config # e.g., "ecs.g6.4xlarge" for 16c/32GB


    # 定义输出文件的名称
    String output_bam_name = "${sample_id}.recal.bam"

    # 机器有 16 核，全部分配给 Spark Executor
    Int spark_executor_cores = 16
    # 机器有 32GB 内存，为主进程留 6GB，剩下 26GB 给 Spark
    Int java_driver_memory_gb = 6
    Int spark_executor_memory_gb = 26

    # 磁盘空间估算：输入 BAM * 2.5 (为 shuffle 和输出留足空间) + 参考基因组大小 + 20GB
    Int disk_gb = ceil(size(dedup_bam, "GB") * 4) + 420

    command <<<
        set -e

        if [ ${intervals_bed} ]; then
            INTERVAL="--intervals ${intervals_bed} --interval-padding ${interval_padding}"
        else
            INTERVAL=""
        fi

        gatk --java-options "-Xmx${java_driver_memory_gb}G" ApplyBQSRSpark \
            -R ${ref_dir}/${fasta} \
            -I ${dedup_bam} \
            --bqsr-recal-file ${recalibration_table} \
            -O ${output_bam_name} \
            $INTERVAL \
            --conf 'spark.executor.cores=${spark_executor_cores}' \
            --conf 'spark.executor.memory=${spark_executor_memory_gb}g'
    >>>

    output {
        # ApplyBQSRSpark 会自动为输出的 BAM 文件生成索引
        File recalibrated_bam = output_bam_name
        File recalibrated_bam_index = "${output_bam_name}.bai"
    }

    runtime {
        docker: docker_image
        cluster: cluster_config
        systemDisk: "cloud_ssd 40"
        dataDisk: "cloud_ssd " + disk_gb + " /cromwell_root/"
    }
}