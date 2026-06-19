task mark_duplicates_spark {

    # Sorted BAM from BWA alignment.
    File input_bam
    File input_bam_index  # GATK tools require the index file
    String sample_id

    # Platform runtime inputs.
    String docker_image
    String cluster_config # e.g., "ecs.g6.4xlarge" for 16c/32GB


    # Output BAM and metrics file names.
    String output_bam_name = "${sample_id}.dedup.bam"
    String metrics_file_name = "${sample_id}.metrics.txt"

    # Estimate disk for BAM input, Spark shuffle, and output BAM.
    Int raw_disk_gb = ceil(size(input_bam, "GB") * 4) + 420
    Int disk_gb = if raw_disk_gb > 1000 then 1000 else raw_disk_gb

    # Spark resource settings for duplicate marking.
    Int spark_executor_cores = 16
    # Keep memory for the driver and assign the rest to Spark executor.
    Int java_driver_memory_gb = 6
    Int spark_executor_memory_gb = 26

    command <<<
        set -e
        call_dir="$PWD"
        copy_task_logs() {
            cp -f "$call_dir/script" "$call_dir/script.txt" 2>/dev/null || true
            cp -f "$call_dir/stdout" "$call_dir/stdout.txt" 2>/dev/null || true
            cp -f "$call_dir/stderr" "$call_dir/stderr.txt" 2>/dev/null || true
        }
        trap copy_task_logs EXIT
        local_work="/tmp/${sample_id}_markdup"
        mkdir -p "$local_work" "$local_work/tmp" "$local_work/spark"
        export TMPDIR="$local_work/tmp"
        export TMP="$TMPDIR"
        export TEMP="$TMPDIR"
        export _JAVA_OPTIONS="-Djava.io.tmpdir=$TMPDIR"
        cp -f ${input_bam} "$local_work/input.bam"
        cp -f ${input_bam_index} "$local_work/input.bam.bai"
        cd "$local_work"

        # Mark duplicate reads and write Picard-style duplicate metrics.
        gatk --java-options "-Djava.io.tmpdir=$TMPDIR -Xmx${java_driver_memory_gb}G" MarkDuplicatesSpark \
            -I input.bam \
            -O ${output_bam_name} \
            -M ${metrics_file_name} \
            --conf "spark.local.dir=$local_work/spark" \
            --conf 'spark.executor.cores=${spark_executor_cores}' \
            --conf 'spark.executor.memory=${spark_executor_memory_gb}g'
        cp -f ${output_bam_name} ${output_bam_name}.bai ${metrics_file_name} "$call_dir"/
    >>>

    output {
        # MarkDuplicatesSpark writes the BAM index automatically.
        File dedup_bam = output_bam_name
        File dedup_bam_index = "${output_bam_name}.bai"
        File dedup_metrics = metrics_file_name
    }

    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
