#!/bin/sh
# Display bring-up loop: build the kernel in the VM, deploy, wait for the phone, report
S=${S:?set S to a work directory (logs)}
K=${KNOWN_HOSTS:?known_hosts file for the phone}
L=$S/vmbuild.log
cd /home/jeff/bastel/github/nura-builds || exit 1
if [ "${NOBUILD:-0}" != 1 ]; then
	tools/s3ve3g-builder.sh build linux-postmarketos-qcom-msm8226 > $L 2>&1 || { sed 's/\x1b\[[0-9;]*m//g' $L | grep -iE "error" | tail -20; echo BUILD FAILED; exit 1; }
	tools/s3ve3g-builder.sh fetch > /dev/null
fi
REPO=out/s3ve3g/packages/armv7 KNOWN_HOSTS=$K timeout 400 tools/s3ve3g-deploy.sh -n linux-postmarketos-qcom-msm8226 2>&1 | grep -E "BOOT|flashing|unchanged|ERROR|error"
# reboot without waiting for processes (a wedged display driver blocks a normal reboot)
timeout 15 ssh -o BatchMode=yes -o UserKnownHostsFile=$K jeff@172.16.42.1 'sudo sync; (sleep 1; echo b | sudo tee /proc/sysrq-trigger) >/dev/null 2>&1 &' 
sleep 30
i=0; until ssh -o BatchMode=yes -o ConnectTimeout=3 -o UserKnownHostsFile=$K jeff@172.16.42.1 true 2>/dev/null; do i=$((i+1)); [ $i -gt 60 ] && { echo "PHONE NOT BACK"; exit 1; }; sleep 3; done
sleep 5
ssh -o BatchMode=yes -o UserKnownHostsFile=$K jeff@172.16.42.1 'sudo rc-service s3ve3g-screen-off stop >/dev/null 2>&1; echo "uptime $(cut -d" " -f1 /proc/uptime) $(uname -v | cut -c1-40)";
	sudo dmesg | grep -iE "s6e8aa0a|mdp5_irq_error|dsi_err|dsi.*(fail|error)|phy|Oops|Internal error" | grep -v "callbacks suppressed" | awk "!seen[\$0]++" | head -20 | cut -c1-170;
	a=$(grep dsi_isr /proc/interrupts | awk "{print \$2}"); sleep 2; b=$(grep dsi_isr /proc/interrupts | awk "{print \$2}"); echo "dsi_isr/s: $(( (b - a) / 2 ))"'
