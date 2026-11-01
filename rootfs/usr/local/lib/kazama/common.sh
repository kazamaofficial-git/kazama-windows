# shellcheck shell=bash
# ============================================================
# Kazama Windows — shared shell library
# Developer  : @kazamaofficial-git
# Repository : https://github.com/kazamaofficial-git/kazama-windows
# ============================================================
# Defines i18n (English / Indonesian) and logging helpers only.

KZ_AUTHOR="@kazamaofficial-git"
KZ_REPO_URL="https://github.com/kazamaofficial-git/kazama-windows"

# APP_LANG: "en" (default) or "id".
case "${APP_LANG:-en}" in
  id | ID | id_ID* | indonesian | Indonesian) KZ_LANG=id ;;
  *) KZ_LANG=en ;;
esac

# Usage: msg "english text" "teks indonesia"
msg() {
  if [[ $KZ_LANG == id ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}

kz_info() { printf '[kazama] %s\n' "$(msg "$1" "$2")" >&2; }
kz_warn() { printf '[kazama] ⚠ %s\n' "$(msg "$1" "$2")" >&2; }
kz_err() { printf '[kazama] ✖ %s\n' "$(msg "$1" "$2")" >&2; }
kz_die() {
  kz_err "$1" "$2"
  exit 1
}
