#!/usr/bin/env bash
set -euo pipefail

SERVICE_MENU_NAME="one-click-audio-converter.desktop"
PLASMA5_DIR="$HOME/.local/share/kservices5/ServiceMenus"
PLASMA6_DIR="$HOME/.local/share/kio/servicemenus"
RUNNER_PATH="$HOME/.local/bin/one-click-audio-converter"
TARGET_DIR=""
FORCE=0

usage() {
  cat <<'EOF'
Usage: ./install-service-menu.sh [options]

Options:
  --force          Overwrite an existing service menu with the same name.
  --plasma5        Install into the Plasma 5 service menu directory.
  --plasma6        Install into the Plasma 6 service menu directory.
  --target-dir DIR Install into DIR instead of the default path.
  -h, --help       Show this help message.

The script installs a KDE service menu that triggers a Zenity-driven batch
audio converter for Dolphin.
EOF
}

detect_plasma_major_version() {
  if command -v plasmashell >/dev/null 2>&1; then
    local version_line
    version_line="$(plasmashell --version 2>/dev/null | head -n1 || true)"
    if [[ "$version_line" =~ ([0-9]+)\. ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return
    fi
  fi
  printf '\n'
}

ensure_shell_access_allowed() {
  local read_cmd=""
  local write_cmd=""
  if command -v kreadconfig6 >/dev/null 2>&1; then
    read_cmd="kreadconfig6"
  elif command -v kreadconfig5 >/dev/null 2>&1; then
    read_cmd="kreadconfig5"
  fi

  if command -v kwriteconfig6 >/dev/null 2>&1; then
    write_cmd="kwriteconfig6"
  elif command -v kwriteconfig5 >/dev/null 2>&1; then
    write_cmd="kwriteconfig5"
  fi

  if [[ -z "$write_cmd" ]]; then
    echo "Warning: kwriteconfig5/6 not found; cannot automatically enable shell access." >&2
    return
  fi

  local current_value=""
  if [[ -n "$read_cmd" ]]; then
    current_value="$("$read_cmd" --group "KDE Action Restrictions" --key shell_access 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  fi
  if [[ "$current_value" != "true" ]]; then
    "$write_cmd" --group "KDE Action Restrictions" --key shell_access true
    echo "Enabled shell_access in ~/.config/kdeglobals so Dolphin can run custom service menus."
  fi
}

ensure_dependencies_installed() {
  local missing_pkgs=()
  command -v ffmpeg >/dev/null 2>&1 || missing_pkgs+=("ffmpeg")
  command -v zenity >/dev/null 2>&1 || missing_pkgs+=("zenity")

  if ((${#missing_pkgs[@]} == 0)); then
    return
  fi

  if ! command -v pkexec >/dev/null 2>&1; then
    echo "Error: pkexec is required to install ${missing_pkgs[*]}. Install them manually and rerun the installer." >&2
    exit 1
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Error: apt-get is required to install ${missing_pkgs[*]}. Install them manually and rerun the installer." >&2
    exit 1
  fi

  echo "Installing missing packages: ${missing_pkgs[*]} (authentication required)..."
  local pkg_cmd=""
  for pkg in "${missing_pkgs[@]}"; do
    pkg_cmd+=" $(printf '%q' "$pkg")"
  done
  pkexec bash -c "set -euo pipefail; export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y${pkg_cmd}"
}

install_runner() {
  mkdir -p "$(dirname "$RUNNER_PATH")"
  cat <<'EOF' > "$RUNNER_PATH"
#!/usr/bin/env bash
set -euo pipefail

TITLE="One-click Audio Converter"

if ! command -v zenity >/dev/null 2>&1; then
  echo "Error: zenity is not available." >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  zenity --error --title="$TITLE" --text="ffmpeg not found. Install it and try again." >/dev/null 2>&1 || true
  exit 1
fi

if [[ $# -eq 0 ]]; then
  zenity --error --title="$TITLE" --text="Select at least one audio file." >/dev/null 2>&1 || true
  exit 1
fi

declare -a files=()
for path in "$@"; do
  if [[ -f "$path" ]]; then
    files+=("$path")
  fi
done

if [[ ${#files[@]} -eq 0 ]]; then
  zenity --error --title="$TITLE" --text="No valid audio files to convert." >/dev/null 2>&1 || true
  exit 1
fi

choose_format() {
  zenity --list \
    --title="$TITLE" \
    --text="Choose the output format." \
    --radiolist \
    --column "Select" --column "Format" --column "Description" \
    TRUE ogg "Ogg Vorbis" \
    FALSE mp3 "MP3 (LAME)" \
    FALSE wma "Windows Media Audio"
}

choose_quality() {
  local format="$1"
  case "$format" in
    ogg)
      zenity --list \
        --title="$TITLE" \
        --text="Quality for Ogg Vorbis." \
        --radiolist \
        --column "Select" --column "Preset" --column "Details" \
        TRUE High "Vorbis q7 (~224 kbps)" \
        FALSE Medium "Vorbis q5 (~160 kbps)" \
        FALSE Low "Vorbis q3 (~112 kbps)"
      ;;
    mp3)
      zenity --list \
        --title="$TITLE" \
        --text="Quality for MP3." \
        --radiolist \
        --column "Select" --column "Preset" --column "Details" \
        TRUE High "MP3 256 kbps" \
        FALSE Medium "MP3 192 kbps" \
        FALSE Low "MP3 128 kbps"
      ;;
    wma)
      zenity --list \
        --title="$TITLE" \
        --text="Quality for WMA." \
        --radiolist \
        --column "Select" --column "Preset" --column "Details" \
        TRUE High "WMA 256 kbps" \
        FALSE Medium "WMA 160 kbps" \
        FALSE Low "WMA 128 kbps"
      ;;
  esac
}

format="$(choose_format)" || exit 1
quality="$(choose_quality "$format")" || exit 1

declare -a codec_args=()
ext="$format"

case "$format" in
  ogg)
    codec_args=(-c:a libvorbis)
    case "$quality" in
      High) codec_args+=(-qscale:a 7) ;;
      Medium) codec_args+=(-qscale:a 5) ;;
      Low) codec_args+=(-qscale:a 3) ;;
    esac
    ;;
  mp3)
    codec_args=(-c:a libmp3lame)
    case "$quality" in
      High) codec_args+=(-b:a 256k) ;;
      Medium) codec_args+=(-b:a 192k) ;;
      Low) codec_args+=(-b:a 128k) ;;
    esac
    ;;
  wma)
    codec_args=(-c:a wmav2)
    case "$quality" in
      High) codec_args+=(-b:a 256k) ;;
      Medium) codec_args+=(-b:a 160k) ;;
      Low) codec_args+=(-b:a 128k) ;;
    esac
    ;;
  *)
    zenity --error --title="$TITLE" --text="Unsupported format: $format" >/dev/null 2>&1 || true
    exit 1
    ;;
esac

make_unique_path() {
  local src="$1"
  local extension="$2"
  local base="${src%.*}"
  local candidate="${base}.${extension}"
  local idx=1
  while [[ -e "$candidate" ]]; do
    candidate="${base} (${idx}).${extension}"
    ((idx+=1))
  done
  printf '%s\n' "$candidate"
}

progress_dir="$(mktemp -d)"
progress_fifo="$progress_dir/pipe"
mkfifo "$progress_fifo"

cleanup() {
  rm -rf "$progress_dir"
}
trap cleanup EXIT

zenity --progress \
  --title="$TITLE" \
  --text="Preparing conversion..." \
  --percentage=0 \
  --auto-close \
  --auto-kill \
  < "$progress_fifo" &
progress_pid=$!

exec 3>"$progress_fifo"
echo "0" >&3

total=${#files[@]}
converted=0
processed=0
declare -a failed=()
cancelled=0

for file in "${files[@]}"; do
  if ! kill -0 "$progress_pid" >/dev/null 2>&1; then
    cancelled=1
    break
  fi

  basename="$(basename "$file")"
  echo "# Converting ${basename}" >&3

  out_path="$(make_unique_path "$file" "$ext")"
  if ffmpeg -y -hide_banner -loglevel error -i "$file" "${codec_args[@]}" "$out_path"; then
    ((++converted))
  else
    failed+=("$basename")
  fi

  ((++processed))
  percent=$(( processed * 100 / total ))
  echo "$percent" >&3
done

echo "100" >&3
exec 3>&-
wait "$progress_pid" || cancelled=1

if (( cancelled )); then
  zenity --warning --title="$TITLE" --text="Conversion cancelled." >/dev/null 2>&1 || true
  exit 1
fi

if ((${#failed[@]} > 0)); then
  printf 'Conversion finished with errors for:\n' > "$progress_dir/result.txt"
  for name in "${failed[@]}"; do
    printf '- %s\n' "$name" >> "$progress_dir/result.txt"
  done
  zenity --warning --title="$TITLE" --text="$(cat "$progress_dir/result.txt")" >/dev/null 2>&1 || true
else
  zenity --info --title="$TITLE" --text="Conversion completed for ${converted}/${total} file(s)." >/dev/null 2>&1 || true
fi
EOF
  chmod 0755 "$RUNNER_PATH"
}

restart_dolphin() {
  if ! command -v dolphin >/dev/null 2>&1; then
    echo "Dolphin executable not found; skipping restart."
    return
  fi

  local quit_cmd=""
  if command -v kquitapp6 >/dev/null 2>&1; then
    quit_cmd="kquitapp6"
  elif command -v kquitapp5 >/dev/null 2>&1; then
    quit_cmd="kquitapp5"
  elif command -v kquitapp >/dev/null 2>&1; then
    quit_cmd="kquitapp"
  fi

  local was_running=0
  if pgrep -x dolphin >/dev/null 2>&1; then
    was_running=1
    if [[ -n "$quit_cmd" ]]; then
      "$quit_cmd" dolphin >/dev/null 2>&1 || true
    else
      pkill -x dolphin >/dev/null 2>&1 || true
    fi
    sleep 1
  fi

  nohup dolphin >/dev/null 2>&1 &

  if [[ $was_running -eq 1 ]]; then
    echo "Dolphin restarted to reload service menus."
  else
    echo "Dolphin launched to load the new service menu."
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    --plasma5)
      TARGET_DIR="$PLASMA5_DIR"
      shift
      ;;
    --plasma6)
      TARGET_DIR="$PLASMA6_DIR"
      shift
      ;;
    --target-dir)
      if [[ $# -lt 2 ]]; then
        echo "Error: --target-dir requires a path." >&2
        exit 1
      fi
      TARGET_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then
  plasma_major="$(detect_plasma_major_version)"
  if [[ -n "$plasma_major" ]] && (( plasma_major >= 6 )); then
    TARGET_DIR="$PLASMA6_DIR"
  elif [[ -d "$PLASMA6_DIR" ]]; then
    TARGET_DIR="$PLASMA6_DIR"
  else
    TARGET_DIR="$PLASMA5_DIR"
  fi
fi

mkdir -p "$TARGET_DIR"
ensure_dependencies_installed
install_runner
ensure_shell_access_allowed

target_file="$TARGET_DIR/$SERVICE_MENU_NAME"

if [[ -e "$target_file" && $FORCE -ne 1 ]]; then
  echo "Refusing to overwrite existing $target_file (use --force)." >&2
  exit 1
fi

cat <<EOF > "$target_file"
[Desktop Entry]
Type=Service
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
MimeType=audio/*;audio/mpeg;audio/mp3;audio/flac;audio/x-flac;audio/aac;audio/x-aac;audio/ogg;audio/x-vorbis+ogg;audio/x-ms-wma;audio/x-wav;audio/wav;audio/x-m4a;audio/webm;
Icon=applications-multimedia
Actions=ConvertAudio
X-KDE-Submenu=One-click Conversion
X-KDE-AuthorizeAction=shell_access

[Desktop Action ConvertAudio]
Name=Convert audio...
Icon=audio-x-generic
Exec=$RUNNER_PATH %F
EOF

chmod 0755 "$target_file"

cat <<EOF
Installed one-click audio converter menu at:
  $target_file

Conversion runner: $RUNNER_PATH
EOF

restart_dolphin
