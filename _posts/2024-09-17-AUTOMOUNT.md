---
layout: post
title: "Auto-mounting encrypted external drive in NixOS"
tags: nix linux
---
I've always been bad at backing up my laptop regularly. I recently had
the chance to change my laptop, and I decided to install NixOS. Since
this is a fresh start, I wanted to make sure my data was regularly
backed up to an external drive.

The external drive will:
- Be formatted with btrfs so that I can send incremental snapshots of my home directory
- LUKS encrypted to defend against losing the external drive. 

I didn't want to have to manually decrypt the external drive and mount
the file system each time I connected it. When I looked online for
information about how to do this, it was a bit scattered and didn't
focus on NixOS. In this article, we will go over how to encrypt the
external hard drive, and auto-mount the encrypted external drive
automatically in NixOS (although the logic is the same on other Linux
distros).

If you know how to LUKS encrypt a drive, skip to the next section.
## LUKS encrypt the external drive:
```
$ cryptsetup luksFormat /dev/nvme1n1p1
## Enter password
$ cryptsetup open /dev/nvme1n1p1 vault
$ dd bs=512 count=4 if=/dev/random of=/root/mykeyfile.key iflag=fullblock
$ cryptsetup luksAddKey /dev/nvme1n1p1 /root/mykeyfile.key
$ sudo mkfs.btrfs -L vault /dev/mapper/vault 
```
The one thing I would recommend is to add a keyfile so that we can
easily decrypt the drive instead of typing the password everytime. I am
not going to explain this any further as there are numerous tutorials on
LUKS encrypting a drive.

This is how the device/FS layout looks like on a real device
```sh
$ lsblk -f
nvme1n1                                                                                 
└─nvme1n1p1 crypto_LUKS 2           1342cc60-7514-4d70-8d1b-303b009cea34                
  └─vault   btrfs             vault e04b44ad-1beb-4902-9b91-e5e6ed43e51c  369.6G    20% /mnt/vault
```
## Auto-mounting in NixOS:
The following needs to be executed to auto-mount an encrypted drive:
- Decrypt the drive automatically when connected. As this is an external
  drive, the decryption should be triggered when a particular device is
  connected.
- Mount the detected filesystem on the decrypted drive.
#### Auto-decrypt using crypttab:
systemd allows specifying the configuration for encrypted block devices
through `/etc/crypttab`. `noauto` option can be specified so that
systemd will not try to unlock the device at boot. The `UUID` specified
in `crypttab` is the **partition's UUID**.

```nix
  environment.etc.crypttab.text = ''
    vault UUID=1342cc60-7514-4d70-8d1b-303b009cea34 /root/mykeyfile.key noauto
  '';
```
This will also generate a new systemd service unit file
`systemd-cryptsetup@vault.service`. Note that this service cannot be
`enabled` it is a transient/generated unit file.

To decrypt the drive manually using the systemd generated file, we could
do:
```sh
$ sudo systemctl start systemd-cryptsetup@vault.service
```

#### Trigger auto-decryption with an udev rule:
We would rather not start the service every time we connect the drive.
Instead, we want to start this systemd service whenever the external
drive is connected. An udev rule could be specified to do exactly that.

This [article](https://reactivated.net/writing_udev_rules.html) covers
the basic udev syntax. We basically specify conditions to trigger a
certain outcome in the udev rule. To uniquely identify the storage
device, `udevadm info <device>` could be used.

The following rule specifies that if the device belongs to `SUBSYSTEM`
“block” and has a specific WWN (unique identifier), then we decrypt the
drive using with `ENV{SYSTEMD_WANTS}=systemd-cryptsetup@vault.service`:

```nix
  services.udev.extraRules = ''
    SUBSYSTEM=="block" ENV{ID_WWN}=="nvme.144d-933432304e50305234983030383659-53616d73756e6720506f727461626c6520535344205835-00000001",\
    ENV{SYSTEMD_WANTS}="systemd-cryptsetup@vault.service"
  '';
```
#### Mount the filesystem:
The last step is pretty trivial. The filesystem mount point needs to
specified to mount the decrypted drive. Some things to keep in mind:

- UUID specified here refers to the decrypted device's uuid(`/dev/mapper/vault` in this case).
- `noauto` is specified again here so that systemd does not try to mount this during boot time.
- `x-systemd.automount`, `x-systemd.device-timeout` is specified so that systemd automounts the device if it is detected.

  ```nix
  fileSystems."/mnt/vault" = {
    device = "/dev/disk/by-uuid/e04b44ad-1beb-4902-9b91-e5e6ed43e51c";
    fsType = "btrfs";
    options = [
      "defaults"
      "noatime"
      "x-systemd.automount"
      "x-systemd.device-timeout=5"
      "noauto"
    ];
  };
```

## Conclusion:
I believed that auto-mounting an encrypted external drive would have
been significantly more straightforward than implementing bespoke udev
rules. However, it was helpful to learn how each part works together.

My final `external-disk.nix`:
```nix
{
  environment.etc.crypttab.text = ''
    vault UUID=1342cc60-7514-4d70-8d1b-303b009cea34 /root/mykeyfile.key noauto
  '';

  # The above crypttab creates a systemd cryptsetup vault service, which the below udev rule depends on
  services.udev.extraRules = ''
    SUBSYSTEM=="block" ENV{ID_WWN}=="nvme.nvme.144d-933432304e50305234983030383659-53616d73756e6720506f727461626c6520535344205835-00000001", ENV{SYSTEMD_WANTS}="systemd-cryptsetup@vault.service"
  '';

  fileSystems."/mnt/vault" = {
    device = "/dev/disk/by-uuid/e04b44ad-1beb-4902-9b91-e5e6ed43e51c";
    fsType = "btrfs";
    options = [
      "defaults"
      "noatime"
      "x-systemd.automount"
      "x-systemd.device-timeout=5"
      "noauto"
    ];
  };
}
```

Happy Backing up your data!
