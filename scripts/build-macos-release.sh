#!/bin/bash
set -euo pipefail

release_tag="${1:?Usage: scripts/build-macos-release.sh <v...|custom-...>}"
if [[ ! "$release_tag" =~ ^(v[0-9]|custom-[0-9])[0-9A-Za-z._-]*$ ]]; then
    printf 'Invalid release tag: %s\n' "$release_tag" >&2
    exit 1
fi

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${FSNOTES_BUILD_DIR:-$repo_dir/.build-release}"
derived_data="${FSNOTES_DERIVED_DATA_DIR:-$build_dir/DerivedData}"
source_packages="${FSNOTES_SOURCE_PACKAGES_DIR:-$build_dir/SourcePackages}"
output_dir="${FSNOTES_OUTPUT_DIR:-$repo_dir/dist}"
build_log="${FSNOTES_BUILD_LOG:-$build_dir/build.log}"
mkdir -p "$build_dir" "$output_dir" "$(dirname "$build_log")"
stage_dir="$(mktemp -d "$build_dir/package.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
cd "$repo_dir"

source_commit="$(git rev-parse HEAD)"
xcode_version="$(xcodebuild -version)"
printf '%s\n' "$xcode_version"
xcode_major="$(printf '%s\n' "$xcode_version" | awk '/^Xcode / {split($2, version, "."); print version[1]}')"
if [[ -z "$xcode_major" || "$xcode_major" -lt 27 ]]; then
    echo 'Xcode 27 or newer is required: upstream uses macOS 27 SDK APIs.' >&2
    exit 1
fi
xcodebuild -project FSNotes.xcodeproj -scheme FSNotes \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    -clonedSourcePackagesDirPath "$source_packages" \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    build 2>&1 | tee "$build_log"

ditto "$derived_data/Build/Products/Release/FSNotes.app" "$stage_dir/FSNotes.app"
cp LICENSE "$stage_dir/LICENSE"
python3 - "$stage_dir/FSNotes.app/Contents/Info.plist" "$release_tag" "$source_commit" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
info['FSNotesCustomReleaseTag'] = sys.argv[2]
info['FSNotesSourceCommit'] = sys.argv[3]
path.write_bytes(plistlib.dumps(info, sort_keys=False))
PY
codesign --force --deep --sign - "$stage_dir/FSNotes.app"
codesign --verify --deep --strict "$stage_dir/FSNotes.app"
lipo -verify_arch arm64 "$stage_dir/FSNotes.app/Contents/MacOS/FSNotes"

archive_base="FSNotes-${release_tag}-macOS-arm64"
archive_name="$archive_base.zip"
disk_image_name="$archive_base.dmg"
python3 - "$stage_dir" "$output_dir" "$release_tag" "$source_commit" "$archive_name" "$disk_image_name" <<'PY'
import os
import plistlib
import sys
from pathlib import Path

stage, output = map(Path, sys.argv[1:3])
tag, commit, archive, disk_image = sys.argv[3:]
repository = os.environ.get('GITHUB_REPOSITORY', 'cjjlovedsn/fsnotes')
info = plistlib.loads((stage / 'FSNotes.app/Contents/Info.plist').read_bytes())
minimum_os = info['LSMinimumSystemVersion']
version = info['CFBundleShortVersionString']
build = info['CFBundleVersion']
(stage / 'README.txt').write_text(f'''FSNotes 定制版 {tag}

源码：https://github.com/{repository}
提交：{commit}
构建：Xcode Release / macOS arm64（Apple Silicon）
系统要求：macOS {minimum_os} 或更新版本
应用内部上游版本号：{version}（{build}）
定制版本标记及源码提交也已写入应用 Info.plist。

推荐：打开 DMG，将 FSNotes.app 拖到旁边的 Applications（应用程序）快捷方式。
安装后推出磁盘映像，从“应用程序”中启动 FSNotes。
使用 ZIP 时，也请先退出旧版，把解压出的 FSNotes.app 拖入“应用程序”后再启动。
本构建采用临时签名，未经过 Apple 公证，不包含 Intel 版本。
原始项目的 MIT 许可见 LICENSE。
后续下载：https://github.com/{repository}/releases/latest
''')
(output / 'release-notes.md').write_text(f'''## Mac 应用下载

推荐下载 `{disk_image}`，打开后把 `FSNotes.app` 拖到旁边的 Applications 快捷方式，再从“应用程序”中启动。

ZIP 便携包 `{archive}` 继续保留；解压后同样建议把应用拖入“应用程序”。

- 平台：Apple Silicon（arm64），macOS {minimum_os} 或更新版本。
- 首次在下载目录或磁盘映像中运行时，提示移到“应用程序”，并可打开访达中的安装位置。
- 此 fork 包含纯图标代码块复制按钮、小手光标修复和两级全选。
- 构建方式：GitHub Actions 在线执行原生组件检查及 Xcode Release 构建。
- 本构建采用临时签名，未经过 Apple 公证；不包含 Intel 版本。
- 随包附带 README 和 MIT 许可证，附件 `SHA256SUMS.txt` 可用于核对完整性。
- 定制标签：`{tag}`；应用内部上游版本号：`{version}`（`{build}`）。

源码提交：[{commit}](https://github.com/{repository}/commit/{commit})

以后下载最新版：https://github.com/{repository}/releases/latest
''')
PY

"$repo_dir/scripts/package-macos.sh" "$stage_dir" "$output_dir" "$archive_base" "FSNotes"
