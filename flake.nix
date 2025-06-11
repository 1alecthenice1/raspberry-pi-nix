{
  description = "Raspberry Pi 5 with NVMe boot support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    rpi.url = "github:nix-community/raspberry-pi-nix";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, rpi, disko, ... }: {
    nixosConfigurations.cumorah = nixpkgs.lib.nixosSystem {
      # Change this to x86_64-linux for cross-compilation
      system = "x86_64-linux";  
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        crossSystem = {
          config = "aarch64-unknown-linux-gnu";
          system = "aarch64-linux";
        };
        config = {
          allowUnfree = true;
          allowUnfreeKernelModules = true;
        };
      };
      modules = [
        rpi.nixosModules.raspberry-pi
        disko.nixosModules.disko
        ({ pkgs, lib, ... }: {
          # Set the target system explicitly
          nixpkgs.hostPlatform = "aarch64-linux";
          
          # Rest of your configuration stays the same...
          raspberry-pi-nix.board = "bcm2712";
          hardware.enableAllFirmware = true;
          
          # Keep your excellent NVMe boot configuration
          boot = {
            loader.grub.enable = false;
            loader.generic-extlinux-compatible.enable = true;
            loader.initScript.enable = lib.mkForce false;

            # Your Pi 5 + NVMe specific kernel parameters - KEEP THESE
            kernelParams = [
              "8250.nr_uarts=1"           # Serial console optimization
              "console=ttyAMA10,115200"   # Pi 5 uses different UART
              "console=tty1"              # Local console
              "rootwait"                  # Wait for root device
              "cma=128M"                  # Contiguous memory allocation
              "coherent_pool=1M"          # DMA coherent pool
            ];

            # Critical NVMe support - KEEP THIS
            initrd = {
              availableKernelModules = [ 
                "nvme" 
                "pcie_brcmstb"      # Pi 5 PCIe controller
                "reset-brcmstb-rescal"
                "sd_mod" 
                "usb_storage"
                "uas"               # USB Attached SCSI
              ];
              kernelModules = [ "nvme" "pcie_brcmstb" ];
            };

            # Pi 5 hardware support - KEEP THIS
            kernelModules = [ 
              "bcm2835_v4l2"      # Camera support
              "i2c-dev"           # I2C interface
              "spi-dev"           # SPI interface
            ];
          };
          
          # Minimal packages for now
          environment.systemPackages = with pkgs; [
            vim
            wget
            curl
            openssh
            rsync
            pciutils
            networkmanager
            git
            htop
          ];
          
          # Essential services only
          services = {
            openssh.enable = true;
            logrotate.enable = false;
          };
          
          # Basic user
          users.users.user = {
            isNormalUser = true;
            extraGroups = [ "wheel" "networkmanager" ];
            initialPassword = "changeme";
          };
          
          system.stateVersion = "24.11";
          
          # Keep your disko NVMe configuration - it's correct
          disko.devices.disk.main = {
            type = "disk";
            device = "/dev/nvme0n1";  # Add this line back
            imageSize = "8G";
            content = {
              type = "gpt";
              partitions = {
                boot = {
                  start = "1MiB";
                  end = "100MiB";
                  type = "EF00";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                    extraArgs = [ "-n" "BOOT" ];
                  };
                };
                root = {
                  start = "100MiB";
                  end = "100%";
                  type = "8300";
                  content = {
                    type = "filesystem";
                    format = "ext4";
                    mountpoint = "/";
                    extraArgs = [ "-L" "nixos" ];
                  };
                };
              };
            };
          };
        })  # Close the module function
      ];    # Close the modules list
    };      # Close the nixosConfigurations.cumorah
    
    # Keep only x86_64-linux packages since that's what GitHub Actions uses
    packages.x86_64-linux = {
      diskImage = self.nixosConfigurations.cumorah.config.system.build.diskoImages;
      vm = self.nixosConfigurations.cumorah.config.system.build.vm;
      partitionScript = self.nixosConfigurations.cumorah.config.system.build.diskoScript;
      system = self.nixosConfigurations.cumorah.config.system.build.toplevel;
      kernel = self.nixosConfigurations.cumorah.config.system.build.kernel;
    };
  };        # Close the outputs function
}           # Close the flake