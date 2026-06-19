task somatic_mutect2 {

    # Tumor sample inputs
    File tumor_bam
    File tumor_bam_index
    String tumor_sample_name

    # Normal sample inputs
    File normal_bam
    File normal_bam_index
    String normal_sample_name

    # Optional interval settings for WES mode.
    String interval_padding
    File? intervals_bed

    # Reference genome
    File ref_dir
    String fasta
    String germline_resource

    # Platform runtime and Mutect2 parallelism inputs.
    String docker_image
    String cluster_config
    Int mutect2_parallel_jobs
    Int mutect2_threads_per_job
    Int mutect2_memory_per_job_gb

    # Define the output VCF name
    String output_vcf_name = "${tumor_sample_name}.mutect2.vcf.gz"
    String merged_stats_name = "${output_vcf_name}.stats"
    String shard_logs_name = "${tumor_sample_name}.mutect2_shard_logs.tar.gz"
    String read_orientation_model_name = "${tumor_sample_name}.read-orientation-model.tar.gz"

    # Estimate disk from tumor/normal BAM size with a reference and temp-file buffer.
    Int raw_disk_gb = ceil(size(tumor_bam, "GB") + size(normal_bam, "GB"))*2 + 440
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
        local_work="/tmp/${tumor_sample_name}_mutect2"
        mkdir -p "$local_work" "$local_work/tmp"
        export TMPDIR="$local_work/tmp"
        export TMP="$TMPDIR"
        export TEMP="$TMPDIR"
        export _JAVA_OPTIONS="-Djava.io.tmpdir=$TMPDIR"
        mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        java_xmx_gb=$((mem_kb * 75 / 100 / 1024 / 1024))
        if [ "$java_xmx_gb" -lt 4 ]; then
            java_xmx_gb=4
        fi
        echo "Using Java heap: "$java_xmx_gb"G" >&2
        cp -f ${tumor_bam} "$local_work/tumor.bam"
        cp -f ${tumor_bam_index} "$local_work/tumor.bam.bai"
        cp -f ${normal_bam} "$local_work/normal.bam"
        cp -f ${normal_bam_index} "$local_work/normal.bam.bai"
        cp -f ${ref_dir}/${germline_resource} "$local_work/${germline_resource}"
        cp -f ${ref_dir}/${germline_resource}.tbi "$local_work/${germline_resource}.tbi"
        cd "$local_work"

        # Build one interval-list shard per contig. In WES mode each shard is intersected with the BED.
        mkdir -p intervals shards logs
        if [ ${intervals_bed} ]; then
            awk 'BEGIN{OFS="\t"} NR==FNR {lengths[$1]=$2; next} ($1 in lengths) && !seen[$1]++ {print $1, "1", lengths[$1], "+", "."}' \
                ${ref_dir}/${fasta}.fai ${intervals_bed} > intervals/all_contigs.interval_list
        else
            awk 'BEGIN{OFS="\t"} {print $1, "1", $2, "+", "."}' ${ref_dir}/${fasta}.fai > intervals/all_contigs.interval_list
        fi

        # Run one Mutect2 shard and write per-shard stdout/stderr logs.
        run_one_interval() {
            idx="$1"
            interval_file="$2"
            shard_prefix=$(printf "shards/%04d" "$idx")
            extra_interval_args=""
            if [ ${intervals_bed} ]; then
                extra_interval_args="-L ${intervals_bed} --interval-padding ${interval_padding} --interval-set-rule INTERSECTION"
            fi

            gatk --java-options "-Djava.io.tmpdir=$TMPDIR -Xmx${mutect2_memory_per_job_gb}G" Mutect2 \
                -R ${ref_dir}/${fasta} \
                -I tumor.bam \
                -I normal.bam \
                -L "$interval_file" \
                $extra_interval_args \
                -normal ${normal_sample_name} \
                --germline-resource ${germline_resource} \
                --native-pair-hmm-threads ${mutect2_threads_per_job} \
                --f1r2-tar-gz "$shard_prefix.f1r2.tar.gz" \
                -O "$shard_prefix.vcf.gz" \
                > "logs/$(basename "$shard_prefix").stdout" \
                2> "logs/$(basename "$shard_prefix").stderr"
        }

        idx=0
        while read -r contig start end strand name; do
            idx=$((idx + 1))
            interval_file=$(printf "intervals/%04d_%s.interval_list" "$idx" "$contig")
            {
                printf "@HD\tVN:1.6\n"
                awk 'BEGIN{OFS="\t"} {print "@SQ","SN:"$1,"LN:"$2}' ${ref_dir}/${fasta}.fai
            } > "$interval_file"
            printf "%s\t%s\t%s\t%s\t%s\n" "$contig" "$start" "$end" "$strand" "$name" >> "$interval_file"

            run_one_interval "$idx" "$interval_file" &
            if [ $((idx % ${mutect2_parallel_jobs})) -eq 0 ]; then
                wait
            fi
        done < intervals/all_contigs.interval_list
        wait

        # Merge per-contig VCFs and Mutect2 stats back into a single sample-level result.
        ls shards/*.vcf.gz | sort | awk '{print "-I "$0}' > merge_vcfs.args
        gatk --java-options "-Djava.io.tmpdir=$TMPDIR -Xmx"$java_xmx_gb"G" MergeVcfs \
            --arguments_file merge_vcfs.args \
            -O ${output_vcf_name}
        gatk IndexFeatureFile -I ${output_vcf_name}

        ls shards/*.vcf.gz.stats | sort | awk '{print "-stats "$0}' > merge_stats.args
        gatk --java-options "-Djava.io.tmpdir=$TMPDIR -Xmx"$java_xmx_gb"G" MergeMutectStats \
            --arguments_file merge_stats.args \
            -O ${merged_stats_name}

        cp -f ${output_vcf_name} ${output_vcf_name}.tbi ${merged_stats_name} "$call_dir"/
        mkdir -p "$call_dir/f1r2_counts"
        cp -f shards/*.f1r2.tar.gz "$call_dir/f1r2_counts"/

        # Build the read orientation model from all shard-level F1R2 tarballs.
        f1r2_args=""
        for f in shards/*.f1r2.tar.gz; do
            if [ ! -s "$f" ]; then
                echo "Missing or empty F1R2 file: $f" >&2
                exit 1
            fi
            f1r2_args="$f1r2_args -I $f"
        done
        gatk --java-options "-Djava.io.tmpdir=$TMPDIR -Xmx"$java_xmx_gb"G" LearnReadOrientationModel \
            $f1r2_args \
            -O ${read_orientation_model_name}
        cp -f ${read_orientation_model_name} "$call_dir"/

        tar -czf ${shard_logs_name} logs
        cp -f ${shard_logs_name} "$call_dir"/
    >>>

    output {
        # Mutect2 generates a VCF, its index, and a stats file for the filter step
        File output_vcf = output_vcf_name
        File output_vcf_index = "${output_vcf_name}.tbi"
        File mutect2_stats = merged_stats_name
        Array[File] f1r2_counts = glob("f1r2_counts/*.f1r2.tar.gz")
        File read_orientation_model = read_orientation_model_name
        File shard_logs = shard_logs_name
    }

    runtime {
        docker: docker_image
        instanceTypes: [cluster_config]
        systemDisk: "cloud " + disk_gb
    }
}
