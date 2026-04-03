#!/bin/bash

set -eu -o pipefail

create_db_and_user() {
	local DATABASE=$1
	local USER=$2
	local PASSWORD="$(< /run/secrets/db_password_$USER)"

	psql -v ON_ERROR_STOP=1 --username postgres <<-EOSQL
	DO \$create_db_and_user\$ BEGIN
		IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$USER') THEN
			CREATE USER $USER WITH PASSWORD '$PASSWORD';
		END IF;

		IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DATABASE') THEN
			CREATE DATABASE $DATABASE WITH OWNER $USER;
		END IF;
	END \$create_db_and_user\$;
	EOSQL
}

create_db_and_user authelia authelia
create_db_and_user lldap lldap
