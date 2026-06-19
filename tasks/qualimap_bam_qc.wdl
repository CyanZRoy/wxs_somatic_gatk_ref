task qualimap_bam_qc {

    # Input from the ApplyBQSR step
    File recalibrated_bam
    File recalibrated_bam_index
    String sample_id

    # A BED or GFF file with gene/feature definitions
    File? intervals_bed

    # Platform runtime inputs.
    String docker_image
    String cluster_config


    # Define the name for the output directory and the final archive
    String output_dir_name = "${sample_id}_qualimap_results"
    String output_archive_name = "${sample_id}.qualimap_results.tar.gz"

    # Disk space estimation: Input BAM size * 2 (for temp files) + 20GB buffer
    Int raw_disk_gb = ceil(size(recalibrated_bam, "GB") * 3) + 320
    Int disk_gb = if raw_disk_gb > 1000 then 1000 else raw_disk_gb

    # Java heap for Qualimap. Keep some memory for the OS and Cromwell runtime.
    Int java_mem_gb = 28

    command <<<
        set -e
        call_dir="$PWD"
        copy_task_logs() {
            cp -f "$call_dir/script" "$call_dir/script.txt" 2>/dev/null || true
            cp -f "$call_dir/stdout" "$call_dir/stdout.txt" 2>/dev/null || true
            cp -f "$call_dir/stderr" "$call_dir/stderr.txt" 2>/dev/null || true
        }
        trap copy_task_logs EXIT
        local_work="/tmp/${sample_id}_qualimap"
        mkdir -p "$local_work"
        cp -f ${recalibrated_bam} "$local_work/input.bam"
        cp -f ${recalibrated_bam_index} "$local_work/input.bam.bai"
        cd "$local_work"

        if [ ${intervals_bed} ]; then
            awk 'BEGIN{OFS="\t"}{sub("\r","",$3);print $1,$2,$3,"",0,"."}' ${intervals_bed} > new.bed
            INTERVAL="-gff new.bed"
        else
            INTERVAL=""
        fi

        # Run Qualimap, directing its output to a specific directory
        qualimap bamqc \
            -bam input.bam \
            $INTERVAL \
            -nt $(nproc) \
            --java-mem-size=${java_mem_gb}G \
            -outformat PDF:HTML \
            -outdir ${output_dir_name}

        # Compress the entire output directory into a single tarball
        # This makes it easy to manage as a single output file in WDL
        tar -czvf ${output_archive_name} ${output_dir_name}
        cp -f ${output_archive_name} "$call_dir"/
    >>>

    output {
        # The final output is the compressed archive containing all Qualimap reports
        File qualimap_report_archive = output_archive_name
    }

    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
