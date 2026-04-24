task bqsr_base_recalibrator_spark {

    # 输入来自 mark_duplicates_spark task
    File dedup_bam
    File dedup_bam_index
    String sample_id
    File? intervals_bed
    String interval_padding

    # 参考基因组和相关文件
    File ref_dir
    String fasta

    # 已知变异位点文件 (例如 dbSNP)
    File dbsnp_dir
    String dbsnp
    File dbmills_dir
    String db_mills

    # --- 平台特定输入 ---
    String docker_image
    String cluster_config


    # 定义输出文件的名称
    String recal_table_filename = "${sample_id}.recal_data.table"

    # 机器有 16 核，但根据要求，只为 Spark 分配 12 个线程
    Int spark_executor_cores = 12 
    # 机器有 32GB 内存，为主进程留 6GB，剩下 26GB 给 Spark
    Int java_driver_memory_gb = 6
    Int spark_executor_memory_gb = 26

    # 磁盘空间估算：输入 BAM 大小 + 参考基因组大小 + 20GB 缓冲
    Int disk_gb = ceil(size(dedup_bam, "GB"))*4 + 420

    command <<<
        set -e

        if [ ${intervals_bed} ]; then
            INTERVAL="--intervals ${intervals_bed} --interval-padding ${interval_padding}"
        else
            INTERVAL=""
        fi

        gatk --java-options "-Xmx${java_driver_memory_gb}G" BaseRecalibratorSpark \
            -R ${ref_dir}/${fasta} \
            -I ${dedup_bam} \
            --known-sites ${dbsnp_dir}/${dbsnp} \
            --known-sites ${dbmills_dir}/${db_mills} \
            -O ${recal_table_filename} \
            $INTERVAL \
            --conf 'spark.executor.cores=${spark_executor_cores}' \
            --conf 'spark.executor.memory=${spark_executor_memory_gb}g'
    >>>

    output {
        File recalibration_table = recal_table_filename
    }

    runtime {
        docker: docker_image
        cluster: cluster_config
        systemDisk: "cloud_ssd 40"
        dataDisk: "cloud_ssd " + disk_gb + " /cromwell_root/"
    }
}