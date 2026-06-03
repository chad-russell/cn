{ config, lib, pkgs, ... }:

{
  services.avahi = {
    enable = true;
    ipv6 = false;
    openFirewall = true;
    publish = {
      enable = true;
      userServices = true;
    };
    extraServiceFiles.smb = ''
      <?xml version="1.0" standalone="no"?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">%h SMB</name>
        <service>
          <type>_smb._tcp</type>
          <port>445</port>
        </service>
      </service-group>
    '';
  };

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "nas";
        security = "user";
        "map to guest" = "Bad Password";
        "guest account" = "nobody";
        "hosts allow" = "192.168.20. 127.0.0.1 10.10.";
      };
      media = {
        path = "/pool/media";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "guest only" = "yes";
        "force user" = "crussell";
      };
      photos = {
        path = "/pool/photos";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "guest only" = "yes";
        "force user" = "crussell";
      };
      backups = {
        path = "/pool/backups";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "guest only" = "yes";
        "force user" = "crussell";
      };
      surveillance = {
        path = "/pool/surveillance";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "guest only" = "yes";
        "force user" = "crussell";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
}
