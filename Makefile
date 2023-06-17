# app custom Makefile


# Docker repo & image name without version
IMAGE    ?= smallstep/step-ca

# Hostname for external access
APP_SITE ?= stepca.dev.lan

# App names (db/user name etc)
APP_NAME ?= stepca

# PgSQL used as DB
USE_DB = yes
DCAPE_DC_USED = false

ADMIN_PASSWORD       ?= $(shell openssl rand -hex 16; echo)

# ------------------------------------------------------------------------------
# app custom config

IMAGE_VER            ?= latest

DCAPE_ROOT           ?= /opt/dcape/var

DATA_PATH            ?= $(APP_NAME)

# ------------------------------------------------------------------------------
# .env template (custom part)
# inserted in .env.sample via 'make config'
define CONFIG_CUSTOM
# ------------------------------------------------------------------------------
# app custom config, generated by make config
# db:$(USE_DB) user:$(ADD_USER)

ADMIN_PASSWORD=$(ADMIN_PASSWORD)

# Path to /opt/dcape/var. Used only outside drone
DCAPE_ROOT=$(DCAPE_ROOT)

DATA_PATH=$(DATA_PATH)

endef

# ------------------------------------------------------------------------------
# Find and include DCAPE/apps/drone/dcape-app/Makefile
DCAPE_COMPOSE   ?= dcape-compose
DCAPE_MAKEFILE  ?= $(shell docker inspect -f "{{.Config.Labels.dcape_app_makefile}}" $(DCAPE_COMPOSE))
ifeq ($(shell test -e $(DCAPE_MAKEFILE) && echo -n yes),yes)
  include $(DCAPE_MAKEFILE)
else
  include /opt/dcape-app/Makefile
endif

define CAJSON
{
	"db": {
		"type": "postgresql",
		"dataSource": "postgresql://",
		"badgerFileLoadingMode": ""
	},
	"authority": {
		"provisioners": [
			{
				"type": "ACME",
				"name": "acme",
				"claims": {
					"minTLSCertDuration": "20m0s",
					"maxTLSCertDuration": "2400h0m0s",
					"defaultTLSCertDuration": "240h0m0s",
					"enableSSHCA": true,
					"disableRenewal": false,
					"allowRenewalAfterExpiry": false
				},
			}
		],
	},
	"commonName": "Dcape Step Online CA"
}

endef

# create config dir
data/config:
	@mkdir -p $@

# create defaul config file
data/config/ca.json: data/config
	@echo "$$CAJSON" >> $@

# db-create addon
db-create: data/config/ca.json

# init storage
ca-create: data/config/ca.json
ca-create: CMD=run --rm app step ca init
ca-create: dc

# set times
ca-time: CMD=run --rm app step ca provisioner update acme --x509-min-dur=20m --x509-max-dur=2400h --x509-default-dur=240h
ca-time: dc

# add ACME provisioner
ca-acme: CMD=exec app step ca provisioner add acme --type ACME
ca-acme: dc

## install root cert on host machine
ca-install:
	sudo cp data/certs/root_ca.crt /usr/local/share/ca-certificates/$(APP_NAME).crt
	sudo /usr/sbin/update-ca-certificates

ca-test:
	curl https://$(APP_SITE)/health

DO ?= sh

## run command if container is running
## Example: make exec DO=ls
exec: CMD=exec app $(DO)
exec: dc

## run new container and run command in it
## Example: make run DO=ls
run: CMD=run --rm app $(DO)
run: dc

