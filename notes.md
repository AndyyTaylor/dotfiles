## Airpods
```
pulseaudio --start
pacmd set-sink-volume 4 0x10000
```

## WFH
openvpn3 session-start --config ~/Downloads/client.ovpn

xfreerdp -grab-keyboard /multimon /u:optiver\\andtay /v:andtay

$mod+Shift+f to make the xfreerdp screen multimonitor

openvpn3 session-manage --disconnect --config ~/Downloads/client.ovpn

## Wifi 'working' but crazy slow

Add to `/etc/modprobe.d/iwlwifi.conf`

options iwlwifi 11n_disable=1
options iwlwifi swcrypto=1
options iwlwifi 11n_disable=8
options iwlwifi bt_coex_active=0
