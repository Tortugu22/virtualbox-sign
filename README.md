# virtualbox-sign
Sign kernel modules and load them manually for immutable distros such as Fedora Silverblue, Bazzite.. to work with Secure Boot.
This script was meant for sporadic use of VirtualBox. A reboot will unload the modules.

## Requirements
LayeredPackages: akmod-VirtualBox VirtualBox

### To generate a key, if you don't have one. You might use a simple password, it will be asked on the blue screen later.

```
sudo mkdir -p /etc/pki/virtualbox-signing
cd /etc/pki/virtualbox-signing

openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 -subj "/CN=VirtualBox Secure Boot Signing/" -keyout MOK.priv -out MOK.pem

openssl x509 -in MOK.pem -outform DER -out MOK.der
sudo mokutil --import MOK.der
```
## Reboot and enroll

After that, run the **script_sign.sh** with **sudo** whenever you need to run virtualbox. Signed modules will be created for every new kernel update.
