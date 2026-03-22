### New VPS setup steps:
1. SSH as root or `sudo` all commands below
2. Update and upgrade packages:
   ```
   apt update && apt upgrade -y
   ```
3. Install git:
   ```
   apt install -y git
   ```
4. Clone the repository:
   ```
   git clone https://github.com/moujikov/6k2_services /opt/services
   ```
5. Run the setup script:
   ```
   /opt/services/setup.sh
   ```
  Provide Git Hub access token when prompted.
6. Add admins with:
   ```
   htdigest /usr/local/share/traefik/auth/admins traefik USER_NAME
   ```
   Add users with:
   ```
   htdigest /usr/local/share/traefik/auth/users traefik USER_NAME
   ```
