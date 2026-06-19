task fastp_qc {

    File fastq1_gz      # Input FASTQ R1.
    File fastq2_gz      # Input FASTQ R2.
    String sample_id    # Sample name used to prefix outputs.
    # Platform runtime inputs.
    String docker_image
    String cluster_config # e.g., "ecs.g6.4xlarge" for 16c/32GB

    # Estimate disk from FASTQ size with additional buffer for trimmed outputs.
    Int raw_disk_gb = ceil(size(fastq1_gz, "GB") + size(fastq2_gz, "GB")) * 2 + 120
    Int disk_gb = if raw_disk_gb > 1000 then 1000 else raw_disk_gb

    # Run shell commands in the task container.
    command <<<
        # Stop immediately when any command fails.
        set -e
        call_dir="$PWD"
        copy_task_logs() {
            cp -f "$call_dir/script" "$call_dir/script.txt" 2>/dev/null || true
            cp -f "$call_dir/stdout" "$call_dir/stdout.txt" 2>/dev/null || true
            cp -f "$call_dir/stderr" "$call_dir/stderr.txt" 2>/dev/null || true
        }
        trap copy_task_logs EXIT
        local_work="/tmp/${sample_id}_fastp"
        mkdir -p "$local_work"
        cp -f ${fastq1_gz} "$local_work/input_R1.fq.gz"
        cp -f ${fastq2_gz} "$local_work/input_R2.fq.gz"
        cd "$local_work"

        # Trim paired FASTQs and generate fastp HTML/JSON QC reports.
        fastp --thread $(nproc) \
              -i input_R1.fq.gz \
              -I input_R2.fq.gz \
              -o "${sample_id}_1.trimmed.fq.gz" \
              -O "${sample_id}_2.trimmed.fq.gz" \
              -h "${sample_id}.html" \
              -j "${sample_id}.json"
        cp -f "${sample_id}_1.trimmed.fq.gz" "${sample_id}_2.trimmed.fq.gz" "${sample_id}.html" "${sample_id}.json" "$call_dir"/
    >>>

    # Files exported by this task.
    output {
        File trimmed_fastq1 = "${sample_id}_1.trimmed.fq.gz"
        File trimmed_fastq2 = "${sample_id}_2.trimmed.fq.gz"
        File html_report = "${sample_id}.html"
        File json_report = "${sample_id}.json"
    }

    # Container image and cloud runtime resources.
    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
