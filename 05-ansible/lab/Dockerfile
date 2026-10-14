# « Serveur » de labo pour Ansible : Ubuntu 24.04 + sshd + python3 + un utilisateur sudoer "ansible".
# Ce n'est PAS une bonne pratique de conteneur (plusieurs services, sshd…) : c'est un simulateur de VM.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-server python3 python3-apt sudo ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --shell /bin/bash ansible \
 && echo 'ansible ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ansible \
 && chmod 0440 /etc/sudoers.d/ansible \
 && mkdir -p /run/sshd /home/ansible/.ssh \
 && chmod 0700 /home/ansible/.ssh

# Clé publique générée par toi (Lab 5.1) : ssh-keygen -t ed25519 -f ~/.ssh/bootcamp_ansible
COPY --chown=ansible:ansible --chmod=0600 authorized_keys /home/ansible/.ssh/authorized_keys

EXPOSE 22 80
CMD ["/usr/sbin/sshd", "-D", "-e"]
