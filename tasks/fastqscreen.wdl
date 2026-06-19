task fastq_screen_contamination {

    # Trimmed FASTQs from fastp. This task is not imported by the main workflow.
    File trimmed_fastq1
    File trimmed_fastq2

    # fastq_screen configuration file.
    File fastq_screen_conf

    # Optional thread count and subsampling size.
    Int threads = 16
    Int subset_n = 1000000


    # Derive output prefixes from input FASTQ names.
    String base_name_1 = basename(trimmed_fastq1, ".fq.gz")
    String base_name_2 = basename(trimmed_fastq2, ".fq.gz")

    # Estimate disk from FASTQ size.
    Int raw_disk_gb = ceil(size(trimmed_fastq1, "GB") + size(trimmed_fastq2, "GB")) + 80
    Int disk_gb = if raw_disk_gb > 1000 then 1000 else raw_disk_gb

    command <<<
        set -e

        # Run contamination screening. Outputs are written to the task working directory.
        fastq_screen --aligner bowtie2 \
                     --conf ${fastq_screen_conf} \
                     --subset ${subset_n} \
                     --threads $(nproc) \
                     ${trimmed_fastq1}

        fastq_screen --aligner bowtie2 \
                     --conf ${fastq_screen_conf} \
                     --subset ${subset_n} \
                     --threads $(nproc) \
                     ${trimmed_fastq2}
    >>>

    output {
        # fastq_screen usually produces PNG and TXT outputs.
        File screen_txt_1 = "${base_name_1}_screen.txt"
        File screen_png_1 = "${base_name_1}_screen.png"

        File screen_txt_2 = "${base_name_2}_screen.txt"
        File screen_png_2 = "${base_name_2}_screen.png"
    }

    runtime {
        # Pin a public image that includes fastq_screen and bowtie2.
        docker: "quay.io/biocontainers/fastq_screen:0.14.1--pl5262h1b792b2_2"
        memory: "16 GB"
        cpu: threads
        disks: "local-disk " + disk_gb + " SSD"
    }
}
