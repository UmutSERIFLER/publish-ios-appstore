SHELL_FILES := scripts/*.sh .github/scripts/*.sh tests/*.sh tests/stubs/*

.PHONY: check lint test

check: lint test

lint:
	shellcheck -x -S style $(SHELL_FILES)
	actionlint

# /bin/bash on purpose: the scripts must keep working with macOS bash 3.2.
test:
	/bin/bash tests/run.sh
