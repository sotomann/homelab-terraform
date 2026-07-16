[linux]
%{ for h in linux_hosts ~}
${h.name} ansible_host=${h.ip}
%{ endfor ~}

[windows]
%{ for h in windows_hosts ~}
${h.name} ansible_host=${h.ip}
%{ endfor ~}
