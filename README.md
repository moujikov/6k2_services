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
   Provide Docker Hub access token and other secrets when prompted.

6. Login to LLDAP at https://users.6k2.ru with user `admin` and password from `/usr/local/share/services/lldap/auth/ldap_user_pass`.
Add user `authelia` with password from `/usr/local/share/services/lldap/auth/authelia_password`, add it to group `lldap_password_manager` to allow Authelia to authenticate in LLDAP and change passwords.
