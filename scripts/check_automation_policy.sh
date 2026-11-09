#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
(cd "$project_dir/android" && ./gradlew --offline :app:compileDebugUnitTestKotlin)
python3 - "$project_dir" <<'PY'
import glob, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
test = next((root/'build/app').rglob('AutomationPolicyChecksKt.class'))
main = next((root/'build/app').rglob('AutomationPolicy.class'))
stdlib = sorted(glob.glob(str(pathlib.Path.home()/'.gradle/caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-stdlib/2.2.20/*/*.jar')))[0]
subprocess.run(['java','-cp',f'{test.parents[3]}:{main.parents[3]}:{stdlib}','pro.kaleert.nextlink.AutomationPolicyChecksKt'],check=True)
PY
