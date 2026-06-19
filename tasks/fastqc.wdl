task fastqc {

    # Trimmed paired FASTQs from fastp.
    File trimmed_fastq1
    File trimmed_fastq2
    String sample_id
    # Platform runtime inputs.
    String docker_image
    String cluster_config


    # Derive output prefixes from input FASTQ names.
    String base_name_1 = basename(trimmed_fastq1, ".fq.gz")
    String base_name_2 = basename(trimmed_fastq2, ".fq.gz")

    # Estimate disk from input FASTQ size.
    Int raw_disk_gb = ceil(size(trimmed_fastq1, "GB") + size(trimmed_fastq2, "GB")) + 120
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
        local_work="/tmp/${sample_id}_fastqc"
        mkdir -p "$local_work"
        cp -f ${trimmed_fastq1} "$local_work/${base_name_1}.fq.gz"
        cp -f ${trimmed_fastq2} "$local_work/${base_name_2}.fq.gz"
        cd "$local_work"

        # Run FastQC and write reports in the local work directory.
        fastqc -t $(nproc) \
               "${base_name_1}.fq.gz" \
               "${base_name_2}.fq.gz" \
               -o .
        cp -f "${base_name_1}_fastqc.html" "${base_name_1}_fastqc.zip" "${base_name_2}_fastqc.html" "${base_name_2}_fastqc.zip" "$call_dir"/
    >>>

    output {
        # FastQC produces one HTML report and one ZIP archive per FASTQ.
        File html_report_1 = "${base_name_1}_fastqc.html"
        File zip_archive_1 = "${base_name_1}_fastqc.zip"
        File html_report_2 = "${base_name_2}_fastqc.html"
        File zip_archive_2 = "${base_name_2}_fastqc.zip"
    }

    # Container image and cloud runtime resources.
    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
