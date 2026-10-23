#!/bin/zsh
# Syntax-checks the JavaScript embedded in Sources/BridgeScripts.swift with Node (if installed).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v node >/dev/null; then
    echo "node not found; skipping bridge JS check"
    exit 0
fi

python3 - <<'EOF'
import re, subprocess, sys, tempfile, os
source = open('Sources/BridgeScripts.swift').read()
blocks = re.findall(r'static let (\w+) = #"""\n(.*?)\n    """#', source, re.S)
if not blocks:
    sys.exit("no script blocks found in BridgeScripts.swift")
failed = False
for name, js in blocks:
    js = js.replace('__VERSION__', '1')
    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False) as f:
        # Wrapped like callAsyncJavaScript does: an async function body.
        f.write('(async function(){\n' + js + '\n})')
    result = subprocess.run(['node', '--check', f.name], capture_output=True, text=True)
    os.unlink(f.name)
    print(f"{name}: {'ok' if result.returncode == 0 else 'FAILED'}")
    if result.returncode:
        print(result.stderr)
        failed = True
sys.exit(1 if failed else 0)
EOF
