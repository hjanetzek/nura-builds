#!/bin/sh
# regenerate patch 0008 from kfork and its checksum
S=${S:?set S to a work directory holding kfork/ (the kernel tree)}
O=/home/jeff/bastel/github/nura-builds/overlays/s3ve3g/device/testing/linux-postmarketos-qcom-msm8226
N=0008-drm-panel-msm8226-generated-Samsung-S6E8AA0A-s3ve3g.patch
cd $S/kfork && { sed -n '1,/^---$/p' $O/$N; git diff -- drivers/gpu/drm/panel/msm8226-generated; } > $O/$N.new && mv $O/$N.new $O/$N
cd $O && python3 - $N <<'PY'
import hashlib, re, sys
n = sys.argv[1]
s = open('APKBUILD').read()
h = hashlib.sha512(open(n, 'rb').read()).hexdigest()
s, k = re.subn(r'^[0-9a-f]{128}  ' + re.escape(n) + '$', h + '  ' + n, s, flags=re.M)
assert k == 1
open('APKBUILD', 'w').write(s)
PY
