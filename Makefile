#
# Basic makefile for general targets
#
PACKAGE = @@project_name@@
MODULE = @@python_module@@

##
## NOTE: Anything changed below this line should be changed in base_service.git
## and then merged into individual projects.  This prevents conflicts and
## maintains consistency between projects.
##
ACTIVATE = $(ENVDIR)/bin/activate
ENVDIR = ./env
CATERER = $(ENVDIR)/bin/caterer
COVERAGE = $(ENVDIR)/bin/coverage
DEVELOPMENT_ENV = $(shell echo $(PACKAGE) | tr 'a-z\-' 'A-Z_')_CONF=configuration/development.conf
EASY_INSTALL = $(ENVDIR)/bin/easy_install
FABRIC = $(ENVDIR)/bin/fab
NOSE = $(ENVDIR)/bin/nosetests
PEP8 = $(ENVDIR)/bin/pep8
PIP = C_INCLUDE_PATH="/opt/local/include:/usr/local/include" $(ENVDIR)/bin/pip
PIPOPTS=$(patsubst %,-r %,$(wildcard $(HOME)/.requirements.pip requirements.pip)) --index-url=http://pypi.colo.lair/simple/
PYLINT = $(ENVDIR)/bin/pylint
PYTHON = $(ENVDIR)/bin/python
PYTHON_VERSION = python2.6
REPORTDIR = reports
SCP = scp
SETUP = . $(ACTIVATE); $(PYTHON) setup.py
# Work around a bug in git describe: http://comments.gmane.org/gmane.comp.version-control.git/178169
VERSION = $(shell git status >/dev/null 2>/dev/null && git describe --abbrev=6 --tags --dirty --match="[0-9]*")
VIRTUALENV = virtualenv
VIRTUALENVOPTS = --python=$(PYTHON_VERSION)

APT_REQ_FILE = requirements.apt
DIST_FILE = dist/$(PACKAGE)-$(VERSION).tar.gz
EGG_LINK = $(ENVDIR)/lib/$(PYTHON_VERSION)/site-packages/$(PACKAGE).egg-link

# Requirements that cannot be installed via pip (packages
# listed here will be installed via easy_install)
ADDTLREQS = nose_machineout readline

## Testing ##
.PHONY: test coverage

test: unit-test integration-test acceptance-test
coverage: unit-coverage

%-test: $(REPORTDIR)
	@echo Running $* tests
	$(DEVELOPMENT_ENV) $(NOSE) --cover-package=$(MODULE),tests --tests=tests/$* --with-xunit --xunit-file=$(REPORTDIR)/$*-xunit.xml

%-coverage: %-test
	@echo Generating $* coverage reports
	$(COVERAGE) html -d $(REPORTDIR)/htmlcov-$* --omit=$(ENVDIR)/*
	$(COVERAGE) xml  -o $(REPORTDIR)/$*-coverage.xml --omit=$(ENVDIR)/*

$(REPORTDIR): $(EGG_LINK)
	test -d "$@" || mkdir -p "$@"
	touch "$@"

## Documentation ##
.PHONY: doc deploy-docs
doc: $(EGG_LINK)
	$(MAKE) --always-make RELEASE-VERSION
	mkdir -p $(CURDIR)/doc/source/_static
	$(SETUP) build_sphinx

$(PACKAGE)_docs.tar.gz: doc
	cd doc/html; tar czf ../../$@ *

deploy-docs: $(PACKAGE)_docs.tar.gz
	$(FABRIC) base.set_documentation_host base.deploy_docs:$(PACKAGE),`cat RELEASE-VERSION` -u ubuntu

## Static Analysis ##
.PHONY: lint pep8 pylint
lint: pep8 pylint

pylint: $(REPORTDIR) .tests.pylintrc
	$(PYLINT) --reports=y --output-format=parseable --rcfile=pylintrc $(MODULE) | tee $(REPORTDIR)/$(MODULE)_pylint.txt
	$(PYLINT) --reports=y --output-format=parseable --rcfile=.tests.pylintrc tests | tee $(REPORTDIR)/tests_pylint.txt

.tests.pylintrc: pylintrc pylintrc-tests-overrides
	cat $^ > $@

pep8: $(REPORTDIR)
	# Strip out warnings about long lines in tests. We loosen the
	# limitation for long lines in tests and Pylint already checks line
	# length for us.
	$(PEP8) --filename="*.py" --repeat $(MODULE) tests | grep -v '^tests/.*E501' | tee $(REPORTDIR)/pep8.txt

## Local Setup ##
.PHONY: requirements req virtualenv dev
requirements:
	@rm -f .req
	$(MAKE) .req

req: .req
.req: $(ENVDIR) requirements.pip
	$(PIP) install $(PIPOPTS)
	$(EASY_INSTALL) -U $(ADDTLREQS)
	@touch .req

setup.py: RELEASE-VERSION
RELEASE-VERSION:
	@echo Updating $@ "($(VERSION))"
	@echo $(VERSION) > $@

dev: $(EGG_LINK)
$(EGG_LINK): setup.py .req
	$(SETUP) develop

virtualenv: $(ENVDIR)
$(ENVDIR):
	$(VIRTUALENV) $(VIRTUALENVOPTS) $(ENVDIR)

## Packaging ##
.PHONY: dist upload $(DIST_FILE)
dist: sdist
sdist: $(DIST_FILE)
$(DIST_FILE):MAKEFLAGS=--always-make
$(DIST_FILE): setup.py
	$(SETUP) sdist

upload:
	rm -rf dist RELEASE-VERSION
	$(MAKE) RELEASE-VERSION sdist
	@if (echo $(VERSION) | grep -q dirty); then echo "Cannot upload a dirty package! Tag a proper release!" >&2 && exit 1; fi
	$(MAKE) sdist
	$(SETUP) register --repository aweber sdist upload --repository aweber

## Housekeeping ##
.PHONY: clean maintainer-clean
clean:
	rm -rf RELEASE-VERSION dist $(REPORTDIR) *.egg *.egg-info
	rm -f .coverage .nose-stopwatch-times .req .tests.pylintrc chef_script pip-log.txt
	find . -type f -name '*.pyc' -delete

maintainer-clean: clean
	rm -rf $(ENVDIR) doc/doctrees doc/html

## Service Deployment ##
.PHONY: vagrant-env chef-roles deploy-vagrant deploy-staging deploy-production
vagrant-env:
	$(CATERER) vagrant $(PACKAGE) Procfile > chef_script; sh chef_script

chef-roles:
	$(CATERER) production $(PACKAGE) Procfile >/dev/null

deploy-vagrant: sdist
	$(FABRIC) base.set_hosts:'vagrant','api' base.deploy_api:'$(DIST_FILE)','$(APT_REQ_FILE)' -u vagrant -p vagrant

deploy-staging: Procfile sdist
	$(CATERER) staging $(PACKAGE) Procfile > chef_script; sh chef_script
	$(FABRIC) base.set_hosts:'staging','api' base.deploy_api:'$(DIST_FILE)','$(APT_REQ_FILE)' -u ubuntu

deploy-production: Procfile sdist
	$(CATERER) production $(PACKAGE) Procfile > chef_script; sh chef_script
	$(FABRIC) base.set_hosts:'production','api' base.deploy_api:'$(DIST_FILE)','$(APT_REQ_FILE)' -u ubuntu

## Development
.PHONY: tdd
tdd:
	$(DEVELOPMENT_ENV) nosyd -1

.PHONY: foreman
foreman: dev
	. $(ACTIVATE); $(DEVELOPMENT_ENV) PYTHON_LOGCONFIG_LOG_TO_STDOUT=1 foreman start


-include Makefile.inc

