task filter_and_select_pass_variants {

    # 输入来自 somatic_mutect2 task
    File mutect2_vcf
    File mutect2_stats # <-- 这是 FilterMutectCalls 的必需输入
    String tumor_sample_name

    # 参考基因组
    File ref_dir
    String fasta

    # --- 平台特定输入 ---
    String docker_image
    String cluster_config


    # 定义中间和最终输出文件的名称
    String filtered_vcf_name = "${tumor_sample_name}.filtered.vcf.gz"
    String pass_vcf_name = "${tumor_sample_name}.pass.vcf.gz"

    # 磁盘空间估算：输入 VCF 大小的 3 倍 (一个用于输入，两个用于输出) + 20GB
    Int disk_gb = ceil(size(mutect2_vcf, "GB") * 5) + 420

    # 对于 16GB 的机器，为 GATK 的 Java 进程分配 13GB 是一个安全值，为 OS 和 Cromwell 留出 3GB
    Int java_mem_gb = 13

    command <<<
        set -e -o pipefail

        # 步骤 1: 运行 GATK FilterMutectCalls
        # 使用 Mutect2 生成的 .stats 文件来帮助过滤
        gatk --java-options "-Xmx${java_mem_gb}G" FilterMutectCalls \
            -R ${ref_dir}/${fasta} \
            -V ${mutect2_vcf} \
            -stats ${mutect2_stats} \
            -O ${filtered_vcf_name}

        # 步骤 2: 从上一步的输出中提取 PASS variants
        # 使用管道高效处理：解压 -> awk 过滤 -> bgzip 重新压缩
        gunzip -c ${filtered_vcf_name} | \
        awk 'BEGIN{FS=OFS="\t"} /^#/ || $7 == "PASS"' | \
        bgzip -c > ${pass_vcf_name}

        # 步骤 3: 为最终的 PASS VCF 文件创建索引
        gatk IndexFeatureFile -I ${pass_vcf_name}
    >>>

    output {
        # 输出 GATK 过滤后的 VCF (包含被标记为 filter 的位点)
        File filtered_vcf = filtered_vcf_name
        File filtered_vcf_index = "${filtered_vcf_name}.tbi"

        # 输出只包含 PASS 位点的最终 VCF
        File pass_vcf = pass_vcf_name
        File pass_vcf_index = "${pass_vcf_name}.tbi"
    }

    runtime {
        docker: docker_image
        cluster: cluster_config
        systemDisk: "cloud_ssd 40"
        dataDisk: "cloud_ssd " + disk_gb + " /cromwell_root/"
    }
}