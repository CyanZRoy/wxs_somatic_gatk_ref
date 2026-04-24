task qualimap_bam_qc {

    # Input from the ApplyBQSR step
    File recalibrated_bam
    File recalibrated_bam_index
    String sample_id

    # A BED or GFF file with gene/feature definitions
    File? intervals_bed

    # --- 平台特定输入 ---
    String docker_image
    String cluster_config


    # Define the name for the output directory and the final archive
    String output_dir_name = "${sample_id}_qualimap_results"
    String output_archive_name = "${sample_id}.qualimap_results.tar.gz"

    # Disk space estimation: Input BAM size * 2 (for temp files) + 20GB buffer
    Int disk_gb = ceil(size(recalibrated_bam, "GB") * 3) + 320

    # 对于 32GB 的机器，为 Qualimap 的 Java 进程分配 28GB，为 OS 预留 4GB
    Int java_mem_gb = 28

    command <<<
        set -e

        if [ ${intervals_bed} ]; then
            awk 'BEGIN{OFS="\t"}{sub("\r","",$3);print $1,$2,$3,"",0,"."}' ${intervals_bed} > new.bed
            INTERVAL="-gff new.bed"
        else
            INTERVAL=""
        fi

        # Run Qualimap, directing its output to a specific directory
        qualimap bamqc \
            -bam ${recalibrated_bam} \
            INTERVAL \
            -nt $(nproc) \
            --java-mem-size=${java_mem_gb}G \
            -outformat PDF:HTML \
            -outdir ${output_dir_name}

        # Compress the entire output directory into a single tarball
        # This makes it easy to manage as a single output file in WDL
        tar -czvf ${output_archive_name} ${output_dir_name}
    >>>

    output {
        # The final output is the compressed archive containing all Qualimap reports
        File qualimap_report_archive = output_archive_name
    }

    runtime {
        docker: docker_image
        cluster: cluster_config
        systemDisk: "cloud_ssd 40"
        dataDisk: "cloud_ssd " + disk_gb + " /cromwell_root/"
    }
}