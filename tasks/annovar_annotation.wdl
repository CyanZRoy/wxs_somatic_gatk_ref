task annovar_annotation {

    # 输入来自 filter_and_select_pass_variants task
    # 注意：你的脚本是针对 .filter.vcf 文件，我们将遵循这个逻辑
    File filtered_vcf
    String tumor_sample_name

    # Annovar 数据库，打包为 tar.gz 文件
    File annovar_database # e.g., "humandb_hg38.tar.gz"

    # Annovar 参数
    String buildver = "hg38"
    String protocols = "refGene,clinvar_20221231,gnomad40_exome,dbnsfp42c,cosmic70"
    String operations = "g,f,f,f,f"
    String cluster_config
    String docker_image


    # 定义输出文件的前缀
    String output_prefix = "${tumor_sample_name}"

    # 磁盘空间估算：数据库解压后大小 + 输入VCF + 输出VCF + 20GB 缓冲
    # 这是一个粗略估算，Annovar 数据库可能很大
    Int disk_gb = ceil(ceil(size(filtered_vcf, "GB") * 4)) + 420

    command <<<
        set -e

        # 步骤 2: 运行 Annovar 注释
        # Docker 镜像中 Annovar 的路径为 /opt/annovar/
        # 我们将解压后的 'humandb' 目录作为数据库路径
        /installations/annovar/table_annovar.pl ${filtered_vcf} \
            ${annovar_database} \
            -buildver ${buildver} \
            -out ${output_prefix} \
            -remove \
            -protocol ${protocols} \
            -operation ${operations} \
            -nastring . \
            -vcfinput \
            -thread $(nproc)
    >>>

    output {
        # Annovar 使用 -vcfinput 参数会生成一个带 .hg38_multianno.vcf 后缀的 VCF 文件
        File annotated_vcf = "${output_prefix}.${buildver}_multianno.vcf"

        # 同时捕获 Annovar 生成的 tab 分隔的注释文本文件
        File annotated_txt = "${output_prefix}.${buildver}_multianno.txt"
    }

    runtime {
        docker: docker_image
        cluster: cluster_config
        systemDisk: "cloud_ssd 40"
        dataDisk: "cloud_ssd " + disk_gb + " /cromwell_root/"
    }
}