task somatic_mutect2 {

    # Tumor sample inputs
    File tumor_bam
    File tumor_bam_index
    String tumor_sample_name

    # Normal sample inputs
    File normal_bam
    File normal_bam_index
    String normal_sample_name

    # bed
    String interval_padding
    File? intervals_bed

    # Reference genome
    File ref_dir
    String fasta

    # --- 平台特定输入 ---
    String docker_image
    String cluster_config

    # 对于 32GB 的机器，为 GATK 的 Java 进程分配 28GB 是一个安全值，为 OS 和 Cromwell 留出 4GB
    Int java_mem_gb = 28


    # Define the output VCF name
    String output_vcf_name = "${tumor_sample_name}.mutect2.vcf.gz"

    # Disk space estimation: Sum of BAMs + Ref + 40GB buffer for VCF and temp files
    Int disk_gb = ceil(size(tumor_bam, "GB") + size(normal_bam, "GB"))*2 + 440


    command <<<
        set -e

        if [ ${intervals_bed} ]; then
            INTERVAL="--intervals ${intervals_bed} --interval-padding ${interval_padding}"
        else
            INTERVAL=""
        fi

        gatk --java-options "-Xmx${java_mem_gb}G" Mutect2 \
            -R ${ref_dir}/${fasta} \
            -I ${tumor_bam} \
            -I ${normal_bam} \
            $INTERVAL \
            -normal ${normal_sample_name} \
            --native-pair-hmm-threads $(nproc) \
            -O ${output_vcf_name}
    >>>

    output {
        # Mutect2 generates a VCF, its index, and a stats file for the filter step
        File output_vcf = output_vcf_name
        File output_vcf_index = "${output_vcf_name}.tbi"
        File mutect2_stats = "${output_vcf_name}.stats"
    }

    runtime {
        docker: docker_image
        cluster: cluster_config
        systemDisk: "cloud_ssd 40"
        dataDisk: "cloud_ssd " + disk_gb + " /cromwell_root/"
    }
}