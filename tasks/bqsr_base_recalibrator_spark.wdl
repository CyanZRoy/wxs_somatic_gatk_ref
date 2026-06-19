task bqsr_base_recalibrator_spark {

    # Deduplicated BAM from MarkDuplicatesSpark.
    File dedup_bam
    File dedup_bam_index
    String sample_id
    File? intervals_bed
    String interval_padding

    # Reference FASTA directory.
    File ref_dir
    String fasta

    # Known-sites resources used by BaseRecalibrator.
    File dbsnp_dir
    String dbsnp
    File dbmills_dir
    String db_mills

    # Platform runtime inputs.
    String docker_image
    String cluster_config


    # Output recalibration table name.
    String recal_table_filename = "${sample_id}.recal_data.table"

    # Spark resource settings for BaseRecalibratorSpark.
    Int spark_executor_cores = 12 
    # Keep memory for the driver and assign the rest to Spark executor.
    Int java_driver_memory_gb = 6
    Int spark_executor_memory_gb = 26

    # Estimate disk for BAM input, Spark temporary files, and known-sites resources.
    Int raw_disk_gb = ceil(size(dedup_bam, "GB"))*4 + 420
    Int disk_gb = if raw_disk_gb > 1000 then 1000 else raw_disk_gb

    command <<<
        set -e
        call_dir="$PWD"
        copy_task_logs() {
            cp -f "$call_dir/script" "$call_dir/script.txt" 2>/dev/null || true
            cp -f "$call_dir/stdout" "$call_dir/stdout.txt" 2>/dev/null || true
            cp -f "$call_dir/stderr" "$call_dir/stderr.txt" 2>/dev/null || true
        }
        trap copy_task_logs EXIT
        local_work="/tmp/${sample_id}_bqsr_recal"
        mkdir -p "$local_work" "$local_work/tmp" "$local_work/spark"
        export TMPDIR="$local_work/tmp"
        export TMP="$TMPDIR"
        export TEMP="$TMPDIR"
        export _JAVA_OPTIONS="-Djava.io.tmpdir=$TMPDIR"
        cp -f ${dedup_bam} "$local_work/input.bam"
        cp -f ${dedup_bam_index} "$local_work/input.bam.bai"
        cp -f ${dbsnp_dir}/${dbsnp}* "$local_work"/
        cp -f ${dbmills_dir}/${db_mills}* "$local_work"/
        cd "$local_work"

        if [ ${intervals_bed} ]; then
            INTERVAL="--intervals ${intervals_bed} --interval-padding ${interval_padding}"
        else
            INTERVAL=""
        fi

        gatk --java-options "-Djava.io.tmpdir=$TMPDIR -Xmx${java_driver_memory_gb}G" BaseRecalibratorSpark \
            -R ${ref_dir}/${fasta} \
            -I input.bam \
            --known-sites ${dbsnp} \
            --known-sites ${db_mills} \
            -O ${recal_table_filename} \
            $INTERVAL \
            --conf "spark.local.dir=$local_work/spark" \
            --conf 'spark.executor.cores=${spark_executor_cores}' \
            --conf 'spark.executor.memory=${spark_executor_memory_gb}g'
        cp -f ${recal_table_filename} "$call_dir"/
    >>>

    output {
        File recalibration_table = recal_table_filename
    }

    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
