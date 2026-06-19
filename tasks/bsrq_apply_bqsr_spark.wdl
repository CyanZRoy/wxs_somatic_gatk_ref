task bsrq_apply_bqsr_spark {

    # Deduplicated BAM from MarkDuplicatesSpark.
    File dedup_bam
    File dedup_bam_index
    File? intervals_bed
    String interval_padding

    # Recalibration table from BaseRecalibratorSpark.
    File recalibration_table

    # Reference FASTA directory.
    File ref_dir
    String fasta

    String sample_id

    # Platform runtime inputs.
    String docker_image
    String cluster_config # e.g., "ecs.g6.4xlarge" for 16c/32GB


    # Output recalibrated BAM name.
    String output_bam_name = "${sample_id}.recal.bam"

    # Spark resource settings for ApplyBQSRSpark.
    Int spark_executor_cores = 16
    # Keep memory for the driver and assign the rest to Spark executor.
    Int java_driver_memory_gb = 6
    Int spark_executor_memory_gb = 26

    # Estimate disk for BAM input, Spark shuffle, and recalibrated BAM output.
    Int raw_disk_gb = ceil(size(dedup_bam, "GB") * 4) + 420
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
        local_work="/tmp/${sample_id}_apply_bqsr"
        mkdir -p "$local_work" "$local_work/tmp" "$local_work/spark"
        export TMPDIR="$local_work/tmp"
        export TMP="$TMPDIR"
        export TEMP="$TMPDIR"
        export _JAVA_OPTIONS="-Djava.io.tmpdir=$TMPDIR"
        cp -f ${dedup_bam} "$local_work/input.bam"
        cp -f ${dedup_bam_index} "$local_work/input.bam.bai"
        cp -f ${recalibration_table} "$local_work/recal_data.table"
        cd "$local_work"

        if [ ${intervals_bed} ]; then
            INTERVAL="--intervals ${intervals_bed} --interval-padding ${interval_padding}"
        else
            INTERVAL=""
        fi

        gatk --java-options "-Djava.io.tmpdir=$TMPDIR -Xmx${java_driver_memory_gb}G" ApplyBQSRSpark \
            -R ${ref_dir}/${fasta} \
            -I input.bam \
            --bqsr-recal-file recal_data.table \
            -O ${output_bam_name} \
            $INTERVAL \
            --conf "spark.local.dir=$local_work/spark" \
            --conf 'spark.executor.cores=${spark_executor_cores}' \
            --conf 'spark.executor.memory=${spark_executor_memory_gb}g'
        cp -f ${output_bam_name} ${output_bam_name}.bai "$call_dir"/
    >>>

    output {
        # ApplyBQSRSpark writes the BAM index automatically.
        File recalibrated_bam = output_bam_name
        File recalibrated_bam_index = "${output_bam_name}.bai"
    }

    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
