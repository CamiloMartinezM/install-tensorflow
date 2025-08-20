# Makefile for setting up a Python virtual environment with virtualenvwrapper

#################################################################################
# GLOBALS                                                                       #
#################################################################################

PROJECT_NAME = tf-2.10
PYTHON_VERSION = 3.10
PYTHON_INTERPRETER = /usr/bin/python${PYTHON_VERSION}
VENV_PATH = /CT/eeg-3d-face/work/.virtualenvs/$(PROJECT_NAME)/bin
SETUP_ENVIRONMENT_VARIABLES_SCRIPT = setup_envars_virtualenvwrapper.sh

#################################################################################
# COMMANDS                                                                      #
#################################################################################


## Install Python Dependencies
.PHONY: requirements
requirements:
	@python -m pip install -U pip
	@python -m pip install --upgrade pip
	@python -m pip install -r requirements.txt --extra-index-url https://pypi.nvidia.com
	@make envars  # Automatically call setup_envars after installing requirements

## Set up python interpreter environment
.PHONY: environment
environment:
	@bash -c "if [ ! -z `which virtualenvwrapper.sh` ]; then source `which virtualenvwrapper.sh`; mkvirtualenv $(PROJECT_NAME) --python=$(PYTHON_INTERPRETER); else mkvirtualenv.bat $(PROJECT_NAME) --python=$(PYTHON_INTERPRETER); fi"
	@echo ">>> New virtualenv created. Activate with: workon $(PROJECT_NAME)"

## Setup environment variables for virtualenv
.PHONY: envars
envars:
	@if [ ! -d "$(VENV_PATH)" ]; then \
		echo -e "\033[31m✘\033[0m \033[1mERROR\033[0m: Virtual environment '$(PROJECT_NAME)' not found in ~/.virtualenvs/"; \
		exit 1; \
	fi
	@cp "$(SETUP_ENVIRONMENT_VARIABLES_SCRIPT)" "$(VENV_PATH)/postactivate"
	@echo -e '#!/bin/bash\nunset LD_LIBRARY_PATH\necho -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Resetting LD_LIBRARY_PATH"' > "$(VENV_PATH)/predeactivate"
	@chmod +x "$(VENV_PATH)/postactivate" "$(VENV_PATH)/predeactivate"
	@echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Environment variable setup scripts have been created and made executable."