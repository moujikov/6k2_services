#!/bin/bash

set -eu -o pipefail

create_db_and_user() {
	local DATABASE=$1
	local USER=$2
	local PASSWORD="$(< /run/secrets/db_password_$USER)"

	psql --username postgres <<-EOSQL
		CREATE USER $USER WITH PASSWORD '$PASSWORD';
		CREATE DATABASE $DATABASE WITH OWNER $USER;
	EOSQL
}

create_db_and_user authelia authelia
create_db_and_user lldap lldap
