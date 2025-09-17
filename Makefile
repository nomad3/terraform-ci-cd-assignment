SHELL := /bin/bash

TF ?= terraform
PY ?= python3

.PHONY: init plan apply destroy fmt validate output url update

init:
	$(TF) init

plan:
	$(TF) plan

apply:
	$(TF) apply -auto-approve

destroy:
	$(TF) destroy -auto-approve

fmt:
	$(TF) fmt -recursive

validate:
	$(TF) validate

output:
	$(TF) output

url:
	@$(TF) output -raw api_base_url

update:
	@if [ -z "$(VALUE)" ]; then echo "Usage: make update VALUE='new string'"; exit 2; fi
	$(PY) scripts/update_dynamic_string.py "$(VALUE)"
