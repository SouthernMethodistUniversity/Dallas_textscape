#!/bin/bash
set -euo pipefail
# ------------------------------------------------------------
# User settings
# ------------------------------------------------------------
JOB_NAME="GoogleMapsOCR"
ACCOUNT="egodat_rts_fyre_0001"
PARTITION="htc"
MODULE_NAME="python/3.11.11/data_science/2025.08.21"
PY_SCRIPT="multi_engine.py"
CPUS="1"
MEM="10G"
TIME="1:00:00"
# ------------------------------------------------------------
# Input handling
# Usage:
#   ./batch_multi_engine.sh stvincent.jpg
#   ./batch_multi_engine.sh /path/to/images
#   ./batch_multi_engine.sh manifest_jpg.txt
# ------------------------------------------------------------
INPUT="${1:-.}"
cd "$(dirname "$0")"
if [[ ! -f "$PY_SCRIPT" ]]; then
  echo "Cannot find Python script: $PY_SCRIPT" >&2
  echo "Make sure batch_multi_engine.sh is in the same directory as $PY_SCRIPT." >&2
  exit 1
fi
mkdir -p logs
MANIFEST="$(pwd)/manifest_multi_engine.txt"
if [[ -f "$INPUT" ]]; then
  case "$INPUT" in
    *.txt|*.manifest)
      MANIFEST="$(realpath "$INPUT")"
      ;;
    *)
      realpath "$INPUT" > "$MANIFEST"
      ;;
  esac
elif [[ -d "$INPUT" ]]; then
  find "$INPUT" -type f \( \
    -iname "*.jpg" -o \
    -iname "*.jpeg" -o \
    -iname "*.png" \
  \) | sort | while read -r f; do
    realpath "$f"
  done > "$MANIFEST"
else
  echo "Input not found: $INPUT" >&2
  exit 1
fi
N="$(wc -l < "$MANIFEST" | tr -d ' ')"
if [[ "$N" -lt 1 ]]; then
  echo "No image files found in manifest: $MANIFEST" >&2
  exit 1
fi
echo "Submitting $N task(s)."
echo "Manifest: $MANIFEST"
echo "Python script: $(pwd)/$PY_SCRIPT"
sbatch \
  --job-name="$JOB_NAME" \
  --account="$ACCOUNT" \
  --partition="$PARTITION" \
  --cpus-per-task="$CPUS" \
  --mem="$MEM" \
  --time="$TIME" \
  --output="logs/%x_%A_%a.out" \
  --error="logs/%x_%A_%a.err" \
  --export=ALL,MANIFEST="$MANIFEST",PY_SCRIPT="$(pwd)/$PY_SCRIPT",MODULE_NAME="$MODULE_NAME" \
  --array=1-"$N" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ -z "${MANIFEST:-}" ]]; then
  echo "MANIFEST not set in job environment" >&2
  exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
  echo "Manifest file not found on compute node: $MANIFEST" >&2
  exit 1
fi
if [[ -z "${PY_SCRIPT:-}" ]]; then
  echo "PY_SCRIPT not set in job environment" >&2
  exit 1
fi
if [[ ! -f "$PY_SCRIPT" ]]; then
  echo "Python script not found on compute node: $PY_SCRIPT" >&2
  exit 1
fi
N="$(wc -l < "$MANIFEST" | tr -d ' ')"
: "${SLURM_ARRAY_TASK_ID:?SLURM_ARRAY_TASK_ID is not set}"
if (( SLURM_ARRAY_TASK_ID < 1 || SLURM_ARRAY_TASK_ID > N )); then
  echo "Task ID ${SLURM_ARRAY_TASK_ID} out of range 1..$N" >&2
  exit 1
fi
FILE="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$MANIFEST")"
if [[ -z "$FILE" ]]; then
  echo "No file found at line ${SLURM_ARRAY_TASK_ID} in $MANIFEST" >&2
  exit 1
fi
if [[ ! -f "$FILE" ]]; then
  echo "Image file not found on compute node: $FILE" >&2
  exit 1
fi
module purge
module load "$MODULE_NAME"
cd "$SLURM_SUBMIT_DIR"
echo "============================================================"
echo "Job:        $SLURM_JOB_NAME"
echo "Job ID:     $SLURM_JOB_ID"
echo "Array task: $SLURM_ARRAY_TASK_ID / $N"
echo "Node:       $(hostname)"
echo "Started:    $(date)"
echo "Python:     $(which python)"
python --version
echo "Script:     $PY_SCRIPT"
echo "Image:      $FILE"
echo "============================================================"
srun python -u "$PY_SCRIPT" "$FILE"
echo "============================================================"
echo "Finished:   $(date)"
echo "============================================================"
EOF