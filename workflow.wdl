import "./tasks/fastp.wdl" as fastp_qc
import "./tasks/fastqc.wdl" as fastqc
import "./tasks/mapping.wdl" as bwa_mem_and_sort
import "./tasks/mark_duplicates_spark.wdl" as mark_duplicates_spark
import "./tasks/bqsr_base_recalibrator_spark.wdl" as bqsr_base_recalibrator_spark
import "./tasks/bsrq_apply_bqsr_spark.wdl" as bsrq_apply_bqsr_spark
import "./tasks/filter_and_select_pass_variants.wdl" as filter_and_select_pass_variants
import "./tasks/somatic_mutect2.wdl" as somatic_mutect2
import "./tasks/get_pileup_summaries.wdl" as get_pileup_summaries_task
import "./tasks/calculate_contamination.wdl" as calculate_contamination_task
import "./tasks/annovar_annotation.wdl" as annovar_annotation
import "./tasks/qualimap_bam_qc.wdl" as qualimap_bam_qc


workflow {{ project_name }} {

    # Sample FASTQ inputs.
    File tumor_fastq1
    File tumor_fastq2
    String tumor_sample_id
    File normal_fastq1
    File normal_fastq2
    String normal_sample_id

    # Reference genome and known-site resources.
    File ref_dir
    String fasta
    File dbsnp_dir
    String dbsnp
    File dbmills_dir
    String db_mills
    String germline_resource
    String common_biallelic_variants

    # Annotation database directory.
    File annovar_database   # ANNOVAR humandb directory.

    # WGS/WES switch. Provide a BED file for WES interval mode; leave it empty for WGS mode.
    File? bed_file
    String interval_padding

    # Docker images.
    String fastp_docker_image
    String fastqc_docker_image
    String gatk_docker_image
    String filter_gatk_docker_image
    String annovar_docker
    String qualimap_docker_image

    # Runtime and parallelism settings.
    String platform
    String cpu4mem8_cluster_config
    String cpu4mem16_cluster_config
    String cpu8mem16_cluster_config
    String cpu16mem32_cluster_config
    String cpu16mem64_cluster_config
    String cpu32mem64_cluster_config
    Int mutect2_parallel_jobs
    Int mutect2_threads_per_job
    Int mutect2_memory_per_job_gb



    # =========================================================================================
    # Step 1: Preprocess tumor and normal reads independently.
    # =========================================================================================

    # Tumor preprocessing: trim, QC, align, mark duplicates, and apply BQSR.
    call fastp_qc.fastp_qc as fastp_tumor {
        input:
            fastq1_gz = tumor_fastq1,
            fastq2_gz = tumor_fastq2,
            sample_id = tumor_sample_id,
            docker_image = fastp_docker_image,
            cluster_config = cpu8mem16_cluster_config
    }

    call fastqc.fastqc as fastqc_tumor {
		input:
            trimmed_fastq1 = fastp_tumor.trimmed_fastq1,
            trimmed_fastq2 = fastp_tumor.trimmed_fastq2,
            sample_id = tumor_sample_id,
            docker_image=fastqc_docker_image,
            cluster_config = cpu4mem8_cluster_config
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
            cluster_config = cpu32mem64_cluster_config
    }

    call mark_duplicates_spark.mark_duplicates_spark as dedup_tumor {
        input:
            input_bam = align_tumor.sorted_bam,
            input_bam_index = align_tumor.sorted_bam_index,
            sample_id = tumor_sample_id,
            docker_image = gatk_docker_image,
            cluster_config = cpu16mem32_cluster_config
    }

    call bqsr_base_recalibrator_spark.bqsr_base_recalibrator_spark as bqsr_recal_tumor {
        input:
            dedup_bam = dedup_tumor.dedup_bam,
            dedup_bam_index = dedup_tumor.dedup_bam_index,
            sample_id = tumor_sample_id,
            intervals_bed = bed_file, # Apply intervals only when WES BED is provided.
            interval_padding = interval_padding,
            fasta=fasta,
		    ref_dir=ref_dir,
            dbsnp_dir=dbsnp_dir,
            dbsnp=dbsnp,
            db_mills=db_mills,
            dbmills_dir=dbmills_dir,
            docker_image = gatk_docker_image,
            cluster_config = cpu16mem32_cluster_config
    }

    call bsrq_apply_bqsr_spark.bsrq_apply_bqsr_spark as apply_bqsr_tumor {
        input:
            dedup_bam = dedup_tumor.dedup_bam,
            dedup_bam_index = dedup_tumor.dedup_bam_index,
            recalibration_table = bqsr_recal_tumor.recalibration_table,
            sample_id = tumor_sample_id,
            intervals_bed = bed_file, # Apply intervals only when WES BED is provided.
            interval_padding = interval_padding,
            fasta=fasta,
		    ref_dir=ref_dir,
            docker_image = gatk_docker_image,
            cluster_config = cpu16mem32_cluster_config
    }

    # Normal preprocessing: trim, QC, align, mark duplicates, and apply BQSR.
    call fastp_qc.fastp_qc as fastp_normal {
        input:
            fastq1_gz = normal_fastq1,
            fastq2_gz = normal_fastq2,
            sample_id = normal_sample_id,
            docker_image = fastp_docker_image,
            cluster_config = cpu8mem16_cluster_config
    }

    call fastqc.fastqc as fastqc_normal {
		input:
		trimmed_fastq1 = fastp_normal.trimmed_fastq1,
        trimmed_fastq2 = fastp_normal.trimmed_fastq2,
        sample_id = normal_sample_id,
		docker_image=fastqc_docker_image,
		cluster_config = cpu4mem8_cluster_config
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
            cluster_config = cpu32mem64_cluster_config
    }

    call mark_duplicates_spark.mark_duplicates_spark as dedup_normal {
        input:
            input_bam = align_normal.sorted_bam,
            input_bam_index = align_normal.sorted_bam_index,
            sample_id = normal_sample_id,
            docker_image = gatk_docker_image,
            cluster_config = cpu16mem32_cluster_config
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
            intervals_bed = bed_file, # Apply intervals only when WES BED is provided.
            interval_padding = interval_padding,
            docker_image = gatk_docker_image,
            cluster_config = cpu16mem32_cluster_config
    }

    call bsrq_apply_bqsr_spark.bsrq_apply_bqsr_spark as apply_bqsr_normal {
        input:
            dedup_bam = dedup_normal.dedup_bam,
            dedup_bam_index = dedup_normal.dedup_bam_index,
            recalibration_table = bqsr_recal_normal.recalibration_table,
            sample_id = normal_sample_id,
            intervals_bed = bed_file, # Apply intervals only when WES BED is provided.
            interval_padding = interval_padding,
            fasta=fasta,
		    ref_dir=ref_dir,
            docker_image = gatk_docker_image,
            cluster_config = cpu16mem32_cluster_config
    }
    
    # =========================================================================================
    # Step 2: Call, filter, and annotate paired tumor-normal somatic variants.
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
            germline_resource = germline_resource,
            intervals_bed = bed_file, # Apply intervals only when WES BED is provided.
            interval_padding = interval_padding,
            mutect2_parallel_jobs = mutect2_parallel_jobs,
            mutect2_threads_per_job = mutect2_threads_per_job,
            mutect2_memory_per_job_gb = mutect2_memory_per_job_gb,
            docker_image = gatk_docker_image,
            cluster_config = cpu16mem32_cluster_config
    }

    call get_pileup_summaries_task.get_pileup_summaries as get_pileup_summaries_tumor {
        input:
            input_bam = apply_bqsr_tumor.recalibrated_bam,
            input_bam_index = apply_bqsr_tumor.recalibrated_bam_index,
            sample_id = tumor_sample_id,
            ref_dir = ref_dir,
            variants_for_contamination = common_biallelic_variants,
            intervals_bed = bed_file,
            interval_padding = interval_padding,
            docker_image = filter_gatk_docker_image,
            cluster_config = cpu4mem16_cluster_config
    }

    call get_pileup_summaries_task.get_pileup_summaries as get_pileup_summaries_normal {
        input:
            input_bam = apply_bqsr_normal.recalibrated_bam,
            input_bam_index = apply_bqsr_normal.recalibrated_bam_index,
            sample_id = normal_sample_id,
            ref_dir = ref_dir,
            variants_for_contamination = common_biallelic_variants,
            intervals_bed = bed_file,
            interval_padding = interval_padding,
            docker_image = filter_gatk_docker_image,
            cluster_config = cpu4mem16_cluster_config
    }

    call calculate_contamination_task.calculate_contamination as calculate_contamination {
        input:
            tumor_pileups = get_pileup_summaries_tumor.pileups_table,
            normal_pileups = get_pileup_summaries_normal.pileups_table,
            tumor_sample_name = tumor_sample_id,
            docker_image = filter_gatk_docker_image,
            cluster_config = cpu4mem8_cluster_config
    }

    call filter_and_select_pass_variants.filter_and_select_pass_variants as filter_and_select_pass_variants {
        input:
            mutect2_vcf = somatic_mutect2.output_vcf,
            mutect2_vcf_index = somatic_mutect2.output_vcf_index,
            mutect2_stats = somatic_mutect2.mutect2_stats,
            read_orientation_model = somatic_mutect2.read_orientation_model,
            contamination_table = calculate_contamination.contamination_table,
            tumor_segments = calculate_contamination.tumor_segments,
            tumor_sample_name = tumor_sample_id,
            fasta=fasta,
		    ref_dir=ref_dir,
            docker_image = filter_gatk_docker_image,
            cluster_config = cpu4mem16_cluster_config
    }

    call annovar_annotation.annovar_annotation as annovar_annotation {
        input:
            filtered_vcf = filter_and_select_pass_variants.pass_vcf,
            tumor_sample_name = tumor_sample_id,
            annovar_database = annovar_database,
            docker_image = annovar_docker,
            cluster_config = cpu4mem16_cluster_config
    }
    
    # =========================================================================================
    # Step 3: Generate BAM QC reports for the final recalibrated BAMs.
    # =========================================================================================

    call qualimap_bam_qc.qualimap_bam_qc as qualimap_tumor {
        input:
            recalibrated_bam = apply_bqsr_tumor.recalibrated_bam,
            recalibrated_bam_index = apply_bqsr_tumor.recalibrated_bam_index,
            sample_id = tumor_sample_id,
            intervals_bed = bed_file,
            docker_image = qualimap_docker_image,
            cluster_config = cpu16mem64_cluster_config
    }

    call qualimap_bam_qc.qualimap_bam_qc as qualimap_normal {
        input:
            recalibrated_bam = apply_bqsr_normal.recalibrated_bam,
            recalibrated_bam_index = apply_bqsr_normal.recalibrated_bam_index,
            sample_id = normal_sample_id,
            intervals_bed = bed_file,
            docker_image = qualimap_docker_image,
            cluster_config = cpu16mem64_cluster_config
    }
}
