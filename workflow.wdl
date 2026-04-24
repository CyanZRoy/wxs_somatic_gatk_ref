import "./tasks/fastp.wdl" as fastp_qc
import "./tasks/fastqc.wdl" as fastqc
import "./tasks/mapping.wdl" as bwa_mem_and_sort
import "./tasks/mark_duplicates_spark.wdl" as mark_duplicates_spark
import "./tasks/bqsr_base_recalibrator_spark.wdl" as bqsr_base_recalibrator_spark
import "./tasks/bsrq_apply_bqsr_spark.wdl" as bsrq_apply_bqsr_spark
import "./tasks/filter_and_select_pass_variants.wdl" as filter_and_select_pass_variants
import "./tasks/somatic_mutect2.wdl" as somatic_mutect2
import "./tasks/annovar_annotation.wdl" as annovar_annotation
import "./tasks/qualimap_bam_qc.wdl" as qualimap_bam_qc


workflow {{ project_name }} {

    # --- 样本输入 ---
    File tumor_fastq1
    File tumor_fastq2
    String tumor_sample_id
    File normal_fastq1
    File normal_fastq2
    String normal_sample_id

    # --- 参考文件 ---
    File ref_dir
    String fasta
    File dbsnp_dir
    String dbsnp
    File dbmills_dir
    String db_mills

    # --- 配置文件 ---
    File annovar_database   # Annovar 数据库 (humandb) 的 tar.gz 压缩包

    # --- WGS/WES 开关 ---
    # 如果提供了这个 BED 文件，流程将以 WES 模式运行 (使用 -L 参数)
    # 如果不提供，则以 WGS 模式运行
    File? bed_file
    String interval_padding

    # --- 软件镜像 ---
    String fastp_docker_image
    String fastqc_docker_image
    String bwa_docker_image
    String gatk_docker_image
    String filter_gatk_docker_image
    String annovar_docker
    String qualimap_docker_image

    # --- 可选参数 ---
    String platform
    String BIGcluster_config
    String MEDcluster_config
    String SMALLcluster_config



    # =========================================================================================
    # 步骤 1: 数据预处理 (并行执行于 Tumor 和 Normal 样本)
    # =========================================================================================

    # --- 肿瘤样本处理流程 ---
    call fastp_qc.fastp_qc as fastp_tumor {
        input:
            fastq1_gz = tumor_fastq1,
            fastq2_gz = tumor_fastq2,
            sample_id = tumor_sample_id,
            docker_image = fastp_docker_image,
            cluster_config = MEDcluster_config
    }

    call fastqc.fastqc as fastqc_tumor {
		input:
            trimmed_fastq1 = fastp_tumor.trimmed_fastq1,
            trimmed_fastq2 = fastp_tumor.trimmed_fastq2,
            sample_id = tumor_sample_id,
            docker_image=fastqc_docker_image,
            cluster_config=MEDcluster_config
	}

    call bwa_mem_and_sort.bwa_mem_and_sort as align_tumor {
        input:
            trimmed_fastq1 = fastp_tumor.trimmed_fastq1,
            trimmed_fastq2 = fastp_tumor.trimmed_fastq2,
            sample_id = tumor_sample_id,
            fasta=fasta,
		    ref_dir=ref_dir,
            platform=platform,
            docker_image = gatk_docker_image,
            cluster_config = BIGcluster_config
    }

    call mark_duplicates_spark.mark_duplicates_spark as dedup_tumor {
        input:
            input_bam = align_tumor.sorted_bam,
            input_bam_index = align_tumor.sorted_bam_index,
            sample_id = tumor_sample_id,
            docker_image = gatk_docker_image,
            cluster_config = MEDcluster_config
    }

    call bqsr_base_recalibrator_spark.bqsr_base_recalibrator_spark as bqsr_recal_tumor {
        input:
            dedup_bam = dedup_tumor.dedup_bam,
            dedup_bam_index = dedup_tumor.dedup_bam_index,
            sample_id = tumor_sample_id,
            intervals_bed = bed_file, # WES/WGS switch
            interval_padding = interval_padding,
            fasta=fasta,
		    ref_dir=ref_dir,
            dbsnp_dir=dbsnp_dir,
            dbsnp=dbsnp,
            db_mills=db_mills,
            dbmills_dir=dbmills_dir,
            docker_image = gatk_docker_image,
            cluster_config = MEDcluster_config
    }

    call bsrq_apply_bqsr_spark.bsrq_apply_bqsr_spark as apply_bqsr_tumor {
        input:
            dedup_bam = dedup_tumor.dedup_bam,
            dedup_bam_index = dedup_tumor.dedup_bam_index,
            recalibration_table = bqsr_recal_tumor.recalibration_table,
            sample_id = tumor_sample_id,
            intervals_bed = bed_file, # WES/WGS switch
            interval_padding = interval_padding,
            fasta=fasta,
		    ref_dir=ref_dir,
            docker_image = gatk_docker_image,
            cluster_config = MEDcluster_config
    }

    # --- 正常样本处理流程 ---
    call fastp_qc.fastp_qc as fastp_normal {
        input:
            fastq1_gz = normal_fastq1,
            fastq2_gz = normal_fastq2,
            sample_id = normal_sample_id,
            docker_image = fastp_docker_image,
            cluster_config = MEDcluster_config
    }

    call fastqc.fastqc as fastqc_normal {
		input:
		trimmed_fastq1 = fastp_normal.trimmed_fastq1,
        trimmed_fastq2 = fastp_normal.trimmed_fastq2,
        sample_id = normal_sample_id,
		docker_image=fastqc_docker_image,
		cluster_config=MEDcluster_config
	}

    call bwa_mem_and_sort.bwa_mem_and_sort as align_normal {
        input:
            trimmed_fastq1 = fastp_normal.trimmed_fastq1,
            trimmed_fastq2 = fastp_normal.trimmed_fastq2,
            sample_id = normal_sample_id,
            fasta=fasta,
		    ref_dir=ref_dir,
            platform=platform,
            docker_image = gatk_docker_image,
            cluster_config = BIGcluster_config
    }

    call mark_duplicates_spark.mark_duplicates_spark as dedup_normal {
        input:
            input_bam = align_normal.sorted_bam,
            input_bam_index = align_normal.sorted_bam_index,
            sample_id = normal_sample_id,
            docker_image = gatk_docker_image,
            cluster_config = MEDcluster_config
    }

    call bqsr_base_recalibrator_spark.bqsr_base_recalibrator_spark as bqsr_recal_normal {
        input:
            dedup_bam = dedup_normal.dedup_bam,
            dedup_bam_index = dedup_normal.dedup_bam_index,
            sample_id = normal_sample_id,
            fasta=fasta,
		    ref_dir=ref_dir,
            dbsnp_dir=dbsnp_dir,
            dbsnp=dbsnp,
            db_mills=db_mills,
            dbmills_dir=dbmills_dir,
            intervals_bed = bed_file, # WES/WGS switch
            interval_padding = interval_padding,
            docker_image = gatk_docker_image,
            cluster_config = MEDcluster_config
    }

    call bsrq_apply_bqsr_spark.bsrq_apply_bqsr_spark as apply_bqsr_normal {
        input:
            dedup_bam = dedup_normal.dedup_bam,
            dedup_bam_index = dedup_normal.dedup_bam_index,
            recalibration_table = bqsr_recal_normal.recalibration_table,
            sample_id = normal_sample_id,
            intervals_bed = bed_file, # WES/WGS switch
            interval_padding = interval_padding,
            fasta=fasta,
		    ref_dir=ref_dir,
            docker_image = gatk_docker_image,
            cluster_config = MEDcluster_config
    }
    
    # =========================================================================================
    # 步骤 2: 体细胞突变检测 (合并 Tumor 和 Normal 的结果)
    # =========================================================================================

    call somatic_mutect2.somatic_mutect2 as somatic_mutect2 {
        input:
            tumor_bam = apply_bqsr_tumor.recalibrated_bam,
            tumor_bam_index = apply_bqsr_tumor.recalibrated_bam_index,
            tumor_sample_name = tumor_sample_id,
            normal_bam = apply_bqsr_normal.recalibrated_bam,
            normal_bam_index = apply_bqsr_normal.recalibrated_bam_index,
            normal_sample_name = normal_sample_id,
            fasta=fasta,
		    ref_dir=ref_dir,
            intervals_bed = bed_file, # WES/WGS switch
            interval_padding = interval_padding,
            docker_image = gatk_docker_image,
            cluster_config = MEDcluster_config
    }

    call filter_and_select_pass_variants.filter_and_select_pass_variants as filter_and_select_pass_variants {
        input:
            mutect2_vcf = somatic_mutect2.output_vcf,
            mutect2_stats = somatic_mutect2.mutect2_stats,
            tumor_sample_name = tumor_sample_id,
            fasta=fasta,
		    ref_dir=ref_dir,
            docker_image = filter_gatk_docker_image,
            cluster_config = SMALLcluster_config
    }

    call annovar_annotation.annovar_annotation as annovar_annotation {
        input:
            filtered_vcf = filter_and_select_pass_variants.pass_vcf,
            tumor_sample_name = tumor_sample_id,
            annovar_database = annovar_database,
            docker_image = annovar_docker,
            cluster_config = SMALLcluster_config
    }
    
    # =========================================================================================
    # (可选) 步骤 3: 最终 BAM 的质量评估
    # =========================================================================================

    call qualimap_bam_qc.qualimap_bam_qc as qualimap_tumor {
        input:
            recalibrated_bam = apply_bqsr_tumor.recalibrated_bam,
            recalibrated_bam_index = apply_bqsr_tumor.recalibrated_bam_index,
            sample_id = tumor_sample_id,
            intervals_bed = bed_file,
            docker_image = qualimap_docker_image,
            cluster_config = MEDcluster_config
    }

    call qualimap_bam_qc.qualimap_bam_qc as qualimap_normal {
        input:
            recalibrated_bam = apply_bqsr_normal.recalibrated_bam,
            recalibrated_bam_index = apply_bqsr_normal.recalibrated_bam_index,
            sample_id = normal_sample_id,
            intervals_bed = bed_file,
            docker_image = qualimap_docker_image,
            cluster_config = MEDcluster_config
    }
}