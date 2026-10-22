#!/bin/bash
# macOS system Bash 3.2+. No Python, Node.js or administrator rights required.
set -eu
umask 077
ADDON_ID='glossa-zotero@yiiwang118'
EXPECTED_HASH='0a71b777731e856ac3ad8d1fceaf598fce6cc15a8ca6a459902bc9b74462a8c9'

compatible_version() {
    [[ "$1" =~ ^10\.([0-9]+)(\.([0-9]+))?$ ]] || return 1
    local minor="${BASH_REMATCH[1]}" patch="${BASH_REMATCH[3]:-0}"
    (( 10#$minor > 0 || 10#$patch >= 6 ))
}

list_profiles() {
    # Preserve spaces, Unicode and '=' in values; do not evaluate INI content.
    awk '
      function emit() {
        if (section ~ /^Profile[0-9]+$/ && path != "")
          printf "%s\t%s\t%s\n", relative == "0" ? "0" : "1", name, path
      }
      { sub(/\r$/, "") }
      /^[ \t]*\[/ { emit(); section=$0; sub(/^[ \t]*\[/,"",section); sub(/\][ \t]*$/,"",section); name=section; path=""; relative="1"; next }
      /^[ \t]*[;#]/ { next }
      index($0,"=") { key=substr($0,1,index($0,"=")-1); val=substr($0,index($0,"=")+1); gsub(/^[ \t]+|[ \t]+$/,"",key); gsub(/^[ \t]+|[ \t]+$/,"",val); if(key=="Name" && val!="")name=val; if(key=="Path")path=val; if(key=="IsRelative")relative=val }
      END { emit() }
    ' "$1"
}

filter_cache_markers() {
    # Match complete preference names only. Leave other preferences untouched.
    LC_ALL=C sed -E '/^[[:space:]]*user_pref\("extensions\.lastApp(BuildId|Version)"/d' "$1"
}

addon_version() {
    /usr/bin/unzip -p "$1" manifest.json | sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1
}

install_profile() {
    local profile="$1" source="$2" extensions target prefs previous stamp backup staged temporary prefs_temp
    local had_target=0 had_prefs=0
    [[ "$(/usr/bin/shasum -a 256 "$source" | awk '{print $1}')" == "$EXPECTED_HASH" ]] || {
        echo '插件 SHA-256 校验失败，请重新下载本安装包。' >&2; return 1;
    }
    extensions="$profile/extensions"
    target="$extensions/$ADDON_ID.xpi"
    prefs="$profile/prefs.js"
    for staged in "$extensions/$ADDON_ID" "$extensions/staged/$ADDON_ID" "$extensions/staged/$ADDON_ID.xpi"; do
        if [[ -e "$staged" || -L "$staged" ]]; then
            echo '发现解包版插件或未完成的安装/移除，请先重启 Zotero 并改用手动安装。' >&2
            return 1
        fi
    done
    if [[ -e "$target" ]]; then
        previous="$(addon_version "$target")"
        if [[ "$previous" == '0.1.0' ]]; then
            echo '请先在 Zotero 中移除 Glossa 0.1.0 并重启，再运行本助手。' >&2; return 1
        fi
        case "$previous" in
            0.1.*|0.2.0) ;;
            *) echo "已有版本为 $previous；为避免降级，已停止。" >&2; return 1 ;;
        esac
        if [[ "$(/usr/bin/shasum -a 256 "$target" | awk '{print $1}')" == "$EXPECTED_HASH" ]]; then
            echo '原版 0.2.0 插件文件已存在，无需重复复制。'
            return 0
        fi
        had_target=1
    fi
    stamp="$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
    backup="$profile/glossa-setup-backups/$stamp"
    mkdir -p "$backup" "$extensions" || return 1
    if [[ $had_target == 1 ]]; then cp -p "$target" "$backup/previous.xpi" || return 1; fi
    if [[ -f "$prefs" ]]; then had_prefs=1; cp -p "$prefs" "$backup/prefs.js" || return 1; fi
    temporary="$extensions/.glossa-setup-$stamp.tmp"
    prefs_temp="$profile/.glossa-prefs-$stamp.tmp"
    # All backup/preparation steps happen before the original files are changed.
    cp "$source" "$temporary" || return 1
    if [[ $had_prefs == 1 ]]; then
        if ! filter_cache_markers "$prefs" > "$prefs_temp"; then rm -f "$temporary" "$prefs_temp"; return 1; fi
    fi
    if ! mv -f "$temporary" "$target"; then rm -f "$temporary" "$prefs_temp"; return 1; fi
    if [[ $had_prefs == 1 ]] && ! mv -f "$prefs_temp" "$prefs"; then
        if [[ $had_target == 1 ]]; then cp -p "$backup/previous.xpi" "$target"; else rm -f "$target"; fi
        cp -p "$backup/prefs.js" "$prefs"
        echo '写入失败，已尝试还原。备份位于：'"$backup" >&2
        return 1
    fi
    echo '插件文件已部署。本次备份：'"$backup"
}

main() {
    [[ "$(uname -s)" == 'Darwin' ]] || { echo '此启动文件用于 macOS。Windows 请运行 START-Windows.cmd。' >&2; return 1; }
    local setup_dir app version app_ini profile_ini profile_root relative name profile_path choice i
    local profiles=() names=() profile_count=0
    setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo 'Zotero + Claude / Glossa 0.2.0 安装助手'
    app=''
    for profile_path in '/Applications/Zotero.app' "$HOME/Applications/Zotero.app"; do
        if [[ -d "$profile_path" ]]; then app="$profile_path"; break; fi
    done
    if [[ -z "$app" ]]; then
        app="$(/usr/bin/osascript -e 'POSIX path of (choose application with prompt "请选择 Zotero" as alias)')" || return 1
        app="${app%/}"
    fi
    version=''
    for app_ini in "$app/Contents/Resources/application.ini" "$app/Contents/MacOS/application.ini"; do
        if [[ -f "$app_ini" ]]; then
            version="$(awk -F= '/^\[App\]/{s=1;next} /^\[/{s=0} s && /^Version=/{sub(/\r$/, "", $2); print $2; exit}' "$app_ini")"
            break
        fi
    done
    if [[ -z "$version" ]]; then
        version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" || return 1
    fi
    echo "Zotero 版本：$version"
    compatible_version "$version" || { echo '此插件仅支持 Zotero 10.0.6 及以后的正式版 10.x，请先核对版本。' >&2; return 1; }
    if /usr/bin/pgrep -ix zotero >/dev/null; then
        read -r -p '请先保存工作并使用 Command+Q 完全退出 Zotero，然后按回车继续：' choice
    fi
    if /usr/bin/pgrep -ix zotero >/dev/null; then echo 'Zotero 仍在运行，已停止。' >&2; return 1; fi
    profile_ini="$HOME/Library/Application Support/Zotero/profiles.ini"
    [[ -f "$profile_ini" ]] || { echo '未找到配置。请先正常启动 Zotero 一次并退出；自定义配置请手动安装。' >&2; return 1; }
    profile_root="$(dirname "$profile_ini")"
    while IFS=$'\t' read -r relative name profile_path; do
        [[ -n "$profile_path" ]] || continue
        if [[ "$relative" != '0' ]]; then profile_path="$profile_root/$profile_path"; fi
        [[ -d "$profile_path" ]] || continue
        profiles[$profile_count]="$profile_path"
        names[$profile_count]="$name"
        profile_count=$((profile_count+1))
    done < <(list_profiles "$profile_ini")
    [[ $profile_count -gt 0 ]] || { echo '没有可用的 Zotero 配置，请使用手动安装。' >&2; return 1; }
    i=0
    if [[ $profile_count -gt 1 ]]; then
        for ((i=0;i<profile_count;i++)); do echo "[$((i+1))] ${names[$i]}  ${profiles[$i]}"; done
        read -r -p '请选择配置编号：' choice
        [[ "$choice" =~ ^[1-9][0-9]*$ && ${#choice} -le 4 ]] || { echo '编号无效。' >&2; return 1; }
        i=$((10#$choice-1))
        (( i < profile_count )) || { echo '编号无效。' >&2; return 1; }
    fi
    if /usr/bin/pgrep -ix zotero >/dev/null; then echo 'Zotero 已重新启动，请退出后重试。' >&2; return 1; fi
    install_profile "${profiles[$i]}" "$setup_dir/payload/glossa-zotero-0.2.0.xpi"
    echo '请打开 Zotero → 工具 → 插件，确认 Glossa；如果显示“启用”，请点一次。'
    echo '然后选中文献 → Glossa → 模型菜单 → 添加 API 服务 → Anthropic。'
    /usr/bin/open -a "$app" --args -profile "${profiles[$i]}" -purgecaches || echo '请手动启动 Zotero。'
    /usr/bin/open "$setup_dir/README.html" || echo '请手动打开同目录的 README.html。'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # An EXIT trap also handles failures under set -e, keeping Terminal readable.
    trap 'result=$?; if [[ $result -ne 0 ]]; then echo; echo "未完成。也可将 payload 内的 .xpi 拖入 Zotero 的工具 → 插件窗口。"; fi; echo; read -r -p "按回车关闭此窗口：" unused || true; exit "$result"' EXIT
    main
fi
