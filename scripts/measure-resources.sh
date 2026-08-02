#!/bin/zsh

set -euo pipefail

usage() {
    echo """
Usage: measure-resources.sh [options]

Options:
  --pid PID          Sample an exact process.
  --name NAME        Find the newest process with this exact name.
                     Default: AgentAwake
  --duration SEC     Total sample duration. Default: 600
  --interval SEC     Seconds between samples. Default: 5
  --csv PATH         Keep the raw samples at a new file path.
  --help             Show this help.
"""
}

target_pid=""
target_name="AgentAwake"
duration=600
interval=5
csv_path=""

while (( $# > 0 )); do
    case "$1" in
        --pid)
            target_pid="${2:-}"
            shift 2
            ;;
        --name)
            target_name="${2:-}"
            shift 2
            ;;
        --duration)
            duration="${2:-}"
            shift 2
            ;;
        --interval)
            interval="${2:-}"
            shift 2
            ;;
        --csv)
            csv_path="${2:-}"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

if [[ ! "$duration" =~ '^[1-9][0-9]*$' \
    || ! "$interval" =~ '^[1-9][0-9]*$' ]]; then
    echo "Duration and interval must be positive whole seconds." >&2
    exit 64
fi

if [[ -z "$target_pid" ]]; then
    target_pid="$(/usr/bin/pgrep -n -x "$target_name" || true)"
fi
if [[ ! "$target_pid" =~ '^[1-9][0-9]*$' ]]; then
    echo "Could not find a process to sample." >&2
    exit 66
fi
if ! /bin/kill -0 "$target_pid" 2>/dev/null; then
    echo "Process is not running: $target_pid" >&2
    exit 66
fi

if [[ -n "$csv_path" ]]; then
    if [[ -e "$csv_path" ]]; then
        echo "CSV path already exists; refusing to overwrite: $csv_path" >&2
        exit 73
    fi
    if [[ ! -d "${csv_path:h}" ]]; then
        echo "CSV parent directory does not exist: ${csv_path:h}" >&2
        exit 73
    fi
fi

sample_file="$(/usr/bin/mktemp -t agentawake-resources)"
trap '/bin/rm -f "$sample_file"' EXIT
echo "timestamp,rss_kib,cpu_percent,threads,open_files" > "$sample_file"

sample_count=$(( (duration + interval - 1) / interval ))
echo "Sampling PID $target_pid every ${interval}s for ${duration}s..."

for (( sample_index = 1; sample_index <= sample_count; sample_index++ )); do
    if ! /bin/kill -0 "$target_pid" 2>/dev/null; then
        echo "Process exited after $(( sample_index - 1 )) samples." >&2
        break
    fi

    process_stats="$(
        /bin/ps -p "$target_pid" -o rss= -o %cpu= \
            | /usr/bin/xargs
    )"
    if [[ -z "$process_stats" ]]; then
        break
    fi
    read -r rss_kib cpu_percent <<< "$process_stats"
    thread_count="$(
        /bin/ps -M -p "$target_pid" \
            | /usr/bin/awk 'NR > 1 { count++ } END { print count + 0 }'
    )"
    open_files="$(
        /usr/sbin/lsof -nP -p "$target_pid" 2>/dev/null \
            | /usr/bin/awk 'NR > 1 { count++ } END { print count + 0 }'
    )"
    timestamp="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "$timestamp,$rss_kib,$cpu_percent,$thread_count,$open_files" \
        >> "$sample_file"

    if (( sample_index < sample_count )); then
        /bin/sleep "$interval"
    fi
done

if [[ -n "$csv_path" ]]; then
    /bin/cp "$sample_file" "$csv_path"
    echo "Raw samples: $csv_path"
fi

/usr/bin/awk -F, '
    NR == 2 { first_rss = $2 }
    NR > 1 {
        samples++
        rss_sum += $2
        cpu_sum += $3
        if (samples == 1 || $2 < rss_min) rss_min = $2
        if ($2 > rss_max) rss_max = $2
        if ($3 > cpu_max) cpu_max = $3
        if ($4 > threads_max) threads_max = $4
        if ($5 > files_max) files_max = $5
        last_rss = $2
    }
    END {
        if (samples == 0) {
            print "No samples collected."
            exit 1
        }
        printf "Samples: %d\n", samples
        printf "RSS MiB: avg %.1f, min %.1f, max %.1f, drift %+.1f\n", \
            rss_sum / samples / 1024, rss_min / 1024, rss_max / 1024, \
            (last_rss - first_rss) / 1024
        printf "CPU %%: avg %.3f, max %.3f\n", cpu_sum / samples, cpu_max
        printf "Maximum threads: %d\n", threads_max
        printf "Maximum open files: %d\n", files_max
    }
' "$sample_file"
