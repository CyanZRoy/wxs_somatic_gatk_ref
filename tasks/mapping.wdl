task bwa_mem_and_sort {

    # Trimmed FASTQs from fastp.
    File trimmed_fastq1
    File trimmed_fastq2
    String sample_id

    # Reference directory. BWA index files must be beside the FASTA.
    File ref_dir
    String fasta

    # Read group and platform settings.
    String platform
    # Platform runtime inputs.
    String docker_image
    String cluster_config # e.g., "ecs.g6.8xlarge" for 32c/64GB


    # Read group is required by downstream GATK tools.
    String read_group = "@RG\\tID:${sample_id}\\tSM:${sample_id}\\tPL:${platform}"

    # Sorted BAM output name.
    String output_bam_name = "${sample_id}.sorted.bam"

    # Estimate disk for FASTQs, sorted BAM, temporary sort files, and reference files.
    Int raw_disk_gb = ceil(size(trimmed_fastq1, "GB") + size(trimmed_fastq2, "GB")) * 2 + 320
    Int disk_gb = if raw_disk_gb > 1000 then 1000 else raw_disk_gb

    # Align reads with BWA, convert to BAM, and coordinate-sort with samtools.
    command <<<
        # pipefail makes alignment/sort failures stop the task.
        set -e -o pipefail
        call_dir="$PWD"
        copy_task_logs() {
            cp -f "$call_dir/script" "$call_dir/script.txt" 2>/dev/null || true
            cp -f "$call_dir/stdout" "$call_dir/stdout.txt" 2>/dev/null || true
            cp -f "$call_dir/stderr" "$call_dir/stderr.txt" 2>/dev/null || true
        }
        trap copy_task_logs EXIT
        local_work="/tmp/${sample_id}_mapping"
        mkdir -p "$local_work"
        cp -f ${trimmed_fastq1} "$local_work/read1.fq.gz"
        cp -f ${trimmed_fastq2} "$local_work/read2.fq.gz"

        # BWA MEM -> BAM conversion -> coordinate sort.
        bwa mem -M \
                -R '${read_group}' \
                -t $(nproc) \
                ${ref_dir}/${fasta} \
                "$local_work/read1.fq.gz" \
                "$local_work/read2.fq.gz" | \
        samtools view -bS -@ $(nproc) - | \
        samtools sort -@ $(nproc) -T "$local_work/${sample_id}.sorttmp" -o "$local_work/${output_bam_name}" -

        # Create BAM index for downstream GATK tasks.
        samtools index -@ $(nproc) "$local_work/${output_bam_name}"
        cp -f "$local_work/${output_bam_name}" ${output_bam_name}
        cp -f "$local_work/${output_bam_name}.bai" ${output_bam_name}.bai
    >>>

    output {
        File sorted_bam = output_bam_name
        File sorted_bam_index = "${output_bam_name}.bai"
    }

    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
