"""CI helper: dump the PowerShell embedded in droidvm_gpu.py for a syntax check."""
import re
src = open('tools/app/droidvm_gpu.py', encoding='utf-8').read()
out = []
for name in ('STATIC_PS', 'LIVE_PS'):
    m = re.search(name + r' = r"""(.*?)"""', src, re.S)
    out.append('$null = {' + m.group(1) + '}')
open('ps_check.ps1', 'w', encoding='utf-8').write('\n'.join(out))
