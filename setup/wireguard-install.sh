#!/usr/bin/env bash -ex
set -euo pipefail
shopt -s inherit_errexit nullglob
YW=`echo "\033[33m"`
RD=`echo "\033[01;31m"`
BL=`echo "\033[36m"`
GN=`echo "\033[1;92m"`
CL=`echo "\033[m"`
RETRY_NUM=10
RETRY_EVERY=3
NUM=$RETRY_NUM
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
BFR="\\r\\033[K"
HOLD="-"

function msg_info() {
    local msg="$1"
    echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
    local msg="$1"
    echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

msg_info "Setting up Container OS "
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
while [ "$(hostname -I)" = "" ]; do
  1>&2 echo -en "${CROSS}${RD}  No Network! "
  sleep $RETRY_EVERY
  ((NUM--))
  if [ $NUM -eq 0 ]
  then
    1>&2 echo -e "${CROSS}${RD}  No Network After $RETRY_NUM Tries${CL}"    
    exit 1
  fi
done
msg_ok "Set up Container OS"
msg_ok "Network Connected: ${BL}$(hostname -I)"

wget -q --tries=10 --timeout=5 --spider http://google.com
if [[ $? -eq 0 ]]; then
        msg_ok "Internet Online"
else
        echo -e "{CROSS}${RD} Internet Offline"
fi

OPTIONS_PATH='/options.conf'
cat >$OPTIONS_PATH <<'EOF'
IPv4dev=eth0
install_user=root
VPN=wireguard
pivpnNET=10.6.0.0
subnetClass=24
ALLOWED_IPS="0.0.0.0/0, ::0/0"
pivpnMTU=1420
pivpnPORT=51820
pivpnDNS1=1.1.1.1
pivpnDNS2=8.8.8.8
pivpnHOST=
pivpnPERSISTENTKEEPALIVE=25
UNATTUPG=1
EOF

msg_info "Updating Container OS"
apt update &>/dev/null
apt-get -qqy upgrade &>/dev/null
msg_ok "Updated Container OS"

msg_info "Installing Dependencies"
apt-get install -y curl &>/dev/null
apt-get install -y sudo &>/dev/null
apt-get install -y gunicorn &>/dev/null
msg_ok "Installed Dependencies"

msg_info "Installing WireGuard (using pivpn.io)"
curl -s -L https://install.pivpn.io > install.sh 
chmod +x install.sh
./install.sh --unattended options.conf &>/dev/null
msg_ok "Installed WireGuard"

msg_info "Installing pip3"
apt-get install python3-pip -y &>/dev/null
pip install flask &>/dev/null
pip install ifcfg &>/dev/null
pip install flask_qrcode &>/dev/null
pip install icmplib &>/dev/null
msg_ok "Installed pip3"

msg_info "Installing WGDashboard"
WGDREL=$(curl -s https://api.github.com/repos/donaldzou/WGDashboard/releases/latest \
| grep "tag_name" \
| awk '{print substr($2, 2, length($2)-3) }') \

git clone -b ${WGDREL} https://github.com/donaldzou/WGDashboard.git /ect/wgdashboard &>/dev/null
cd /ect/wgdashboard/src
sudo chmod u+x wgd.sh
sudo ./wgd.sh install &>/dev/null
sudo chmod -R 755 /etc/wireguard
msg_ok "Installed WGDashboard"

msg_info "Creating Service"
service_path="/etc/systemd/system/wg-dashboard.service"
echo "[Unit]
After=netword.service

[Service]
WorkingDirectory=/ect/wgdashboard/src
ExecStart=/usr/bin/python3 /ect/wgdashboard/src/dashboard.py
Restart=always


[Install]
WantedBy=default.target" > $service_path
sudo chmod 664 /etc/systemd/system/wg-dashboard.service
sudo systemctl daemon-reload
sudo systemctl enable wg-dashboard.service &>/dev/null
sudo systemctl start wg-dashboard.service
msg_ok "Created Service"

PASS=$(grep -w "root" /etc/shadow | cut -b6);
  if [[ $PASS != $ ]]; then
msg_info "Customizing Container"
rm /etc/motd
rm /etc/update-motd.d/10-uname
touch ~/.hushlogin
GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
mkdir -p $(dirname $GETTY_OVERRIDE)
cat << EOF > $GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
systemctl daemon-reload
systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed 's/\.d//')
msg_ok "Customized Container"
  fi
  
msg_info "Cleaning up"
apt-get autoremove >/dev/null
apt-get autoclean >/dev/null
rm -rf /var/{cache,log}/* /var/lib/apt/lists/*
msg_ok "Cleaned"
