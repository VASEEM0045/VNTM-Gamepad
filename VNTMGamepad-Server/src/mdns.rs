//! mDNS / Bonjour Service Advertiser for VNTM Gamepad
//! Allows iOS app to automatically discover this PC on the local Wi-Fi network

use colored::*;
use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::collections::HashMap;

pub struct MdnsAdvertiser {
    daemon: Option<ServiceDaemon>,
    fullname: Option<String>,
}

impl MdnsAdvertiser {
    pub fn new() -> Self {
        MdnsAdvertiser {
            daemon: None,
            fullname: None,
        }
    }

    /// Starts advertising the `_vntmgamepad._tcp.local.` service.
    pub fn start(&mut self, port: u16) {
        let local_ip = match local_ip_address::local_ip() {
            Ok(ip) => ip.to_string(),
            Err(_) => "127.0.0.1".to_string(),
        };

        let hostname = match hostname::get() {
            Ok(h) => h.to_string_lossy().to_string(),
            Err(_) => "Windows-PC".to_string(),
        };

        match ServiceDaemon::new() {
            Ok(daemon) => {
                let service_type = "_vntmgamepad._tcp.local.";
                let instance_name = format!("VNTM-{}", hostname);
                let host_name = format!("{}.local.", hostname);

                let mut properties = HashMap::new();
                properties.insert("name".to_string(), format!("VNTM Gamepad ({})", hostname));
                properties.insert("version".to_string(), "1.0.0".to_string());
                properties.insert("platform".to_string(), "windows".to_string());

                match ServiceInfo::new(
                    service_type,
                    &instance_name,
                    &host_name,
                    &local_ip,
                    port,
                    properties,
                ) {
                    Ok(info) => {
                        let fullname = info.get_fullname().to_string();
                        if let Err(e) = daemon.register(info) {
                            eprintln!(
                                "{} Failed to register mDNS service: {:?}",
                                "[mDNS Error]".yellow(),
                                e
                            );
                        } else {
                            println!(
                                "{} Broadcasting Bonjour service: {}",
                                "[Bonjour/mDNS]".cyan().bold(),
                                fullname.bright_cyan()
                            );
                            self.fullname = Some(fullname);
                            self.daemon = Some(daemon);
                        }
                    }
                    Err(e) => {
                        eprintln!(
                            "{} Could not construct mDNS ServiceInfo: {:?}",
                            "[mDNS Error]".yellow(),
                            e
                        );
                    }
                }
            }
            Err(e) => {
                eprintln!(
                    "{} Could not start mDNS daemon: {:?}",
                    "[mDNS Warning]".yellow(),
                    e
                );
            }
        }
    }
}

impl Drop for MdnsAdvertiser {
    fn drop(&mut self) {
        if let (Some(daemon), Some(fullname)) = (&self.daemon, &self.fullname) {
            let _ = daemon.unregister(fullname);
            let _ = daemon.shutdown();
        }
    }
}
